local Roster = GSC.module('Roster')

local GuardConf = Config.GuardSpawnConf

local ZoneRoster = {}
local lastKillReport = {}
local lastRosterRequest = {} -- [src] = GetGameTimer() of the last requestZoneRoster

---oo[ THE MEN THEMSELVES ]oo---
local LEASE_SECONDS = 20
local VERIFY_MARGIN = 60.0
local KILL_REPORT_RANGE = 300.0

local leaseCounter = 0
local guardModelSet = nil      -- [hash] = true

local function GuardModelSet()
    if guardModelSet then return guardModelSet end
    guardModelSet = {}
    for _, name in ipairs(Shared.GuardModels()) do
        if name then guardModelSet[GetHashKey(name)] = true end
    end
    return guardModelSet
end

---o[ Which zone is this? ]o---
local function FindZone(zoneName)
    for i, zoneData in ipairs(Config.TreeZones) do
        if (zoneData.name or zoneData.label) == zoneName then
            return i, zoneData
        end
    end
    return nil, nil
end

local function CountPosts(zoneData)
    if zoneData.guardPosts and #zoneData.guardPosts > 0 then return #zoneData.guardPosts end
    if zoneData.guardSpawn and #zoneData.guardSpawn > 0 then return #zoneData.guardSpawn end
    return #Shared.BuildAutoPosts(zoneData)
end

---o[ Build the shift that walks in for a given wave ]o---
local function BuildSlots(zoneData, wave)
    local postCount = CountPosts(zoneData)
    if postCount == 0 then return {} end

    ---o[ Hand-placed posts: one man on every post, slot i on post i ]o---
    local handPlaced = (zoneData.guardPosts and #zoneData.guardPosts > 0)
        or (zoneData.guardSpawn and #zoneData.guardSpawn > 0)
    if GuardConf.AtPostsOnly ~= false and handPlaced then
        local slots = {}
        for i = 1, postCount do slots[i] = { id = i, post = i, dead = false } end
        return slots
    end

    local cap = GuardConf.GuardsPerZone or 0
    local onDuty = postCount
    if cap > 0 and cap < postCount then onDuty = cap end

    local pool = {}
    for i = 1, postCount do pool[i] = i end

    for i = 1, onDuty do
        local j = math.random(i, postCount)
        pool[i], pool[j] = pool[j], pool[i]
    end

    local extras = math.min((wave - 1) * (GuardConf.WaveExtraGuards or 0), GuardConf.MaxExtraGuards or 0)
    local slots = {}

    for i = 1, onDuty do
        slots[#slots + 1] = { id = #slots + 1, post = pool[i], dead = false }
    end

    for i = 1, extras do
        slots[#slots + 1] = { id = #slots + 1, post = pool[((i - 1) % onDuty) + 1], dead = false }
    end

    return slots
end

local function WaveAccuracy(wave)
    local base = GuardConf.Accuracy or 60
    local bonus = (math.max(1, wave) - 1) * (GuardConf.WaveAccuracyBonus or 0)
    return math.min(GuardConf.MaxAccuracy or 90, base + bonus)
end

local function EnsureRoster(zoneName)
    local roster = ZoneRoster[zoneName]
    if roster then return roster end

    local _, zoneData = FindZone(zoneName)
    if not zoneData then return nil end

    roster = {
        wave = 1,
        slots = BuildSlots(zoneData, 1),
        waveAt = nil,
        broken = false,
    }

    ZoneRoster[zoneName] = roster
    return roster
end

---o[ The slot's ped, if it is still in the world ]o---
local function SlotEntity(slot)
    if not slot.netId then return 0 end
    local entity = NetworkGetEntityFromNetworkId(slot.netId)
    if entity ~= 0 and DoesEntityExist(entity) then return entity end
    return 0
end

local function DeleteSlotPed(slot)
    local entity = SlotEntity(slot)
    if entity ~= 0 then DeleteEntity(entity) end

    slot.netId = nil
    slot.verified = nil
    slot.lease = nil
    slot.diedAt = nil
end

local function DeleteRosterPeds(roster)
    for _, slot in ipairs(roster.slots) do DeleteSlotPed(slot) end
end

local function RosterHasPeds(roster)
    for _, slot in ipairs(roster.slots) do
        if slot.netId or slot.lease then return true end
    end
    return false
end

---o[ Who is near this point? ]o---
local function NearestPlayer(coords)
    local bestSrc, bestDist = nil, math.huge

    for _, playerId in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped and ped ~= 0 then
            local p = GetEntityCoords(ped)
            local dx, dy = p.x - coords.x, p.y - coords.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestDist then bestSrc, bestDist = tonumber(playerId), d end
        end
    end

    return bestSrc, bestDist
end

local function ZoneRanges(zoneData)
    local spawn = zoneData.spawnDistance or GuardConf.SpawnDistance or 200.0
    local reach = math.max(zoneData.despawnDistance or GuardConf.DespawnDistance or 260.0, spawn + 20.0) -- as the client
    return spawn, reach
end

---o[ Yard news goes only to players close enough to have its guards on their map, not to the whole server ]o---
local SEND_MARGIN = 100.0 -- metres past the despawn distance: a player walking off still hears the last change

---o[ Returns the set of players it sent to ]o---
function Roster.SendNear(zoneData, eventName, ...)
    local _, reach = ZoneRanges(zoneData)
    local limit = reach + SEND_MARGIN
    local limitSq = limit * limit
    local cx, cy = zoneData.coords.x, zoneData.coords.y
    local sent = {}

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local ped = target and GetPlayerPed(playerId)
        if ped and ped ~= 0 then
            local p = GetEntityCoords(ped)
            local dx, dy = p.x - cx, p.y - cy
            if (dx * dx + dy * dy) <= limitSq then
                TriggerClientEvent(eventName, target, ...)
                sent[target] = true
            end
        end
    end

    return sent
end

---o[ Is any player close enough to have this yard's guards on his map? ]o---
local function AnyPlayerNear(zoneData)
    local _, reach = ZoneRanges(zoneData)
    local _, dist = NearestPlayer(zoneData.coords)
    return dist <= reach
end

---o[ The message clients act on ]o---
local function RosterPayload(zoneName, roster)
    local manned = {}

    for _, slot in ipairs(roster.slots) do
        if not slot.dead then
            manned[#manned + 1] = { id = slot.id, post = slot.post, netId = slot.verified and slot.netId or nil }
        end
    end

    return {
        zone = zoneName,
        wave = roster.wave,
        accuracy = WaveAccuracy(roster.wave),
        manned = manned,
        broken = roster.broken,
        waveIn = roster.waveAt and math.max(0, roster.waveAt - os.time()) or nil,
    }
end

local function BroadcastRoster(zoneName, target)
    local roster = ZoneRoster[zoneName]
    if not roster then return end

    local payload = RosterPayload(zoneName, roster)
    if target then
        return TriggerClientEvent('gsc_kassippu_alert:client:zoneRoster', target, payload)
    end

    ---o[ Players further out ask for it themselves when they come in range ]o---
    local _, zoneData = FindZone(zoneName)
    if zoneData then
        Roster.SendNear(zoneData, 'gsc_kassippu_alert:client:zoneRoster', payload)
    else
        TriggerClientEvent('gsc_kassippu_alert:client:zoneRoster', -1, payload)
    end
end

---o[ AN UNGUARDED YARD HEARS THE NEXT BREAK-IN ]o---
function Roster.RushBrokenWave(zoneKey)
    local roster = ZoneRoster[zoneKey]
    if not roster or not roster.broken or not roster.waveAt then return end

    local rush = GuardConf.BrokenAlarmRushSeconds or 60
    if rush <= 0 then return end

    local rushedTo = os.time() + rush
    if rushedTo >= roster.waveAt then return end -- already arriving sooner than that

    roster.waveAt = rushedTo
    Shared.Debug(string.format("^3[Guards]^7 %s is empty and somebody tripped the alarm - next shift pulled in to %ds",
        zoneKey, rush))

    BroadcastRoster(zoneKey)
end

---o[ /clearguards ]o---
function Roster.ResetAll()
    for zoneName, roster in pairs(ZoneRoster) do
        DeleteRosterPeds(roster)
        ZoneRoster[zoneName] = nil
    end
    Shared.Debug("^3[Guards]^7 every yard reset by an admin")
end

---o[ A guard went down ]o---
local function MarkSlotDead(zoneName, roster, slot)
    if slot.dead then return end

    slot.dead = true
    slot.diedAt = os.time()
    slot.respawnAt = os.time() + (GuardConf.RespawnSeconds or 120)

    ---o[ AlwaysStaffed ]o---
    if GuardConf.AlwaysStaffed ~= false then
        Shared.Debug(string.format("^3[Guards]^7 %s: slot %d down, back on his post in %ds",
            zoneName, slot.id, GuardConf.RespawnSeconds or 120))
        BroadcastRoster(zoneName)
        return
    end

    ---o[ Is anybody left standing? ]o---
    local anyAlive = false
    for _, entry in ipairs(roster.slots) do
        if not entry.dead then anyAlive = true break end
    end

    if anyAlive then
        Shared.Debug(string.format("^3[Guards]^7 %s: slot %d down, replacement in %ds",
            zoneName, slot.id, GuardConf.RespawnSeconds or 120))
    else
        roster.broken = true

        if roster.wave >= (GuardConf.MaxWaves or 3) then
            roster.waveAt = os.time() + ((GuardConf.ClearedMinutes or 30) * 60)
            roster.wave = 0
            Shared.Debug(string.format("^1[Guards]^7 %s wiped for the last time - unguarded for %d minutes",
                zoneName, GuardConf.ClearedMinutes or 30))
        else
            roster.waveAt = os.time() + (GuardConf.WaveDelaySeconds or 300)
            Shared.Debug(string.format("^1[Guards]^7 %s wiped - wave %d rides in in %ds",
                zoneName, roster.wave + 1, GuardConf.WaveDelaySeconds or 300))
        end
    end

    BroadcastRoster(zoneName)
end

---o[ A client reports that a guard went down ]o---
RegisterNetEvent('gsc_kassippu_alert:server:guardKilled')
AddEventHandler('gsc_kassippu_alert:server:guardKilled', function(zoneName, slotId)
    local _source = source
    if type(zoneName) ~= 'string' or type(slotId) ~= 'number' then return end

    ---o[ Rate limit that cannot eat a real kill ]o---
    local now = GetGameTimer()
    local report = lastKillReport[_source]

    if not report or (now - report.windowAt) > 1000 then
        report = { windowAt = now, burst = 0 }
        lastKillReport[_source] = report
    end

    report.burst = report.burst + 1

    local burstCeiling = (GuardConf.GuardsPerZone or 8) + (GuardConf.MaxExtraGuards or 0) + 8
    if report.burst > burstCeiling then return end

    local roster = ZoneRoster[zoneName]
    if not roster then return end

    local slot = nil
    for _, entry in ipairs(roster.slots) do
        if entry.id == slotId then slot = entry break end
    end

    if not slot or slot.dead or not slot.verified then return end

    ---o[ The server can see the ped: believe it, not the client ]o---
    local entity = SlotEntity(slot)
    if entity ~= 0 then
        if GetEntityMaxHealth(entity) > 0 and GetEntityHealth(entity) > 0 then return end -- alive here; the clock re-checks

        local ped = GetPlayerPed(_source)
        if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > KILL_REPORT_RANGE then return end
    end

    MarkSlotDead(zoneName, roster, slot)
end)

---o[ A client streaming the zone in asks who should be standing there ]o---
RegisterNetEvent('gsc_kassippu_alert:server:requestZoneRoster')
AddEventHandler('gsc_kassippu_alert:server:requestZoneRoster', function(zoneName)
    local _source = source
    if type(zoneName) ~= 'string' then return end

    ---o[ A client asks every few seconds at most; anything faster is spam ]o---
    local now = GetGameTimer()
    if lastRosterRequest[_source] and (now - lastRosterRequest[_source]) < 1000 then return end
    lastRosterRequest[_source] = now

    if EnsureRoster(zoneName) then
        BroadcastRoster(zoneName, _source)
    end
end)

---o[ The player we asked to create a guard reports back ]o---
RegisterNetEvent('gsc_kassippu_alert:server:guardSpawned')
AddEventHandler('gsc_kassippu_alert:server:guardSpawned', function(leaseId, netId)
    local _source = source
    if type(leaseId) ~= 'number' then return end

    for _, roster in pairs(ZoneRoster) do
        for _, slot in ipairs(roster.slots) do
            local lease = slot.lease
            if lease and lease.id == leaseId then
                if lease.src ~= _source or slot.netId then return end

                if type(netId) ~= 'number' then
                    slot.lease = nil
                    return
                end

                slot.netId = netId
                lease.reportedAt = os.time()
                return
            end
        end
    end

    ---o[ Too late, or a lease that never existed ]o---
    if type(netId) == 'number' then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 1
            and GuardModelSet()[GetEntityModel(entity)]
            and NetworkGetEntityOwner(entity) == _source then
            DeleteEntity(entity)
        end
    end
end)

---o[ ONE ZONE, ONE PASS: leases, checks, bodies, despawn ]o---
local function TickZone(zoneData, now)
    local zoneName = zoneData.name or zoneData.label
    local spawn, reach = ZoneRanges(zoneData)
    local hostSrc, nearest = NearestPlayer(zoneData.coords)

    local roster = ZoneRoster[zoneName]
    if nearest <= spawn then roster = EnsureRoster(zoneName) end
    if not roster then return end

    if nearest <= reach then roster.nearAt = now end

    local changed = false
    local bodySeconds = GuardConf.BodyCleanupSeconds or 45

    for _, slot in ipairs(roster.slots) do
        local entity = SlotEntity(slot)

        if slot.netId and entity == 0 then
            ---o[ Reported, but not (or no longer) in the world ]o---
            local reportedAt = slot.lease and slot.lease.reportedAt
            if slot.verified or not reportedAt or (now - reportedAt) > LEASE_SECONDS then
                slot.netId, slot.verified, slot.lease, slot.diedAt = nil, nil, nil, nil
                changed = true
            end
        elseif slot.netId and not slot.verified then
            ---o[ Is it the man we asked for, where we asked for him? ]o---
            if GetEntityType(entity) == 1 and GuardModelSet()[GetEntityModel(entity)]
                and Shared.InZoneWithMargin(GetEntityCoords(entity), zoneData, VERIFY_MARGIN) then
                slot.verified = true
                slot.lease = nil
                changed = true
            else
                Shared.Debug(string.format("^1[Guards]^7 %s: spawn report for slot %d rejected (model/position)",
                    zoneName, slot.id))
                slot.netId, slot.lease = nil, nil
            end
        elseif slot.verified and not slot.dead then
            ---o[ The server sees him die even if no client says so ]o---
            if GetEntityMaxHealth(entity) > 0 and GetEntityHealth(entity) <= 0 then
                MarkSlotDead(zoneName, roster, slot)
            end
        elseif slot.verified and slot.dead and slot.diedAt and (now - slot.diedAt) >= bodySeconds then
            ---o[ Clear the corpse ]o---
            DeleteSlotPed(slot)
            changed = true
        end

        ---o[ A lease nobody answered ]o---
        if slot.lease and not slot.netId and (now - slot.lease.at) > LEASE_SECONDS then
            slot.lease = nil
        end
    end

    if nearest <= spawn and not roster.broken then
        ---o[ Empty posts get a man ]o---
        local perPass = GuardConf.AtPostsOnly ~= false and math.huge or (GuardConf.SpawnPerPass or 1)
        local handedOut = 0

        for _, slot in ipairs(roster.slots) do
            if handedOut >= perPass then break end

            if not slot.dead and not slot.netId and not slot.lease and hostSrc then
                leaseCounter = leaseCounter + 1
                slot.lease = { id = leaseCounter, src = hostSrc, at = now }
                handedOut = handedOut + 1

                TriggerClientEvent('gsc_kassippu_alert:client:spawnGuard', hostSrc,
                    zoneName, slot.id, slot.post, leaseCounter, WaveAccuracy(roster.wave))
            end
        end
    elseif nearest > reach and RosterHasPeds(roster)
        and (now - (roster.nearAt or 0)) >= math.max(0, GuardConf.DespawnGraceSeconds or 10) then
        ---o[ Nobody about: take the shift off the map (the roster stays) ]o---
        DeleteRosterPeds(roster)
        changed = true
        Shared.Debug(string.format("^3[Guards]^7 %s: nobody near - guards off the map", zoneName))
    end

    if changed then BroadcastRoster(zoneName) end
end

CreateThread(function()
    while true do
        Wait(2000)

        if GuardConf.Enabled ~= false then
            local now = os.time()
            for _, zoneData in ipairs(Config.TreeZones) do
                TickZone(zoneData, now)
            end
        end
    end
end)

---o[ ROSTER CLOCK ]o---
CreateThread(function()
    while true do
        Wait(5000)

        local now = os.time()

        for zoneName, roster in pairs(ZoneRoster) do
            local changed = false

            if roster.broken then
                ---o[ Waiting on a whole new shift ]o---
                if roster.waveAt and now >= roster.waveAt then
                    local _, zoneData = FindZone(zoneName)

                    if zoneData then
                        DeleteRosterPeds(roster) -- old bodies go with the old shift
                        roster.wave = roster.wave + 1
                        roster.slots = BuildSlots(zoneData, roster.wave)
                        roster.broken = false
                        roster.waveAt = nil
                        changed = true

                        Shared.Debug(string.format("^2[Guards]^7 %s: wave %d took over the yard (%d men, accuracy %d)",
                            zoneName, roster.wave, #roster.slots, WaveAccuracy(roster.wave)))
                    end
                end
            else
                ---o[ Individual replacements taking their posts ]o---
                local anyDead = false
                for _, slot in ipairs(roster.slots) do
                    if slot.dead and slot.respawnAt and now >= slot.respawnAt then
                        DeleteSlotPed(slot) -- his body, if it is still lying there
                        slot.dead = false
                        slot.respawnAt = nil
                        changed = true
                    end
                    if slot.dead then anyDead = true end
                end

                ---o[ AlwaysStaffed ]o---
                if anyDead and GuardConf.AlwaysStaffed ~= false then
                    local _, zoneData = FindZone(zoneName)
                    if zoneData and not AnyPlayerNear(zoneData) then
                        for _, slot in ipairs(roster.slots) do
                            if slot.dead then DeleteSlotPed(slot) end
                            slot.dead = false
                            slot.respawnAt = nil
                        end
                        changed = true
                        Shared.Debug(string.format("^2[Guards]^7 %s: nobody near - full shift back on duty", zoneName))
                    end
                end
            end

            if changed then BroadcastRoster(zoneName) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local _source = source
    lastKillReport[_source] = nil
    lastRosterRequest[_source] = nil

    ---o[ His unanswered spawn jobs go to somebody else ]o---
    for _, roster in pairs(ZoneRoster) do
        for _, slot in ipairs(roster.slots) do
            if slot.lease and slot.lease.src == _source and not slot.netId then slot.lease = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, roster in pairs(ZoneRoster) do
        DeleteRosterPeds(roster)
    end
end)

---o[ Admin view of who is on duty ]o---
RegisterCommand('zoneguards', function(source)
    if source ~= 0 then return end -- server console only

    for zoneName, roster in pairs(ZoneRoster) do
        local alive, spawned = 0, 0
        for _, slot in ipairs(roster.slots) do
            if not slot.dead then alive = alive + 1 end
            if slot.verified then spawned = spawned + 1 end
        end

        print(string.format("^3[Guards]^7 %s: wave %d, %d/%d on duty, %d in the world%s",
            zoneName, roster.wave, alive, #roster.slots, spawned,
            roster.waveAt and string.format(", next shift in %ds", math.max(0, roster.waveAt - os.time())) or ""))
    end
end, true)
