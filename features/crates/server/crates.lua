local Crates = GSC.module('Crates')

---o[ State ]o---
local CrateList = {}

local CrateWatchers = {} -- [uid] = { [src] = owner id of the character stood there }
local WatchedCrate = {}  -- [src] = uid
local PickAttempts = {}  -- [src] = { uid, started, startedMs } while a lockpick minigame is running
local PickCooldown = {}  -- [src] = os.time() his next attempt is allowed
local TendAttempts = {}  -- [src] = { uid, opened, started (GetGameTimer ms) } while a crate job minigame is running
local CratesLoaded = false  -- true once the crates came back from the database
local LastCrateRequest = {} -- [src] = os.time() of their last full-sync request

local TIER_ORDER = { NORMAL = 1, GOOD = 2, PERFECT = 3 }

---oo[ Helpers ]oo---

local function Conf()
    return Config.CrateAging
end

local function LockConf()
    return Conf().Lock or {}
end

local function QualityLabel(quality)
    local q = Config.Product.Qualities[quality]
    return q and q.label or tostring(quality)
end

local function RecipeLabel(recipeKey, fallback)
    local recipe = Config.Recipes[recipeKey]
    return recipe and recipe.label or fallback or tostring(recipeKey)
end

---o[ What a bottle is called: "Strong Kassippu", or just the recipe ]o---
local function BottleName(bottle)
    local meta = bottle.meta or {}
    return meta.productLabel or RecipeLabel(bottle.recipe, bottle.item)
end

---o[ An activity or a hazard, by key ]o---
local function FindActivity(key)
    local conf = Conf()
    for _, activity in ipairs(conf.Activities or {}) do
        if activity.key == key then return activity, false end
    end
    for _, hazard in ipairs(conf.Hazards or {}) do
        if hazard.key == key then return hazard, true end
    end
    return nil, false
end

---o[ One entry from a list, by its `weight` (1 when unset) ]o---
local function PickWeighted(list)
    local total = 0
    for _, entry in ipairs(list) do total = total + math.max(0, entry.weight or 1) end
    if total <= 0 then return list[math.random(#list)] end

    local roll = math.random() * total
    for _, entry in ipairs(list) do
        roll = roll - math.max(0, entry.weight or 1)
        if roll <= 0 then return entry end
    end
    return list[#list]
end

local function OwnerIdOf(Character)
    return tostring(Character.charIdentifier or Character.identifier)
end

local function IsOwner(Character, crate)
    return crate.owner == OwnerIdOf(Character)
end

---o[ Has this character already set down Config.CrateAging.MaxPerPlayer crates? Tells him if so ]o---
local function AtCrateLimit(src, Character)
    local limit = tonumber(Config.CrateAging.MaxPerPlayer) or 0
    if limit <= 0 then return false end

    local ownerId, owned = OwnerIdOf(Character), 0
    for _, crate in pairs(CrateList) do
        if crate.owner == ownerId then owned = owned + 1 end
    end
    if owned < limit then return false end

    GSC.Notify.SendObjective(src, string.format(Config.Text.CrateLimitReached, limit), 4000)
    return true
end

---o[ Unique enough within a crate, and stable across restarts ]o---
local idCounter = 0
local function NewBottleId()
    idCounter = (idCounter + 1) % 0x10000
    return string.format("%x%04x", os.time(), idCounter)
end

---o[ What the crate's climate works out to ]o---
local function ApplyClimate(crate)
    local climate = crate.climate or {}
    local band, ageRate, keepRate = Shared.CrateClimate(climate.temp, climate.sheltered)
    crate.band, crate.ageRate, crate.keepRate = band, ageRate, keepRate
end

---o[ Which fresh bottles a crate will take ]o---
local FreshLookup = nil

local function GetFreshLookup()
    if FreshLookup then return FreshLookup end
    FreshLookup = {}

    -- First runs before second runs: an untagged bottle is the spirit it was distilled as,
    -- not the second run that happens to share its item (local_kasippu is Kassippu, not Arrack).
    -- Lowest grade first: when every grade shares one item (local_kasippu), a bottle that carries
    -- no grade of its own (a shop's, another script's) is taken as the poorest it could be - never
    -- as Perfect, which would let it age into the best aged items. Distinct items per grade are
    -- unaffected: each item still maps to its own grade.
    local recipeKeys = {}
    for key in pairs(Config.Recipes) do recipeKeys[#recipeKeys + 1] = key end
    table.sort(recipeKeys, function(a, b)
        local sa, sb = Config.Recipes[a].secondRun == true, Config.Recipes[b].secondRun == true
        if sa ~= sb then return not sa end
        return a < b
    end)

    for _, recipeKey in ipairs(recipeKeys) do
        local qualities = {}
        for quality in pairs(Config.Recipes[recipeKey].rewards or {}) do qualities[#qualities + 1] = quality end
        table.sort(qualities, function(a, b) return (TIER_ORDER[a] or 0) < (TIER_ORDER[b] or 0) end)

        for _, quality in ipairs(qualities) do
            local reward = Config.Recipes[recipeKey].rewards[quality]
            if reward.item and not FreshLookup[reward.item] then
                FreshLookup[reward.item] = { recipe = recipeKey, quality = quality }
            end
        end
    end

    return FreshLookup
end

---o[ Is this inventory stack a fresh bottle, and of what? ]o---
local function ResolveFreshBottle(item)
    local meta = item.metadata or {}
    if meta.aged or meta.soured then return nil end

    if meta.recipe and meta.quality then
        local recipe = Config.Recipes[meta.recipe]
        local reward = recipe and recipe.rewards and recipe.rewards[meta.quality]
        local strength = meta.strength and GSC.Mash.Strength(meta.recipe, meta.strength)
        if reward and (reward.item == item.name or (strength and strength.item == item.name)) then
            return meta.recipe, meta.quality
        end
    end

    local fallback = GetFreshLookup()[item.name]
    if fallback then return fallback.recipe, fallback.quality end

    return nil
end

---o[ The tag a barrel puts on every bottle it fills ]o---
function Crates.FreshBottleMetadata(recipeKey, quality, strengthKey)
    local conf = Conf()
    if not conf or not conf.Enabled or not conf.TagFreshBottles then return nil end
    if not Config.Recipes[recipeKey] then return nil end

    local product = GSC.Mash.ProductLabel(recipeKey, strengthKey)
    local t = Config.Tasting
    return {
        description = (t and t.Enabled and t.HideUntasted) -- the grade is for a taster to find
            and string.format(Config.Text.BottleUntastedDescription, product)
            or string.format(Config.Text.BottleFreshDescription, product, QualityLabel(quality)),
        recipe = recipeKey,
        quality = quality,
    }
end

---o[ For the tasting: the recipe and grade of a satchel stack (fresh, aged or untagged), or nil ]o---
function Crates.BottleRecipe(item)
    local meta = item and item.metadata or {}
    if meta.soured then return nil end
    if meta.aged and meta.recipe and meta.quality then return meta.recipe, meta.quality end
    return ResolveFreshBottle(item)
end

---oo[ Maturity ]oo---

local function AgeSeconds(bottle, now)
    return math.max(0, (now or os.time()) - (bottle.stored or now or os.time()))
end

local function MaturityMinutes(crate, bottle, now)
    return AgeSeconds(bottle, now) * (crate.ageRate or 1.0) / 60
end

local function SpoilSeconds(crate)
    return math.max(60, (Conf().SpoilMinutes or 90) * 60 * (crate.keepRate or 1.0))
end

---o[ Which tier the clock alone has earned ]o---
local function TimeTierIndex(crate, bottle, now)
    local minutes = MaturityMinutes(crate, bottle, now)

    for i, tier in ipairs(Conf().Tiers) do
        if minutes >= tier.minutes then return i end
    end
    return nil
end

local function TierIndexByKey(key)
    if not key then return nil end
    for i, tier in ipairs(Conf().Tiers) do
        if tier.key == key then return i end
    end
    return nil
end

---o[ ...and what the care is worth on top of it ]o---
local function EffectiveTier(crate, bottle, now)
    if bottle.soured then return nil end

    local conf = Conf()
    local index = TimeTierIndex(crate, bottle, now)

    if index then
        local care = bottle.care or 0.0

        if care >= (conf.GoodCare or math.huge) then
            index = math.max(1, index - 1)
        elseif care <= (conf.PoorCare or -math.huge) then
            index = index + 1
            if index > #conf.Tiers then index = nil end
        end
    end

    ---o[ Aging can't be undone: never below the richest tier this bottle has reached (TickCrate sets bottle.best) ]o---
    local best = TierIndexByKey(bottle.best)
    if best and (not index or best < index) then index = best end

    if not index then return nil end
    return index, conf.Tiers[index]
end

---o[ Where a bottle is headed, at the care it has now ]o---
local function Outlook(crate, bottle, now)
    local tiers = Conf().Tiers
    local minutes = MaturityMinutes(crate, bottle, now)
    local currentIndex = EffectiveTier(crate, bottle, now)
    if currentIndex == 1 then return 1.0, nil, nil end -- at the richest tier (by time or by care): full bar, nothing ahead
    local spoilLeft = SpoilSeconds(crate) - AgeSeconds(bottle, now)

    local floor, ahead = 0, {}
    for i = #tiers, 1, -1 do
        local m = tiers[i].minutes
        if m > minutes then
            ahead[#ahead + 1] = m
        elseif m > floor then
            floor = m
        end
    end

    local progress = ahead[1] and ((minutes - floor) / math.max(0.01, ahead[1] - floor)) or 1.0

    for _, m in ipairs(ahead) do
        local wait = math.ceil((m - minutes) * 60 / (crate.ageRate or 1.0))
        if wait >= spoilLeft then break end

        local index, tier = EffectiveTier(crate, bottle, now + wait + 1)
        if index and (not currentIndex or index < currentIndex) then
            return progress, wait, tier.label or tier.key
        end
    end

    return progress, nil, nil
end

---o[ Tasting (Config.Tasting): is this bottle's grade and taint known yet? ]o---
local function HidingUntasted()
    local t = Config.Tasting
    return t and t.Enabled and t.HideUntasted
end

local function Revealed(meta)
    return not HidingUntasted() or (meta ~= nil and meta.tasted == true)
end

---o[ The tasting fields a bottle keeps through the crate ]o---
local function CarryTasting(from, to)
    if not from then return to end
    to.profile, to.tasted, to.tastedNote = from.profile, from.tasted, from.tastedNote
    return to
end

---o[ What a bottle comes out of the crate as ]o---
local function ResolveTakenBottle(crate, bottle, now)
    local recipeKey, quality = bottle.recipe, bottle.quality
    local recipe = Config.Recipes[recipeKey]
    local recipeLabel = BottleName(bottle)

    local strength = bottle.meta and bottle.meta.strength or nil
    local productLabel = bottle.meta and bottle.meta.productLabel or nil
    local tainted = bottle.meta and bottle.meta.tainted or nil
    local proof = bottle.meta and tonumber(bottle.meta.proof) or nil
    local known = Revealed(bottle.meta)
    local taintNote = (proof and string.format(Config.Text.BottleProof, proof) or "")
        .. ((tainted and known) and Config.Text.Cuts.TaintedDescription or "")
        .. ((known and bottle.meta and bottle.meta.tastedNote) or "")

    ---o[ Turned ]o---
    if bottle.soured then
        local plain = recipe and recipe.rewards and recipe.rewards.NORMAL
        local label = string.format(Config.Text.BottleSourLabel, recipeLabel)

        return (plain and plain.item) or bottle.item, CarryTasting(bottle.meta, {
            label = label,
            description = string.format(Config.Text.BottleSourDescription, recipeLabel) .. taintNote,
            recipe = recipeKey,
            quality = "NORMAL",
            soured = true,
            strength = strength,
            proof = proof,
            productLabel = productLabel,
            tainted = tainted,
        }), string.format(Config.Text.CrateTakenSour, label)
    end

    ---o[ Not aged yet: you get back exactly what you laid down ]o---
    local _, tier = EffectiveTier(crate, bottle, now)
    if not tier then
        local meta = bottle.meta
        if meta and next(meta) == nil then meta = nil end
        return bottle.item, meta, string.format(Config.Text.CrateTakenRaw, recipeLabel)
    end

    ---o[ Aged ]o---
    local reward = recipe and recipe.rewards and recipe.rewards[quality]
    local agedItem = reward and reward.agedItems and reward.agedItems[tier.key]
    local tierLabel = tier.label or tier.key

    local minutes = math.floor(AgeSeconds(bottle, now) / 60)
    local metadata = CarryTasting(bottle.meta, {
        description = (known
            and string.format(Config.Text.BottleAgedDescription, recipeLabel, QualityLabel(quality), minutes, tierLabel)
            or string.format(Config.Text.BottleAgedUntasted, recipeLabel, minutes, tierLabel)) .. taintNote,
        recipe = recipeKey,
        quality = quality,
        aged = tier.key,
        strength = strength,
        proof = proof,
        productLabel = productLabel,
        tainted = tainted,
    })

    local shownLabel = string.format(Config.Text.BottleAgedLabel, recipeLabel, tierLabel)
    if not agedItem then metadata.label = shownLabel end

    return agedItem or bottle.item, metadata, string.format(Config.Text.CrateTakenAged, shownLabel)
end

---o[ A fresh bottle as it would come out of a crate: at a tier, or turned (admin give) ]o---
-- state: a tier key from Config.CrateAging.Tiers, or "TURNED". Runs through ResolveTakenBottle
-- so the result is exactly what a real crate hands back. nil when the crate is switched off.
function Crates.AgedBottle(item, meta, recipeKey, quality, state)
    local conf = Conf()
    if not conf or not conf.Enabled then return nil end

    local now = os.time()
    local minutes = 0
    if state ~= "TURNED" then
        local index = TierIndexByKey(state)
        if not index then return nil end
        minutes = conf.Tiers[index].minutes
    end

    local bottle = {
        item = item,
        recipe = recipeKey,
        quality = quality,
        stored = now - math.ceil(minutes * 60),
        care = 0.0,
        soured = state == "TURNED" or nil,
        meta = meta,
    }
    local newItem, newMeta = ResolveTakenBottle({ ageRate = 1.0 }, bottle, now)
    return newItem, newMeta
end

---o[ What the next pass is worth, from the run so far ]o---
local function RhythmMultiplier(streak)
    local conf = Conf()
    return 1.0 + (conf.RhythmStep or 0) * math.min(streak or 0, conf.RhythmMaxSteps or 0)
end

---oo[ Persistence ]oo---

local function SaveCrateToDB(uid, isNew)
    local crate = CrateList[uid]
    if not crate then return end

    exports.oxmysql:execute(isNew and [[
        INSERT INTO gsc_kassippu_crates (uid, owner, coords, heading, bottles, tend_anchor, locked, climate, streak)
        VALUES (:uid, :owner, :coords, :heading, :bottles, :anchor, :locked, :climate, :streak)
    ]] or [[
        UPDATE gsc_kassippu_crates SET
            owner = :owner,
            coords = :coords,
            heading = :heading,
            bottles = :bottles,
            tend_anchor = :anchor,
            locked = :locked,
            climate = :climate,
            streak = :streak
        WHERE uid = :uid
    ]], {
        uid = uid,
        owner = crate.owner,
        coords = json.encode({
            x = Shared.Round(crate.pos.x, 2), y = Shared.Round(crate.pos.y, 2), z = Shared.Round(crate.pos.z, 2),
        }),
        heading = crate.heading or 0.0,
        bottles = json.encode(crate.bottles),
        anchor = crate.anchor or 0,
        locked = crate.locked and 1 or 0,
        climate = crate.climate and json.encode(crate.climate) or '',
        streak = crate.streak or 0,
    })
end

---o[ Everything a client needs to draw one crate ]o---
local function PublicCrate(crate)
    return {
        x = crate.pos.x, y = crate.pos.y, z = crate.pos.z,
        heading = crate.heading or 0.0,
        count = #crate.bottles,
    }
end

local function SyncAllCratesTo(target)
    local list = {}
    for uid, crate in pairs(CrateList) do list[uid] = PublicCrate(crate) end
    TriggerClientEvent('gsc_kassippu:client:syncCrates', target, list)
end

---oo[ The Owner ]oo---

---o[ The owner's server id, if he is on that character right now ]o---
local function OwnerSource(crate)
    if not crate or not crate.owner then return nil end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local Character = src and Shared.GetChar(src)
        if Character and OwnerIdOf(Character) == crate.owner then return src end
    end
    return nil
end

---o[ What the owner's blip should say about this crate ]o---
local function Attention(crate, now)
    if #crate.bottles == 0 then return "idle" end

    if not crate.tendDone then
        local _, isHazard = FindActivity(crate.activity)
        return isHazard and "hazard" or "due"
    end

    local spoil = SpoilSeconds(crate)
    local ready = false

    for _, bottle in ipairs(crate.bottles) do
        if not bottle.soured then
            ---o[ Close to turning, and nothing better to wait for (Outlook has no next tier in time) ]o---
            if AgeSeconds(bottle, now) > spoil * 0.8 then
                local _, nextIn = Outlook(crate, bottle, now)
                if not nextIn then return "turning" end
            end
            if EffectiveTier(crate, bottle, now) == 1 then ready = true end
        end
    end

    return ready and "ready" or "idle"
end

local function MyCrateEntry(crate, state)
    return { x = crate.pos.x, y = crate.pos.y, z = crate.pos.z, state = state }
end

---o[ Re-send the owner's blip when its state changes ]o---
local function PushAttention(uid, crate, now)
    local state = Attention(crate, now)
    if state == crate.attention then return end
    crate.attention = state

    local src = OwnerSource(crate)
    if src then TriggerClientEvent('gsc_kassippu:client:myCrate', src, uid, MyCrateEntry(crate, state)) end
end

---o[ Every crate this character owns, for his map ]o---
local function SyncMyCratesTo(src)
    local Character = Shared.GetChar(src)
    if not Character then return end

    local ownerId = OwnerIdOf(Character)
    local now = os.time()
    local list = {}

    for uid, crate in pairs(CrateList) do
        if crate.owner == ownerId then
            crate.attention = crate.attention or Attention(crate, now)
            list[uid] = MyCrateEntry(crate, crate.attention)
        end
    end

    TriggerClientEvent('gsc_kassippu:client:myCrates', src, list)
end

---o[ Called by GSC.Distillery once the schema exists ]o---
function Crates.LoadCratesFromDB()
    if not Conf() or not Conf().Enabled then return end

    exports.oxmysql:execute('SELECT * FROM gsc_kassippu_crates', {}, function(results, err)
        ---o[ Failed: say so. CratesLoaded stays false, so no crate is set down that the limit could not count ]o---
        if err then
            return print("^1[Error]^7 Could not load aging crates from gsc_kassippu_crates - no crates this session: " .. tostring(err))
        end
        CratesLoaded = true -- from now on a client's own request is answered (requestCrates)
        if not results then return end

        local now = os.time()
        local every = math.max(1, Conf().TendEverySeconds)
        local count = 0

        for _, row in ipairs(results) do
            local coords = row.coords and json.decode(row.coords)
            if coords then
                local bottles = (row.bottles and json.decode(row.bottles)) or {}
                local anchor = tonumber(row.tend_anchor) or 0
                if #bottles == 0 then anchor = 0 end

                for _, bottle in ipairs(bottles) do
                    bottle.id = bottle.id or NewBottleId()
                end

                local climate = nil
                if type(row.climate) == 'string' and row.climate ~= '' then climate = json.decode(row.climate) end
                if type(climate) ~= 'table' then climate = nil end

                local crate = {
                    pos = vector3(coords.x, coords.y, coords.z),
                    heading = tonumber(row.heading) or 0.0,
                    owner = row.owner,
                    bottles = bottles,
                    climate = climate,
                    locked = row.locked == true or tonumber(row.locked) == 1,
                    streak = tonumber(row.streak) or 0,
                    anchor = anchor,
                    tendIndex = anchor > 0 and math.floor((now - anchor) / every) or 0,
                    tendDone = true,
                    activity = nil,
                }
                ApplyClimate(crate)

                CrateList[row.uid] = crate
                count = count + 1
            end
        end

        SyncAllCratesTo(-1)
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            if src then SyncMyCratesTo(src) end
        end

        print("^2[Kassippu]^7 Loaded " .. count .. " aging crates.")
    end, GetCurrentResourceName(), true)
end

---o[ A client asks for every crate itself (its scripts started after the server's load broadcast) ]o---
RegisterServerEvent('gsc_kassippu:server:requestCrates')
AddEventHandler('gsc_kassippu:server:requestCrates', function()
    local _source = source
    if not Conf().Enabled or not CratesLoaded then return end -- the load broadcast is still to come
    local now = os.time()
    if LastCrateRequest[_source] and now - LastCrateRequest[_source] < 15 then return end
    LastCrateRequest[_source] = now
    SyncAllCratesTo(_source)
    SyncMyCratesTo(_source)
end)

AddEventHandler('playerDropped', function()
    LastCrateRequest[source] = nil
end)

AddEventHandler("vorp:SelectedCharacter", function(source)
    local _source = source
    if not Conf().Enabled then return end

    Citizen.SetTimeout(4000, function()
        SyncAllCratesTo(_source)
        SyncMyCratesTo(_source)
    end)
end)

---oo[ Watchers ]oo---
local function SetCrateWatcher(src, uid)
    local previous = WatchedCrate[src]
    if previous and CrateWatchers[previous] then
        CrateWatchers[previous][src] = nil
        if next(CrateWatchers[previous]) == nil then CrateWatchers[previous] = nil end
    end

    WatchedCrate[src] = uid

    if uid then
        local Character = Shared.GetChar(src)
        CrateWatchers[uid] = CrateWatchers[uid] or {}
        CrateWatchers[uid][src] = Character and OwnerIdOf(Character) or false
    end
end

RegisterServerEvent('gsc_kassippu:server:watchCrate')
AddEventHandler('gsc_kassippu:server:watchCrate', function(uid)
    if uid ~= nil and type(uid) ~= 'string' then return end
    SetCrateWatcher(source, uid)
end)

AddEventHandler('playerDropped', function()
    local _source = source
    SetCrateWatcher(_source, nil)
    PickAttempts[_source] = nil
    PickCooldown[_source] = nil
    TendAttempts[_source] = nil
end)

local function NotifyCrateWatchers(uid, text, ms)
    local watchers = CrateWatchers[uid]
    if not watchers or not text then return end

    for src in pairs(watchers) do
        GSC.Notify.Send(src, text, ms or 3000)
    end
end

---o[ Tell the owner, wherever he is ]o---
local function NotifyOwnerAway(uid, text)
    local crate = CrateList[uid]
    if not crate or not Conf().NotifyOwnerAway then return end

    local src = OwnerSource(crate)
    if src and not (CrateWatchers[uid] and CrateWatchers[uid][src] ~= nil) then
        GSC.Notify.Send(src, text, 5000)
    end
end

---o[ The gauge, for whoever is stood at the crate ]o---
local function SyncCrateGauge(uid, now)
    local watchers = CrateWatchers[uid]
    if not watchers then return end

    local crate = CrateList[uid]
    if not crate then return end

    local conf = Conf()
    local spoil = SpoilSeconds(crate)
    local slots, careSum, careCount = {}, 0.0, 0
    local best = nil
    local hazardOpen = false

    if not crate.tendDone then
        local _, isHazard = FindActivity(crate.activity)
        hazardOpen = isHazard
    end

    for i, bottle in ipairs(crate.bottles) do
        local slot = {
            id = bottle.id,
            name = BottleName(bottle),
            grade = Revealed(bottle.meta) and QualityLabel(bottle.quality) or "?", -- untasted: unknown
            care = Shared.Round(bottle.care or 0.0, 1),
            aged = math.floor(AgeSeconds(bottle, now) / 60),
            target = (hazardOpen and bottle.id == crate.target) or nil,
        }

        if bottle.soured then
            slot.sour = true
        else
            local index, tier = EffectiveTier(crate, bottle, now)

            slot.tier = tier and tier.key or nil
            slot.tierLabel = tier and (tier.label or tier.key) or nil
            slot.peak = (index == 1) or nil
            slot.turnsIn = math.max(0, math.floor(spoil - AgeSeconds(bottle, now)))
            slot.progress, slot.nextIn, slot.nextLabel = Outlook(crate, bottle, now)
            slot.turning = (slot.turnsIn < spoil * 0.2 and not slot.nextIn) or nil -- not while a better tier is still coming

            careSum = careSum + (bottle.care or 0.0)
            careCount = careCount + 1

            if index and (not best or index < best) then best = index end
        end

        slots[i] = slot
    end

    local climate = crate.climate or {}
    local gauge = {
        count = #crate.bottles,
        capacity = conf.Capacity,
        slots = slots,
        best = best and (conf.Tiers[best].label or conf.Tiers[best].key) or nil,
        care = careCount > 0 and (careSum / careCount) or nil,
        locked = crate.locked or nil,
        streak = crate.streak or 0,
        rhythm = RhythmMultiplier(crate.streak),
        climate = {
            label = crate.band and crate.band.label or nil,
            temp = climate.temp,
            sheltered = climate.sheltered or nil,
            age = crate.ageRate,
            keep = crate.keepRate,
        },
    }

    if crate.anchor > 0 then
        local every = conf.TendEverySeconds

        if not crate.tendDone then
            local activity = FindActivity(crate.activity)
            gauge.tendDue = true
            gauge.hazard = hazardOpen or nil
            gauge.activity = crate.activity
            gauge.activityLabel = activity and activity.label or crate.activity
            gauge.windowLeft = math.max(0, (crate.closes or now) - now)
        else
            gauge.nextIn = math.max(0, crate.anchor + ((crate.tendIndex + 1) * every) - now)
        end
    end

    for src, ownerId in pairs(watchers) do
        gauge.mine = (ownerId and ownerId == crate.owner) or nil
        TriggerClientEvent('gsc_kassippu:client:crateGauge', src, uid, gauge)
    end
end

local function BroadcastCount(uid)
    local crate = CrateList[uid]
    TriggerClientEvent('gsc_kassippu:client:crateCount', -1, uid, crate and #crate.bottles or 0)
end

---o[ Common front door for every action at a crate ]o---
local function ValidateAtCrate(src, uid)
    if not Conf().Enabled then return nil end

    local Character = Shared.GetChar(src)
    if not Character then return nil end

    local crate = type(uid) == 'string' and CrateList[uid]
    if not crate then
        Shared.Debug("^1[Crate]^7 Unknown crate " .. tostring(uid))
        return nil
    end

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    if #(playerCoords - crate.pos) > ((Conf().InteractRadius or 1.8) + 3.0) then
        Shared.Debug("^1[Warning]^7 Player " .. src .. " tried a crate action from too far away.")
        return nil
    end

    return Character, crate
end

---o[ A locked crate is the owner's alone until the lock is picked ]o---
local function LockedAgainst(Character, crate)
    return LockConf().Enabled and crate.locked and not IsOwner(Character, crate)
end

---o[ An empty crate stops asking for anything ]o---
local function ResetSchedule(crate)
    crate.anchor = 0
    crate.tendIndex = 0
    crate.tendDone = true
    crate.activity = nil
    crate.opened, crate.closes, crate.target = nil, nil, nil
    crate.streak = 0
end

local function CloseWindow(crate)
    crate.tendDone = true
    crate.target = nil
end

---oo[ Placement ]oo---

---o[ The item only starts the ghost - it is taken when the crate is set down ]o---
if Config.CrateAging.Enabled then
    exports.vorp_inventory:registerUsableItem(Config.CrateAging.ItemName, function(data)
        local _source = data.source
        local Character = Shared.GetChar(_source)
        if not Character or not CratesLoaded then return end -- before the load the limit and spot checks see no crates
        if AtCrateLimit(_source, Character) then return end -- don't start a ghost he can't set down

        exports.vorp_inventory:closeInventory(_source)
        TriggerClientEvent('gsc_kassippu:client:startCratePlacement', _source)
    end)
end

---o[ The climate line a player is told, for a placement or a preview ]o---
local function ClimateText(crate)
    local climate = crate.climate or {}
    local band = crate.band
    if not band or not climate.temp then return nil end

    return string.format(Config.Text.CrateClimate, band.label or band.key, math.floor(climate.temp + 0.5),
        climate.sheltered and Config.Text.CrateClimateIndoors or "", crate.ageRate or 1.0, crate.keepRate or 1.0)
end

RegisterServerEvent('gsc_kassippu:server:placeCrate')
AddEventHandler('gsc_kassippu:server:placeCrate', function(coords, heading, climate)
    local _source = source
    local conf = Conf()
    if not conf.Enabled or not CratesLoaded then return end -- before the load the limit and spot checks see no crates

    local Character = Shared.GetChar(_source)
    if not Character or type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end

    local pos = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    if #(GetEntityCoords(GetPlayerPed(_source)) - pos) > 6.0 then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to place a crate from too far away.")
        return
    end

    ---o[ One crate per spot ]o---
    for _, other in pairs(CrateList) do
        if #(other.pos - pos) < 1.0 then
            return GSC.Notify.SendObjective(_source, Config.Text.CrateTooClose, 3000)
        end
    end

    ---o[ Checked again here: the item check above is only a courtesy, this is the one a client can't skip ]o---
    if AtCrateLimit(_source, Character) then return end

    if exports.vorp_inventory:getItemCount(_source, nil, conf.ItemName) < 1 then return end
    if not exports.vorp_inventory:subItem(_source, conf.ItemName, 1) then return end -- not taken: no crate

    local temp = type(climate) == 'table' and tonumber(climate.temp) or nil
    if temp then temp = math.max(-40.0, math.min(60.0, temp)) end

    local uid = Shared.GenerateCrateUID(pos)
    local crate = {
        pos = pos,
        heading = tonumber(heading) or 0.0,
        owner = OwnerIdOf(Character),
        bottles = {},
        climate = temp and { temp = Shared.Round(temp, 1), sheltered = climate.sheltered == true } or nil,
        locked = (LockConf().Enabled and LockConf().LockOnPlace) or false,
        streak = 0,
        anchor = 0,
        tendIndex = 0,
        tendDone = true,
        activity = nil,
    }
    ApplyClimate(crate)
    crate.attention = "idle"
    CrateList[uid] = crate

    SaveCrateToDB(uid, true)
    TriggerClientEvent('gsc_kassippu:client:crateAdded', -1, uid, PublicCrate(crate))
    TriggerClientEvent('gsc_kassippu:client:myCrate', _source, uid, MyCrateEntry(crate, crate.attention))

    local climateLine = ClimateText(crate)
    GSC.Notify.SendObjective(_source, Config.Text.CratePlaced .. (climateLine and (" " .. climateLine) or ""), 6000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "place_crate") -- the shared set-down animation (Config.AnimConf.Actions)

    Shared.Debug(string.format("^2[Crate]^7 (ID: %s) %s placed %s (%s)", _source, Character.firstname, uid,
        crate.band and crate.band.key or "no climate"))
end)

---o[ Pick an empty crate back up ]o---
RegisterServerEvent('gsc_kassippu:server:pickupCrate')
AddEventHandler('gsc_kassippu:server:pickupCrate', function(uid)
    local _source = source
    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character then return end

    if #crate.bottles > 0 then
        return GSC.Notify.Send(_source, Config.Text.CratePickupNotEmpty, 3000)
    end

    if (Conf().PickupOwnerOnly or LockedAgainst(Character, crate)) and not IsOwner(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateNotYours, 3000)
    end

    if not exports.vorp_inventory:canCarryItem(_source, Conf().ItemName, 1) then
        return GSC.Notify.Send(_source, Config.Text.CratePocketsFull, 3000)
    end

    local ownerSrc = OwnerSource(crate)

    CrateList[uid] = nil
    CrateWatchers[uid] = nil
    exports.oxmysql:execute('DELETE FROM gsc_kassippu_crates WHERE uid = ?', { uid })

    exports.vorp_inventory:addItem(_source, Conf().ItemName, 1)
    TriggerClientEvent('gsc_kassippu:client:crateRemoved', -1, uid)
    if ownerSrc then TriggerClientEvent('gsc_kassippu:client:myCrate', ownerSrc, uid, nil) end
    GSC.Notify.Send(_source, Config.Text.CratePickedUp, 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "pickup")
end)

---oo[ Bottles In And Out ]oo---

---o[ Lay one bottle down ]o---
RegisterServerEvent('gsc_kassippu:server:storeCrateBottle')
AddEventHandler('gsc_kassippu:server:storeCrateBottle', function(uid)
    local _source = source
    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character then return end

    if LockedAgainst(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateIsLocked, 3000)
    end

    local conf = Conf()
    if #crate.bottles >= conf.Capacity then
        return GSC.Notify.Send(_source, Config.Text.CrateFull, 3000)
    end

    local chosen, chosenRecipe, chosenQuality = nil, nil, nil

    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(_source) or {}) do
        if (tonumber(item.count) or 0) > 0 then
            local recipeKey, quality = ResolveFreshBottle(item)
            if recipeKey and (not chosen or (TIER_ORDER[quality] or 0) > (TIER_ORDER[chosenQuality] or 0)) then
                chosen, chosenRecipe, chosenQuality = item, recipeKey, quality
            end
        end
    end

    if not chosen then
        return GSC.Notify.Send(_source, Config.Text.CrateNoBottle, 3000)
    end

    -- not taken from the satchel: it must not be laid down too (that would be a copy)
    if not exports.vorp_inventory:subItemById(_source, chosen.id, nil, nil, 1) then
        return GSC.Notify.Send(_source, Config.Text.CrateNoBottle, 3000)
    end

    local now = os.time()

    if #crate.bottles == 0 then
        ResetSchedule(crate)
        crate.anchor = now
    end

    crate.bottles[#crate.bottles + 1] = {
        id = NewBottleId(),
        item = chosen.name,
        recipe = chosenRecipe,
        quality = chosenQuality,
        stored = now,
        care = 0.0,
        meta = chosen.metadata,
    }

    SaveCrateToDB(uid)
    BroadcastCount(uid)
    SyncCrateGauge(uid, now)

    TriggerClientEvent('gsc_kassippu:client:crateAction', _source, uid, "bottle")
    GSC.Notify.Send(_source, string.format(Config.Text.CrateStored,
        ((chosen.metadata or {}).productLabel or RecipeLabel(chosenRecipe, chosen.name))
            .. (Revealed(chosen.metadata) and (" (" .. QualityLabel(chosenQuality) .. ")") or ""), -- untasted: no grade
        #crate.bottles, conf.Capacity), 4000)

    Shared.Debug(string.format("^5[Crate]^7 (ID: %s) %s laid down %s/%s in %s",
        _source, Character.firstname, chosenRecipe, chosenQuality, uid))
end)

---o[ Take one bottle out ]o---
RegisterServerEvent('gsc_kassippu:server:takeCrateBottle')
AddEventHandler('gsc_kassippu:server:takeCrateBottle', function(uid, bottleId)
    local _source = source
    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character then return end

    if #crate.bottles == 0 then
        return GSC.Notify.Send(_source, Config.Text.CrateEmpty, 3000)
    end

    if LockedAgainst(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateIsLocked, 3000)
    end

    if Conf().TakeOwnerOnly and not IsOwner(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateNotYours, 3000)
    end

    local index = nil
    if bottleId ~= nil then
        for i, bottle in ipairs(crate.bottles) do
            if bottle.id == bottleId then index = i end
        end

        if not index then
            return GSC.Notify.Send(_source, Config.Text.CrateBottleGone, 3000)
        end
    else
        index = 1
        for i, bottle in ipairs(crate.bottles) do
            if (bottle.stored or 0) < (crate.bottles[index].stored or 0) then index = i end
        end
    end

    local now = os.time()
    local bottle = crate.bottles[index]
    local itemName, metadata, message = ResolveTakenBottle(crate, bottle, now)

    if not exports.vorp_inventory:canCarryItem(_source, itemName, 1) then
        return GSC.Notify.Send(_source, Config.Text.CratePocketsFull, 3000)
    end

    table.remove(crate.bottles, index)
    if #crate.bottles == 0 then ResetSchedule(crate) end

    exports.vorp_inventory:addItem(_source, itemName, 1, metadata)

    SaveCrateToDB(uid)
    BroadcastCount(uid)
    SyncCrateGauge(uid, now)

    TriggerClientEvent('gsc_kassippu:client:crateAction', _source, uid, "bottle")
    GSC.Notify.Send(_source, message, 4000)

    Shared.Debug(string.format("^5[Crate]^7 (ID: %s) %s took %s out of %s",
        _source, Character.firstname, itemName, uid))

    ---o[ Out of someone else's crate: for the staff log ]o---
    if not IsOwner(Character, crate) then
        GSC.Logs.Send("theft", (Config.Text.Logs or {}).CrateTaken, {
            { name = GSC.Logs.Label("Who"), value = GSC.Logs.Player(_source), raw = true },
            { name = GSC.Logs.Label("Crate"), value = uid, inline = true },
            { name = GSC.Logs.Label("Item"), value = (metadata and metadata.label) or itemName, inline = true },
            { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(crate.owner), raw = true },
            { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(crate.pos), inline = true },
        })
    end
end)

---oo[ Activities ]oo---

---o[ Mark every bottle that was in the crate when the window opened ]o---
local function ApplyCare(crate, amount, targetAmount)
    local conf = Conf()
    local openedAt = crate.opened or 0

    for _, bottle in ipairs(crate.bottles) do
        if not bottle.soured and (bottle.stored or 0) <= openedAt then
            local delta = amount
            if targetAmount and bottle.id == crate.target then delta = delta + targetAmount end
            bottle.care = math.max(conf.CareMin, math.min(conf.CareMax, (bottle.care or 0.0) + delta))
        end
    end
end

---o[ Open the next window: a routine activity, or now and then a hazard ]o---
local function OpenWindow(crate, now)
    local conf = Conf()
    local hazards = conf.Hazards or {}
    local activities = conf.Activities or {}

    ---o[ Bottles that can still gain: not turned and not yet at the richest tier ]o---
    local candidates = {}
    for _, bottle in ipairs(crate.bottles) do
        if not bottle.soured and EffectiveTier(crate, bottle, now) ~= 1 then candidates[#candidates + 1] = bottle end
    end

    ---o[ Nothing left to gain: skip this check (no job, no hazard), the clock moves on ]o---
    if #candidates == 0 then
        crate.tendIndex = crate.tendIndex + 1
        return nil
    end

    local entry, isHazard = nil, false
    if #hazards > 0 and #candidates > 0 and math.random() < (conf.HazardChance or 0) then
        entry, isHazard = PickWeighted(hazards), true
    elseif #activities > 0 then
        entry = PickWeighted(activities)
    end
    if not entry then return nil end

    crate.tendIndex = crate.tendIndex + 1
    crate.tendDone = false
    crate.activity = entry.key
    crate.opened = now
    crate.closes = now + (entry.window or conf.TendWindowSeconds)
    crate.target = isHazard and candidates[math.random(#candidates)].id or nil

    return entry, isHazard
end

---o[ The player starts on the job: the server times the game from here ]o---
RegisterServerEvent('gsc_kassippu:server:startTendCrate')
AddEventHandler('gsc_kassippu:server:startTendCrate', function(uid)
    local _source = source
    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character then return end

    if crate.tendDone or crate.anchor <= 0 then
        return GSC.Notify.Send(_source, Config.Text.CrateTendNotDue, 3000)
    end

    ---o[ A locked crate's jobs are the owner's ]o---
    if LockedAgainst(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateIsLocked, 3000)
    end

    ---o[ Spam guard: one start for this window every 2 s ]o---
    local nowMs = GetGameTimer()
    local pending = TendAttempts[_source]
    if pending and pending.uid == uid and pending.opened == crate.opened and nowMs - pending.started < 2000 then return end

    TendAttempts[_source] = { uid = uid, opened = crate.opened, started = nowMs }
    TriggerClientEvent('gsc_kassippu:client:crateRunActivity', _source, uid, crate.activity)
end)

---o[ The player answered the crate ]o---
RegisterServerEvent('gsc_kassippu:server:tendCrate')
AddEventHandler('gsc_kassippu:server:tendCrate', function(uid, activityKey, passed)
    local _source = source
    local attempt = TendAttempts[_source]
    TendAttempts[_source] = nil

    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character then return end

    if crate.tendDone or crate.anchor <= 0 then
        return GSC.Notify.Send(_source, Config.Text.CrateTendNotDue, 3000)
    end

    if activityKey ~= crate.activity then return end

    ---o[ Only a game the server started, for this window ]o---
    if not attempt or attempt.uid ~= uid or attempt.opened ~= crate.opened then return end

    if LockedAgainst(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateIsLocked, 3000)
    end

    local conf = Conf()

    ---o[ Sooner than a real game can be won: it counts as failed ]o---
    local took = (GetGameTimer() - attempt.started) / 1000.0
    if passed == true and took < (conf.TendMinSeconds or 0) then
        Shared.Debug(string.format("^1[Crate]^7 (ID: %s) job result after %.2fs - too fast, counted as failed", _source, took))
        passed = false
    end

    local activity, isHazard = FindActivity(crate.activity)
    local label = activity and activity.label or crate.activity
    local now = os.time()

    if passed == true then
        ---o[ Some activities cost something ]o---
        if activity and activity.item then
            if exports.vorp_inventory:getItemCount(_source, nil, activity.item) < 1
                or not exports.vorp_inventory:subItem(_source, activity.item, 1) then
                return GSC.Notify.Send(_source,
                    string.format(Config.Text.CrateTendNeedsItem, activity.item), 4000)
            end
        end

        local rhythm = RhythmMultiplier(crate.streak)
        local bonus = ((activity and activity.bonus) or conf.PassBonus) * rhythm

        ApplyCare(crate, bonus, isHazard and (activity.targetBonus or 0) or nil)
        crate.streak = (crate.streak or 0) + 1

        local text = string.format(isHazard and Config.Text.CrateHazardPassed or Config.Text.CrateTendPassed, label)
        if rhythm > 1.0 then text = text .. string.format(Config.Text.CrateRhythm, rhythm) end

        TriggerClientEvent('gsc_kassippu:client:crateAction', _source, uid, "activity", crate.activity)
        GSC.Notify.Send(_source, text, 4000)
    else
        ApplyCare(crate, -conf.FailPenalty, isHazard and -(activity.failTarget or 0) or nil)
        crate.streak = 0
        GSC.Notify.Send(_source, isHazard and Config.Text.CrateHazardFailed or Config.Text.CrateTendFailed, 4000)
    end

    CloseWindow(crate)

    Shared.Debug(string.format("^5[Crate]^7 (ID: %s) %s %s %s at %s",
        _source, Character.firstname, passed and "passed" or "failed", tostring(crate.activity), uid))

    SaveCrateToDB(uid)
    PushAttention(uid, crate, now)
    SyncCrateGauge(uid, now)
end)

---oo[ The Lock ]oo---

---o[ The owner locks or unlocks his crate ]o---
RegisterServerEvent('gsc_kassippu:server:toggleCrateLock')
AddEventHandler('gsc_kassippu:server:toggleCrateLock', function(uid)
    local _source = source
    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character or not LockConf().Enabled then return end

    if not IsOwner(Character, crate) then
        return GSC.Notify.Send(_source, Config.Text.CrateNotYours, 3000)
    end

    crate.locked = not crate.locked
    SaveCrateToDB(uid)

    TriggerClientEvent('gsc_kassippu:client:crateAction', _source, uid, "lock")
    GSC.Notify.Send(_source, crate.locked and Config.Text.CrateLocked or Config.Text.CrateUnlocked, 3000)
    SyncCrateGauge(uid, os.time())
end)

---o[ Someone else starts on the lock ]o---
RegisterServerEvent('gsc_kassippu:server:pickCrateLock')
AddEventHandler('gsc_kassippu:server:pickCrateLock', function(uid)
    local _source = source
    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character then return end

    local lock = LockConf()
    if not lock.Enabled or not crate.locked or IsOwner(Character, crate) then return end

    local now = os.time()

    local pending = PickAttempts[_source]
    if pending and now - pending.started < 60 then return end

    if (PickCooldown[_source] or 0) > now then
        return GSC.Notify.Send(_source,
            string.format(Config.Text.CratePickCooldown, PickCooldown[_source] - now), 3000)
    end

    if lock.PickItem and exports.vorp_inventory:getItemCount(_source, nil, lock.PickItem) < 1 then
        return GSC.Notify.Send(_source, string.format(Config.Text.CratePickNeedsItem, lock.PickItem), 3000)
    end

    PickAttempts[_source] = { uid = uid, started = now, startedMs = GetGameTimer() }
    TriggerClientEvent('gsc_kassippu:client:crateLockpick', _source, uid)

    local ownerSrc = OwnerSource(crate)
    if ownerSrc and ownerSrc ~= _source then
        GSC.Notify.Send(ownerSrc, Config.Text.CrateLockTampered, 6000)
    end

    Shared.Debug(string.format("^3[Crate]^7 (ID: %s) %s is picking the lock on %s", _source, Character.firstname, uid))
end)

---o[ ...and how it went ]o---
RegisterServerEvent('gsc_kassippu:server:pickCrateLockResult')
AddEventHandler('gsc_kassippu:server:pickCrateLockResult', function(uid, passed)
    local _source = source
    local attempt = PickAttempts[_source]
    PickAttempts[_source] = nil
    if not attempt or attempt.uid ~= uid then return end

    local lock = LockConf()
    local now = os.time()
    PickCooldown[_source] = now + (lock.PickCooldownSeconds or 0)

    if now - attempt.started > 60 then return end

    local Character, crate = ValidateAtCrate(_source, uid)
    if not Character or not crate.locked then return end

    ---o[ Sooner than a real game can be won: it counts as failed ]o---
    local took = (GetGameTimer() - (attempt.startedMs or 0)) / 1000.0
    if passed == true and took < (lock.PickMinSeconds or 0) then
        Shared.Debug(string.format("^1[Crate]^7 (ID: %s) lock picked after %.2fs - too fast, counted as failed", _source, took))
        passed = false
    end

    local function LogPick(title)
        GSC.Logs.Send("lockpick", title, {
            { name = GSC.Logs.Label("Who"), value = GSC.Logs.Player(_source), raw = true },
            { name = GSC.Logs.Label("Crate"), value = uid, inline = true },
            { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(crate.owner), raw = true },
            { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(crate.pos), inline = true },
        })
    end
    local L = Config.Text.Logs or {}

    if passed == true then
        if lock.PickItem and lock.PickConsumeOnSuccess then exports.vorp_inventory:subItem(_source, lock.PickItem, 1) end

        crate.locked = false
        SaveCrateToDB(uid)
        SyncCrateGauge(uid, now)

        GSC.Notify.Send(_source, Config.Text.CratePickSuccess, 4000)

        local ownerSrc = OwnerSource(crate)
        if ownerSrc and ownerSrc ~= _source then
            GSC.Notify.Send(ownerSrc, Config.Text.CrateLockPicked, 8000)
        end

        Shared.Debug(string.format("^1[Crate]^7 (ID: %s) %s picked the lock on %s", _source, Character.firstname, uid))
        LogPick(L.LockPicked)
    elseif lock.PickItem and math.random() < (lock.PickBreakChance or 0)
        and exports.vorp_inventory:getItemCount(_source, nil, lock.PickItem) > 0 then
        exports.vorp_inventory:subItem(_source, lock.PickItem, 1)
        GSC.Notify.Send(_source, Config.Text.CratePickBroke, 4000)
        LogPick(L.LockBroke)
    else
        GSC.Notify.Send(_source, Config.Text.CratePickFailed, 4000)
        LogPick(L.LockFailed)
    end
end)

---oo[ The Crate Clock ]oo---
---o[ For GSC.Upkeep: who owns a crate, and taking away an owner's crates (he has been gone too long) ]o---
function Crates.Owners()
    local owners = {}
    for _, crate in pairs(CrateList) do
        if crate.owner then owners[crate.owner] = (owners[crate.owner] or 0) + 1 end
    end
    return owners
end

function Crates.ExpireOwner(owner)
    local removed = 0
    for uid, crate in pairs(CrateList) do
        if crate.owner == owner then
            CrateList[uid] = nil
            CrateWatchers[uid] = nil
            exports.oxmysql:execute('DELETE FROM gsc_kassippu_crates WHERE uid = ?', { uid })
            TriggerClientEvent('gsc_kassippu:client:crateRemoved', -1, uid)
            removed = removed + 1
        end
    end
    return removed
end

-- A crate nobody stands at is ticked this often (sec): tiers and souring move in minutes, and 360 crates
-- x 12 bottles every second was the heaviest work on the server thread
local QUIET_TICK = 5

local function TickCrate(uid, crate, now)
    local conf = Conf()
    local changed = false

    if #crate.bottles > 0 and crate.anchor > 0 then
        ---o[ Has the open window run out? ]o---
        if not crate.tendDone and now >= (crate.closes or 0) then
            local activity, isHazard = FindActivity(crate.activity)
            ApplyCare(crate, -conf.MissPenalty, isHazard and -(activity.missTarget or 0) or nil)
            crate.streak = 0

            local broken = nil
            if isHazard and activity.breakOnMiss and crate.target then
                for i, bottle in ipairs(crate.bottles) do
                    if bottle.id == crate.target then
                        broken = table.remove(crate.bottles, i)
                        break
                    end
                end
            end

            CloseWindow(crate)
            changed = true

            if broken then
                local text = string.format(Config.Text.CrateHazardBroke, RecipeLabel(broken.recipe, broken.item))
                NotifyCrateWatchers(uid, text, 6000)
                NotifyOwnerAway(uid, text)
                BroadcastCount(uid)
            else
                NotifyCrateWatchers(uid, Config.Text.CrateTendMissed, 4000)
            end

            Shared.Debug("^3[Crate]^7 " .. uid .. " missed " .. tostring(crate.activity)
                .. (broken and " and lost a bottle" or ""))
        end

        if #crate.bottles == 0 then
            ResetSchedule(crate)
        else
            ---o[ Time for the next one? ]o---
            if crate.tendDone and now - crate.anchor >= ((crate.tendIndex + 1) * conf.TendEverySeconds) then
                local entry, isHazard = OpenWindow(crate, now)

                if entry then
                    NotifyCrateWatchers(uid, entry.due or entry.label, 5000)
                    NotifyOwnerAway(uid, string.format(
                        isHazard and Config.Text.CrateHazardAway or Config.Text.CrateTendDueAway, entry.label))
                end
            end

            ---o[ Tiers reached, and bottles turned ]o---
            local spoil = SpoilSeconds(crate)
            local reached, soured = {}, 0

            for _, bottle in ipairs(crate.bottles) do
                if not bottle.soured then
                    if AgeSeconds(bottle, now) >= spoil then
                        bottle.soured = true
                        soured = soured + 1
                        changed = true
                    else
                        local index, tier = EffectiveTier(crate, bottle, now)
                        local lastIndex = TierIndexByKey(bottle.tier)

                        ---o[ Keep the richest tier reached (saved with the bottles JSON) ]o---
                        -- EffectiveTier never goes below bottle.best, so a different key here is always a step up
                        if tier and bottle.best ~= tier.key then
                            bottle.best = tier.key
                            changed = true
                        end

                        if tier and bottle.tier ~= tier.key then
                            if not lastIndex or index < lastIndex then
                                local label = tier.label or tier.key
                                reached[label] = (reached[label] or 0) + 1
                            end
                            bottle.tier = tier.key
                            changed = true
                        end
                    end
                end
            end

            for label, n in pairs(reached) do
                NotifyCrateWatchers(uid, string.format(Config.Text.CrateTierReached, n, label), 4000)
            end

            if soured > 0 then
                NotifyCrateWatchers(uid, string.format(Config.Text.CrateSoured, soured), 6000)
                Shared.Debug(string.format("^1[Crate]^7 %d bottle(s) turned in %s", soured, uid))
            end
        end
    end

    if changed then SaveCrateToDB(uid) end
    PushAttention(uid, crate, now)
    SyncCrateGauge(uid, now)
end

Citizen.CreateThread(function()
    while true do
        if not Conf().Enabled or next(CrateList) == nil then
            Wait(5000)
        else
            Wait(1000)
            local now = os.time()
            for uid, crate in pairs(CrateList) do
                ---o[ Watched: every second (its card counts down). The rest: every QUIET_TICK s, spread over those seconds ]o---
                if not crate.nextTick then crate.nextTick = now + math.random(0, QUIET_TICK - 1) end
                if CrateWatchers[uid] or now >= crate.nextTick then
                    crate.nextTick = now + QUIET_TICK
                    TickCrate(uid, crate, now)
                end
            end
        end
    end
end)
