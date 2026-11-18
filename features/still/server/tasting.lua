local Tasting = GSC.module('Tasting')

---oo[ Tasting: a sip that tells you what is really in the bottle ]oo---

local Sessions = {}
local Cooldown = {}
local LastPick = {}

local function Conf()
    return Config.Tasting or {}
end

local function T()
    return Config.Text.Tasting or {}
end

---oo[ The hidden profile: "84;clean,fruity;spiked" ]oo---
function Tasting.Encode(profile)
    if type(profile) ~= 'table' then return nil end
    return string.format("%s;%s;%s", profile.score and tostring(math.floor(profile.score)) or "",
        table.concat(profile.notes or {}, ","), table.concat(profile.flaws or {}, ","))
end

function Tasting.Decode(text)
    if type(text) ~= 'string' then return nil end
    local score, notes, flaws = text:match("^([^;]*);([^;]*);([^;]*)$")
    if not score then return nil end
    local function List(s)
        local out = {}
        for word in s:gmatch("[^,]+") do out[#out + 1] = word end
        return out
    end
    return { score = tonumber(score), notes = List(notes), flaws = List(flaws) }
end

---o[ A bottle with no profile ]o---
local GRADE_NOTE = { PERFECT = "rich", GOOD = "plain", NORMAL = "sharp" }

local function GradeLabel(quality)
    local q = ((Config.Product or {}).Qualities or {})[quality or ""]
    return q and q.label or tostring(quality or "?")
end

local function Words(keys, dict)
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = (dict or {})[key] or key end
    return out
end

---o[ What a reading of this accuracy learns, or nil for a muddled one ]o---
function Tasting.Read(meta, quality, accuracy)
    local conf = Conf()
    accuracy = math.max(0, math.min(1, tonumber(accuracy) or 0))
    if accuracy < (conf.MuddledBelow or 0.35) then return nil end

    local full = accuracy >= (conf.FullFrom or 0.75)
    local profile = Tasting.Decode(meta and meta.profile)
    local notes, flaws = {}, {}

    if profile then
        for _, n in ipairs(profile.notes) do notes[#notes + 1] = n end
        for _, f in ipairs(profile.flaws) do flaws[#flaws + 1] = f end
    elseif meta and meta.tainted then
        flaws[1] = "harsh"
    end
    if #notes == 0 then notes[1] = GRADE_NOTE[quality or ""] or "plain" end

    if not full then
        notes = { notes[1] }
        flaws = flaws[1] and { flaws[1] } or {}
    end

    return {
        full = full,
        quality = quality,
        score = full and profile and profile.score or nil,
        notes = notes,
        flaws = flaws,
    }
end

---o[ The bottle as it reads once tasted: metadata to write back ]o---
function Tasting.Describe(meta, recipeKey, quality, reading)
    local t = T()
    local out = {}
    for k, v in pairs(meta or {}) do out[k] = v end

    local product = out.productLabel or GSC.Mash.ProductLabel(recipeKey, out.strength)
    local grade = GradeLabel(quality)
    local notesText = table.concat(Words(reading.notes, t.Notes), ", ")
    local flawText = #reading.flaws > 0
        and string.format(t.DescribedFlaw, table.concat(Words(reading.flaws, t.Flaws), ", ")) or ""

    out.recipe = out.recipe or recipeKey
    out.quality = out.quality or quality
    out.tasted = true
    out.tastedNote = " " .. string.format(t.TastedNote, notesText) .. flawText -- kept for the crate

    local desc = string.format(t.Described, product, grade, notesText) .. flawText
    if out.aged then
        local tierLabel = out.aged
        for _, tier in ipairs((Config.CrateAging or {}).Tiers or {}) do
            if tier.key == out.aged then tierLabel = tier.label or tier.key end
        end
        desc = desc .. string.format(t.DescribedAged, tierLabel)
    end
    if out.proof then desc = desc .. string.format(Config.Text.BottleProof, tonumber(out.proof) or 0) end
    if out.tainted then
        desc = desc .. Config.Text.Cuts.TaintedDescription
        if Config.Cuts.TaintedLabel and Config.Tasting.HideUntasted then
            out.label = string.format(Config.Cuts.TaintedLabel, out.label or product)
        end
    end
    out.description = desc
    return out, product, grade
end

---oo[ The satchel ]oo---
local function FindStack(src, id)
    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
        if item.id == id and (tonumber(item.count) or 0) > 0 then return item end
    end
    return nil
end

local function Tasteable(item)
    local meta = item.metadata or {}
    if meta.tasted or meta.soured then return nil end
    local recipeKey, quality = GSC.Crates.BottleRecipe(item)
    if not recipeKey or not Config.Recipes[recipeKey] then return nil end
    return recipeKey, quality
end

local function HasCup(src)
    return exports.vorp_inventory:getItemCount(src, nil, Config.Items.TastingCup) > 0
end

---o[ The cup: list what can be tasted ]o---
if Conf().Enabled and Config.Items.TastingCup then
    exports.vorp_inventory:registerUsableItem(Config.Items.TastingCup, function(data)
        local src = data.source
        if not Shared.GetChar(src) then return end
        exports.vorp_inventory:closeInventory(src)

        local now = os.time()
        if Cooldown[src] and now < Cooldown[src] then
            return GSC.Notify.Send(src, string.format(T().Wait, Cooldown[src] - now), 3000)
        end

        local list = {}
        for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
            if (tonumber(item.count) or 0) > 0 and #list < (Conf().PickerMax or 12) then
                local recipeKey = Tasteable(item)
                if recipeKey then
                    local meta = item.metadata or {}
                    local tierLabel = nil
                    if meta.aged then
                        tierLabel = meta.aged
                        for _, tier in ipairs((Config.CrateAging or {}).Tiers or {}) do
                            if tier.key == meta.aged then tierLabel = tier.label or tier.key end
                        end
                    end
                    list[#list + 1] = {
                        id = item.id,
                        label = meta.label or meta.productLabel or GSC.Mash.ProductLabel(recipeKey, meta.strength),
                        count = tonumber(item.count) or 1,
                        aged = tierLabel,
                        recipe = recipeKey,
                    }
                end
            end
        end

        if #list == 0 then return GSC.Notify.Send(src, T().NoneToTaste, 4000) end
        TriggerClientEvent('gsc_kassippu:client:tastePicker', src, list)
    end)
end

---o[ A bottle picked ]o---
RegisterServerEvent('gsc_kassippu:server:tastePick')
AddEventHandler('gsc_kassippu:server:tastePick', function(id)
    local _source = source
    if not Conf().Enabled or not Shared.GetChar(_source) then return end
    if type(id) ~= 'number' and type(id) ~= 'string' then return end

    local now = os.time()
    if LastPick[_source] and now - LastPick[_source] < 2 then return end
    LastPick[_source] = now
    if Cooldown[_source] and now < Cooldown[_source] then return end
    if not HasCup(_source) then return GSC.Notify.Send(_source, T().NoCup, 3000) end

    local item = FindStack(_source, id)
    local recipeKey = item and Tasteable(item)
    if not recipeKey then return GSC.Notify.Send(_source, T().NotThere, 3000) end

    Sessions[_source] = { id = id, started = now }
    TriggerClientEvent('gsc_kassippu:client:tasteGame', _source, id, recipeKey, (item.metadata or {}).aged ~= nil)
end)

---o[ The reading ]o---
RegisterServerEvent('gsc_kassippu:server:tasteResult')
AddEventHandler('gsc_kassippu:server:tasteResult', function(id, accuracy)
    local _source = source
    local session = Sessions[_source]
    if not session or session.id ~= id then return end -- only the tasting the server opened
    Sessions[_source] = nil
    if not Shared.GetChar(_source) then return end

    local conf = Conf()
    local now = os.time()
    local took = now - session.started
    local window = (tonumber(conf.Minigame and conf.Minigame.time) or 16) + 15
    if took > window then return end

    accuracy = math.max(0, math.min(1, tonumber(accuracy) or 0))
    if took < (conf.MinSeconds or 5) then accuracy = 0 end -- sooner than a real tasting: muddled

    local item = FindStack(_source, id)
    local recipeKey, quality = nil, nil
    if item then recipeKey, quality = Tasteable(item) end
    if not recipeKey then return GSC.Notify.Send(_source, T().NotThere, 3000) end

    local reading = Tasting.Read(item.metadata, quality, accuracy)
    if not reading then
        Cooldown[_source] = now + (conf.RetrySeconds or 20)
        return GSC.Notify.Send(_source, T().Muddled, 5000, "warning")
    end

    local meta, product, grade = Tasting.Describe(item.metadata, recipeKey, quality, reading)
    exports.vorp_inventory:setItemMetadata(_source, item.id, meta, 1) -- one bottle off the stack, now tasted

    if conf.ConsumeCup then exports.vorp_inventory:subItem(_source, Config.Items.TastingCup, 1) end
    Cooldown[_source] = now + 3

    local t = T()
    TriggerClientEvent('gsc_kassippu:client:tastingCard', _source, {
        product = product,
        grade = grade,
        quality = quality,
        full = reading.full,
        score = reading.score,
        notes = Words(reading.notes, t.Notes),
        flaws = Words(reading.flaws, t.Flaws),
    })
    GSC.Notify.Send(_source, string.format(t.Done, product, grade), 5000)
    Shared.Debug(string.format("^6[Tasting]^7 %s tasted %s (%s): accuracy %.2f, %s", _source, product, tostring(quality),
        accuracy, reading.full and "full" or "partial"))
end)

AddEventHandler('playerDropped', function()
    Sessions[source], Cooldown[source], LastPick[source] = nil, nil, nil
end)
