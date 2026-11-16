local Stations = GSC.module('Stations')

---oo[ The Water Barrel and the Log Rack beside a still (Config.Stations) - they feed Hold The Heat ]oo---
-- Saved with the still (gsc_kassippu_barrels.stations, written by Distillery's SaveBarrelToDB).

local Sites = {}      -- [uid] = { water = { x, y, z, h, level }, rack = { x, y, z, h, logs = { [kind] = n }, split = { kind, left } } }
local Ready = false   -- true once the stills (and so these) came back from the database
local LastAction = {} -- [src] = GetGameTimer() of the last fill / stack / pick up (spam guard)

local KINDS = { water = "WaterBarrel", rack = "LogRack" } -- kind -> its key in Config.Items / Config.Stations / Text.Stations
local RIGHT = { water = "cool", rack = "fuel" }            -- the crew right each one needs (Config.BarrelCrew.CrewCan)

local function Conf()
    return Config.Stations or {}
end

local function On()
    return Conf().Enabled == true
end

local function Text()
    return Config.Text.Stations or {}
end

local function Label(kind)
    return Text()[KINDS[kind]] or kind
end

local function ItemOf(kind)
    return Config.Items[KINDS[kind]]
end

local function Capacity(kind)
    return tonumber((Conf()[KINDS[kind]] or {}).Capacity) or 0
end

local function GameConf()
    return (Config.HeatSkill or {}).Game or {}
end

local function SplitsPerLog()
    return math.max(1, math.floor(tonumber(GameConf().SplitsPerLog) or 1))
end

local function RackTotal(rack)
    local total = 0
    for _, n in pairs(rack.logs or {}) do total = total + (tonumber(n) or 0) end
    return total
end

---o[ The logs a rack takes, in the order a stoke splits them ]o---
local function LogKinds()
    local list, seen = {}, {}
    for _, kind in ipairs(((Conf().LogRack or {}).BurnOrder) or {}) do
        if Config.Fuel.Logs[kind] and not seen[kind] then list[#list + 1], seen[kind] = kind, true end
    end
    for kind in pairs(Config.Fuel.Logs or {}) do
        if not seen[kind] then list[#list + 1], seen[kind] = kind, true end
    end
    return list
end

local function Near(src, spot, radius)
    if not spot then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - vector3(spot.x, spot.y, spot.z)) <= radius
end

local function Spammed(src)
    local now = GetGameTimer()
    if LastAction[src] and now - LastAction[src] < 500 then return true end
    LastAction[src] = now
    return false
end

AddEventHandler('playerDropped', function()
    LastAction[source] = nil
end)

---oo[ What the clients see: where each stands, and how full ]oo---
function Stations.Public(uid)
    local site = Sites[uid]
    if not site then return nil end

    local out = {}
    if site.water then
        local w = site.water
        out.water = { x = w.x, y = w.y, z = w.z, h = w.h, level = w.level, cap = Capacity("water") }
    end
    if site.rack then
        local r = site.rack
        out.rack = { x = r.x, y = r.y, z = r.z, h = r.h, logs = RackTotal(r), cap = Capacity("rack"),
            splits = Stations.SplitsLeft(uid) }
    end
    if not out.water and not out.rack then return nil end
    return out
end

local function Broadcast(uid)
    TriggerClientEvent('gsc_kassippu:client:stations', -1, uid, Stations.Public(uid))
end

local function AllPublic()
    local all = {}
    for uid in pairs(Sites) do all[uid] = Stations.Public(uid) end
    return all
end

---oo[ Persistence (called by Distillery) ]oo---
local function Coord(t)
    return type(t) == 'table' and tonumber(t.x) and tonumber(t.y) and tonumber(t.z)
end

function Stations.Load(uid, raw)
    Sites[uid] = nil
    if type(raw) ~= 'string' or raw == "" then return end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return end

    local site = {}
    local w = decoded.water
    if Coord(w) then
        site.water = { x = w.x + 0.0, y = w.y + 0.0, z = w.z + 0.0, h = tonumber(w.h) or 0.0,
            level = math.max(0, math.min(Capacity("water"), tonumber(w.level) or 0)) }
    end
    local r = decoded.rack
    if Coord(r) then
        local logs = {}
        for kind, n in pairs(type(r.logs) == 'table' and r.logs or {}) do
            if Config.Fuel.Logs[kind] then logs[kind] = math.max(0, math.floor(tonumber(n) or 0)) end
        end
        local split = type(r.split) == 'table' and Config.Fuel.Logs[r.split.kind]
            and { kind = r.split.kind, left = math.max(0, math.floor(tonumber(r.split.left) or 0)) } or nil
        site.rack = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, h = tonumber(r.h) or 0.0, logs = logs, split = split }
    end
    if site.water or site.rack then Sites[uid] = site end
end

function Stations.Serialize(uid)
    local site = Sites[uid]
    if not site or (not site.water and not site.rack) then return nil end
    return json.encode(site)
end

---o[ The stills are loaded: everyone gets the stations ]o---
function Stations.Loaded()
    Ready = true
    TriggerClientEvent('gsc_kassippu:client:allStations', -1, AllPublic())
end

---o[ The still is gone (seized, blown up, expired, picked up): its stations go with it ]o---
function Stations.Forget(uid)
    if not Sites[uid] then return end
    Sites[uid] = nil
    Broadcast(uid)
end

---o[ The still blew up: both go up with it (a blast at each, just after hers) and are gone for good ]o---
function Stations.Explode(uid)
    local site = Sites[uid]
    if not site then return end

    local spots = {}
    for _, kind in ipairs({ "water", "rack" }) do
        local spot = site[kind]
        if spot then spots[#spots + 1] = { kind = kind, x = spot.x, y = spot.y, z = spot.z } end
    end
    Sites[uid] = nil
    TriggerClientEvent('gsc_kassippu:client:stationsBoom', -1, uid, spots)
    Shared.Debug(string.format("^1[Stations]^7 %d station(s) of %s went up with it", #spots, uid))
end

---o[ The still is picked up: both items back, and the rack's logs (what fits); the water is poured away ]o---
function Stations.ReturnAll(src, uid)
    local site = Sites[uid]
    if not site then return end

    for kind in pairs(KINDS) do
        if site[kind] then
            local item = ItemOf(kind)
            if item and exports.vorp_inventory:canCarryItem(src, item, 1) then
                exports.vorp_inventory:addItem(src, item, 1)
            end
        end
    end
    if site.rack then
        for kind, n in pairs(site.rack.logs or {}) do
            local log = Config.Fuel.Logs[kind]
            if log and n > 0 and exports.vorp_inventory:canCarryItem(src, log.item, n) then
                exports.vorp_inventory:addItem(src, log.item, n)
            end
        end
    end
end

---oo[ What Hold The Heat draws on (called by Distillery every second of the push) ]oo---
function Stations.Has(uid, kind)
    return Sites[uid] ~= nil and Sites[uid][kind] ~= nil
end

function Stations.WaterLeft(uid)
    local w = Sites[uid] and Sites[uid].water
    return w and w.level or 0
end

---o[ Take up to `litres`: how much there was ]o---
function Stations.TakeWater(uid, litres)
    local w = Sites[uid] and Sites[uid].water
    if not w then return 0 end
    local taken = math.min(w.level, math.max(0, litres or 0))
    w.level = w.level - taken
    return taken
end

---o[ All of `litres`, or none (the still's pour / condenser / scrub, Config.Stations.StillUsesStock) ]o---
function Stations.TakeWaterExact(uid, litres)
    local w = Sites[uid] and Sites[uid].water
    if not w or w.level < litres then return false end
    w.level = w.level - litres
    GSC.Distillery.Save(uid)
    Broadcast(uid)
    return true
end

---o[ Whole logs of one kind on the rack (Add Wood / Light The Fire take one) ]o---
function Stations.LogCount(uid, kind)
    local r = Sites[uid] and Sites[uid].rack
    return r and (r.logs[kind] or 0) or 0
end

function Stations.TakeLog(uid, kind)
    local r = Sites[uid] and Sites[uid].rack
    if not r or (r.logs[kind] or 0) < 1 then return false end
    r.logs[kind] = r.logs[kind] - 1
    Broadcast(uid)
    return true
end

function Stations.SplitsLeft(uid)
    local r = Sites[uid] and Sites[uid].rack
    if not r then return 0 end
    return (r.split and r.split.left or 0) + RackTotal(r) * SplitsPerLog()
end

---o[ One split off the rack: the power of its log and its kind, or nil when the rack is bare ]o---
function Stations.TakeSplit(uid)
    local r = Sites[uid] and Sites[uid].rack
    if not r then return nil end

    if not (r.split and r.split.left > 0) then
        r.split = nil
        for _, kind in ipairs(LogKinds()) do
            if (r.logs[kind] or 0) > 0 then
                r.logs[kind] = r.logs[kind] - 1
                r.split = { kind = kind, left = SplitsPerLog() }
                break
            end
        end
        if not r.split then return nil end
    end

    r.split.left = r.split.left - 1
    local log = Config.Fuel.Logs[r.split.kind] or {}
    return tonumber(log.power) or 1.0, r.split.kind
end

---oo[ Setting one down: from the satchel (the item used at the still) or the still's F2 menu ]oo---
local function StartPlacing(src, uid, kind)
    if not Shared.GetChar(src) or not On() then return end
    if not uid or not GSC.Distillery.Position(uid) then
        return GSC.Notify.SendObjective(src, Text().NotAtStill, 4000)
    end
    if not GSC.BarrelCrew.Allow(src, uid, RIGHT[kind]) then return end
    if Stations.Has(uid, kind) then
        return GSC.Notify.SendObjective(src, string.format(Text().Already, Label(kind)), 4000)
    end
    if (exports.vorp_inventory:getItemCount(src, nil, ItemOf(kind)) or 0) < 1 then return end

    exports.vorp_inventory:closeInventory(src)
    TriggerClientEvent('gsc_kassippu:client:placeStation', src, uid, kind)
end

for kind in pairs(KINDS) do
    local item = ItemOf(kind)
    if item then
        exports.vorp_inventory:registerUsableItem(item, function(data)
            StartPlacing(data.source, GSC.Distillery.WatchedBy(data.source), kind)
        end)
    end
end

---o[ F2 at the still: "Set Down Water Barrel / Log Rack" (only the still the player stands at) ]o---
RegisterServerEvent('gsc_kassippu:server:placeStationFromMenu')
AddEventHandler('gsc_kassippu:server:placeStationFromMenu', function(uid, kind)
    local _source = source
    if type(uid) ~= 'string' or not KINDS[kind] then return end
    if GSC.Distillery.WatchedBy(_source) ~= uid then return end
    StartPlacing(_source, uid, kind)
end)

---o[ Which of the two this player carries (the F2 menu offers to set down only those) ]o---
local LastAsk = {}
RegisterServerEvent('gsc_kassippu:server:stationItems')
AddEventHandler('gsc_kassippu:server:stationItems', function()
    local _source = source
    local now = GetGameTimer()
    if LastAsk[_source] and now - LastAsk[_source] < 1000 then return end
    LastAsk[_source] = now
    if not Shared.GetChar(_source) or not On() then return end

    local carried = {}
    for kind in pairs(KINDS) do
        carried[kind] = (exports.vorp_inventory:getItemCount(_source, nil, ItemOf(kind)) or 0) > 0
    end
    TriggerClientEvent('gsc_kassippu:client:stationItems', _source, carried)
end)

AddEventHandler('playerDropped', function()
    LastAsk[source] = nil
end)

RegisterServerEvent('gsc_kassippu:server:placeStation')
AddEventHandler('gsc_kassippu:server:placeStation', function(uid, kind, coords, heading)
    local _source = source
    if not Shared.GetChar(_source) or not On() then return end
    if type(uid) ~= 'string' or not KINDS[kind] or not Coord(coords) then return end

    local still = GSC.Distillery.Position(uid)
    if not still then return end
    if not GSC.BarrelCrew.Allow(_source, uid, RIGHT[kind]) then return end

    local pos = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    if #(GetEntityCoords(GetPlayerPed(_source)) - pos) > 6.0 then return end

    local dist = #(pos - still)
    if dist > (Conf().MaxDistance or 3.0) then
        return GSC.Notify.SendObjective(_source, string.format(Text().TooFar, Conf().MaxDistance or 3.0), 4000)
    end
    if dist < (Conf().MinDistance or 0.8) then
        return GSC.Notify.SendObjective(_source, Text().TooClose, 4000)
    end
    if Stations.Has(uid, kind) then
        return GSC.Notify.SendObjective(_source, string.format(Text().Already, Label(kind)), 4000)
    end

    local item = ItemOf(kind)
    if exports.vorp_inventory:getItemCount(_source, nil, item) < 1 then return end
    if not exports.vorp_inventory:subItem(_source, item, 1) then return end -- not taken: not set down

    Sites[uid] = Sites[uid] or {}
    local spot = { x = pos.x, y = pos.y, z = pos.z, h = tonumber(heading) or 0.0 }
    if kind == "water" then spot.level = 0 else spot.logs = {} end
    Sites[uid][kind] = spot

    GSC.Distillery.Save(uid)
    Broadcast(uid)
    GSC.Notify.SendObjective(_source, string.format(Text().Placed, Label(kind)), 4000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "place_" .. kind) -- place_water / place_rack
    Shared.Debug(string.format("^2[Stations]^7 (ID: %s) set down a %s at %s", _source, kind, uid))
end)

---oo[ Filling, stacking, picking up ]oo---
local function AtStation(src, uid, kind)
    local spot = Sites[uid] and Sites[uid][kind]
    return spot ~= nil and Near(src, spot, (Conf().InteractRadius or 1.5) + 2.0)
end

---oo[ Fill Water Barrel: start the pour, and the water only goes in once it has been played out ]oo---
-- 1. fillStation: checked (at the barrel, crew right, not full, a bucket with water) - nothing taken yet.
--    The player is marked as pouring, and his client plays the pour (Config.AnimConf.Actions.fill).
-- 2. fillStationDone: the client says how it went. Broken off (X, moved away, ragdoll, dead) = no water.
--    Played out = everything checked again, one use of water taken, the barrel filled.
-- One pour at a time per player, and "done" before the pour's time is up is refused: no spamming.
local Pouring = {}     -- [src] = { uid, ends = GetGameTimer() the pour is over }
local POUR_SLACK = 750 -- ms a client may report "done" before that (frame / network timing)
local POUR_LOST  = 5000 -- ms after the pour's end a missing "done" stops blocking him

local function PourMs()
    local a = Config.AnimConf and Config.AnimConf.Actions and Config.AnimConf.Actions.fill
    return math.floor(tonumber(a and a.time) or 3500)
end

AddEventHandler('playerDropped', function()
    Pouring[source] = nil
end)

RegisterServerEvent('gsc_kassippu:server:fillStation')
AddEventHandler('gsc_kassippu:server:fillStation', function(uid)
    local _source = source
    if not Shared.GetChar(_source) or not On() or type(uid) ~= 'string' then return end

    local now = GetGameTimer()
    local pour = Pouring[_source]
    if pour and now < pour.ends + POUR_LOST then return end -- already pouring: one at a time

    if Spammed(_source) or not AtStation(_source, uid, "water") then return end
    if not GSC.BarrelCrew.Allow(_source, uid, RIGHT.water) then return end

    local cap = Capacity("water")
    if Sites[uid].water.level >= cap then return GSC.Notify.Send(_source, Text().Full, 3000) end
    if GSC.Distillery.WaterUsesLeft(_source) < 1 then
        return GSC.Notify.Send(_source, Text().NoBucket, 3000)
    end

    local ms = PourMs()
    Pouring[_source] = { uid = uid, ends = now + ms }
    TriggerClientEvent('gsc_kassippu:client:stationPour', _source, uid, ms)
end)

RegisterServerEvent('gsc_kassippu:server:fillStationDone')
AddEventHandler('gsc_kassippu:server:fillStationDone', function(uid, done)
    local _source = source
    local pour = Pouring[_source]
    if not pour or pour.uid ~= uid then return end -- no pour of his under way: nothing to finish
    Pouring[_source] = nil

    if done ~= true then return GSC.Notify.Send(_source, Text().PourCancelled, 3000) end
    if GetGameTimer() < pour.ends - POUR_SLACK then return end -- "done" before it could be: no water

    ---o[ Checked again: the barrel, his place and his right may have changed during the pour ]o---
    if not Shared.GetChar(_source) or not On() or not AtStation(_source, uid, "water") then return end
    if not GSC.BarrelCrew.Allow(_source, uid, RIGHT.water) then return end

    local w = Sites[uid].water
    local cap = Capacity("water")
    if w.level >= cap then return GSC.Notify.Send(_source, Text().Full, 3000) end

    if not GSC.Distillery.UseWater(_source, 1) then
        return GSC.Notify.Send(_source, Text().NoBucket, 3000)
    end

    w.level = math.min(cap, w.level + (tonumber((Conf().WaterBarrel or {}).PerBucketUse) or 10))
    GSC.Distillery.Save(uid)
    Broadcast(uid)
    GSC.Notify.Send(_source, string.format(Text().Filled, math.floor(w.level), cap), 3000)
end)

RegisterServerEvent('gsc_kassippu:server:stockStation')
AddEventHandler('gsc_kassippu:server:stockStation', function(uid)
    local _source = source
    if not Shared.GetChar(_source) or not On() or type(uid) ~= 'string' then return end
    if Spammed(_source) or not AtStation(_source, uid, "rack") then return end
    if not GSC.BarrelCrew.Allow(_source, uid, RIGHT.rack) then return end

    local r = Sites[uid].rack
    local cap = Capacity("rack")
    local free = cap - RackTotal(r)
    if free <= 0 then return GSC.Notify.Send(_source, Text().RackFull, 3000) end

    local added = 0
    for _, kind in ipairs(LogKinds()) do
        if free <= 0 then break end
        local log = Config.Fuel.Logs[kind]
        local have = exports.vorp_inventory:getItemCount(_source, nil, log.item) or 0
        local take = math.min(have, free)
        if take > 0 and exports.vorp_inventory:subItem(_source, log.item, take) then -- only logs really taken go on the rack
            r.logs[kind] = (r.logs[kind] or 0) + take
            free, added = free - take, added + take
        end
    end
    if added == 0 then return GSC.Notify.Send(_source, Text().NoLogs, 3000) end

    GSC.Distillery.Save(uid)
    Broadcast(uid)
    GSC.Notify.Send(_source, string.format(Text().Stacked, added, RackTotal(r), cap), 4000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "stack")
end)

RegisterServerEvent('gsc_kassippu:server:pickupStation')
AddEventHandler('gsc_kassippu:server:pickupStation', function(uid, kind)
    local _source = source
    if not Shared.GetChar(_source) or type(uid) ~= 'string' or not KINDS[kind] then return end
    if Spammed(_source) or not AtStation(_source, uid, kind) then return end
    if not GSC.BarrelCrew.Allow(_source, uid, RIGHT[kind]) then return end
    if GSC.Distillery.Stage(uid) == Shared.BarrelStage.FINAL_PUSH then
        return GSC.Notify.Send(_source, Text().NotNow, 3000)
    end

    local item = ItemOf(kind)
    if not exports.vorp_inventory:canCarryItem(_source, item, 1) then
        return GSC.Notify.Send(_source, Text().NoRoom, 3000)
    end

    local site = Sites[uid]
    if kind == "rack" then
        for logKind, n in pairs(site.rack.logs or {}) do
            local log = Config.Fuel.Logs[logKind]
            if n > 0 and not exports.vorp_inventory:canCarryItem(_source, log.item, n) then
                return GSC.Notify.Send(_source, Text().NoRoom, 3000)
            end
        end
        for logKind, n in pairs(site.rack.logs or {}) do
            if n > 0 then exports.vorp_inventory:addItem(_source, Config.Fuel.Logs[logKind].item, n) end
        end
    end

    site[kind] = nil
    if not site.water and not site.rack then Sites[uid] = nil end
    exports.vorp_inventory:addItem(_source, item, 1)

    GSC.Distillery.Save(uid)
    Broadcast(uid)
    GSC.Notify.Send(_source, string.format(Text().PickedUp, Label(kind)), 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "pickup")
end)

---o[ A client that starts late asks for them ]o---
local LastStationsAsk = {} -- [src] = os.time() of their last accepted ask

AddEventHandler('playerDropped', function()
    LastStationsAsk[source] = nil
end)

RegisterServerEvent('gsc_kassippu:server:requestStations')
AddEventHandler('gsc_kassippu:server:requestStations', function()
    local _source = source
    if not Ready then return end -- the load broadcast is still to come, and will reach it

    ---o[ The whole list: once every 15 s per player (as requestBarrels / requestCrates) ]o---
    local now = os.time()
    if LastStationsAsk[_source] and now - LastStationsAsk[_source] < 15 then return end
    LastStationsAsk[_source] = now
    TriggerClientEvent('gsc_kassippu:client:allStations', _source, AllPublic())
end)
