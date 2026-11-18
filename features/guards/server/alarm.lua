GSC.module('Alarm')

local alarmCooldown = Config.GuardSpawnConf.AlertCoolDown

local lastAlarmTime = {} -- [zoneKey][src] = ms
local lastDispatch = {}  -- [zoneKey] = ms

local function IsLawman(job)
    return tostring(job):lower() == tostring(Config.LawJob):lower()
end

local function FindZone(zoneName, label)
    for _, zoneData in ipairs(Config.TreeZones) do
        if (zoneName and zoneData.name == zoneName) or (label and zoneData.label == label) then
            return zoneData
        end
    end
end

---o[ Where the lawman's marker goes ]o---
local function MarkerCoords(src, zoneData, reported)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local pos = GetEntityCoords(ped)
        if pos and (math.abs(pos.x) + math.abs(pos.y)) > 1.0 then return pos end
    end

    if zoneData and type(reported) == 'vector3'
        and Shared.InZoneWithMargin(reported, zoneData, 150.0) then
        return reported
    end

    return zoneData and zoneData.coords or reported
end

---o[ Events ]o---
RegisterNetEvent('gsc_kassippu_alert:server:AreaTrespass', function(coords, gardenLabel, zoneName, suspectCoords, isUpdate)
    local _source = source
    local currentTime = os.time() * 1000
    local Character = Shared.GetChar(_source)
    local zoneData = FindZone(zoneName, gardenLabel)

    ---o[ Only a real yard, raised by someone actually at it ]o---
    if not zoneData then return end

    local zoneKey = zoneData.name or zoneData.label or "unknown"
    zoneName = zoneData.name or zoneName
    gardenLabel = zoneData.label or gardenLabel

    local ped = GetPlayerPed(_source)
    local pos = ped and ped ~= 0 and GetEntityCoords(ped)
    local near = false
    if pos then
        if zoneData.size then
            near = Shared.InZoneWithMargin(pos, zoneData, 150.0) -- the same margin MarkerCoords trusts
        else
            local dx, dy = pos.x - zoneData.coords.x, pos.y - zoneData.coords.y
            near = (dx * dx + dy * dy) <= (300.0 * 300.0)
        end
    end
    if not near then
        Shared.Debug("^1[SERVER DEBUG] Alarm for " .. zoneKey .. " from source " .. _source .. " who is not near it. Ignored.^7")
        return
    end

    Shared.Debug("^3[SERVER DEBUG] Trespass detected by Source: " .. _source .. " at " .. (gardenLabel or "Unknown") .. "^7")

    if not Character then
        Shared.Debug("^1[SERVER DEBUG] CRITICAL: VORP User not found for source " .. _source .. "^7")
        return
    end

    if IsLawman(Character.job) then
        Shared.Debug("^3[SERVER DEBUG] Triggered by Lawman. Ignoring alarm.^7" .. " Source: " .. _source .. " Job: " .. Character.job)
        return
    end

    ---o[ This player's own cooldown ]o---
    local zoneAlarms = lastAlarmTime[zoneKey]
    if not zoneAlarms then
        zoneAlarms = {}
        lastAlarmTime[zoneKey] = zoneAlarms
    end

    if zoneAlarms[_source] and (currentTime - zoneAlarms[_source]) < alarmCooldown then
        Shared.Debug("^1[SERVER DEBUG] Alarm is on cooldown for this player. Skipping trigger.^7")
        return
    end

    zoneAlarms[_source] = currentTime
    Shared.Debug("^2[SERVER DEBUG] Valid Alarm at " .. zoneKey .. " raised by " .. _source .. ".^7")

    local markerAt = MarkerCoords(_source, zoneData, suspectCoords) or coords

    if not isUpdate then
        ---o[ Everybody in that yard, not just the man who made the noise ]o---
        TriggerClientEvent('gsc_kassippu_alert:client:AlertGuards', -1, zoneName, gardenLabel, _source, markerAt)

        ---o[ An empty yard hears about it too ]o---
        GSC.Roster.RushBrokenWave(zoneKey)
    end

    ---o[ Dispatch: one call per yard, however many trespassers ]o---
    if lastDispatch[zoneKey] and (currentTime - lastDispatch[zoneKey]) < alarmCooldown then
        return
    end
    lastDispatch[zoneKey] = currentTime

    local announce = not isUpdate or (Config.GuardSpawnConf.LawDispatch or {}).UpdateNotify == true
    local text = Config.Text or {}
    local message = Shared.PlainText(string.format(
        isUpdate and (text.LawDispatchUpdateNotify or "Trespasser still on the move at %s. Marker updated.")
            or (text.LawDispatchNotify or "Trespasser at %s. Marked on your map."),
        gardenLabel or "a restricted yard"))

    for _, playerSrc in ipairs(GetPlayers()) do
        local playerId = tonumber(playerSrc)
        local targetChar = Shared.GetChar(playerId)

        if targetChar and IsLawman(targetChar.job) then
            Shared.Debug("^5[SERVER DEBUG] Notifying Police ID: " .. playerId .. "^7" .. " Job: " .. tostring(targetChar.job))
            if announce then
                GSC.Notify.Send(playerId, message, 6000, "alert",
                    Shared.PlainText(text.LawDispatchTitle or "DISPATCH"))
            end
            TriggerClientEvent('gsc_kassippu_alert:client:CreateTempBlip', playerId, markerAt, gardenLabel)
        end
    end
end)

---o[ Is this player the law? ]o---
RegisterNetEvent('gsc_kassippu_alert:server:requestLawStatus', function()
    local _source = source
    local Character = Shared.GetChar(_source)
    TriggerClientEvent('gsc_kassippu_alert:client:lawStatus', _source,
        Character ~= nil and IsLawman(Character.job))
end)

---o[ Per-Player Cleanup ]o---
AddEventHandler('playerDropped', function()
    local _source = source

    for _, zoneAlarms in pairs(lastAlarmTime) do
        zoneAlarms[_source] = nil
    end
end)
