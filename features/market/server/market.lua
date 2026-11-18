local Market = GSC.module('Market')

---oo[ The Market: buyers who pay for what you brew (Config.Market) ]oo---

local Sessions = {}
local LastSale = {}  -- [src] = os.time() of the last sale
local LastAsk = {}
local Trust = {}
local Demand = {}    -- [buyer id] = { sold, since }
local CampIndex = nil -- the travelling buyer's camp

local function Conf()
    return Config.Market or {}
end

local function T()
    return (Config.Text or {}).Market or {}
end

local function Round2(x)
    return math.floor(x * 100 + 0.5) / 100
end

---oo[ The buyers ]oo---

---o[ Every buyer by id ]o---
function Market.Buyer(id)
    local conf = Conf()
    if id == "traveller" then
        local tr = conf.Traveller or {}
        local camp = tr.Enabled and CampIndex and (tr.Camps or {})[CampIndex]
        if not camp then return nil end
        return { id = id, name = tr.Name, coords = camp.coords, rate = tr.Rate or 1.0, hours = tr.Hours, camp = camp }
    end
    if type(id) ~= 'string' or id:sub(1, 7) ~= "saloon:" then return nil end
    local key = id:sub(8)
    for _, s in ipairs(conf.Saloons or {}) do
        if s.id == key then
            return { id = id, name = s.name, coords = s.coords, rate = conf.SaloonRate or 1.0, hours = s.hours, saloon = true }
        end
    end
    return nil
end

---o[ Is he dealing at this game hour? (no hour known yet: yes) ]o---
local function IsOpen(buyer)
    local h = buyer.hours
    if not h then return true end
    local hour = GSC.Law and GSC.Law.Hour and GSC.Law.Hour()
    if not hour then return true end
    if h.from <= h.to then return hour >= h.from and hour < h.to end
    return hour >= h.from or hour < h.to -- across midnight
end

local function Near(src, buyer)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - buyer.coords) <= (Conf().SellDistance or 4.0)
end

---o[ The travelling buyer moves on ]o---
function Market.MoveTraveller()
    local camps = ((Conf().Traveller or {}).Camps) or {}
    if #camps == 0 then CampIndex = nil return nil end
    local nextIndex = math.random(#camps)
    if #camps > 1 then
        while nextIndex == CampIndex do nextIndex = math.random(#camps) end
    end
    CampIndex = nextIndex
    TriggerClientEvent('gsc_kassippu:client:buyerCamp', -1, CampIndex)
    Shared.Debug("^6[Market]^7 The travelling buyer moved to " .. tostring(camps[CampIndex].name))
    return camps[CampIndex]
end

function Market.CampIndex()
    return CampIndex
end

---oo[ Demand: each buyer takes so many bottles per restock ]oo---
local function DemandOf(buyerId, now)
    local conf = Conf()
    local d = Demand[buyerId]
    if not d or (now - d.since) >= (conf.RestockMinutes or 60) * 60 then
        d = { sold = 0, since = now }
        Demand[buyerId] = d
    end
    return d
end

---o[ The share of the price for the n-th bottle this period ]o---
function Market.DemandRate(n)
    local conf = Conf()
    return math.max(conf.DemandFloor or 0.6, 1 - (conf.DemandDrop or 0.02) * n)
end

---oo[ Trust ]oo---

local function Today()
    return os.date("%Y%m%d")
end

function Market.TrustRate(trust)
    local t = Conf().Trust or {}
    local low, high = t.LowRate or 0.8, t.HighRate or 1.2
    return low + (high - low) * math.max(0, math.min(100, trust)) / 100
end

---o[ A character's trust record, from the cache or the database ]o---
local function LoadTrust(charid, cb)
    if Trust[charid] then return cb(Trust[charid]) end
    exports.oxmysql:execute('SELECT trust, sold, updated FROM gsc_kassippu_trust WHERE charid = ?', { charid }, function(rows, err)
        ---o[ Failed ]o---
        if err then return print("^1[Error]^7 Could not read buyer trust from gsc_kassippu_trust: " .. tostring(err)) end
        local row = rows and rows[1]
        Trust[charid] = Trust[charid] or {
            trust = row and tonumber(row.trust) or ((Conf().Trust or {}).Start or 50),
            sold = row and tonumber(row.sold) or 0,
            updated = row and tonumber(row.updated) or os.time(),
            day = Today(),
            gained = 0,
        }
        cb(Trust[charid])
    end, GetCurrentResourceName(), true)
end

local function SaveTrust(charid, rec)
    exports.oxmysql:execute(
        'INSERT INTO gsc_kassippu_trust (charid, trust, sold, updated) VALUES (?, ?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE trust = VALUES(trust), sold = VALUES(sold), updated = VALUES(updated)',
        { charid, math.floor(rec.trust + 0.5), rec.sold, os.time() })
end

---o[ Below the starting trust it creeps back with time, from when it was last saved ]o---
function Market.Recover(rec, now)
    local t = Conf().Trust or {}
    local start = t.Start or 50
    if rec.trust < start and (t.RecoverPerHour or 0) > 0 then
        local hours = math.max(0, (now - (rec.updated or now)) / 3600)
        rec.trust = math.min(start, rec.trust + hours * t.RecoverPerHour)
    end
    rec.updated = now
    return rec
end

---o[ After a sale ]o---
function Market.ApplyTrust(rec, bottles, sickBottles)
    local t = Conf().Trust or {}
    if rec.day ~= Today() then rec.day, rec.gained = Today(), 0 end
    rec.sold = (rec.sold or 0) + bottles
    if sickBottles > 0 then
        rec.trust = math.max(0, rec.trust - (t.TaintedHit or 8) * sickBottles)
    else
        local gain = math.max(0, math.min(t.PerSale or 2, (t.DailyGain or 10) - rec.gained))
        rec.trust = math.min(100, rec.trust + gain)
        rec.gained = rec.gained + gain
    end
    return rec
end

---oo[ The price of one bottle of a stack, or nil if he won't take it ]oo---

local function TierLabel(key)
    for _, tier in ipairs((Config.CrateAging or {}).Tiers or {}) do
        if tier.key == key then return tier.label or key end
    end
    return key
end

local function GradeLabel(quality)
    local q = ((Config.Product or {}).Qualities or {})[quality or ""]
    return q and q.label or tostring(quality)
end

local function Hiding()
    local t = Config.Tasting
    return t and t.Enabled and t.HideUntasted
end

---o[ unit = everything but demand ]o---
function Market.Offer(item, buyer, trust)
    local conf = Conf()
    local meta = item.metadata or {}
    local tm = T().Tags or {}

    local recipeKey, quality, soured = nil, nil, meta.soured == true
    if soured then
        recipeKey, quality = Shared.RecipeKey(meta.recipe), "NORMAL"
        if (conf.SouredRate or 0) <= 0 then return nil end
    else
        recipeKey, quality = GSC.Crates.BottleRecipe(item)
    end
    if not recipeKey or not Config.Recipes[recipeKey] then return nil end

    local known = not Hiding() or meta.tasted == true
    local tags = {}
    local price = (conf.Base or {})[recipeKey] or conf.DefaultBase or 4.0

    local strength = meta.strength and GSC.Mash.Strength(recipeKey, meta.strength)
    if strength then
        price = price * ((conf.Strength or {})[strength.key] or 1.0)
        tags[#tags + 1] = strength.proof and string.format(tm.Proof or "%d proof", strength.proof) or strength.label
    end

    if soured then
        price = price * ((conf.Grade or {}).NORMAL or 1.0) -- turned: worth the same tasted or not
    elseif known then
        price = price * ((conf.Grade or {})[quality] or 1.0)
        tags[#tags + 1] = GradeLabel(quality)
    else
        price = price * ((conf.Grade or {})[conf.UntastedAs or "GOOD"] or 1.0) * (conf.UntastedRate or 1.0)
        tags[#tags + 1] = tm.Untasted
    end

    if meta.aged and not soured then
        price = price * ((conf.Aged or {})[meta.aged] or 1.0)
        tags[#tags + 1] = string.format(tm.Aged or "aged: %s", TierLabel(meta.aged))
    end

    local hiddenTaint = false
    if soured then
        price = price * conf.SouredRate
        tags[#tags + 1] = tm.Soured
    elseif meta.tainted and known then
        price = price * (conf.TaintedKnownRate or 0.4)
        tags[#tags + 1] = tm.Tainted
    elseif meta.tainted then
        hiddenTaint = true
    end
    if known and meta.tasted and not soured then tags[#tags + 1] = tm.Tasted end

    price = price * Market.TrustRate(trust) * (buyer.rate or 1.0)
    return { unit = price, tags = tags, hiddenTaint = hiddenTaint, recipe = recipeKey }
end

---o[ What n bottles of one stack fetch, starting at the n-th bottle the buyer has bought ]o---
function Market.LineTotal(unit, startAt, qty)
    local total = 0
    for i = 0, qty - 1 do total = total + Round2(unit * Market.DemandRate(startAt + i)) end
    return Round2(total)
end

---oo[ The ledger ]oo---

local function Rows(src, buyer, trust)
    local rows = {}
    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
        local count = tonumber(item.count) or 0
        if count > 0 and #rows < (Conf().MaxLines or 20) then
            local offer = Market.Offer(item, buyer, trust)
            if offer then
                local meta = item.metadata or {}
                rows[#rows + 1] = {
                    id = item.id,
                    label = meta.label or meta.productLabel or GSC.Mash.ProductLabel(offer.recipe, meta.strength),
                    count = count,
                    unit = Round2(offer.unit),
                    tags = offer.tags,
                }
            end
        end
    end
    return rows
end

RegisterServerEvent('gsc_kassippu:server:buyerOpen')
AddEventHandler('gsc_kassippu:server:buyerOpen', function(buyerId)
    local _source = source
    local conf = Conf()
    if not conf.Enabled then return end
    local Character = Shared.GetChar(_source)
    if not Character then return end

    local buyer = Market.Buyer(buyerId)
    if not buyer or not Near(_source, buyer) then return end
    local t = T()
    if not IsOpen(buyer) then
        return GSC.Notify.Send(_source, string.format(t.Closed, buyer.hours.from, buyer.hours.to), 4000)
    end

    LoadTrust(Shared.CharId(Character), function(rec)
        Market.Recover(rec, os.time())
        if (rec.trust or 0) < ((conf.Trust or {}).RefuseBelow or 15) then
            return GSC.Notify.Send(_source, t.Refuse, 5000, "warning")
        end

        local now = os.time()
        local d = DemandOf(buyer.id, now)
        local rows = Rows(_source, buyer, rec.trust)
        if #rows == 0 then return GSC.Notify.Send(_source, t.None, 4000) end

        local rumour = nil
        if buyer.saloon then
            local camp = Market.Buyer("traveller")
            rumour = camp and string.format(t.Rumour, camp.camp.name) or t.NoRumour
        end

        Sessions[_source] = { buyer = buyer.id, at = now }
        TriggerClientEvent('gsc_kassippu:client:buyerLedger', _source, {
            buyer = buyer.id,
            name = buyer.name,
            trust = math.floor(rec.trust + 0.5),
            rows = rows,
            left = math.max(0, (conf.Demand or 24) - d.sold),
            soldBefore = d.sold,
            drop = conf.DemandDrop or 0.02,
            floor = conf.DemandFloor or 0.6,
            rumour = rumour,
        })
    end)
end)

RegisterServerEvent('gsc_kassippu:server:buyerClose')
AddEventHandler('gsc_kassippu:server:buyerClose', function()
    Sessions[source] = nil
end)

---o[ The lines the client sent ]o---
function Market.CleanLines(lines)
    if type(lines) ~= 'table' then return nil end
    local out, seen = {}, {}
    for i, line in ipairs(lines) do
        if i > (Conf().MaxLines or 20) then break end
        local id, qty = type(line) == 'table' and line.id, type(line) == 'table' and tonumber(line.qty)
        if (type(id) == 'number' or type(id) == 'string') and qty and qty >= 1 and qty <= 1000
            and qty == math.floor(qty) and not seen[id] then
            seen[id] = true
            out[#out + 1] = { id = id, qty = qty }
        end
    end
    return #out > 0 and out or nil
end

RegisterServerEvent('gsc_kassippu:server:buyerSell')
AddEventHandler('gsc_kassippu:server:buyerSell', function(buyerId, lines)
    local _source = source
    local conf = Conf()
    local session = Sessions[_source]
    if not session or session.buyer ~= buyerId then return end -- only the ledger the server opened
    local now = os.time()
    if now - session.at > (conf.SessionSeconds or 180) then Sessions[_source] = nil return end
    if LastSale[_source] and now - LastSale[_source] < 2 then return end
    LastSale[_source] = now

    local Character = Shared.GetChar(_source)
    local buyer = Market.Buyer(buyerId)
    if not Character or not buyer or not IsOpen(buyer) or not Near(_source, buyer) then return end
    local clean = Market.CleanLines(lines)
    if not clean then return end

    local charid = Shared.CharId(Character)
    local rec = Trust[charid]
    if not rec or rec.trust < ((conf.Trust or {}).RefuseBelow or 15) then return end
    Sessions[_source] = nil

    local stacks = {}
    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(_source) or {}) do stacks[item.id] = item end

    local d = DemandOf(buyer.id, now)
    local left = math.max(0, (conf.Demand or 24) - d.sold)
    local total, bottles, sick = 0, 0, 0
    local soldLabels = {}

    for _, line in ipairs(clean) do
        if left <= 0 then break end
        local item = stacks[line.id]
        local have = item and tonumber(item.count) or 0
        local offer = item and have > 0 and Market.Offer(item, buyer, rec.trust)
        if offer then
            local qty = math.min(line.qty, have, left)
            if exports.vorp_inventory:subItemById(_source, item.id, nil, nil, qty) ~= false then
                total = total + Market.LineTotal(offer.unit, d.sold, qty)
                d.sold = d.sold + qty
                left = left - qty
                bottles = bottles + qty
                if offer.hiddenTaint then sick = sick + qty end
                local meta = item.metadata or {}
                soldLabels[#soldLabels + 1] = string.format("%dx %s", qty, meta.label or meta.productLabel or item.name)
            end
        end
    end

    local t = T()
    if bottles == 0 then
        TriggerClientEvent('gsc_kassippu:client:buyerResult', _source, { sold = 0 })
        return GSC.Notify.Send(_source, left <= 0 and t.Full or t.NothingSold, 4000)
    end

    total = Round2(total)
    Character.addCurrency(0, total)

    Market.ApplyTrust(rec, bottles, sick)
    SaveTrust(charid, rec)

    TriggerClientEvent('gsc_kassippu:client:buyerResult', _source, { sold = bottles, total = total, trust = math.floor(rec.trust + 0.5) })
    GSC.Notify.Send(_source, string.format(t.Sold, bottles, total), 5000)

    if sick > 0 then
        local delay = ((conf.Trust or {}).SickDelay or 180) * 1000
        SetTimeout(delay, function()
            local still = Shared.GetChar(_source) -- still here, as the same character
            if still and Shared.CharId(still) == charid then GSC.Notify.Send(_source, t.Sick, 7000, "warning") end
        end)
    end

    ---o[ Staff log, and a chance somebody saw ]o---
    local L = (Config.Text or {}).Logs or {}
    GSC.Logs.Send("market", L.Sale or "Bottles sold", {
        { name = GSC.Logs.Label("Who"), value = GSC.Logs.Player(_source), raw = true },
        { name = GSC.Logs.Label("Buyer"), value = buyer.name, inline = true },
        { name = GSC.Logs.Label("Paid"), value = string.format("$%.2f", total), inline = true },
        { name = GSC.Logs.Label("Bottles"), value = table.concat(soldLabels, ", ") },
        { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(buyer.coords) },
    })
    if GSC.Law and GSC.Law.ReportSale then GSC.Law.ReportSale(_source, buyer.coords) end

    Shared.Debug(string.format("^6[Market]^7 %s sold %d bottles to %s for $%.2f (trust now %.0f%s)",
        _source, bottles, buyer.id, total, rec.trust, sick > 0 and (", " .. sick .. " hidden taint") or ""))
end)

---oo[ The travelling buyer's camp, for clients ]oo---
RegisterServerEvent('gsc_kassippu:server:buyerCampAsk')
AddEventHandler('gsc_kassippu:server:buyerCampAsk', function()
    local _source = source
    local now = os.time()
    if LastAsk[_source] and now - LastAsk[_source] < 10 then return end
    LastAsk[_source] = now
    TriggerClientEvent('gsc_kassippu:client:buyerCamp', _source, CampIndex)
end)

CreateThread(function()
    local tr = Conf().Traveller or {}
    if not (Conf().Enabled and tr.Enabled) then return end
    Market.MoveTraveller()
    while true do
        Wait(math.max(1, tr.MoveMinutes or 45) * 60000)
        Market.MoveTraveller()
    end
end)

---oo[ Admin: /kasippubuyer move ]oo---
RegisterCommand('kasippubuyer', function(source, args)
    local _source = source
    if _source ~= 0 and not GSC.Admin.Is(_source) then
        return GSC.Notify.Send(_source, Config.Text.AdminNoAccess, 3000)
    end
    if (args[1] or "") ~= "move" then
        if _source == 0 then return print("[kasippu] usage: kasippubuyer move") end
        return GSC.Notify.Send(_source, T().AdminUsage, 4000)
    end
    local camp = Market.MoveTraveller()
    local text = camp and string.format(T().Moved, camp.name) or T().NoRumour
    if _source == 0 then return print("[kasippu] " .. text) end
    GSC.Notify.Send(_source, text, 4000)
end, false)

AddEventHandler('playerDropped', function()
    Sessions[source], LastSale[source], LastAsk[source] = nil, nil, nil
end)
