local Guards = GSC.module('Guards')

local GuardConf = Config.GuardSpawnConf

local zoneGuards = {}     -- [zoneIndex][slotId] = { ped=, post=, state=, ... }
local zoneAlertUntil = {} -- [zoneIndex] = timestamp the guards stop hunting
local zoneRoster = {}     -- [zoneIndex] = who the SERVER says is on duty
local rosterAsked = {}    -- [zoneIndex] = when this client last asked for a roster

---oo[ SUSPICION ]oo---
local zoneSuspicion = {}    -- [zoneIndex] = 0..Max
local zoneSuspLevel = {}    -- [zoneIndex] = "calm" | "notice" | "investigate" | "hostile"
local zoneHostileSince = {} -- [zoneIndex] = when it last crossed into hostile
local zoneNoise = {}        -- [zoneIndex] = latest report from GSC.Zones
local zoneLawCalled = {}    -- [zoneIndex] = true once dispatch has been asked for
local zoneForced = {}       -- [zoneIndex] = hostility was FORCED, so the passive ceiling must not undo it
local zoneLastKnown = {}    -- [zoneIndex] = where any man last saw or heard him; the search party goes here
local zoneSensedAt = {}     -- [zoneIndex] = when any man last saw or heard him: what makes loud movement WITNESSED
local zoneLevelSince = {}   -- [zoneIndex] = when the yard reached its current level, for the drop hysteresis
local zoneWarnUntil = {}    -- [zoneIndex] = a man is holding him at gunpoint until then
local zoneWarnedAt = {}     -- [zoneIndex] = when he was last warned: caught again inside MemorySeconds, no second warning

local SUSP_CALM, SUSP_NOTICE = "calm", "notice"
local SUSP_INVESTIGATE, SUSP_HOSTILE = "investigate", "hostile"
local LEVEL_RANK = { calm = 0, notice = 1, investigate = 2, hostile = 3 }

local ClearSuspicion
local ClearZoneCompletely

local function devPrint(msg)
    Shared.Debug("^1[Guards]^7 " .. tostring(msg))
end

---o[ IS THE LOCAL PLAYER THE LAW? ]o---
local isLawman = false
local lawAskedAt = nil

RegisterNetEvent('gsc_kassippu_alert:client:lawStatus', function(lawman)
    isLawman = lawman == true
end)

local function RefreshLawStatus()
    local now = GetGameTimer()
    if lawAskedAt and (now - lawAskedAt) < 60000 then return end
    lawAskedAt = now
    TriggerServerEvent('gsc_kassippu_alert:server:requestLawStatus')
end

local function LawExempt()
    return isLawman and GuardConf.LawmenIgnored ~= false
end

---o[ NOTIFICATIONS ]o---
local notifyAt = {}   -- ["zone:key"] = when it was last shown
local zoneWarned = {} -- [zoneIndex] = the player has been told the yard is after him

local function ZoneNotify(zoneIndex, key, text, duration, tip, cooldownMs)
    text = Shared.PlainText(text)
    if not text or text == "" then return end

    local id = tostring(zoneIndex) .. ":" .. key
    local now = GetGameTimer()
    cooldownMs = cooldownMs or (GuardConf.Detection or {}).WarnCooldown or 8000

    if notifyAt[id] and (now - notifyAt[id]) < cooldownMs then return end
    notifyAt[id] = now

    -- tip = the yard is after him (hostile, warned): drawn as a warning note
    GSC.Notify.Show(text, duration, tip and "warning" or "info")
end

---o[ MODEL LOADER ]o---
local function ForceLoadModel(modelHash)
    if not IsModelInCdimage(modelHash) then
        devPrint("^1Model not in CD image: " .. tostring(modelHash))
        return false
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(100)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        devPrint("^2Model loaded successfully: " .. tostring(modelHash))
        return true
    else
        devPrint("^1Failed to load model: " .. tostring(modelHash))
        return false
    end
end
---o[ MODEL / RELATIONSHIP SETUP ]o---
local guardModelHash = nil

local function LoadGuardModel()
    if guardModelHash and HasModelLoaded(guardModelHash) then
        return guardModelHash
    end

    for _, modelName in ipairs(Shared.GuardModels()) do
        local hash = GetHashKey(modelName)
        if ForceLoadModel(hash) then
            guardModelHash = hash
            devPrint("^2Guard model ready: " .. modelName)
            return hash
        end
    end

    devPrint("^1Failed to load any guard ped model!")
    return nil
end

local guardGroupHash = nil

local function EnsureGuardGroup()
    if guardGroupHash then return guardGroupHash end

    local groupName = GuardConf.RelationshipGroup or "KASSIPPU_GUARDS"
    pcall(function() AddRelationshipGroup(groupName) end)
    guardGroupHash = GetHashKey(groupName)

    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(3, guardGroupHash, playerGroup)
    SetRelationshipBetweenGroups(3, playerGroup, guardGroupHash)

    return guardGroupHash
end

local function SetGuardsHostile(hostile)
    local group = EnsureGuardGroup()
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    local rel = hostile and 5 or 3 -- 5 = hate, 3 = neutral

    SetRelationshipBetweenGroups(rel, group, playerGroup)
    SetRelationshipBetweenGroups(rel, playerGroup, group)
end

---o[ GUARD SETUP ]o---
-- Combat settings, group and weapon live on the machine that OWNS the ped, so whoever
-- takes him over (the man who created him, or a player who has to fight him) applies them again
local function ApplyGuardSetup(ped, accuracy)
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedKeepTask(ped, true)

    SetPedRelationshipGroupHash(ped, EnsureGuardGroup())

    SetPedCombatAttributes(ped, 0, true)  -- Can fight
    SetPedCombatAttributes(ped, 1, true)  -- Can investigate
    SetPedCombatAttributes(ped, 2, true)  -- Always fight
    SetPedCombatAttributes(ped, 3, true)  -- Can use cover
    SetPedCombatAttributes(ped, 5, true)  -- Can flank
    SetPedCombatAttributes(ped, 46, true) -- Aggressive
    SetPedCombatAbility(ped, 2)
    SetPedCombatRange(ped, 1)             -- 0 = Close, 1 = Medium, 2 = Far
    SetPedCombatMovement(ped, 2)          -- Can run while fighting
    SetPedCombatBehaviour(ped, 0)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanBeTargetted(ped, true)
    SetPedAccuracy(ped, accuracy or GuardConf.Accuracy or 60)

    local weaponHash = GetHashKey(GuardConf.Weapons)
    local ammo = math.max(0, math.floor(tonumber(GuardConf.AmmoCount) or 100)) -- honour the config: 0 = can never fire back

    GiveWeaponToPed(ped, weaponHash, ammo, false, true)
    SetPedAmmo(ped, weaponHash, ammo)
    SetCurrentPedWeapon(ped, weaponHash, true, 0, false, false)
end

---o[ CREATE A GUARD PED - only when the server hands us the job, and networked so all see him ]o---
local function CreateGuardPed(modelHash, coords, heading, accuracy)
    local ped = CreatePed(modelHash, coords.x, coords.y, coords.z, heading or 0.0, true, true, true, true)

    if not DoesEntityExist(ped) then
        devPrint("^1Failed to create guard ped!")
        return nil
    end

    local timeout = GetGameTimer() + 5000
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < timeout do Wait(50) end

    if not NetworkGetEntityIsNetworked(ped) then
        devPrint("^1Guard ped never became networked - removed")
        DeleteEntity(ped)
        return nil
    end

    SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(ped), true)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- outfit: synced, so it is set once, here
    ApplyGuardSetup(ped, accuracy)

    return ped
end

local GUARD_PATROL = "patrol"
local GUARD_SUSPICIOUS = "suspicious"
local GUARD_COMBAT = "combat"
local GUARD_SEARCH = "search"
local GUARD_RETURN = "return"
local GUARD_WARN = "warn"

local Detection = GuardConf.Detection or {}
local bodyAlerted = {}  -- [zoneIndex] = a corpse here has already raised the alarm once

---o[ A DEAD GUARD IS DEAD, WHICHEVER NATIVE YOU ASK ]o---
local function IsGuardDead(ped)
    if not ped or not DoesEntityExist(ped) then return true end

    return IsEntityDead(ped)
        or IsPedDeadOrDying(ped, true)
        or GetEntityHealth(ped) <= 0
end

---o[ NIGHT CHECK ]o---
local function IsNightTime()
    local hour = GetClockHours()
    local from = Detection.NightStartHour or 20
    local to = Detection.NightEndHour or 6

    if from > to then
        return hour >= from or hour < to
    end
    return hour >= from and hour < to
end

---o[ IS HE CROUCH-WALKING? ]o---
local function IsCrouchWalking(crouching, noise)
    if GuardConf.CrouchWalkUndetected == false then return false end
    noise = noise or {}
    return crouching and not noise.running and not noise.jumping and not noise.falling and not noise.shooting
end

---o[ CAN THIS GUARD TELL THE PLAYER IS THERE? ]o---
local function GuardSensesPlayer(guard, playerPed, playerCoords, noise)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return false end

    local guardCoords = GetEntityCoords(ped)
    local offset = playerCoords - guardCoords
    local distSq = (offset.x * offset.x) + (offset.y * offset.y) + (offset.z * offset.z)

    noise = noise or {}

    local crouching = Citizen.InvokeNative(0xD5FE956C70FF370B, playerPed, Citizen.ResultAsInteger()) == 1 -- GetPedCrouchMovement
    local running = noise.running or IsPedRunning(playerPed) or IsPedSprinting(playerPed)

    ---o[ Crouch-walking: neither seen nor heard ]o---
    if IsCrouchWalking(crouching, noise) and guard.state ~= GUARD_COMBAT then
        return false
    end

    local quietMult = crouching and (Detection.CrouchMultiplier or 0.45) or 1.0

    ---o[ Frozen: crouched and not moving ]o---
    local stealth = GuardConf.Stealth or {}

    if stealth.Enabled ~= false and noise.still then
        quietMult = quietMult * (stealth.StillRangeMultiplier or 0.55)
    end

    ---o[ Ears: no line of sight needed, running carries ]o---
    local hearRange
    if noise.shooting then
        hearRange = Detection.HearRangeGunshot or 90.0
    elseif running or noise.jumping or noise.falling then
        hearRange = (Detection.HearRangeRunning or 28.0) * quietMult
    else
        hearRange = (Detection.HearRangeWalking or 10.0) * quietMult
    end

    if distSq <= (hearRange * hearRange) then
        return true, math.sqrt(distSq), "noise"
    end

    ---o[ Up in the canopy ]o---
    if stealth.Enabled ~= false and noise.concealed then
        local lookUp = stealth.ConcealLookUpRange or 8.0
        if distSq > (lookUp * lookUp) then return false end
    end

    ---o[ Eyes: range, then facing, then an actual line of sight ]o---
    local sightRange = (Detection.SightRange or 35.0) * quietMult
    if IsNightTime() then sightRange = sightRange * (Detection.NightMultiplier or 0.6) end

    if distSq > (sightRange * sightRange) then return false end

    local dist = math.sqrt(distSq)
    if dist > 0.01 then
        local forward = GetEntityForwardVector(ped)
        local dot = ((offset.x / dist) * forward.x) + ((offset.y / dist) * forward.y)
        local halfFov = math.cos(math.rad((Detection.FOV or 120.0) / 2))

        if dot < halfFov then return false end -- behind him / out of the cone
    end

    if not HasEntityClearLosToEntity(ped, playerPed, 17) then return false end

    return true, dist, "sight"
end

---o[ TASKING HELPERS ]o---
local function ClearGuardTasks(ped)
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
end

---o[ WALK THERE, ROUND THINGS RATHER THAN THROUGH THEM ]o---
local function TaskWalkTo(ped, point, speed)
    local ok = pcall(function()
        TaskFollowNavMeshToCoord(ped, point.x, point.y, point.z, speed, -1, 1.0, false, 0.0)
    end)

    if not ok then
        pcall(function()
            TaskGoStraightToCoord(ped, point.x, point.y, point.z, speed, -1, 0.0, 0.0)
        end)
    end
end

local function TerritoryConf()
    return GuardConf.Territory or {}
end

local function TerritoryOn()
    return TerritoryConf().Enabled ~= false
end

---o[ Is this point inside the yard's leash? ]o---
local function InLeash(coords, zoneData, extra)
    if not zoneData or not zoneData.size then return true end
    return Shared.InZoneWithMargin(coords, zoneData, (TerritoryConf().LeashMargin or 25.0) + (extra or 0.0))
end

---o[ The nearest point to `coords` that is inside the leash ]o---
local function ClampToLeash(coords, zoneData, inset)
    if not zoneData or not zoneData.size then return coords end

    local c, size = zoneData.coords, zoneData.size
    local m = (TerritoryConf().LeashMargin or 25.0) - (inset or 0.0)
    local x = math.max(c.x - size.x - m, math.min(c.x + size.x + m, coords.x))
    local y = math.max(c.y - size.y - m, math.min(c.y + size.y + m, coords.y))

    return vector3(x, y, coords.z)
end

---o[ Where may this guard be, right now? ]o---
local function GuardInTerritory(guard, coords)
    if #(coords - guard.post.coords) <= 15.0 then return true end

    if guard.role == "hold" then
        local reach = TerritoryConf().HoldRadius or 10.0
        return #(coords - guard.post.coords) <= reach * 1.5
    end
    return InLeash(coords, guard.zoneData)
end

---o[ Keep his combat inside the territory ]o---
local function ApplyCombatArea(guard)
    if not TerritoryOn() then return end

    local x, y, z, radius
    if guard.role == "hold" then
        local p = guard.post.coords
        x, y, z = p.x, p.y, p.z
        radius = TerritoryConf().HoldRadius or 10.0
    else
        local zd = guard.zoneData
        if not zd or not zd.size then return end
        local c = zd.coords
        x, y, z = c.x, c.y, c.z
        radius = math.sqrt((zd.size.x ^ 2) + (zd.size.y ^ 2)) + (TerritoryConf().LeashMargin or 25.0) * 0.5
    end

    pcall(function()
        SetPedSphereDefensiveArea(guard.ped, x, y, z, radius, false, false, false)
    end)
end

---oo[ NETWORKED GUARDS: ONE MAN, MANY PLAYERS ]oo---
-- Every player sees the same ped, but only the machine that OWNS him can task him.
-- Routine (standing, patrolling, walking back) runs on the owner. Anything aimed at THIS player
-- (looking, searching, warning, fighting) takes him over first, then runs.
local myServerId = GetPlayerServerId(PlayerId())

local function Owns(ped)
    return ped ~= nil and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped)
end

---o[ Is another player, still in the fight, using this man right now? ]o---
local function BusyForSomeoneElse(guard)
    local by = Entity(guard.ped).state.gscBusy
    if not by or by == myServerId then return false end

    local player = GetPlayerFromServerId(by)
    if not player or player == -1 then return false end

    local theirPed = GetPlayerPed(player)
    if not theirPed or theirPed == 0 or IsEntityDead(theirPed) then return false end

    return not guard.zoneData or InLeash(GetEntityCoords(theirPed), guard.zoneData, TerritoryConf().HoldFireRange or 45.0)
end

local function SetBusy(guard, busy)
    local state = Entity(guard.ped).state
    local value = busy and myServerId or nil
    if state.gscBusy ~= value then state:set('gscBusy', value, true) end
end

---o[ Routine orders: the owner only, and never over another player's fight ]o---
local function Routine(guard, apply)
    if not Owns(guard.ped) or BusyForSomeoneElse(guard) then return end
    guard.retask = nil
    apply()
    SetBusy(guard, false)
end

---o[ Orders about this player: take him over, then give them ]o---
local function Escalate(guard, apply)
    if Owns(guard.ped) then
        guard.retask = nil
        apply()
        SetBusy(guard, true)
        return
    end

    guard.retask = apply -- run as soon as control arrives
    NetworkRequestControlOfEntity(guard.ped)
end

---o[ THE CIRCUIT: A RECTANGLE AROUND THE OUTSIDE OF THE YARD ]o---
local zoneRingCache = {} -- [zoneIndex] = the perimeter points, in walking order

---o[ Drop a flat point onto the terrain ]o---
local function GroundPoint(x, y, fallbackZ)
    local ok, found, groundZ = pcall(GetGroundZFor_3dCoord, x, y, fallbackZ + 60.0, false)
    if ok and found and groundZ then
        return vector3(x, y, groundZ), true
    end
    return vector3(x, y, fallbackZ), false
end

local function GetZoneRing(zoneIndex, zoneData)
    local cached = zoneRingCache[zoneIndex]
    if cached then return cached end

    local flat = Shared.BuildZonePerimeter(zoneData,
        GuardConf.PatrolMargin or 8.0,
        GuardConf.PatrolPointsPerSide or 3)

    if #flat == 0 then return {} end

    local ring, grounded = {}, 0

    for _, p in ipairs(flat) do
        local point, ok = GroundPoint(p.x, p.y, zoneData.coords.z)
        if ok then grounded = grounded + 1 end
        ring[#ring + 1] = point
    end

    if grounded > 0 then
        zoneRingCache[zoneIndex] = ring
    end

    return ring
end

---o[ POSTS ]o---
local zonePostCache = {} -- [zoneIndex] = the generated posts

local function GetZonePosts(zoneIndex, zoneData)
    if zoneData.guardPosts and #zoneData.guardPosts > 0 then
        return zoneData.guardPosts
    end

    if zoneData.guardSpawn and #zoneData.guardSpawn > 0 then
        local posts = {}
        for _, coords in ipairs(zoneData.guardSpawn) do
            posts[#posts + 1] = { coords = coords, heading = 0.0 }
        end
        return posts
    end

    local cached = zonePostCache[zoneIndex]
    if cached then return cached end

    local flat = Shared.BuildAutoPosts(zoneData)
    if #flat == 0 then return {} end

    local c = zoneData.coords
    local range = GuardConf.DefaultGuardRange or 20.0
    local posts, grounded = {}, 0

    for _, s in ipairs(flat) do
        local point, ok = GroundPoint(s.x, s.y, c.z)
        if ok then grounded = grounded + 1 end
        posts[#posts + 1] = { coords = point, heading = s.heading, range = range }
    end

    if grounded > 0 then zonePostCache[zoneIndex] = posts end

    return posts
end

local function BuildZonePatrolRoute(zoneIndex, zoneData, slotId, guardCount)
    local ring = GetZoneRing(zoneIndex, zoneData)
    local points = #ring
    if points == 0 then return nil end

    local slot = math.max(1, slotId or 1)
    local count = math.max(1, guardCount or 1)

    local start = math.floor(((slot - 1) * points) / count) % points
    local backwards = GuardConf.PatrolAlternateDirection and ((slot % 2) == 0)

    local route = {}
    for i = 0, points - 1 do
        local idx = backwards and ((start - i) % points) or ((start + i) % points)
        route[#route + 1] = ring[idx + 1]
    end

    return route
end

local function ResumeRouteFromNearest(guard)
    if not guard.route or #guard.route == 0 then return end
    if not guard.ped or not DoesEntityExist(guard.ped) then return end

    local coords = GetEntityCoords(guard.ped)
    local bestIdx, bestSq = 1, math.huge

    for i = 1, #guard.route do
        local off = coords - guard.route[i]
        local distSq = (off.x * off.x) + (off.y * off.y) + (off.z * off.z)
        if distSq < bestSq then
            bestSq, bestIdx = distSq, i
        end
    end

    guard.routeIndex = bestIdx
end

---o[ STANDING HIS POST ]o---
local function DutyConf()
    return GuardConf.Duty or {}
end

local function ScenarioHash(scenario)
    return type(scenario) == "string" and GetHashKey(scenario) or scenario
end

local function TaskGuardIdle(guard)
    local ped = guard.ped
    local d = DutyConf()
    local post = guard.post

    local swing = d.IdleLookSwing or 35.0
    SetEntityHeading(ped, ((post.heading or 0.0) + ((math.random() * 2.0) - 1.0) * swing) % 360.0)

    ---o[ Something to do, and not the same thing twice running ]o---
    local scenario = post.scenario
    local list = d.IdleScenarios or {}
    if not scenario and #list > 0 then
        for _ = 1, 3 do
            scenario = list[math.random(#list)]
            if scenario ~= guard.idleScenario then break end
        end
    end
    guard.idleScenario = scenario

    local ok = scenario ~= nil and pcall(function()
        TaskStartScenarioInPlace(ped, ScenarioHash(scenario), -1, true, false, false, false)
    end)

    if not ok then
        pcall(function()
            TaskStandGuard(ped, post.coords.x, post.coords.y, post.coords.z, post.heading or 0.0, "WORLD_HUMAN_GUARD_STAND")
        end)
    end
end

local function TaskGuardPatrol(guard)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    local post = guard.post
    guard.state = GUARD_PATROL
    guard.stateAt = GetGameTimer()
    guard.taskTime = guard.stateAt
    guard.pauseUntil = nil

    if guard.duty == "idle" then
        local span = DutyConf().IdleChangeSeconds or { 40, 80 }
        guard.idleUntil = guard.stateAt + math.random(span[1] or 40, span[2] or span[1] or 80) * 1000
    end

    Routine(guard, function()
        ClearGuardTasks(ped)

        if guard.duty == "idle" then
            TaskGuardIdle(guard)
        elseif guard.route and #guard.route > 0 then
            local point = guard.route[guard.routeIndex] or guard.route[1]
            TaskWalkTo(ped, point, GuardConf.PatrolSpeed or 1.0)
        elseif post.scenario then
            pcall(function()
                TaskStartScenarioInPlace(ped, ScenarioHash(post.scenario), -1, true, false, false, false)
            end)
        else
            pcall(function()
                TaskStandGuard(ped, post.coords.x, post.coords.y, post.coords.z, post.heading or 0.0, "WORLD_HUMAN_GUARD_STAND")
            end)
        end

        SetPedKeepTask(ped, true)
    end)
end

local function TaskGuardPause(guard)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    local now = GetGameTimer()
    guard.pauseUntil = now + ((GuardConf.PatrolPauseSeconds or 6) * 1000)
    guard.taskTime = now

    Routine(guard, function()
        ClearGuardTasks(ped)

        if guard.post.scenario then
            pcall(function()
                TaskStartScenarioInPlace(ped, ScenarioHash(guard.post.scenario), -1, true, false, false, false)
            end)
        end

        SetPedKeepTask(ped, true)
    end)
end

local function TaskGuardInvestigate(guard, coords)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    if TerritoryOn() then coords = ClampToLeash(coords, guard.zoneData, 4.0) end

    guard.state = GUARD_SUSPICIOUS
    guard.stateAt = GetGameTimer()
    guard.taskTime = guard.stateAt
    guard.lastKnown = coords
    guard.goingTo = coords

    Escalate(guard, function()
        ClearGuardTasks(ped)

        pcall(function()
            TaskGoToCoordAnyMeans(ped, coords.x, coords.y, coords.z, 1.4, 0, false, 786603, 0.0)
        end)

        SetPedKeepTask(ped, true)
    end)
end

local function WarnConf()
    return GuardConf.Warning or {}
end

---o[ Hold him at gunpoint ]o---
local function TaskGuardWarn(guard, targetPed, playerCoords, untilAt)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    local wc = WarnConf()
    local now = GetGameTimer()
    local seconds = wc.Seconds or 5

    guard.state = GUARD_WARN
    guard.stateAt = now
    guard.taskTime = now
    guard.warnUntil = untilAt or (now + (seconds * 1000))
    guard.warnFromDist = #(GetEntityCoords(ped) - playerCoords)
    guard.warnFromCentre = guard.zoneData and Shared.ZoneCentreDistance(playerCoords, guard.zoneData) or nil
    guard.lastKnown = playerCoords

    Escalate(guard, function()
        ClearGuardTasks(ped)
        pcall(function()
            TaskAimGunAtEntity(ped, targetPed, (seconds + 1) * 1000, false, false)
        end)

        SetPedKeepTask(ped, true)
    end)
end

local function TaskGuardCombat(guard, targetPed)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    guard.state = GUARD_COMBAT
    guard.stateAt = GetGameTimer()
    guard.taskTime = guard.stateAt
    guard.lastSeen = guard.stateAt
    guard.combatMode = "fight"

    Escalate(guard, function()
        ClearGuardTasks(ped)
        ApplyCombatArea(guard)
        TaskCombatPed(ped, targetPed, 0, 16)
        SetPedKeepTask(ped, true)
    end)
end

---o[ The player is off the yard: shoot from the fence line, do not chase ]o---
local function TaskGuardHoldLine(guard, targetPed)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    guard.combatMode = "hold"
    guard.taskTime = GetGameTimer()

    Escalate(guard, function()
        ClearGuardTasks(ped)

        local maxShot = TerritoryConf().HoldFireRange or 45.0
        local canShoot = #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) <= maxShot
            and HasEntityClearLosToEntity(ped, targetPed, 17)

        local tasked = false
        if canShoot then
            tasked = pcall(function()
                TaskShootAtEntity(ped, targetPed, 3000, GetHashKey("FIRING_PATTERN_BURST_FIRE"), true)
            end)
        end

        if not tasked then
            tasked = pcall(function()
                TaskAimGunAtEntity(ped, targetPed, 3000, false, false)
            end)
        end

        if not tasked then
            pcall(function() TaskTurnPedToFaceEntity(ped, targetPed, 3000) end)
        end

        SetPedKeepTask(ped, true)
    end)
end

---o[ Back inside the territory, at a run ]o---
local function TaskGuardRegroup(guard)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    local target
    if guard.role == "hold" then
        target = guard.post.coords
    else
        target = ClampToLeash(GetEntityCoords(ped), guard.zoneData, 8.0)
    end

    guard.combatMode = "regroup"
    guard.taskTime = GetGameTimer()

    Escalate(guard, function()
        ClearGuardTasks(ped)
        pcall(function()
            TaskGoToCoordAnyMeans(ped, target.x, target.y, target.z, 2.0, 0, false, 786603, 0.0)
        end)

        SetPedKeepTask(ped, true)
    end)
end

local function TaskGuardSearch(guard)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    local around = guard.lastKnown or guard.post.coords
    if TerritoryOn() then around = ClampToLeash(around, guard.zoneData, 12.0) end

    guard.state = GUARD_SEARCH
    guard.stateAt = GetGameTimer()
    guard.taskTime = guard.stateAt

    Escalate(guard, function()
        ClearGuardTasks(ped)
        pcall(function()
            TaskWanderInArea(ped, around.x, around.y, around.z, 12.0, 2.0, 3.0)
        end)

        SetPedKeepTask(ped, true)
    end)
end

local function TaskGuardReturn(guard)
    local ped = guard.ped
    if not ped or not DoesEntityExist(ped) then return end

    local post = guard.post

    guard.state = GUARD_RETURN
    guard.stateAt = GetGameTimer()
    guard.taskTime = guard.stateAt
    guard.lastKnown = nil
    guard.role = nil
    guard.combatMode = nil
    guard.searchParty = nil

    Routine(guard, function()
        pcall(function() RemovePedDefensiveArea(ped, false) end)

        ClearGuardTasks(ped)
        pcall(function()
            TaskGoToCoordAnyMeans(ped, post.coords.x, post.coords.y, post.coords.z, 1.2, 0, false, 786603, 0.0)
        end)

        SetPedKeepTask(ped, true)
    end)
end

---o[ IS THIS SPOT IN THE PLAYER'S VIEW? ]o---
local function IsSpotVisible(coords)
    local ok, visible = pcall(function()
        return IsSphereVisible(coords.x, coords.y, coords.z, 1.5)
    end)

    if not ok then return true end
    return visible and true or false
end

---o[ WHERE DOES A GUARD COME FROM? ]o---
local spawnWaitSince = {} -- ["zone:slot"] = when this slot started waiting

local function PickGuardEntry(zoneIndex, zoneData, post, slotId)
    -- AtPostsOnly: straight onto his own post, whoever is watching
    if GuardConf.AtPostsOnly ~= false or not GuardConf.SpawnOutOfSight then return post.coords, false end

    local tc = TerritoryConf()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local unnoticed = tc.SpawnUnnoticedDistance or 90.0
    local minDist = tc.SpawnMinPlayerDistance or 25.0
    local key = tostring(zoneIndex) .. ":" .. tostring(slotId)

    local function Hidden(coords)
        local d = #(playerCoords - coords)
        if d < minDist then return false end
        return d >= unnoticed or not IsSpotVisible(coords)
    end

    ---o[ 1. His own post ]o---
    if Hidden(post.coords) then
        spawnWaitSince[key] = nil
        return post.coords, false
    end

    ---o[ 2. Somewhere on the yard he can walk in from ]o---
    local candidates = {}
    for _, c in ipairs(zoneData.reinforceSpawns or {}) do candidates[#candidates + 1] = c end
    for _, c in ipairs(GetZoneRing(zoneIndex, zoneData)) do candidates[#candidates + 1] = c end

    for _, c in ipairs(candidates) do
        if Hidden(c) then
            spawnWaitSince[key] = nil
            return c, true
        end
    end

    ---o[ 3. Everything is being watched: wait a little, then least-bad ]o---
    local now = GetGameTimer()
    spawnWaitSince[key] = spawnWaitSince[key] or now
    if (now - spawnWaitSince[key]) < ((tc.MaxSpawnWaitSeconds or 10) * 1000) then
        return nil, false
    end

    local best, bestDist = nil, -1
    candidates[#candidates + 1] = post.coords
    for _, c in ipairs(candidates) do
        local d = #(playerCoords - c)
        if d > bestDist then best, bestDist = c, d end
    end

    spawnWaitSince[key] = nil
    return best, best ~= post.coords
end

---o[ WHO STANDS AND WHO WALKS ]o---
local function DutyFor(roster, slotId)
    if GuardConf.AtPostsOnly ~= false then return "idle" end -- everyone stands his post

    local ids = {}
    for _, slot in ipairs(roster.manned or {}) do ids[#ids + 1] = slot.id end
    table.sort(ids)

    local idleCount = math.floor((#ids * (DutyConf().IdleShare or 0.5)) + 0.5)
    local walkers = math.max(1, #ids - idleCount)

    for i, id in ipairs(ids) do
        if id == slotId then
            if i <= idleCount then return "idle" end
            return "patrol", i - idleCount, walkers
        end
    end

    return "patrol", 1, walkers
end

---o[ THE SERVER'S PED FOR A NETWORK ID, IF IT HAS STREAMED IN HERE ]o---
local function ResolveGuardPed(netId)
    if type(netId) ~= 'number' or not NetworkDoesNetworkIdExist(netId) then return nil end

    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped and ped ~= 0 and DoesEntityExist(ped) then return ped end
    return nil
end

---o[ RECONCILE LOCAL GUARDS WITH THE SERVER ROSTER ]o---
-- The server creates and removes the men; this only keeps track of which ped is which slot
local function ReconcileZoneGuards(zoneIndex, zoneData)
    local roster = zoneRoster[zoneIndex]

    local now = GetGameTimer()

    ---o[ No roster yet: ask, and stand down until it arrives ]o---
    if not roster then
        if not rosterAsked[zoneIndex] or (now - rosterAsked[zoneIndex]) > 5000 then
            rosterAsked[zoneIndex] = now
            TriggerServerEvent('gsc_kassippu_alert:server:requestZoneRoster', zoneData.name or zoneData.label)
        end
        return
    end

    ---o[ Stale roster: re-ask now and then ]o---
    if (now - (roster.receivedAt or 0)) > 60000
        and (not rosterAsked[zoneIndex] or (now - rosterAsked[zoneIndex]) > 30000) then
        rosterAsked[zoneIndex] = now
        TriggerServerEvent('gsc_kassippu_alert:server:requestZoneRoster', zoneData.name or zoneData.label)
    end

    local posts = GetZonePosts(zoneIndex, zoneData)
    if #posts == 0 then return end

    local guards = zoneGuards[zoneIndex]
    if not guards then
        guards = {}
        zoneGuards[zoneIndex] = guards
    end

    local manned = {}
    for _, slot in ipairs(roster.manned or {}) do manned[slot.id] = slot end

    ---o[ Anybody the server no longer has on duty, or who was replaced ]o---
    for slotId, guard in pairs(guards) do
        local slot = manned[slotId]

        if not slot or slot.netId ~= guard.netId then
            local body = not slot and guard.deadAt and DoesEntityExist(guard.ped)
            if not body then guards[slotId] = nil end -- a body stays tracked until the server removes it
        end
    end

    ---o[ Every man the server has put in the world ]o---
    for slotId, slot in pairs(manned) do
        local post = posts[slot.post]

        if post and slot.netId and not guards[slotId] then
            local ped = ResolveGuardPed(slot.netId)

            if ped then -- nil = not streamed in here yet, try next pass
                local duty, walkerIndex, walkers = DutyFor(roster, slotId)
                local route = nil

                if post.patrolPoints then
                    duty, route = "patrol", post.patrolPoints
                elseif duty == "patrol" then
                    route = BuildZonePatrolRoute(zoneIndex, zoneData, walkerIndex, walkers)
                end

                guards[slotId] = {
                    ped = ped,
                    netId = slot.netId,
                    slotId = slotId,
                    duty = duty,
                    post = post,
                    zoneIndex = zoneIndex,
                    zoneData = zoneData,
                    accuracy = roster.accuracy,
                    state = GUARD_PATROL,
                    stateAt = now,
                    route = route,
                    routeIndex = 1,
                    range = post.range or GuardConf.DefaultGuardRange or 20.0,
                    taskTime = now,
                    owned = false, -- the upkeep loop sets him up when this machine owns him
                }
            end
        end
    end
end

---o[ THE SERVER ASKS THIS PLAYER TO CREATE ONE GUARD ]o---
RegisterNetEvent('gsc_kassippu_alert:client:spawnGuard', function(zoneName, slotId, postIndex, leaseId, accuracy)
    local netId = nil

    for i, zoneData in ipairs(Config.TreeZones) do
        if (zoneData.name or zoneData.label) == zoneName then
            local post = GetZonePosts(i, zoneData)[postIndex]
            local modelHash = post and LoadGuardModel()
            local entry = modelHash and PickGuardEntry(i, zoneData, post, slotId) -- nil = being watched, try later

            if entry then
                local ped = CreateGuardPed(modelHash, entry, post.heading, accuracy)
                if ped then
                    netId = NetworkGetNetworkIdFromEntity(ped)
                    devPrint(string.format("Created guard for %s slot %d (net %d)", zoneName, slotId, netId))
                end
            end
            break
        end
    end

    TriggerServerEvent('gsc_kassippu_alert:server:guardSpawned', leaseId, netId)
end)

---o[ This machine just became his owner: set him up and give him his orders ]o---
local function TakeOverGuard(guard)
    ApplyGuardSetup(guard.ped, guard.accuracy)
    if guard.retask then return end -- an order of ours is waiting; the loop runs it

    if guard.state == GUARD_PATROL then
        local leash = DutyConf().IdleLeashDistance or 4.0
        if #(GetEntityCoords(guard.ped) - guard.post.coords) > leash then
            TaskGuardReturn(guard) -- walked in from elsewhere, or pulled off his post
        else
            TaskGuardPatrol(guard)
        end
    elseif guard.state == GUARD_RETURN then
        TaskGuardReturn(guard)
    end
end

---o[ SPAWN / DESPAWN A ZONE'S GUARDS ]o---
-- The server owns the men; these only start and stop watching them
function Guards.Spawn(zoneIndex, zoneData)
    if GuardConf.Enabled == false then return end

    RefreshLawStatus()
    ReconcileZoneGuards(zoneIndex, zoneData)
end

function Guards.Despawn(zoneIndex)
    if not zoneGuards[zoneIndex] then return end

    zoneGuards[zoneIndex] = nil
    zoneAlertUntil[zoneIndex] = nil
    ClearSuspicion(zoneIndex)
    devPrint("Stopped watching guards for zone index " .. tostring(zoneIndex))
end

function Guards.Cleanup()
    for zoneIndex in pairs(zoneGuards) do
        Guards.Despawn(zoneIndex)
    end
    SetGuardsHostile(false)
end

---o[ ROSTER FROM THE SERVER ]o---
RegisterNetEvent('gsc_kassippu_alert:client:zoneRoster', function(payload)
    if type(payload) ~= 'table' or not payload.zone then return end

    for i, zoneData in ipairs(Config.TreeZones) do
        if (zoneData.name or zoneData.label) == payload.zone then
            local previous = zoneRoster[i]
            payload.receivedAt = GetGameTimer()
            zoneRoster[i] = payload

            local wasBroken = previous and previous.broken

            ---o[ The last man just went down ]o---
            if payload.broken and not wasBroken then
                ClearZoneCompletely(i)

            elseif wasBroken and not payload.broken then
                local pCoords = GetEntityCoords(PlayerPedId())
                if Shared.InZone(pCoords, zoneData) then
                    ZoneNotify(i, "wave", Config.Text.GuardWaveNotify, 5000, true, 30000)
                end
            end

            devPrint(string.format("Roster for %s: wave %d, %d on duty%s",
                payload.zone, payload.wave or 0, #(payload.manned or {}),
                payload.waveIn and (", next shift in " .. math.floor(payload.waveIn) .. "s") or ""))
            return
        end
    end
end)

---o[ ALERT / CALM ]o---
local function AnyZoneAlerted()
    local now = GetGameTimer()
    for _, expiresAt in pairs(zoneAlertUntil) do
        if expiresAt and now < expiresAt then return true end
    end
    return false
end

local function AlertZoneGuards(zoneIndex, targetPed)
    local guards = zoneGuards[zoneIndex]
    if not guards or next(guards) == nil then
        devPrint("Alert received but no guards are spawned for zone " .. tostring(zoneIndex))
        return false
    end

    zoneAlertUntil[zoneIndex] = GetGameTimer() + (GuardConf.CalmDownTime or 30000)
    SetGuardsHostile(true)

    local alive = {}
    for _, guard in pairs(guards) do
        if guard.ped and not IsGuardDead(guard.ped) then alive[#alive + 1] = guard end
    end

    ---o[ Who hunts and who holds ]o---
    local holdCount = 0
    if TerritoryOn() and #alive >= 2 then
        holdCount = math.floor(#alive * (TerritoryConf().HoldShare or 0.25))
        holdCount = math.max(0, math.min(holdCount, #alive - 1))
    end

    if holdCount > 0 then
        local from = GetEntityCoords(targetPed)
        table.sort(alive, function(a, b)
            return #(GetEntityCoords(a.ped) - from) > #(GetEntityCoords(b.ped) - from)
        end)
    end

    for i, guard in ipairs(alive) do
        local role = (i <= holdCount) and "hold" or "hunt"

        if guard.state == GUARD_COMBAT then
            if guard.role ~= role then
                guard.role = role
                if Owns(guard.ped) then ApplyCombatArea(guard) end
            end
        else
            guard.role = role
            TaskGuardCombat(guard, targetPed)
        end
    end

    devPrint(string.format("^1%d guards engaging the trespasser (%d holding posts)", #alive, holdCount))
    return #alive > 0
end

---o[ ownedOnly: somebody ELSE set it off - only the men this machine already runs go looking ]o---
local function SearchZoneGuards(zoneIndex, around, ownedOnly)
    local guards = zoneGuards[zoneIndex]
    if not guards then return end

    around = around or zoneLastKnown[zoneIndex]

    local available = {}
    for _, guard in pairs(guards) do
        if guard.ped and not IsGuardDead(guard.ped)
            and (not ownedOnly or Owns(guard.ped))
            and guard.state ~= GUARD_COMBAT and guard.state ~= GUARD_WARN then
            available[#available + 1] = guard
        end
    end

    if not around or not TerritoryOn() then
        for _, guard in ipairs(available) do TaskGuardSearch(guard) end
        devPrint("Guards are searching zone index " .. tostring(zoneIndex))
        return
    end

    table.sort(available, function(a, b)
        return #(GetEntityCoords(a.ped) - around) < #(GetEntityCoords(b.ped) - around)
    end)

    local party = TerritoryConf().SearchParty or 2
    for i, guard in ipairs(available) do
        if i > party then break end
        guard.lastKnown = around
        guard.searchParty = true
        TaskGuardSearch(guard)
    end

    devPrint(string.format("Search party of %d sent in zone %s", math.min(party, #available), tostring(zoneIndex)))
end

---o[ THE YARD IS CLEARED: STOP WATCHING IT (the server removes the bodies) ]o---
function ClearZoneCompletely(zoneIndex)
    local wasHere = zoneGuards[zoneIndex] ~= nil

    zoneGuards[zoneIndex] = nil
    zoneAlertUntil[zoneIndex] = nil
    bodyAlerted[zoneIndex] = nil
    ClearSuspicion(zoneIndex)

    if not AnyZoneAlerted() then
        SetGuardsHostile(false)
    end

    zoneWarned[zoneIndex] = nil

    if wasHere then
        ZoneNotify(zoneIndex, "cleared", Config.Text.GuardZoneClearedNotify, 5000, true, 30000)
    end
    devPrint("^2Zone " .. tostring(zoneIndex) .. " cleared")
end

local function CalmZoneGuards(zoneIndex)
    local guards = zoneGuards[zoneIndex]
    zoneAlertUntil[zoneIndex] = nil
    zoneWarnUntil[zoneIndex] = nil

    if (GuardConf.Suspicion or {}).Enabled == false then
        zoneSuspLevel[zoneIndex] = nil
        zoneHostileSince[zoneIndex] = nil
        zoneLawCalled[zoneIndex] = nil
    end

    if zoneWarned[zoneIndex] then
        zoneWarned[zoneIndex] = nil
        ZoneNotify(zoneIndex, "lost", Config.Text.GuardLostYouNotify, 3500, false)
    end

    if not AnyZoneAlerted() then
        SetGuardsHostile(false)
    end

    if not guards then return end

    for _, guard in pairs(guards) do
        if guard.ped and not IsGuardDead(guard.ped) then
            TaskGuardReturn(guard) -- walk back to the post, then settle
        end
    end

    devPrint("Guards standing down for zone index " .. tostring(zoneIndex))
end

local function SuspConf()
    return GuardConf.Suspicion or {}
end

---o[ What makes them open fire (GuardSpawnConf.FireOn) ]o---
-- Defaults are the old behaviour, for a config without FireOn
local FIRE_DEFAULTS = {
    Running = true, Jumping = true, Gunshot = true, AimAtGuard = true,
    SeenClimbing = false, SeenArmed = false, Falling = false, TooClose = "warn",
    SeenUpright = false,
}

local function FireRule(key)
    local rules = GuardConf.FireOn
    if rules and rules[key] ~= nil then return rules[key] end
    return FIRE_DEFAULTS[key]
end

local function LevelFor(score)
    local c = SuspConf()
    if score >= (c.Hostile or 75) then return SUSP_HOSTILE end
    if score >= (c.Investigate or 50) then return SUSP_INVESTIGATE end
    if score >= (c.Notice or 25) then return SUSP_NOTICE end
    return SUSP_CALM
end

---o[ Push a zone straight to the top ]o---
local function ForceHostile(zoneIndex, reason)
    local c = SuspConf()
    zoneSuspicion[zoneIndex] = c.Max or 100.0
    zoneForced[zoneIndex] = true
    devPrint(string.format("Zone %s forced hostile: %s", tostring(zoneIndex), reason))
end

---o[ Call the Sheriff ]o---
local function CallLaw(zoneIndex)
    local zoneData = Config.TreeZones[zoneIndex]
    if not zoneData then return end

    local now = GetGameTimer()
    local last = zoneLawCalled[zoneIndex]
    local repeatMs = ((GuardConf.LawDispatch or {}).RepeatSeconds or 30) * 1000

    if last and (now - last) < repeatMs then return end
    zoneLawCalled[zoneIndex] = now

    TriggerServerEvent('gsc_kassippu_alert:server:AreaTrespass',
        zoneData.coords, zoneData.label, zoneData.name,
        GetEntityCoords(PlayerPedId()), last ~= nil)
end

---o[ The yard turns hostile: guns out, player told, law called ]o---
local function GoHostile(zoneIndex, playerPed, text)
    local now = GetGameTimer()
    zoneSuspLevel[zoneIndex] = SUSP_HOSTILE
    zoneLevelSince[zoneIndex] = now
    zoneHostileSince[zoneIndex] = now
    zoneWarnUntil[zoneIndex] = nil

    AlertZoneGuards(zoneIndex, playerPed)
    zoneWarned[zoneIndex] = true
    ZoneNotify(zoneIndex, "hostile", text or Config.Text.GuardHostileNotify, 5000, true)

    CallLaw(zoneIndex)
end

---o[ What GSC.Zones saw the player doing ]o---
function Guards.ReportPlayerNoise(zoneIndex, noise)
    if not zoneIndex then return end

    if LawExempt() then
        zoneNoise[zoneIndex] = nil
        return
    end

    zoneNoise[zoneIndex] = noise

    if not noise or not (noise.alarm or noise.falling) then return end

    local now = GetGameTimer()

    ---o[ Held at gunpoint and told to back off ]o---
    if zoneWarnUntil[zoneIndex] and now < zoneWarnUntil[zoneIndex] and not noise.shooting then
        return
    end

    local guards = zoneGuards[zoneIndex]
    local staffed = guards ~= nil and next(guards) ~= nil

    ---o[ Did anybody actually see or hear it? ]o---
    local witnessed = GuardConf.LoudMovementNeedsWitness == false
        or noise.shooting
        or (zoneSensedAt[zoneIndex] ~= nil and (now - zoneSensedAt[zoneIndex]) < 1500)

    if noise.alarm and (GuardConf.LawDispatch or {}).OnLoudMovement ~= false and (witnessed or not staffed) then
        CallLaw(zoneIndex)
    end

    ---o[ Only what FireOn lists opens fire; the rest is left to suspicion ]o---
    local fires = (noise.running and FireRule("Running")) or (noise.jumping and FireRule("Jumping"))
        or (noise.shooting and FireRule("Gunshot")) or (noise.falling and FireRule("Falling"))
    if not fires then return end
    if not staffed or not witnessed then return end

    if zoneAlertUntil[zoneIndex] and now < zoneAlertUntil[zoneIndex] then
        zoneAlertUntil[zoneIndex] = now + (GuardConf.CalmDownTime or 30000)
        zoneSuspicion[zoneIndex] = SuspConf().Max or 100.0
        zoneHostileSince[zoneIndex] = now
        return
    end

    ForceHostile(zoneIndex, (noise.shooting and "gunfire" or (noise.jumping and "jumping"
        or (noise.falling and "falling" or "running"))) .. " in the yard")
    GoHostile(zoneIndex, PlayerPedId())
end

---o[ One second of the yard making its mind up ]o---
local function UpdateSuspicion(zoneIndex, witnesses, heard, playerPed)
    local c = SuspConf()
    local score = zoneSuspicion[zoneIndex] or 0.0
    local noise = zoneNoise[zoneIndex] or {}

    local gain = 0.0
    local loud = noise.running or noise.jumping or noise.falling

    ---o[ Seen ]o---
    if witnesses > 0 then
        gain = gain + (noise.running and (c.SeenRunning or 18.0) or (c.SeenWalking or 5.0))

        if noise.armed then
            gain = gain + (c.SeenArmed or 10.0)
            loud = true
        end
        if noise.climbing then
            gain = gain + (c.SeenClimbing or 20.0)
            loud = true
        end

        if witnesses > 1 then
            gain = gain * (1.0 + ((witnesses - 1) * (c.PerExtraWitness or 0.45)))
        end
    end

    ---o[ Heard ]o---
    if heard and noise.running then
        gain = gain + (c.HeardRunning or 9.0)
    end

    ---o[ Noise nobody saw or heard ]o---
    if noise.alarm and witnesses == 0 and not heard then
        gain = gain + (c.DistantNoise or 3.0)
    end

    ---o[ Things that are loud wherever he is ]o---
    if noise.jumping then gain = gain + (c.Jumping or 12.0) end
    if noise.falling then gain = gain + (c.Falling or 7.0) end

    ---o[ Held at gunpoint ]o---
    local now = GetGameTimer()
    if zoneWarnUntil[zoneIndex] and now < zoneWarnUntil[zoneIndex] then
        gain = 0.0
    end

    if noise.crouching then gain = gain * (c.CrouchMultiplier or 0.5) end

    if gain > 0.0 then
        score = score + gain
    elseif zoneWarnUntil[zoneIndex] and now < zoneWarnUntil[zoneIndex] then
    else
        ---o[ Waiting it out ]o---
        local st = GuardConf.Stealth or {}
        local decay = c.DecayPerSecond or 4.0

        if st.Enabled ~= false then
            if noise.concealed then
                decay = decay * (st.ConcealDecayMultiplier or 2.5)
            elseif noise.still then
                decay = decay * (st.StillDecayMultiplier or 2.0)
            end
        end

        score = score - decay
    end

    score = math.max(0.0, math.min(c.Max or 100.0, score))

    ---o[ Being watched is not a crime ]o---
    if not loud and not zoneForced[zoneIndex] then
        local ceiling = c.PassiveCeiling or (c.Hostile or 75.0)
        if score > ceiling then score = ceiling end
    end

    if score <= 0.0 then zoneForced[zoneIndex] = nil end

    zoneSuspicion[zoneIndex] = score

    ---o[ Hostility has a grace, so one tick behind a rock cannot end it ]o---
    local level = LevelFor(score)
    local previous = zoneSuspLevel[zoneIndex] or SUSP_CALM

    if level == SUSP_HOSTILE then
        zoneHostileSince[zoneIndex] = now
    elseif zoneHostileSince[zoneIndex] then
        local graceMs = (c.HostileGraceSeconds or 12) * 1000
        if (now - zoneHostileSince[zoneIndex]) < graceMs then
            level = SUSP_HOSTILE -- still hot, even though the score has dipped
        else
            zoneHostileSince[zoneIndex] = nil
        end
    end

    ---o[ ...and the lower levels a margin, so a score on a line cannot flicker ]o---
    if previous ~= SUSP_HOSTILE and LEVEL_RANK[level] < LEVEL_RANK[previous] then
        local line = (previous == SUSP_INVESTIGATE) and (c.Investigate or 50) or (c.Notice or 25)
        local settledFor = now - (zoneLevelSince[zoneIndex] or 0)

        if score >= line - (c.LevelDropMargin or 8.0) or settledFor < (c.LevelMinSeconds or 3) * 1000 then
            level = previous
        end
    end

    ---o[ Act on a change of mind ]o---
    zoneSuspLevel[zoneIndex] = level

    if level ~= previous then
        zoneLevelSince[zoneIndex] = now
        devPrint(string.format("Zone %s: %s -> %s (%.0f)", tostring(zoneIndex), previous, level, score))

        local rising = LEVEL_RANK[level] > LEVEL_RANK[previous]

        if level == SUSP_HOSTILE then
            GoHostile(zoneIndex, playerPed)

        elseif level == SUSP_INVESTIGATE then
            SearchZoneGuards(zoneIndex)
            if rising then
                zoneWarned[zoneIndex] = true
                ZoneNotify(zoneIndex, "search", Config.Text.GuardSearchingNotify, 3500, false)
            end

        elseif level == SUSP_NOTICE then
            if rising then
                ZoneNotify(zoneIndex, "spotted", Config.Text.GuardSpottedNotify, 2500, false)
            end

        elseif level == SUSP_CALM then
            zoneLawCalled[zoneIndex] = nil
            if zoneWarned[zoneIndex] or previous == SUSP_HOSTILE or previous == SUSP_INVESTIGATE then
                CalmZoneGuards(zoneIndex)
            end
        end
    end

    return level
end

function ClearSuspicion(zoneIndex)
    zoneSuspicion[zoneIndex] = nil
    zoneSuspLevel[zoneIndex] = nil
    zoneHostileSince[zoneIndex] = nil
    zoneNoise[zoneIndex] = nil
    zoneLawCalled[zoneIndex] = nil
    zoneForced[zoneIndex] = nil
    zoneWarned[zoneIndex] = nil
    zoneLastKnown[zoneIndex] = nil
    zoneSensedAt[zoneIndex] = nil
    zoneLevelSince[zoneIndex] = nil
    zoneWarnUntil[zoneIndex] = nil
end

---o[ BODIES - the server removes them after BodyCleanupSeconds ]o---
local function HandleDeadGuard(guard, zoneData, now)
    guard.deadAt = guard.deadAt or now
    guard.state = GUARD_PATROL -- no AI for a corpse
    guard.lastKnown = nil
    guard.retask = nil

    ---o[ Tell the server his post is empty (it checks for itself too) ]o---
    if not guard.reported then
        guard.reported = true

        if guard.slotId and zoneData then
            TriggerServerEvent('gsc_kassippu_alert:server:guardKilled',
                zoneData.name or zoneData.label, guard.slotId)
        end
    end
end

---o[ GUARD UPKEEP THREAD ]o---
CreateThread(function()
    while true do
        if next(zoneGuards) == nil then
            Wait(3000)
            goto continue
        end

        local now = GetGameTimer()
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local playerDead = IsEntityDead(playerPed)
        local busy = false -- any guard doing something other than patrolling

        local playerCrouching = Citizen.InvokeNative(0xD5FE956C70FF370B, playerPed, Citizen.ResultAsInteger()) == 1 -- GetPedCrouchMovement
        local rangeGraceMs = (GuardConf.RangeGraceSeconds or 2) * 1000
        local rangeNeedsLos = GuardConf.RangeRequiresLineOfSight ~= false
        local crouchMult = GuardConf.RangeCrouchMultiplier or 0.5
        local suspicionOn = (GuardConf.Suspicion or {}).Enabled ~= false

        local exempt = LawExempt()

        ---o[ What is he pointing a gun at? ]o---
        local aimedAt = nil
        local aimMs = FireRule("AimAtGuard") and (GuardConf.AimAtGuardSeconds or 1.0) * 1000 or 0
        local tooClose = FireRule("TooClose") -- "fire" | "warn" | false
        if aimMs > 0 then
            local okAim, aiming, entity = pcall(GetEntityPlayerIsFreeAimingAt, PlayerId())
            if okAim and aiming and entity and entity ~= 0 then
                aimedAt = entity
            else
                local okTarget, targeting, target = pcall(GetPlayerTargetEntity, PlayerId())
                if okTarget and targeting and target and target ~= 0 then aimedAt = target end
            end
        end

        for zoneIndex, guards in pairs(zoneGuards) do
            local zoneData = Config.TreeZones[zoneIndex]
            local insideZone = zoneData ~= nil and Shared.InZone(playerCoords, zoneData)
            local alerted = zoneAlertUntil[zoneIndex] and now < zoneAlertUntil[zoneIndex]
            local zoneLevel = zoneSuspLevel[zoneIndex] or SUSP_CALM
            local crouchWalking = IsCrouchWalking(playerCrouching, zoneNoise[zoneIndex])

            if zoneAlertUntil[zoneIndex] and not alerted then
                CalmZoneGuards(zoneIndex)
                alerted = false
            end

            ---o[ Make the local peds match the server's roster ]o---
            if zoneData then ReconcileZoneGuards(zoneIndex, zoneData) end

            ---o[ Is there a body lying about? ]o---
            local corpseCoords = nil
            for _, guard in pairs(guards) do
                if guard.ped and guard.deadAt and DoesEntityExist(guard.ped) then
                    corpseCoords = GetEntityCoords(guard.ped)
                    break
                end
            end

            if not corpseCoords then bodyAlerted[zoneIndex] = nil end

            ---o[ Tallied across the guard loop, spent once at the end of it ]o---
            local witnesses, heardHim = 0, false

            ---o[ How many men may break off to look ]o---
            local investigators = 0
            for _, g in pairs(guards) do
                if g.ped and not g.deadAt and g.state == GUARD_SUSPICIOUS then
                    investigators = investigators + 1
                end
            end
            local investigatorCap = (zoneLevel == SUSP_NOTICE) and (SuspConf().NoticeInvestigators or 1)
                or (TerritoryConf().SearchParty or 2)

            for slotId, guard in pairs(guards) do
                ---o[ Gone: removed by the server, or streamed out - reconcile picks him up again ]o---
                if not guard.ped or not DoesEntityExist(guard.ped) then
                    guards[slotId] = nil
                    goto nextGuard
                end

                if IsGuardDead(guard.ped) then
                    HandleDeadGuard(guard, zoneData, now)
                    goto nextGuard
                end

                ---o[ Did he just come to this machine? Set him up, and run any order that was waiting ]o---
                do
                    local owned = NetworkHasControlOfEntity(guard.ped)
                    if owned and not guard.owned then
                        guard.owned = true
                        TakeOverGuard(guard)
                    elseif not owned then
                        guard.owned = false
                    end

                    if owned and guard.retask then
                        local order = guard.retask
                        guard.retask = nil
                        order()
                        SetBusy(guard, true)
                    end
                end

                if playerDead then
                    if guard.state ~= GUARD_PATROL and guard.state ~= GUARD_RETURN then
                        TaskGuardReturn(guard)
                    end
                    goto nextGuard
                end

                do
                    local det = Detection

                    local sensed, dist, how = false, nil, nil
                    local tracking = guard.state == GUARD_COMBAT and zoneData ~= nil
                        and InLeash(playerCoords, zoneData, TerritoryConf().HoldFireRange or 45.0)

                    local looks = insideZone or tracking or aimedAt == guard.ped
                    if exempt and guard.state ~= GUARD_COMBAT then looks = false end

                    if looks then
                        sensed, dist, how = GuardSensesPlayer(guard, playerPed, playerCoords, zoneNoise[zoneIndex])

                        if sensed and insideZone then
                            zoneLastKnown[zoneIndex] = playerCoords
                            zoneSensedAt[zoneIndex] = now
                            if how == "sight" then
                                witnesses = witnesses + 1
                            else
                                heardHim = true
                            end
                        end
                    end

                    if guard.state ~= GUARD_PATROL then busy = true end

                    ---o[ A GUN POINTED AT HIM ]o---
                    if aimedAt == guard.ped and sensed and how == "sight"
                        and guard.state ~= GUARD_COMBAT and not exempt then
                        guard.aimedSince = guard.aimedSince or now

                        if (now - guard.aimedSince) >= aimMs then
                            guard.aimedSince = nil
                            devPrint("Guard opening fire: a gun was pointed at him")
                            ForceHostile(zoneIndex, "a gun pointed at a guard")
                            GoHostile(zoneIndex, playerPed, Config.Text.GuardAimedNotify)
                            busy = true
                            goto nextGuard
                        end
                    else
                        guard.aimedSince = nil
                    end

                    ---o[ TOO CLOSE TO THIS MAN ]o---
                    local inRange = false

                    if tooClose and insideZone and guard.range and not crouchWalking and not exempt then
                        local guardCoords = GetEntityCoords(guard.ped)
                        local rOffset = playerCoords - guardCoords
                        local rDistSq = (rOffset.x * rOffset.x) + (rOffset.y * rOffset.y) + (rOffset.z * rOffset.z)
                        local reach = playerCrouching and (guard.range * crouchMult) or guard.range

                        if rDistSq <= (reach * reach)
                            and (not rangeNeedsLos or HasEntityClearLosToEntity(guard.ped, playerPed, 17)) then
                            inRange = true
                        end
                    end

                    if inRange then
                        guard.inRangeSince = guard.inRangeSince or now
                    else
                        guard.inRangeSince = nil
                    end

                    if guard.state ~= GUARD_COMBAT and guard.state ~= GUARD_WARN
                        and guard.inRangeSince
                        and (now - guard.inRangeSince) >= rangeGraceMs then

                        ---o[ Close, but is he BRAZEN? ]o---
                        local st = GuardConf.Stealth or {}
                        local spared = st.Enabled ~= false
                            and st.RangeSparesCrouched ~= false
                            and playerCrouching
                            and zoneLevel == SUSP_CALM

                        if spared then
                            zoneSuspicion[zoneIndex] = (zoneSuspicion[zoneIndex] or 0.0)
                                + (st.RangeSuspicionPerSecond or 22.0)
                            busy = true
                            goto nextGuard
                        end

                        ---o[ Upright and close: challenge him first ]o---
                        local wc = WarnConf()
                        local warnActive = zoneWarnUntil[zoneIndex] and now < zoneWarnUntil[zoneIndex]
                        local warnedRecently = zoneWarnedAt[zoneIndex]
                            and (now - zoneWarnedAt[zoneIndex]) < ((wc.MemorySeconds or 90) * 1000)

                        if tooClose == "warn" and wc.Enabled ~= false and (warnActive or not warnedRecently) then
                            TaskGuardWarn(guard, playerPed, playerCoords, warnActive and zoneWarnUntil[zoneIndex] or nil)
                            guard.inRangeSince = nil

                            if not warnActive then
                                zoneWarnedAt[zoneIndex] = now
                                zoneWarnUntil[zoneIndex] = guard.warnUntil
                                ZoneNotify(zoneIndex, "warn", string.format(Config.Text.GuardWarnNotify
                                    or "A guard has his gun on you: \"Back off. You have %d seconds.\"",
                                    wc.Seconds or 5), 4000, true, 1000)
                                devPrint("Guard challenging the trespasser")
                            end

                            busy = true
                            goto nextGuard
                        end

                        devPrint("Guard opening fire: trespasser inside his range")

                        ForceHostile(zoneIndex, warnedRecently and "back in range after a warning"
                            or "trespasser inside a guard's range")

                        if tooClose ~= "warn" then
                            GoHostile(zoneIndex, playerPed, Config.Text.GuardHostileNotify) -- no warning: straight to guns
                        elseif warnedRecently then
                            GoHostile(zoneIndex, playerPed, Config.Text.GuardRewarnNotify)
                        else
                            AlertZoneGuards(zoneIndex, playerPed)
                        end
                        busy = true
                        goto nextGuard
                    end

                    ---o[ SHOT AT: always fight back ]o---
                    if guard.state ~= GUARD_COMBAT
                        and HasEntityBeenDamagedByEntity(guard.ped, playerPed, true) then
                        ClearEntityLastDamageEntity(guard.ped)
                        TaskGuardCombat(guard, playerPed)
                        ForceHostile(zoneIndex, "a guard was shot")
                        AlertZoneGuards(zoneIndex, playerPed)
                        busy = true
                        goto nextGuard
                    end

                    ---o[ STRAYED OFF THE YARD ]o---
                    if TerritoryOn() and zoneData and guard.state ~= GUARD_COMBAT then
                        local pedCoords = GetEntityCoords(guard.ped)

                        if not GuardInTerritory(guard, pedCoords) then
                            guard.strayedAt = guard.strayedAt or now
                            local teleportMs = (TerritoryConf().StrayTeleportSeconds or 20) * 1000

                            if (now - guard.strayedAt) > teleportMs and Owns(guard.ped)
                                and not BusyForSomeoneElse(guard)
                                and not IsSpotVisible(pedCoords) and not IsSpotVisible(guard.post.coords) then
                                local p = guard.post.coords
                                SetEntityCoords(guard.ped, p.x, p.y, p.z, false, false, false, false)
                                guard.strayedAt = nil
                                ResumeRouteFromNearest(guard)
                                TaskGuardPatrol(guard)
                                devPrint("Strayed guard put back on his post")
                            elseif guard.state ~= GUARD_RETURN or (now - guard.taskTime) > 15000 then
                                TaskGuardReturn(guard)
                            end

                            busy = true
                            goto nextGuard
                        end

                        guard.strayedAt = nil
                    end

                    ---o[ COMBAT ]o---
                    if guard.state == GUARD_COMBAT then
                        if sensed then
                            guard.lastSeen = now
                            guard.lastKnown = playerCoords
                        end

                        local territory = TerritoryOn() and zoneData ~= nil
                        local guardOut = territory and not GuardInTerritory(guard, GetEntityCoords(guard.ped))
                        local playerOut = territory and guard.role ~= "hold"
                            and not InLeash(playerCoords, zoneData)

                        if not alerted and (now - (guard.lastSeen or now)) > ((det.LoseTargetSeconds or 8) * 1000) then
                            TaskGuardSearch(guard) -- lost him, sweep the area

                        elseif guardOut then
                            if guard.combatMode ~= "regroup" or (now - guard.taskTime) > 6000 then
                                TaskGuardRegroup(guard)
                            end

                        elseif playerOut then
                            if guard.combatMode ~= "hold" or (now - guard.taskTime) > 3000 then
                                TaskGuardHoldLine(guard, playerPed)
                            end

                        elseif guard.combatMode ~= "fight" then
                            guard.combatMode = "fight"
                            guard.taskTime = now
                            local ped = guard.ped
                            Escalate(guard, function()
                                ClearGuardTasks(ped)
                                ApplyCombatArea(guard)
                                TaskCombatPed(ped, playerPed, 0, 16)
                            end)

                        elseif not IsPedInCombat(guard.ped, playerPed) and (now - guard.taskTime) > 3000 then
                            guard.taskTime = now
                            local ped = guard.ped
                            Escalate(guard, function() TaskCombatPed(ped, playerPed, 0, 16) end)
                        end

                    ---o[ WARN - holding him at gunpoint ]o---
                    elseif guard.state == GUARD_WARN then
                        local wc = WarnConf()
                        local d = #(GetEntityCoords(guard.ped) - playerCoords)
                        local reach = playerCrouching and (guard.range * crouchMult) or guard.range
                        local advancing = d < (guard.warnFromDist or d) - (wc.AdvanceTolerance or 2.5)
                        local pushingIn = guard.warnFromCentre ~= nil and zoneData ~= nil
                            and Shared.ZoneCentreDistance(playerCoords, zoneData)
                                < guard.warnFromCentre - (wc.DeeperTolerance or 3.0)
                        local settled = not zoneWarnUntil[zoneIndex]

                        if alerted then
                            TaskGuardCombat(guard, playerPed)

                        elseif settled or not insideZone then
                            if zoneWarnUntil[zoneIndex] then
                                zoneWarnUntil[zoneIndex] = nil
                                ZoneNotify(zoneIndex, "complied", Config.Text.GuardWarnCompliedNotify, 3500, true)
                            end
                            TaskGuardReturn(guard)

                        elseif advancing or pushingIn then
                            devPrint("Warning defied: " .. (advancing and "advancing on the guard" or "pushing into the yard"))
                            ForceHostile(zoneIndex, "defied a warning")
                            GoHostile(zoneIndex, playerPed, Config.Text.GuardWarnIgnoredNotify)

                        elseif d > reach * (wc.ComplyDistanceFactor or 1.25) then
                            zoneWarnUntil[zoneIndex] = nil
                            ZoneNotify(zoneIndex, "complied", Config.Text.GuardWarnCompliedNotify, 3500, true)
                            TaskGuardReturn(guard)

                        elseif now >= (guard.warnUntil or now) then
                            devPrint("Warning ran out with him still in range")
                            ForceHostile(zoneIndex, "ignored a warning")
                            GoHostile(zoneIndex, playerPed, Config.Text.GuardWarnIgnoredNotify)
                        end

                    ---o[ SUSPICIOUS - going to look ]o---
                    elseif guard.state == GUARD_SUSPICIOUS then
                        if alerted then
                            TaskGuardCombat(guard, playerPed)
                        elseif sensed then
                            guard.lastKnown = playerCoords

                            if (now - guard.taskTime) > 4000 and how == "sight"
                                and (not guard.goingTo or #(playerCoords - guard.goingTo) > 4.0) then
                                TaskGuardInvestigate(guard, playerCoords)
                            end
                        elseif (now - guard.stateAt) > ((det.InvestigateSeconds or 12) * 1000) then
                            TaskGuardReturn(guard) -- must have been nothing
                        end

                    ---o[ SEARCH - he knows someone is about ]o---
                    elseif guard.state == GUARD_SEARCH then
                        if alerted then
                            TaskGuardCombat(guard, playerPed)
                        elseif sensed then
                            TaskGuardInvestigate(guard, playerCoords) -- there you are
                        elseif (now - guard.stateAt) > ((det.SearchSeconds or 15) * 1000) then
                            TaskGuardReturn(guard)
                        end

                    ---o[ RETURN - walking back to the post ]o---
                    elseif guard.state == GUARD_RETURN then
                        local backHome = #(GetEntityCoords(guard.ped) - guard.post.coords) < 3.0

                        if alerted then
                            TaskGuardCombat(guard, playerPed)
                        elseif sensed and how == "sight"
                            and (not suspicionOn or (zoneLevel ~= SUSP_CALM and investigators < investigatorCap)) then
                            investigators = investigators + 1
                            TaskGuardInvestigate(guard, playerCoords)
                        elseif backHome or (now - guard.stateAt) > 30000 then
                            if Owns(guard.ped) and not BusyForSomeoneElse(guard) then
                                SetEntityHeading(guard.ped, guard.post.heading or 0.0)
                            end
                            ResumeRouteFromNearest(guard)
                            TaskGuardPatrol(guard)
                        end

                    ---o[ PATROL ]o---
                    else
                        if alerted then
                            TaskGuardCombat(guard, playerPed)
                        elseif sensed
                            and (not suspicionOn or (zoneLevel ~= SUSP_CALM and investigators < investigatorCap)) then
                            investigators = investigators + 1
                            TaskGuardInvestigate(guard, playerCoords)
                            busy = true
                        elseif corpseCoords and not bodyAlerted[zoneIndex]
                            and #(GetEntityCoords(guard.ped) - corpseCoords) <= (det.BodyDiscoveryRange or 12.0) then
                            bodyAlerted[zoneIndex] = true
                            devPrint("A guard found a body")
                            SearchZoneGuards(zoneIndex, corpseCoords)
                            if insideZone then
                                ZoneNotify(zoneIndex, "search", Config.Text.GuardBodyFoundNotify
                                    or Config.Text.GuardSearchingNotify, 3500, false)
                            end
                            busy = true
                        else
                            ---o[ Ordinary patrol upkeep ]o---
                            local pedCoords = GetEntityCoords(guard.ped)

                            if guard.duty == "idle" then
                                ---o[ Standing his post ]o---
                                if #(pedCoords - guard.post.coords) > (DutyConf().IdleLeashDistance or 4.0) then
                                    TaskGuardReturn(guard)
                                elseif not guard.idleUntil or now >= guard.idleUntil then
                                    TaskGuardPatrol(guard)
                                end
                            elseif guard.route and #guard.route > 0 then
                                ---o[ Walking the circuit ]o---
                                local point = guard.route[guard.routeIndex]
                                local reach = GuardConf.PatrolReachDistance or 4.0
                                local stuckMs = (GuardConf.PatrolStuckSeconds or 35) * 1000

                                if guard.pauseUntil then
                                    if now >= guard.pauseUntil then
                                        guard.pauseUntil = nil
                                        guard.routeIndex = (guard.routeIndex % #guard.route) + 1
                                        TaskGuardPatrol(guard)
                                    end
                                elseif not point then
                                    guard.routeIndex = 1
                                    TaskGuardPatrol(guard)
                                elseif #(pedCoords - point) < reach or (now - guard.taskTime) > stuckMs then
                                    TaskGuardPause(guard)
                                end
                            elseif guard.post.scenario then
                                if (now - guard.taskTime) > 60000 then TaskGuardPatrol(guard) end
                            elseif (now - guard.taskTime) > 60000 then
                                TaskGuardPatrol(guard)
                            end
                        end
                    end
                end

                ::nextGuard::
            end

            ---o[ Seen climbing, with a gun out, or just not sneaking: FireOn says shoot ]o---
            if witnesses > 0 and insideZone and not playerDead and not exempt then
                local seen = zoneNoise[zoneIndex] or {}
                local why = (seen.climbing and FireRule("SeenClimbing") and "seen climbing a tree")
                    or (seen.armed and FireRule("SeenArmed") and "seen with a gun drawn")
                    or (seen.upright and FireRule("SeenUpright") and "seen walking upright in the yard")

                if why then
                    busy = true
                    if alerted then
                        zoneAlertUntil[zoneIndex] = now + (GuardConf.CalmDownTime or 30000)
                        zoneHostileSince[zoneIndex] = now
                    else
                        devPrint("Guards opening fire: " .. why)
                        ForceHostile(zoneIndex, why)
                        GoHostile(zoneIndex, playerPed)
                        alerted = true
                    end
                end
            end

            ---o[ The yard makes its mind up, once per second, per zone ]o---
            if suspicionOn and zoneData then
                if insideZone or (zoneSuspicion[zoneIndex] or 0) > 0 then
                    local level = UpdateSuspicion(zoneIndex, witnesses, heardHim, playerPed)
                    if level ~= SUSP_CALM then busy = true end
                end
            end
        end

        Wait(busy and 500 or 1000)

        ::continue::
    end
end)

---o[ SERVER-APPROVED ALARM ]o---
RegisterNetEvent('gsc_kassippu_alert:client:AlertGuards', function(zoneName, zoneLabel, offender, at)
    for i, zoneData in ipairs(Config.TreeZones) do
        if zoneData.name == zoneName or zoneData.label == zoneLabel then
            ---o[ Somebody else set it off ]o---
            if offender and offender ~= GetPlayerServerId(PlayerId()) then
                local spot = (type(at) == 'vector3' or type(at) == 'table') and at.x
                    and vector3(at.x + 0.0, at.y + 0.0, at.z + 0.0) or nil

                if zoneGuards[i] and not Guards.IsHunting(i) and spot then
                    zoneLastKnown[i] = spot
                    SearchZoneGuards(i, spot, true) -- only the men we already run; his own game sends the rest
                end
                return
            end

            if Guards.IsHunting(i) then
                zoneAlertUntil[i] = GetGameTimer() + (GuardConf.CalmDownTime or 30000)
                return
            end

            if AlertZoneGuards(i, PlayerPedId()) then
                zoneWarned[i] = true
                ZoneNotify(i, "hostile", string.format(Config.Text.GuardAlarmNotify
                    or "The alarm is up at %s. The guards are hunting you.",
                    zoneData.label or zoneLabel or "the yard"), 5000, true)
            end
            return
        end
    end

    devPrint("^1Alert for unknown zone: " .. tostring(zoneName))
end)
---o[ RESET GUARDS (/clearguards: admins, checked by the server) ]o---
RegisterNetEvent('gsc_kassippu:client:adminCommand')
AddEventHandler('gsc_kassippu:client:adminCommand', function(name)
    if name ~= 'clearguards' then return end

    Guards.Cleanup()
    GSC.Notify.Show("Guards reset.", 3000)
    devPrint("Guards manually reset via command")
end)

---oo[ What GSC.Zones Is Allowed To Ask ]oo---

function Guards.AreStaffed(zoneIndex)
    return zoneGuards[zoneIndex] ~= nil
end

function Guards.IsHunting(zoneIndex)
    local until_ = zoneAlertUntil[zoneIndex]
    return until_ ~= nil and GetGameTimer() < until_
end

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Guards.Cleanup()
end)
