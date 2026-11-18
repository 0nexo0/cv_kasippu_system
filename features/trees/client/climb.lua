local Climb = GSC.module('Climb')

local maxSteps = Config.TreeClimbConf.ClimbMaxSteps
local currentHeight = 0
local active = false
local climbPromptLatched = false
local TreeGroup = GetRandomIntInRange(0, 0xffffff)
local ClimbPrompt
local CreateClimbPrompt
local climbPendingUID = nil
local climbApproval = nil
local groundTree, groundTreeData = nil, nil
local atTop = false
local topRequest = nil
local climbBlockedUntil = 0
local lastGripCheckEnd = 0

local StartClimbSequence, HandleFall, ClimbDownSequence

---oo[ Attach Height -> Local Z On The Trunk ]oo---
function Climb.AttachZForHeight(heightSteps)
    local conf = Config.TreeClimbConf
    return (conf.ClimbBaseOffset or 1.0) + ((heightSteps or 0) * (conf.ClimbStepHeight or 1.5))
end
---oo[ Hanging On The Trunk ]oo---
local function AttachAtHeight(ped, treeEntity, heightSteps)
    local conf = Config.TreeClimbConf
    local z = Climb.AttachZForHeight(heightSteps)

    AttachEntityToEntity(ped, treeEntity, 0,
        0.0, conf.ClimbForwardOffset or 0.45, z,
        0.0, 0.0, 180.0,
        false, false, false, false, 2, true)

    GSC.TreeCamera.UpdateHeight(z)
    return z
end

---oo[ Freeze Him At A Climb Level, For Everyone ]oo---
local climbAnim = nil
local lastPinAt = 0

local function SetClimbAnim(dict, name, flag, duration)
    climbAnim = dict and {
        dict = dict, name = name, flag = flag or 1, duration = duration or -1,
        phase = 0.0, expect = nil, startedAt = GetGameTimer(),
    } or nil
end

local function ReadClimbAnimPhase(ped)
    local a = climbAnim
    if not a or not IsEntityPlayingAnim(ped, a.dict, a.name, 3) then return nil end
    local ok, t = pcall(GetEntityAnimCurrentTime, ped, a.dict, a.name)
    if ok and type(t) == "number" and t >= 0.0 and t <= 1.0 then return t end
    return nil
end

local function StartClimbAnimAt(ped, phase)
    local a = climbAnim
    if not a or not HasAnimDictLoaded(a.dict) then return end
    TaskPlayAnim(ped, a.dict, a.name, 1000.0, -4.0, a.duration, a.flag, phase or 0.0, false, false, false)
    a.startedAt = GetGameTimer()
    a.expect = phase
end

local function TrackClimbAnim(ped)
    local a = climbAnim
    if not a then return end

    if not IsEntityPlayingAnim(ped, a.dict, a.name, 3) then
        if (GetGameTimer() - a.startedAt) > 250 then
            StartClimbAnimAt(ped, a.phase)
        end
        return
    end

    local now = ReadClimbAnimPhase(ped)
    local expect = a.expect
    a.expect = nil

    if expect and now and now < (expect - 0.05) then
        pcall(SetEntityAnimCurrentTime, ped, a.dict, a.name, expect)
        a.phase = expect
        return
    end

    if now then a.phase = now end
end

local function PinAtHeight(ped, treeEntity, heightSteps)
    local conf = Config.TreeClimbConf
    local z = Climb.AttachZForHeight(heightSteps)
    local pos = GetOffsetFromEntityInWorldCoords(treeEntity, 0.0, conf.ClimbForwardOffset or 0.45, z)

    local a = climbAnim
    if a then
        local phase = ReadClimbAnimPhase(ped)
        if a.expect and (not phase or phase < (a.expect - 0.05)) then phase = a.expect end
        if phase then a.phase = phase end
    end

    FreezeEntityPosition(ped, true) -- first, so the detach cannot drop him
    DetachEntity(ped, false, false)
    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ped, (GetEntityHeading(treeEntity) + 180.0) % 360.0)

    local result = AttachAtHeight(ped, treeEntity, heightSteps)

    if a and climbAnim == a then
        if not IsEntityPlayingAnim(ped, a.dict, a.name, 3) then
            StartClimbAnimAt(ped, a.phase)
        else
            a.expect = a.phase
        end
    end

    lastPinAt = GetGameTimer()
    return result
end

---oo[ Climbing Up: Keep Everyone Updated Between Minigames ]oo---
local function ClimbUpToHeight(ped, treeEntity, heightSteps)
    local interval = Config.TreeClimbConf.ClimbUpSyncMs
    if type(interval) == "number" and interval > 0
        and (GetGameTimer() - lastPinAt) >= interval then
        return PinAtHeight(ped, treeEntity, heightSteps)
    end
    local z = AttachAtHeight(ped, treeEntity, heightSteps)
    TrackClimbAnim(ped)
    return z
end

---oo[ One Grip Check ]oo---
local function RunKeypressCheck()
    local kp = Config.LegendKeyPressConf
    local gap = kp.KeyPressGapMs or 2300

    while active and (GetGameTimer() - lastGripCheckEnd) < gap do
        Wait(0)
    end
    if not active then return nil end

    local startedAt = GetGameTimer()
    local ok, success = pcall(function()
        return exports['legends-keypress']:startkp(kp.TotalTime, kp.NumOfKeys)
    end)
    lastGripCheckEnd = GetGameTimer()

    if not active then return nil end

    if not ok then
        Shared.Debug("^1[Climb]^7 legends-keypress errored: " .. tostring(success))
        return "unavailable"
    end

    if success ~= true and (lastGripCheckEnd - startedAt) < 250 then
        Shared.Debug("^1[Climb]^7 legends-keypress refused to start a round")
        return "unavailable"
    end

    return success == true
end

---oo[ One Grip Check ]oo---
local function RunGripCheck(step)
    if Config.TreeMinigameProvider == "legacy" then return RunKeypressCheck() end

    local conf = Config.TreeClimbConf
    local grip = conf.GripMinigame or { type = "reach" }

    local harder = 1.0 + (conf.GripHarderPerRung or 0) * math.max(0, step - 1)
    local game = {}
    for k, v in pairs(grip) do game[k] = v end
    game.zone = (grip.zone or 0.24) / harder
    game.speed = (grip.speed or 0.75) * harder

    local watching = true
    CreateThread(function()
        while watching do
            if not active then
                GSC.Minigame.Cancel()
                break
            end
            Wait(100)
        end
    end)

    local result = GSC.Minigame.Play(game, string.format(Config.Text.ClimbGripTitle or "Grip %d/%d", step, maxSteps))
    watching = false

    if not active or result == nil then return nil end
    return result == true
end

---oo[ Step Away From The Trunk ]oo---
local function ClearOfTrunk(ped, treeEntity)
    if not treeEntity or not DoesEntityExist(treeEntity) then return end

    local pos = GetEntityCoords(ped)
    local tree = GetEntityCoords(treeEntity)
    local dx, dy = pos.x - tree.x, pos.y - tree.y
    local len = math.sqrt((dx * dx) + (dy * dy))

    if len < 0.01 then
        local fwd = GetEntityForwardVector(treeEntity)
        dx, dy, len = fwd.x, fwd.y, 1.0
    end

    local clear = Config.TreeClimbConf.FallClearDistance or 1.2
    if len >= clear then return end

    SetEntityCoordsNoOffset(ped, tree.x + (dx / len) * clear, tree.y + (dy / len) * clear, pos.z, false, false, false)
end

RegisterNetEvent('gsc_kassippu:client:climbResponse')
AddEventHandler('gsc_kassippu:client:climbResponse', function(uid, approved)
    if climbPendingUID == uid then
        climbApproval = approved
    end
end)

---oo[ Ask The Server For Permission Before Climbing ]oo---
function Climb.TryStart(treeEntity, treeData)
    local ped = PlayerPedId()
    local conf = Config.TreeClimbConf
    local anim = Config.AnimConf
    local prepareMs = math.floor(math.max(0, conf.PrepareSeconds or 3) * 1000)

    climbPendingUID = treeData.uid
    climbApproval = nil
    TriggerServerEvent('gsc_kassippu:server:requestClimb', treeData.uid)

    ---o[ Face the tree and get the rope out ]o---
    pcall(function() TaskTurnPedToFaceEntity(ped, treeEntity, 800) end)

    if prepareMs > 0 and anim.ClimbPrepareAnimDict then
        RequestAnimDict(anim.ClimbPrepareAnimDict)

        local waited = 0
        while not HasAnimDictLoaded(anim.ClimbPrepareAnimDict) and waited < 100 do
            Wait(10)
            waited = waited + 1
        end

        if HasAnimDictLoaded(anim.ClimbPrepareAnimDict) then
            TaskPlayAnim(ped, anim.ClimbPrepareAnimDict, anim.ClimbPrepareAnimName,
                4.0, -4.0, prepareMs, anim.ClimbPrepareAnimFlag or 31, 0, false, false, false)
        else
            Shared.Debug("^1[Climb]^7 Prepare anim dict failed to load: " .. tostring(anim.ClimbPrepareAnimDict))
        end
    end

    if Config.Text.ClimbPreparingNotify then
        GSC.Notify.Show(Config.Text.ClimbPreparingNotify, 2000)
    end

    ---o[ Ready up and wait on the answer at the same time ]o---
    local startedAt = GetGameTimer()
    local treeCoords = GetEntityCoords(treeEntity)
    local cancelRange = (conf.InteractRadius or 3.0) + 2.0
    local cancelSq = cancelRange * cancelRange
    local walkedOff = false

    while true do
        Wait(50)

        local elapsed = GetGameTimer() - startedAt
        local offset = GetEntityCoords(PlayerPedId()) - treeCoords

        if ((offset.x * offset.x) + (offset.y * offset.y) + (offset.z * offset.z)) > cancelSq then
            walkedOff = true
            break
        end

        if elapsed >= prepareMs and climbApproval ~= nil then break end

        if elapsed > (prepareMs + 3000) then break end
    end

    if walkedOff then
        ClearPedTasks(ped)
        GSC.Notify.Show(Config.Text.ClimbCancelledNotify, 3000)
        return
    end

    if climbApproval == true then
        StartClimbSequence(treeEntity, treeData)
    elseif climbApproval == false then
        ClearPedTasks(ped)
        GSC.Notify.Show(Config.Text.ClimbRopeRequiredNotify, 3000)
    else
        ClearPedTasks(ped)
        Shared.Debug("^1[Climb]^7 Server did not respond to climb request in time.")
    end
end
---oo[ Top Of The Tree Prompts ]oo---
local TopGroup = GetRandomIntInRange(0, 0xffffff)
local topPrompts = {}
local searchPrompt, collectPrompt, climbDownPrompt = nil, nil, nil
local atTop = false
local holdArmed = {}

local function PromptHoldMs()
    return Config.TreeClimbConf.PromptHoldMs or 1000
end

local function HoldCompleted(prompt)
    if not prompt then return false end
    if not UiPromptHasHoldModeCompleted(prompt) then
        holdArmed[prompt] = true
        return false
    end
    if holdArmed[prompt] then
        holdArmed[prompt] = false
        return true
    end
    return false
end

local function CreateTopPrompt(key, text, holdMs)
    local prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, key)
    UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', text))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    if holdMs then
        UiPromptSetHoldMode(prompt, holdMs)
    else
        UiPromptSetStandardMode(prompt, true)
    end
    UiPromptSetGroup(prompt, TopGroup, 0)
    UiPromptRegisterEnd(prompt)
    return prompt
end

local function SetTopPromptsEnabled(enabled)
    for _, prompt in ipairs(topPrompts) do
        UiPromptSetEnabled(prompt, enabled)
    end
end

local function ShowTopPrompts(visible)
    if visible == atTop then return end
    atTop = visible

    if visible then
        if ClimbPrompt then
            UiPromptDelete(ClimbPrompt)
            ClimbPrompt = nil
        end

        local keys, txt = Config.InteractKeys, Config.PromptsTxt
        local holdMs = PromptHoldMs()
        climbDownPrompt = CreateTopPrompt(keys.TreeClimbKey, txt.TreeClimbDownPrompt or "Climb Down", holdMs)
        collectPrompt = CreateTopPrompt(keys.TreeCoconutCollectKey, txt.TreeCollectPrompt or "Collect Coconut Flower Sap", holdMs)
        searchPrompt = CreateTopPrompt(keys.TreeSearchKey, txt.TreeSearchPrompt or "Search", holdMs)
        topPrompts = { searchPrompt, collectPrompt, climbDownPrompt }
    else
        for _, prompt in ipairs(topPrompts) do
            UiPromptDelete(prompt)
        end
        topPrompts = {}
        holdArmed = {}
        searchPrompt, collectPrompt, climbDownPrompt = nil, nil, nil

        if not ClimbPrompt then CreateClimbPrompt() end
    end
end

CreateThread(function()
    local name = Config.TreeClimbConf.TreeName or "Coconut Tree"
    local label = VarString(10, 'LITERAL_STRING', name) -- built once, not every frame

    while true do
        if atTop then
            UiPromptSetActiveGroupThisFrame(TopGroup, label, 0, 0, 0, 0)
            Wait(0)
        else
            Wait(active and 250 or 1000) -- not on a tree: look less often
        end
    end
end)

---o[ Start TreeClimbUp Function ]o---
function StartClimbSequence(treeEntity, treeData)
    if active or not treeEntity then return end

    active = true
    local ped = PlayerPedId()
    currentHeight = 0
    local conf = Config.TreeClimbConf
    local animDict = Config.AnimConf.TreeClimbUpAnimDict
    local animName = Config.AnimConf.TreeClimbUpAnimName
    local animTime = Config.AnimConf.TreeClimbUpAnimTime
    local animFlag = Config.AnimConf.TreeClimbUpAnimFlag

    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true, 0, false, false)

    RequestAnimDict(animDict)
    local dictTimeout = 0
    while not HasAnimDictLoaded(animDict) and dictTimeout < 100 do
        Wait(10)
        dictTimeout = dictTimeout + 1
    end

    RequestAnimDict(Config.AnimConf.TreeCrouchAnimDict)

    GSC.TreeCamera.StartClimb(treeEntity, 0) -- framing the base of the trunk

    SetClimbAnim(nil)
    PinAtHeight(ped, treeEntity, 0)

    TaskPlayAnim(ped, animDict, animName, 4.0, -4.0, animTime, animFlag, 0, false, false, false)
    SetClimbAnim(animDict, animName, animFlag, animTime)

    ---o[ THE ASCENT: continuous, and never stops for the skill check ]o---
    local climbing = true
    local climbCeiling = 1.0

    CreateThread(function()
        local speed = math.max(0.05, conf.ClimbSpeed or 0.28)        -- rungs per second
        local easeDist = math.max(0.05, conf.ClimbEaseDistance or 0.4)
        local minRate = math.max(0.0, conf.ClimbMinSpeedFactor or 0.12)
        local lastFrame = GetGameTimer()

        while climbing and active do
            Wait(0)

            if not (climbing and active) then break end

            local now = GetGameTimer()
            local dt = math.min((now - lastFrame) / 1000, 0.1) -- clamp so a hitch cannot launch him
            lastFrame = now

            local remaining = climbCeiling - currentHeight

            if remaining > 0.001 then
                local rate = speed

                if remaining < easeDist then
                    local t = remaining / easeDist
                    rate = speed * math.max(minRate, t * t * (3.0 - (2.0 * t)))
                end

                currentHeight = math.min(climbCeiling, currentHeight + (rate * dt))
                ClimbUpToHeight(ped, treeEntity, currentHeight)
            else
                TrackClimbAnim(ped)
            end
        end
    end)

    ---o[ The skill checks, paced by the climb rather than by each other ]o---
    for step = 1, maxSteps do
        while active and currentHeight < ((step - 1) - 0.001) do
            Wait(0)
        end

        if not active then
            climbing = false
            return
        end

        local success = RunGripCheck(step)

        local retries = 0
        while success == "unavailable" and retries < 2 and active do
            retries = retries + 1
            Wait(1500)
            success = RunGripCheck(step)
        end

        if success == nil then
            climbing = false
            return
        end

        if success == "unavailable" then
            climbing = false
            GSC.TreeCamera.StopClimb()
            GSC.Notify.Show(Config.Text.ClimbCheckUnavailableNotify
                or "Could not get a grip. Climbing back down.", 3000)
            ClimbDownSequence(ped, treeEntity)
            return
        end

        if success ~= true then
            climbing = false
            HandleFall(ped, treeEntity)
            return
        end

        PinAtHeight(ped, treeEntity, currentHeight)
        climbCeiling = math.min(maxSteps, step + 1)
        GSC.Notify.Show(Config.Text.ClimbingUpNotify .. step .. "/" .. maxSteps, 1000)
    end

    ---o[ 8/8 passed: up the last rung at once ]o---
    climbing = false

    if not active then return end

    local finishSpeed = conf.FinishRungSpeed or 6.0
    if finishSpeed > 0 then
        local lastFrame = GetGameTimer()
        while active and currentHeight < maxSteps do
            Wait(0)
            if not active then break end
            local now = GetGameTimer()
            local dt = math.min((now - lastFrame) / 1000, 0.1)
            lastFrame = now
            currentHeight = math.min(maxSteps, currentHeight + (finishSpeed * dt))
            ClimbUpToHeight(ped, treeEntity, currentHeight)
        end
    end

    if not active then return end

    currentHeight = maxSteps
    PinAtHeight(ped, treeEntity, maxSteps) -- frozen at the crown, for everyone

    ---o[ Reached the crown: hold the last grip a moment ]o---
    local settleMs = math.floor((conf.TopSettleSeconds or 0) * 1000)
    if settleMs > 0 then
        local settleUntil = GetGameTimer() + settleMs
        while active and GetGameTimer() < settleUntil do
            Wait(0)
            TrackClimbAnim(ped)
        end
        if not active then return end
    end

    ---o[ He is up. Hand the screen to his own eyes ]o---
    local wentFirstPerson = GSC.TreeCamera.SetTopView(true, ped)
    GSC.TreeCamera.StopClimb(not wentFirstPerson)

    local crouchAnimDict = Config.AnimConf.TreeCrouchAnimDict
    local crouchAnimName = Config.AnimConf.TreeCrouchAnimName
    local crouchAnimFlag = Config.AnimConf.TreeCrouchAnimFlag or 1

    ---o[ Load the crouch, with a timeout ]o---
    RequestAnimDict(crouchAnimDict)
    local loadUntil = GetGameTimer() + 3000
    while not HasAnimDictLoaded(crouchAnimDict) and GetGameTimer() < loadUntil do
        Wait(10)
    end
    local crouchReady = HasAnimDictLoaded(crouchAnimDict)
    if not crouchReady then
        Shared.Debug("^1[Climb]^7 Top crouch anim dict failed to load: " .. tostring(crouchAnimDict))
    end

    local function PlayTopPose(blendIn)
        if not crouchReady then return end
        TaskPlayAnim(ped, crouchAnimDict, crouchAnimName, blendIn, -2.0, -1, crouchAnimFlag, 0, false, false, false)
    end

    local function InTopPose()
        return crouchReady and IsEntityPlayingAnim(ped, crouchAnimDict, crouchAnimName, 3)
    end

    ---o[ Blend from the climb into the crouch ]o---
    SetClimbAnim(nil)
    PlayTopPose(8.0)
    StopAnimTask(ped, animDict, animName, 8.0)

    local verifyUntil = GetGameTimer() + 250
    while active and crouchReady and not InTopPose() and GetGameTimer() < verifyUntil do
        Wait(0)
    end
    if active and crouchReady and not InTopPose() then
        ClearPedTasksImmediately(ped)
        PlayTopPose(8.0)
    end

    local canSearch = true
    local canCollectCoconut = true
    GSC.Notify.Show(Config.Text.ReachedTopOfTreeNotify, 5000)
    ShowTopPrompts(true)
    atTop, topRequest = true, nil

    GSC.Harvest.WatchTree(treeData.uid)

    local poseCheckAt = 0

    while active do
        Wait(0)
        if not active then break end

        local request = topRequest
        topRequest = nil

        if canSearch and (HoldCompleted(searchPrompt) or request == "search") then
            canSearch = false
            SetTopPromptsEnabled(false)
            GSC.Harvest.SearchTree(ped, treeEntity, treeData)
            SetTopPromptsEnabled(true)
            canSearch = true
            PlayTopPose(4.0)
        end

        if canCollectCoconut and (HoldCompleted(collectPrompt) or request == "collect") then
            canCollectCoconut = false
            SetTopPromptsEnabled(false)
            GSC.Harvest.CollectCoconutWater(ped, treeEntity, treeData)
            SetTopPromptsEnabled(true)
            canCollectCoconut = true
            PlayTopPose(4.0)
        end

        ---o[ Hold the pose for as long as he is up there ]o---
        local now = GetGameTimer()
        if now >= poseCheckAt then
            poseCheckAt = now + 1000
            if crouchReady and not InTopPose() then PlayTopPose(4.0) end
            AttachAtHeight(ped, treeEntity, maxSteps)
        end

        if HoldCompleted(climbDownPrompt) or request == "down" then
            climbPromptLatched = true
            ShowTopPrompts(false) -- not while he is on the way down
            ClearPedTasksImmediately(ped)
            ClimbDownSequence(ped, treeEntity)
            break
        end
    end

    ShowTopPrompts(false)
    atTop, topRequest = false, nil
    GSC.Harvest.WatchTree(nil)
    GSC.TreeCamera.SetTopView(false)
end

---oo[ Letting Go Of The Trunk ]oo---
local function ReleasePedFromTree(ped, placeOnGround)
    SetClimbAnim(nil)
    if not ped or not DoesEntityExist(ped) then return end

    DetachEntity(ped, true, true)
    ClearPedTasksImmediately(ped)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)

    if not placeOnGround then return end

    local coords = GetEntityCoords(ped)
    local ok, found, groundZ = pcall(GetGroundZFor_3dCoord, coords.x, coords.y, coords.z + 2.0, false)

    if ok and found and groundZ then
        local drop = coords.z - groundZ
        if drop > 0.15 and drop < 3.0 then
            SetEntityCoordsNoOffset(ped, coords.x, coords.y, groundZ + 0.05, false, false, false)
        end
    end
end

---oo[ After A Fall: Make Sure He Can Walk Away ]oo---
local function EnsureRecoveredAfterFall(treeEntity, ragdollMs)
    CreateThread(function()
        local function FreeHim(ped)
            if IsEntityAttached(ped) then DetachEntity(ped, true, true) end
            FreezeEntityPosition(ped, false)
            SetEntityCollision(ped, true, true)
        end

        local deadline = GetGameTimer() + ragdollMs + 2500

        while GetGameTimer() < deadline do
            Wait(100)
            if active then return end

            local ped = PlayerPedId()
            if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
            FreeHim(ped)
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
        FreeHim(ped)

        if IsPedRagdoll(ped) then
            ClearPedTasksImmediately(ped)
            ClearOfTrunk(ped, treeEntity)
            Shared.Debug("^3[Climb]^7 Ragdoll never ended after a fall - stood the player up")
        end
    end)
end

---oo[ The Drop ]oo---
local fallProtected = false

local function EndFallProtection(ped)
    if not fallProtected then return end
    fallProtected = false
    if ped and DoesEntityExist(ped) then SetEntityInvincible(ped, false) end
end

local function WatchFall(ped, treeEntity, ragdollMs)
    local conf = Config.TreeClimbConf
    local push = conf.FallPushSpeed or 1.5
    local clear = conf.FallClearDistance or 1.2

    CreateThread(function()
        local startedAt = GetGameTimer()
        local pushed, landedAt = false, nil

        while DoesEntityExist(ped) and not IsEntityDead(ped) do
            Wait(0)
            local now = GetGameTimer()
            local elapsed = now - startedAt
            local hasTree = treeEntity and DoesEntityExist(treeEntity)

            if not IsPedRagdoll(ped) then
                if elapsed < 500 then
                    SetPedToRagdoll(ped, ragdollMs, ragdollMs, 0, false, false, false)
                end
            elseif not pushed then
                pushed = true
                if push > 0 and hasTree then
                    local pos, t = GetEntityCoords(ped), GetEntityCoords(treeEntity)
                    local dx, dy = pos.x - t.x, pos.y - t.y
                    local len = math.sqrt((dx * dx) + (dy * dy))
                    if len < 0.01 then
                        local fwd = GetEntityForwardVector(treeEntity)
                        dx, dy, len = fwd.x, fwd.y, 1.0
                    end
                    local v = GetEntityVelocity(ped)
                    SetEntityVelocity(ped, (dx / len) * push, (dy / len) * push, v.z)
                end
            end

            if hasTree and not landedAt then
                local pos, t = GetEntityCoords(ped), GetEntityCoords(treeEntity)
                local dx, dy = pos.x - t.x, pos.y - t.y
                if ((dx * dx) + (dy * dy)) < (clear * clear) then
                    SetEntityNoCollisionEntity(ped, treeEntity, true)
                end
            end

            if not landedAt and elapsed > 250 and (GetEntityHeightAboveGround(ped) or 0.0) < 0.6 then
                landedAt = now
            end

            if (landedAt and (now - landedAt) >= 300) or elapsed >= ragdollMs then break end
        end

        EndFallProtection(ped)

        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            SetEntityHealth(ped, math.max(0, GetEntityHealth(ped) - (conf.HealthReduceCount or 0)))
        end
    end)
end

---oo[ Falling Off The Trunk ]oo---
function HandleFall(ped, treeEntity)
    local conf = Config.TreeClimbConf
    local ragdollMs = math.floor((conf.FallRagdollSeconds or 5.0) * 1000)

    GSC.TreeCamera.StopClimb()
    GSC.Harvest.WatchTree(nil)
    GSC.TreeCamera.SetTopView(false)
    active = false
    currentHeight = 0

    ReleasePedFromTree(ped, false)

    if conf.FallGameDamage ~= true then
        fallProtected = true
        SetEntityInvincible(ped, true)
    end

    SetPedCanRagdoll(ped, true)
    SetPedToRagdoll(ped, ragdollMs, ragdollMs, 0, false, false, false)

    climbBlockedUntil = GetGameTimer() + ragdollMs + ((conf.FallClimbCooldownSeconds or 1) * 1000)
    climbPromptLatched = true

    GSC.Notify.Show(Config.Text.TreeFallNotify, 3000)

    WatchFall(ped, treeEntity, ragdollMs)
    EnsureRecoveredAfterFall(treeEntity, ragdollMs)
end

function ClimbDownSequence(ped, treeEntity)
    GSC.Harvest.WatchTree(nil)

    local conf = Config.TreeClimbConf
    local anim = Config.AnimConf
    local stepHeight = conf.ClimbStepHeight or 1.5
    local speed = math.max(0.2, conf.DescendSpeed or 2.4)
    local easeFrom = math.max(0.0, conf.DescendEaseDistance or 1.5)

    GSC.TreeCamera.StartClimb(treeEntity, currentHeight)
    GSC.TreeCamera.SetTopView(false, ped, false)

    ---o[ One animation, started once and left to run ]o---
    RequestAnimDict(anim.TreeClimbDownAnimDict)
    local timeout = 0
    while not HasAnimDictLoaded(anim.TreeClimbDownAnimDict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(anim.TreeClimbDownAnimDict) then
        TaskPlayAnim(ped, anim.TreeClimbDownAnimDict, anim.TreeClimbDownAnimName,
            4.0, -4.0, -1, anim.TreeClimbDownAnimFlag or 1, 0, false, false, false)
        SetClimbAnim(anim.TreeClimbDownAnimDict, anim.TreeClimbDownAnimName,
            anim.TreeClimbDownAnimFlag or 1, -1)
    else
        SetClimbAnim(nil)
    end

    GSC.Notify.Show(Config.Text.TreeClimbingDownNotify, 2000)

    ---o[ Continuous slide, timed in metres per second ]o---
    local lastFrame = GetGameTimer()

    while currentHeight > 0 do
        Wait(0)
        if not active then return end

        local now = GetGameTimer()
        local dt = math.min((now - lastFrame) / 1000, 0.1) -- clamp so a hitch cannot drop him
        lastFrame = now

        local metresLeft = currentHeight * stepHeight
        local rate = speed

        if easeFrom > 0 and metresLeft < easeFrom then
            rate = speed * math.max(0.25, metresLeft / easeFrom)
        end

        local rungBefore = math.ceil(currentHeight)
        currentHeight = math.max(0.0, currentHeight - ((rate * dt) / stepHeight))

        local syncMs = conf.ClimbDownSyncMs
        local due
        if type(syncMs) == "number" and syncMs > 0 then
            due = (GetGameTimer() - lastPinAt) >= syncMs
        else
            due = math.ceil(currentHeight) < rungBefore
        end

        if due then
            PinAtHeight(ped, treeEntity, currentHeight)
        else
            AttachAtHeight(ped, treeEntity, currentHeight)
            TrackClimbAnim(ped)
        end
    end

    currentHeight = 0
    GSC.TreeCamera.StopClimb()

    ReleasePedFromTree(ped, true)

    active = false
    GSC.Notify.Show(Config.Text.TreeClimbDownSafeNotify, 3000)
end

---oo[ Prompt Creation ]oo---
local climbPromptShown = false

local function ShowClimbPrompt(visible)
    if not ClimbPrompt or visible == climbPromptShown then return end
    climbPromptShown = visible
    UiPromptSetVisible(ClimbPrompt, visible)
end

function CreateClimbPrompt()
    local str = Config.PromptsTxt.PlamTreeClimbPrompt
    ClimbPrompt = UiPromptRegisterBegin()
    climbPromptShown = false
    UiPromptSetControlAction(ClimbPrompt, Config.InteractKeys.TreeClimbKey)
    str = VarString(10, 'LITERAL_STRING', str)
    UiPromptSetText(ClimbPrompt, str)
    UiPromptSetEnabled(ClimbPrompt, true)
    UiPromptSetVisible(ClimbPrompt, false)
    UiPromptSetHoldMode(ClimbPrompt, PromptHoldMs())
    UiPromptSetGroup(ClimbPrompt, TreeGroup, 0)
    UiPromptRegisterEnd(ClimbPrompt)
    Shared.Debug("^2[Prompt]^7 Climb prompt created")
end
---oo[ MAIN THREAD: Prompt Handling ]oo---
CreateThread(function()
    CreateClimbPrompt()

    local groupLabel = VarString(10, 'LITERAL_STRING', Config.TreeClimbConf.TreeName or "Coconut Tree") -- built once
    local interactRadius = Config.TreeClimbConf.InteractRadius or 3.0
    local nearestTree, treeData = nil, nil
    local lastScan = 0

    while true do
        local sleep = 500

        if active then
            nearestTree, treeData = nil, nil
            sleep = 500
        elseif GetGameTimer() < climbBlockedUntil or IsPedRagdoll(PlayerPedId()) then
            nearestTree, treeData = nil, nil
            sleep = 250
        elseif not GSC.Trees.AnySpawned() then
            nearestTree, treeData = nil, nil
            sleep = 1500
        else
            local now = GetGameTimer()

            if (now - lastScan) > 250 then
                lastScan = now
                nearestTree, treeData = GSC.Trees.GetNearest(interactRadius)
            end

            if nearestTree and treeData then
                sleep = 0
                UiPromptSetActiveGroupThisFrame(TreeGroup, groupLabel, 0, 0, 0, 0)

                local done = ClimbPrompt ~= nil and UiPromptHasHoldModeCompleted(ClimbPrompt)

                if done and not climbPromptLatched then
                    climbPromptLatched = true
                    Climb.TryStart(nearestTree, treeData)
                elseif not done then
                    climbPromptLatched = false
                end
            end
        end

        ShowClimbPrompt(nearestTree ~= nil and treeData ~= nil)
        groundTree, groundTreeData = nearestTree, treeData

        Wait(sleep)
    end
end)
---oo[ Test The First Person View Without Climbing ]oo---
RegisterNetEvent('gsc_kassippu:client:adminCommand')
AddEventHandler('gsc_kassippu:client:adminCommand', function(name)
    if name ~= 'treeview' then return end

    if GSC.TreeCamera.IsFirstPerson() then
        GSC.TreeCamera.SetTopView(false)
        Shared.Debug("^2[Tree View]^7 First person off")
        GSC.Notify.Show("First person OFF", 3000)
        return
    end

    if GSC.TreeCamera.SetTopView(true, PlayerPedId()) then
        Shared.Debug("^2[Tree View]^7 First person on - /treeview again to leave")
        GSC.Notify.Show("First person ON - /treeview again to leave", 4000)
    else
        Shared.Debug("^1[Tree View]^7 Camera could not be created (FirstPersonAtTop is " ..
            tostring(Config.TreeClimbConf.FirstPersonAtTop) .. ")")
        GSC.Notify.Show("First person could not start", 3000)
    end
end)

---oo[ Public State ]oo---

---o[ For GSC.Radial ]o---
function Climb.RadialActions()
    if not (GSC.Radial ~= nil and GSC.Radial.Owns("tree")) then return nil end
    local P, R = Config.PromptsTxt, Config.Text.Radial or {}

    if active and atTop then
        return { title = R.Tree or "Tree", icon = "tree", actions = {
            { id = "gsc_tree_search", title = P.TreeSearchPrompt, icon = "magnifying-glass", run = function() topRequest = "search" end },
            { id = "gsc_tree_collect", title = P.TreeCollectPrompt, icon = "droplet", run = function() topRequest = "collect" end },
            { id = "gsc_tree_down", title = P.TreeClimbDownPrompt, icon = "arrow-down", run = function() topRequest = "down" end },
        } }
    end

    if active or not groundTree or not groundTreeData or GetGameTimer() < climbBlockedUntil then return nil end

    local tree, data = groundTree, groundTreeData
    return { title = R.Tree or "Tree", icon = "tree", actions = {
        { id = "gsc_tree_climb", title = P.PlamTreeClimbPrompt, icon = "person-hiking", run = function() Climb.TryStart(tree, data) end },
    } }
end

function Climb.IsActive()
    return active
end

function Climb.Height()
    return currentHeight
end

---oo[ Get Him Off The Tree, Whatever He Was Doing ]oo---
function Climb.Abort(placeOnGround)
    if not active then return false end

    active = false
    currentHeight = 0

    ShowTopPrompts(false)
    GSC.Harvest.WatchTree(nil)
    GSC.TreeCamera.SetTopView(false)
    GSC.TreeCamera.StopClimb()

    ReleasePedFromTree(PlayerPedId(), placeOnGround == true)
    return true
end

---oo[ Death Watchdog ]oo---
CreateThread(function()
    while true do
        local sleep = 1000

        if active then
            sleep = 200
            local ped = PlayerPedId()

            if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
                Shared.Debug("^1[Climb]^7 Player died on the tree - releasing")
                Climb.Abort(false)
            end
        end

        Wait(sleep)
    end
end)

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    EndFallProtection(PlayerPedId())

    if not Climb.Abort(true) then
        local ped = PlayerPedId()
        if DoesEntityExist(ped) then ReleasePedFromTree(ped, true) end
    end
end)
