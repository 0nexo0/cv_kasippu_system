GSC.module('Zones')

local GuardConf = Config.GuardSpawnConf
local VORPcore = exports.vorp_core:GetCore()

local activeAlertBlip = nil

local currentZoneKey = nil
local lastMoveWarn = nil
local fallLoudUntil = 0
local lastEnterNotify = {}
local lastNoiseNotify = 0

local function devPrint(msg)
    Shared.Debug("^1[Zone Debug]^7 " .. tostring(msg))
end

---o[ Is the player jumping / vaulting? ]o---
local HasJumpNative = IsPedJumping ~= nil
local HasClimbNative = IsPedClimbing ~= nil

local function IsPlayerJumping(ped)
    if HasJumpNative and IsPedJumping(ped) then return true end
    if HasClimbNative and IsPedClimbing(ped) then return true end
    return false
end

---o[ Is the player coming down out of a tree? ]o---
local HasFallNative = IsPedFalling ~= nil
local HasRagdollNative = IsPedRagdoll ~= nil
local HasHeightNative = GetEntityHeightAboveGround ~= nil

local function IsPlayerFallingFrom(ped, minHeight)
    local airborne = (HasFallNative and IsPedFalling(ped))
        or (HasRagdollNative and IsPedRagdoll(ped))

    if not airborne then return false end
    if not HasHeightNative then return true end

    return GetEntityHeightAboveGround(ped) >= (minHeight or 2.5)
end

---o[ Is the player holding the sprint key (Shift)? ]o---
local INPUT_SPRINT = 0x8FFC75D6

local function IsSprintKeyHeld()
    return IsControlPressed(0, INPUT_SPRINT) or IsDisabledControlPressed(0, INPUT_SPRINT)
end
---o[ Is there a gun in his hand? ]o---
local function IsPlayerArmed(ped)
    local ok, armed = pcall(function()
        return Citizen.InvokeNative(0xCB690F680A3EA971, ped, 4) -- IsPedArmed
    end)
    return ok and (armed == true or armed == 1)
end

---o[ Has the player fired a gun in here? ]o---
local shotFiredAt = 0

CreateThread(function()
    local armedCheckedAt = 0
    local armed = false

    while true do
        if currentZoneKey then
            local ped = PlayerPedId()
            local now = GetGameTimer()

            ---o[ A shot is a one-frame flag ]o---
            if (now - armedCheckedAt) >= 250 then
                armedCheckedAt = now
                armed = IsPlayerArmed(ped)
            end

            if armed then
                if IsPedShooting(ped) then shotFiredAt = now end
                Wait(0)
            else
                Wait(250)
            end
        else
            armed, armedCheckedAt = false, 0
            Wait(1000)
        end
    end
end)

---o[ DEBUG ZONE OUTLINE ]o---
local debugOn = false

local function DrawZoneOutline(zoneData)
    local c, size = zoneData.coords, zoneData.size
    if not size then return end

    local z = c.z + 1.0
    local corners = {
        vector3(c.x - size.x, c.y + size.y, z),
        vector3(c.x + size.x, c.y + size.y, z),
        vector3(c.x + size.x, c.y - size.y, z),
        vector3(c.x - size.x, c.y - size.y, z),
    }

    for i = 1, 4 do
        local a = corners[i]
        local b = corners[(i % 4) + 1]
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, 0, 200, 120, 180)
    end
end

CreateThread(function()
    while true do
        local sleep = 1000

        if debugOn then
            sleep = 0
            local pCoords = GetEntityCoords(PlayerPedId())

            for _, zoneData in ipairs(Config.TreeZones) do
                if Shared.ZoneCentreDistance(pCoords, zoneData) < 400.0 then
                    DrawZoneOutline(zoneData)
                end
            end
        end

        Wait(sleep)
    end
end)

---o[ OPTIMIZED ZONE ENGINE ]o---
CreateThread(function()
    while not VORPcore do
        Wait(100)
        VORPcore = exports.vorp_core:GetCore()
    end

    Wait(2000)

    ---o[ Each yard may set its own guard distances ]o---
    local ranges = {} -- [zoneIndex] = { spawnSq, despawnSq }
    for i, zoneData in ipairs(Config.TreeZones) do
        local spawn = zoneData.spawnDistance or GuardConf.SpawnDistance or 200.0
        local despawn = zoneData.despawnDistance or GuardConf.DespawnDistance or 260.0

        if despawn < spawn + 20.0 then
            devPrint(string.format("%s: despawnDistance %.0f is too close to spawnDistance %.0f - using %.0f",
                zoneData.name, despawn, spawn, spawn + 20.0))
            despawn = spawn + 20.0
        end

        local corner = zoneData.size and math.sqrt(zoneData.size.x ^ 2 + zoneData.size.y ^ 2) or 0.0
        if spawn < corner then
            devPrint(string.format("%s: spawnDistance %.0f is inside the yard (corner at %.0f) - guards will pop in",
                zoneData.name, spawn, corner))
        end

        ranges[i] = { spawnSq = spawn ^ 2, despawnSq = despawn ^ 2 }
    end

    local leftZoneAt = {}
    local graceMs = math.max(0, (GuardConf.DespawnGraceSeconds or 10)) * 1000

    devPrint("Zone engine started")

    while true do
        local ped = PlayerPedId()
        local sleep = 5000

        if DoesEntityExist(ped) then
            local pCoords = GetEntityCoords(ped)
            local closestSq = math.huge
            local activeZone, activeIndex = nil, nil
            local inSpawnRange = false

            for i, zoneData in ipairs(Config.TreeZones) do
                local offset = pCoords - zoneData.coords
                local distSq = (offset.x * offset.x) + (offset.y * offset.y)

                if distSq < closestSq then
                    closestSq = distSq
                end

                ---o[ The shift goes on the map a long way out ]o---
                if distSq <= ranges[i].spawnSq then
                    leftZoneAt[i] = nil
                    inSpawnRange = true
                    GSC.Guards.Spawn(i, zoneData)
                elseif distSq > ranges[i].despawnSq then
                    if not GSC.Guards.AreStaffed(i) then
                        GSC.Guards.ForgetRoster(i)
                    elseif GSC.Guards.IsHunting(i) then
                        leftZoneAt[i] = nil
                    else
                        local now = GetGameTimer()
                        leftZoneAt[i] = leftZoneAt[i] or now

                        if (now - leftZoneAt[i]) > graceMs then
                            GSC.Guards.Despawn(i)
                            leftZoneAt[i] = nil
                        end
                    end
                end

                ---o[ ...but the YARD is the square box ]o---
                if not activeZone and Shared.InZone(pCoords, zoneData) then
                    activeZone, activeIndex = zoneData, i
                end
            end

            if activeZone then
                sleep = 500

                local zoneKey = activeZone.name or activeZone.label or "unknown"
                local zoneLabel = activeZone.label or "Restricted Area"

                if currentZoneKey ~= zoneKey then
                    currentZoneKey = zoneKey
                    lastMoveWarn = nil

                    local now = GetGameTimer()
                    local cooldown = ((GuardConf.Notify or {}).EnterCooldownSeconds or 60) * 1000
                    if not lastEnterNotify[zoneKey] or (now - lastEnterNotify[zoneKey]) > cooldown then
                        lastEnterNotify[zoneKey] = now
                        GSC.Notify.Show(Shared.PlainText(string.format(Config.Text.ZoneEnterNotify
                            or "Restricted area: %s. Move quietly.", zoneLabel)), 3000)
                    end
                    devPrint("Entered zone: " .. zoneLabel)
                end

                local currentTime = GetGameTimer()
                local st = GuardConf.Stealth or {}
                local onTree = GSC.Climb and GSC.Climb.IsActive()
                local speed = GetEntitySpeed(ped)
                local isCrouching = Citizen.InvokeNative(0xD5FE956C70FF370B, ped, Citizen.ResultAsInteger()) == 1 -- GetPedCrouchMovement

                local sprintKey = GuardConf.SprintKeyIsLoud ~= false
                    and not onTree
                    and speed > (st.StillSpeed or 0.15)
                    and IsSprintKeyHeld()

                local isRunning = sprintKey
                    or ((IsPedRunning(ped) or IsPedSprinting(ped)) and not isCrouching)
                local isJumping = not onTree and IsPlayerJumping(ped)
                local isShooting = (currentTime - shotFiredAt) < 1000

                ---o[ Coming down out of a tree ]o---
                local isFalling = false

                if GuardConf.FallingIsLoud ~= false and not onTree then
                    if IsPlayerFallingFrom(ped, GuardConf.FallMinHeight or 2.5) then
                        fallLoudUntil = currentTime + ((GuardConf.FallLoudSeconds or 5) * 1000)
                    end
                    isFalling = currentTime < fallLoudUntil
                end

                local isLoud = isJumping or isFalling or isRunning or isShooting
                local guardsEnabled = GuardConf.Enabled ~= false

                ---o[ Hand what he is doing to the yard, and let it decide ]o---
                if guardsEnabled then
                    local still = isCrouching and speed <= (st.StillSpeed or 0.15)

                    local concealed = onTree
                        and (GSC.Climb.Height() or 0) >= (st.ConcealHeightSteps or 1.5)

                    GSC.Guards.ReportPlayerNoise(activeIndex, {
                        running = isRunning,
                        jumping = isJumping,
                        falling = isFalling,
                        crouching = isCrouching,
                        still = still,
                        shooting = isShooting,
                        alarm = isRunning or isJumping or isShooting,
                        concealed = concealed,
                        climbing = onTree and not concealed,
                        armed = not onTree and IsPlayerArmed(ped),
                        upright = not onTree and not isCrouching, -- FireOn.SeenUpright: not sneaking
                    })
                end

                local noiseCooldown = ((GuardConf.Notify or {}).NoiseCooldownSeconds or 10) * 1000
                local canWarn = lastMoveWarn ~= "loud" and (currentTime - lastNoiseNotify) > noiseCooldown

                if isLoud and not guardsEnabled then
                    if canWarn then
                        lastMoveWarn = "loud"
                        lastNoiseNotify = currentTime
                        GSC.Notify.Show(Shared.PlainText(Config.Text.ZoneNoiseNoGuardsNotify
                            or "Keep it down. This is a restricted area."), 2500)
                    end
                elseif isLoud then
                    if canWarn and not GSC.Guards.IsHunting(activeIndex) then
                        lastMoveWarn = "loud"
                        lastNoiseNotify = currentTime
                        GSC.Notify.Show(Shared.PlainText(Config.Text.ZoneNoiseNotify
                            or "You are making noise."), 2500)
                    end
                    if lastMoveWarn ~= "loud" then
                        lastMoveWarn = "loud"
                        devPrint((isFalling and "Fall" or (isJumping and "Jump" or "Running"))
                            .. " reported to the yard: " .. zoneLabel)
                    end
                else
                    lastMoveWarn = nil
                end
            else
                if closestSq < 2500.0 then        -- < 50m
                    sleep = 1000
                elseif closestSq < 22500.0 then   -- < 150m
                    sleep = 2500
                else
                    sleep = 5000
                end
                currentZoneKey = nil
                lastMoveWarn = nil
            end

            if inSpawnRange then sleep = math.min(sleep, 1000) end
        end

        Wait(sleep)
    end
end)

---o[ SHERIFF DISPATCH MARKER ]o---
local alertRouteOn = false
local alertMarkerAt = nil
local alertMarkerId = 0

local function ClearDispatchMarker()
    if activeAlertBlip and DoesBlipExist(activeAlertBlip) then
        RemoveBlip(activeAlertBlip)
    end
    activeAlertBlip = nil

    if alertRouteOn then
        pcall(function()
            SetGpsMultiRouteRender(false)
            ClearGpsMultiRoute()
        end)
        alertRouteOn = false
    end

    alertMarkerAt = nil
end

RegisterNetEvent('gsc_kassippu_alert:client:CreateTempBlip', function(coords, label, blipName)
    if not coords then return end

    local conf = GuardConf.LawDispatch or {}
    ClearDispatchMarker()

    ---o[ The blip ]o---
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
    SetBlipSprite(blip, GetHashKey(GuardConf.AlertBlipName or "blip_ambient_bounty_hunter"), true)
    SetBlipScale(blip, 1.0)
    pcall(function()
        Citizen.InvokeNative(0x662D364ABF16DE2F, blip, GetHashKey(conf.BlipColour or "BLIP_MODIFIER_MP_COLOR_8")) -- BlipAddModifier
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, "LITERAL_STRING",
            (blipName or conf.BlipName or "Trespasser") .. (label and (" - " .. label) or ""))) -- SetBlipName
    end)
    activeAlertBlip = blip

    ---o[ The waypoint ]o---
    if conf.Waypoint ~= false then
        alertRouteOn = pcall(function()
            ClearGpsMultiRoute()
            StartGpsMultiRoute(GetHashKey(conf.RouteColour or "COLOR_RED"), true, true)
            AddPointToGpsMultiRoute(coords.x, coords.y, coords.z)
            SetGpsMultiRouteRender(true)
        end)
    end

    alertMarkerAt = coords
    alertMarkerId = alertMarkerId + 1
    local myId = alertMarkerId

    devPrint("Dispatch marker set at: " .. tostring(coords))

    SetTimeout((conf.MarkerSeconds or 90) * 1000, function()
        if alertMarkerId == myId and alertMarkerAt then
            ClearDispatchMarker()
            devPrint("Dispatch marker expired")
        end
    end)
end)

---o[ Lawman reached the marker: take it off his map ]o---
CreateThread(function()
    while true do
        local sleep = 2000

        if alertMarkerAt then
            local reach = (GuardConf.LawDispatch or {}).ClearWithin or 15.0
            local pos = GetEntityCoords(PlayerPedId())

            if #(pos - alertMarkerAt) <= reach then
                ClearDispatchMarker()
                devPrint("Dispatch marker reached")
            end
        end

        Wait(sleep)
    end
end)
---o[ TOGGLE DEBUG ZONES ]o---
RegisterNetEvent('gsc_kassippu:client:adminCommand')
AddEventHandler('gsc_kassippu:client:adminCommand', function(name)
    if name ~= 'toggledebugzones' then return end

    debugOn = not debugOn
    GSC.Notify.Show(debugOn and "Zone outline on" or "Zone outline off", 2000)
    devPrint("Zone outline " .. tostring(debugOn))
end)

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    ClearDispatchMarker()

    devPrint("Cleanup completed")
end)
