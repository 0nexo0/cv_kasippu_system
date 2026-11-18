local Barrels = GSC.module('Barrels')

local inZone = false
local isPlacing = false
local ghostEntity = nil
local isUIOpen = false
local OpenBarrelUIPrompt
local AddWoodPrompt
local FuelSelectPrompt
local fuelChoiceShown = false
local fuelSelectText = nil
local AddWaterPrompt
local AddIngredientsPrompt
local VentPrompt
local ScrubPrompt
local RepairPrompt
local CrewLeavePrompt
local StealPrompt
local SeizePrompt
local PourPrompt
local seizeShown = false
local pourShown = false
local IncidentPrompt
local menuHintShown = false
local incidentShown = false
local PickupPrompt
local pickupShown = false
local TarpPrompt
local tarpShown = false
local tarpPromptText = nil
local incidentPromptText = nil

local barrelIncident = {}
local barrelTended = {}
local ingredientsPromptText = nil

local barrelAccess = {}
local crewLeaveShown = false
local crewLeaveText = nil
local stealShown = false
local isBusy = false

local woodPromptText = nil
local stealPromptText = nil
local waterPromptText = nil

local barrelCut = {}
local barrelFitted = {}
local barrelFittedSig = {}

local barrelNeedsScrub = false
local barrelNeedsRepair = false
local PromptGroups = CreateVarString(10, 'LITERAL_STRING', "Distillery")
local currentInteractingBarrel = nil
local BarrelStage = {}
local activeBarrels = {}

local barrelProps = {}

---oo[ Helper Functions ]oo---

---o[ Register a Barrel's Interaction Spot ]o---
local function CreateBarrelZone(uid, coords)
    activeBarrels[uid] = vector3(coords.x, coords.y, coords.z - 0.5)
end

---o[ Is the player stood at a barrel? ]o---
function Barrels.IsAtBarrel()
    return inZone and currentInteractingBarrel ~= nil
end

local function RemoveBarrelZone(uid)
    if not activeBarrels[uid] then return end

    activeBarrels[uid] = nil

    if currentInteractingBarrel == uid then
        currentInteractingBarrel = nil
        inZone = false
        TriggerServerEvent('gsc_kassippu:server:watchBarrel', nil)
    end
end

---o[ Barrel Proximity Thread (replaces the per-barrel PolyZones) ]o---
CreateThread(function()
    local radius = Config.KasiyaBarrelKitConf.BarrelInteractRadius or 2.5
    local radiusSq = radius * radius

    while true do
        local sleep = 2000

        if next(activeBarrels) ~= nil then
            local pCoords = GetEntityCoords(PlayerPedId())
            local insideUid, nearestSq = nil, math.huge

            for uid, pos in pairs(activeBarrels) do
                local offset = pCoords - pos
                local distSq = (offset.x * offset.x) + (offset.y * offset.y) + (offset.z * offset.z)

                if distSq < nearestSq then
                    nearestSq = distSq
                    if distSq <= radiusSq then insideUid = uid end
                end
            end

            ---o[ Entered / left a barrel ]o---
            if insideUid ~= currentInteractingBarrel then
                currentInteractingBarrel = insideUid
                inZone = insideUid ~= nil

                TriggerServerEvent('gsc_kassippu:server:watchBarrel', insideUid)
                Shared.Debug("^2[Barrel]^7 Interaction target: " .. tostring(insideUid))
            end

            if nearestSq <= radiusSq then
                sleep = 200
            elseif nearestSq <= 400.0 then    -- < 20m
                sleep = 400
            elseif nearestSq <= 10000.0 then  -- < 100m
                sleep = 1000
            else
                sleep = 2000
            end
        elseif currentInteractingBarrel then
            currentInteractingBarrel = nil
            inZone = false
            TriggerServerEvent('gsc_kassippu:server:watchBarrel', nil)
        end

        Wait(sleep)
    end
end)

---o[ Out of a scenario for sure ]o---
local SCENARIO_EXIT_MS = 1500

local function EndScenario(ped, scenario)
    ped = ped or PlayerPedId()
    local hash = scenario and GetHashKey(scenario) or nil
    local function Held()
        if hash then return IsPedUsingScenarioHash(ped, hash) end
        return IsPedUsingAnyScenario(ped)
    end

    ClearPedTasks(ped)
    local untilMs = GetGameTimer() + SCENARIO_EXIT_MS
    while Held() and GetGameTimer() < untilMs do Wait(100) end
    if Held() then ClearPedTasksImmediately(ped) end
end

---o[ For radial.lua / crates.lua ]o---
function Barrels.EndScenario(ped, scenario)
    EndScenario(ped, scenario)
end

---o[ Player Anims Play Function ]o---
local function PlayAdvancedAnim(animDict, animName, time, loop, propData)
    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) then return end

    if not animDict then
        TaskStartScenarioInPlace(playerPed, GetHashKey(animName), time, true, false, false, false)
    else
        RequestAnimDict(animDict)
        local startTime = GetGameTimer()
        while not HasAnimDictLoaded(animDict) do
            if GetGameTimer() - startTime > 5000 then
                Shared.Debug("Anim Load Fail: " .. animDict)
                return
            end
            Wait(10)
        end

        local flag = loop and 1 or 16
        local playbackTime = loop and -1 or time
        TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, playbackTime, flag, 0, false, false, false)
    end

    local attachedObj = nil
    if propData and propData.model then
        local modelHash = GetHashKey(propData.model)
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do Wait(10) end

        local pCoords = GetEntityCoords(playerPed)
        attachedObj = CreateObject(modelHash, pCoords.x, pCoords.y, pCoords.z, true, true, false)

        local boneIndex = GetEntityBoneIndexByName(playerPed, propData.bone or "PH_R_Hand")
        local off = propData.offset or vector3(0.0, 0.0, 0.0)
        local rot = propData.rotation or vector3(0.0, 0.0, 0.0)

        AttachEntityToEntity(attachedObj, playerPed, boneIndex, off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true,
            false, true, 1, true)
    end

    Wait(time)
    if DoesEntityExist(attachedObj) then DeleteObject(attachedObj) end
    if animDict then
        ClearPedTasks(playerPed)
        RemoveAnimDict(animDict)
    else
        EndScenario(playerPed, animName)
    end
end

---oo[ Sweep Stray Props Of One Model Around A Point ]oo---
local function SweepNearbyProps(coords, modelHash, radius, label)
    local removed = 0

    for _ = 1, 10 do
        local prop = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, modelHash, false, false, false)
        if not DoesEntityExist(prop) then break end

        NetworkRequestControlOfEntity(prop)
        local timeout = 0
        while not NetworkHasControlOfEntity(prop) and timeout < 20 do
            Wait(5)
            timeout = timeout + 1
        end

        SetEntityAsMissionEntity(prop, true, true)
        DeleteObject(prop)

        if DoesEntityExist(prop) then
            Shared.Debug("^3[Cleanup]^7 Could not remove a stray " .. (label or "prop") .. " - leaving it")
            break
        end

        removed = removed + 1
        Wait(0)
    end

    if removed > 0 then
        Shared.Debug(string.format("^1[Cleanup]^7 Removed %d stray %s(s)", removed, label or "prop"))
    end

    return removed
end

---oo[ Barrel And Fire Props ]oo---

local wreckage = {}

local function LoadPropModel(name)
    local hash = GetHashKey(name)
    if HasModelLoaded(hash) then return hash end

    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - started > 5000 then
            Shared.Debug("^1[Barrel]^7 Model failed to load: " .. tostring(name))
            return nil
        end
        Wait(0)
    end
    return hash
end

local function DeleteLocalProp(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end

local function SweepLegacyProps(pos)
    SweepNearbyProps(pos, GetHashKey(Config.Models.KasiyaBarrelKitModel), 0.6, "stray barrel")
    SweepNearbyProps(pos, GetHashKey(Config.Models.WoodFireModel), 1.0, "stray fire")
end

---oo[ Still Dressing ]oo---

local function DeleteDressing(info)
    for key, prop in pairs(info.dressingProps or {}) do
        if type(prop) == 'table' then
            for _, entity in ipairs(prop) do DeleteLocalProp(entity) end
        else
            DeleteLocalProp(prop)
        end
        info.dressingProps[key] = nil
    end
end

local function AttachDressing(info, spec, extra)
    if not spec or not spec.model or spec.model == "" then return nil end -- "" = this prop is off
    local hash = LoadPropModel(spec.model)
    if not hash or not info.entity then return nil end

    local off = spec.offset or vector3(0.0, 0.0, 0.0)
    local rot = spec.rotation or vector3(0.0, 0.0, 0.0)
    if extra then off = off + extra end

    local prop = CreateObject(hash, info.pos.x, info.pos.y, info.pos.z, false, false, false)
    AttachEntityToEntity(prop, info.entity, 0, off.x, off.y, off.z, rot.x, rot.y, rot.z, true, false, false,
        false, 2, true)
    return prop
end

---o[ One prop: there or not, and the right model ]o---
local function SetDressingProp(info, key, spec, wanted)
    local props = info.dressingProps
    local current = props[key]

    if current and (not wanted or info.dressingModels[key] ~= spec.model) then
        DeleteLocalProp(current)
        props[key], info.dressingModels[key] = nil, nil
        current = nil
    end

    if wanted and not current and spec then
        props[key] = AttachDressing(info, spec)
        info.dressingModels[key] = spec.model
    end
end

---o[ Looped particle effects on a barrel: steam and smoke ]o---
local function SetLoopedFx(info, key, spec, scale)
    info.fx = info.fx or {}
    local current = info.fx[key]
    if current and current.scale == scale then return end

    if current then
        pcall(StopParticleFxLooped, current.handle, false)
        pcall(RemoveParticleFx, current.handle, false)
        info.fx[key] = nil
    end

    if not scale or not spec or not info.entity then return end

    pcall(function()
        local assetHash = GetHashKey(spec.asset)
        RequestNamedPtfxAsset(assetHash)
        local started = GetGameTimer()
        while not HasNamedPtfxAssetLoaded(assetHash) and GetGameTimer() - started < 3000 do Wait(10) end

        UseParticleFxAsset(spec.asset)
        local off = spec.offset or vector3(0.0, 0.0, 1.0)
        local handle = StartParticleFxLoopedOnEntity(spec.name, info.entity, off.x, off.y, off.z,
            0.0, 0.0, 0.0, scale, false, false, false)
        if handle then info.fx[key] = { handle = handle, scale = scale } end
    end)
end

local function StopAllFx(info)
    for key in pairs(info.fx or {}) do SetLoopedFx(info, key, nil, nil) end
end

---o[ Bring a barrel's props in line with what the server last said ]o---
local function ApplyDressing(info)
    local conf = Config.StillDressing
    local d = info.dressing or {}

    if info.fire and DoesEntityExist(info.fire) then SetEntityVisible(info.fire, d.lit == true, false) end

    if not conf or not conf.Enabled or not info.entity then return end
    info.dressingProps = info.dressingProps or {}
    info.dressingModels = info.dressingModels or {}

    SetDressingProp(info, "logs", conf.Logs, not d.lit)
    SetDressingProp(info, "jar", d.jar == "full" and conf.JarFull or conf.JarEmpty, d.jar ~= nil)
    SetDressingProp(info, "tarp", conf.Tarp, d.tarp == true)
    local steam = conf.Steam
    SetLoopedFx(info, "steam", steam, d.steam and steam and (steam.scale or 1.0) or nil)

    local smoke = conf.Smoke
    local level = tonumber(d.smoke) or 0
    SetLoopedFx(info, "smoke", smoke, level > 0 and smoke and smoke.scales and smoke.scales[level] or nil)

    ---o[ A jug per bottle waiting ]o---
    local jugsConf = conf.Jugs
    if jugsConf then
        local want = math.min(tonumber(d.jugs) or 0, jugsConf.max or 6)
        local jugs = info.dressingProps.jugs or {}
        info.dressingProps.jugs = jugs

        while #jugs > want do
            DeleteLocalProp(table.remove(jugs))
        end
        while #jugs < want do
            local step = jugsConf.step or vector3(0.2, 0.0, 0.0)
            local jug = AttachDressing(info, jugsConf, step * #jugs)
            if not jug then break end
            jugs[#jugs + 1] = jug
        end
    end
end

local function DespawnBarrelProp(info)
    StopAllFx(info)
    DeleteDressing(info)
    DeleteLocalProp(info.fire)
    DeleteLocalProp(info.entity)
    info.fire, info.entity = nil, nil
end

---o[ Stand a prop on the ground ]o---
local function SnapToGround(entity)
    for _ = 1, 10 do
        if PlaceObjectOnGroundProperly(entity) then return true end
        Wait(100)
    end
    return false
end

local function SpawnBarrelProp(uid)
    local info = barrelProps[uid]
    if not info or info.entity then return end

    local barrelModel = LoadPropModel(Config.Models.KasiyaBarrelKitModel)
    local fireModel = LoadPropModel(Config.Models.WoodFireModel)
    if not barrelModel then return end

    SweepLegacyProps(info.pos)

    if barrelProps[uid] ~= info or info.entity then return end

    local entity = CreateObject(barrelModel, info.pos.x, info.pos.y, info.pos.z, false, false, false)
    SetEntityHeading(entity, info.heading or 0.0)
    info.entity = entity
    SnapToGround(entity)

    if barrelProps[uid] ~= info or info.entity ~= entity then return end
    FreezeEntityPosition(entity, true)

    if fireModel then
        local fire = CreateObject(fireModel, info.pos.x, info.pos.y, info.pos.z, false, false, false)
        SetEntityVisible(fire, info.dressing and info.dressing.lit == true or false, false)
        AttachEntityToEntity(fire, entity, 0, -0.4, 0.105, -0.5, 0.0, 0.0, 0.0, true, false, false,
            false, 2, true)
        info.fire = fire
    end

    info.dressingDirty = true
end

---o[ Barrels this client knows about ]o---
local function RegisterBarrel(uid, coords, heading)
    local pos = vector3(coords.x, coords.y, coords.z)
    local info = barrelProps[uid]

    if info and #(info.pos - pos) < 0.01 then
        info.heading = heading or 0.0
        if info.entity then SetEntityHeading(info.entity, info.heading) end
    else
        if info then DespawnBarrelProp(info) end
        barrelProps[uid] = { pos = pos, heading = heading or 0.0 }
        info = barrelProps[uid]
    end

    if coords.dressing then
        info.dressing = coords.dressing
        info.dressingDirty = true
    end

    CreateBarrelZone(uid, pos)
end

local function ForgetBarrel(uid)
    local info = barrelProps[uid]
    if info then DespawnBarrelProp(info) end
    barrelProps[uid] = nil
    BarrelStage[uid] = nil
    barrelAccess[uid] = nil
    barrelCut[uid] = nil
    barrelIncident[uid] = nil
    barrelTended[uid] = nil
    barrelFitted[uid] = nil
    barrelFittedSig[uid] = nil
    RemoveBarrelZone(uid)
end

---o[ Streaming thread ]o---
CreateThread(function()
    while true do
        local sleep = 2000

        if next(barrelProps) ~= nil then
            local pCoords = GetEntityCoords(PlayerPedId())
            local streamIn = Config.KasiyaBarrelKitConf.StreamDistance or 80.0
            local streamOut = streamIn + 10.0

            local uids = {}
            for uid in pairs(barrelProps) do uids[#uids + 1] = uid end

            for _, uid in ipairs(uids) do
                local info = barrelProps[uid]
                if info then
                    local dist = #(pCoords - info.pos)

                    if dist <= streamIn and not info.entity then
                        SpawnBarrelProp(uid)
                    elseif dist > streamOut and info.entity then
                        DespawnBarrelProp(info)
                    end

                    if info.entity and info.dressingDirty and barrelProps[uid] == info then
                        info.dressingDirty = false
                        ApplyDressing(info)
                    end

                    if dist <= streamOut + 30.0 then sleep = 1000 end
                end
            end
        end

        Wait(sleep)
    end
end)

---oo[ Barrel Prompts ]oo---
CreateThread(function()
    local holdTime = Config.KasiyaBarrelKitConf.KasiyaBarrelPromptsHoldTime

    ---o[ UI Open Prompt ]o---
    OpenBarrelUIPrompt = PromptRegisterBegin()
    PromptSetControlAction(OpenBarrelUIPrompt, Config.InteractKeys.BarrelUIInteractingKey)
    PromptSetText(OpenBarrelUIPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelUIPrompt))
    PromptSetEnabled(OpenBarrelUIPrompt, true)
    PromptSetVisible(OpenBarrelUIPrompt, false)
    PromptSetHoldMode(OpenBarrelUIPrompt, holdTime)
    PromptSetGroup(OpenBarrelUIPrompt, PromptGroups, 0)
    PromptRegisterEnd(OpenBarrelUIPrompt)

    ---o[ Wood Fuel Add Prompt ]o---
    AddWoodPrompt = PromptRegisterBegin()
    PromptSetControlAction(AddWoodPrompt, Config.InteractKeys.WoodFuelAddingKey)
    PromptSetText(AddWoodPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.WoodFuelAddingPrompt))
    PromptSetEnabled(AddWoodPrompt, true)
    PromptSetVisible(AddWoodPrompt, false)
    PromptSetHoldMode(AddWoodPrompt, holdTime)
    PromptSetGroup(AddWoodPrompt, PromptGroups, 0)
    PromptRegisterEnd(AddWoodPrompt)

    ---o[ Fuel Choice Prompt ]o---
    FuelSelectPrompt = PromptRegisterBegin()
    PromptSetControlAction(FuelSelectPrompt, Config.InteractKeys.FuelSelectLeftKey)
    PromptSetControlAction(FuelSelectPrompt, Config.InteractKeys.FuelSelectRightKey)
    PromptSetText(FuelSelectPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.FuelSelectPrompt))
    PromptSetEnabled(FuelSelectPrompt, true)
    PromptSetVisible(FuelSelectPrompt, false)
    PromptSetStandardMode(FuelSelectPrompt, true)
    PromptSetGroup(FuelSelectPrompt, PromptGroups, 0)
    PromptRegisterEnd(FuelSelectPrompt)

    ---o[ Water Adding Prompt ]o---
    AddWaterPrompt = PromptRegisterBegin()
    PromptSetControlAction(AddWaterPrompt, Config.InteractKeys.WaterPouringKey)
    PromptSetText(AddWaterPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.WaterAddingPrompt))
    PromptSetEnabled(AddWaterPrompt, true)
    PromptSetVisible(AddWaterPrompt, false)
    PromptSetHoldMode(AddWaterPrompt, holdTime)
    PromptSetGroup(AddWaterPrompt, PromptGroups, 0)
    PromptRegisterEnd(AddWaterPrompt)

    ---o[ Ingredients Adding Prompt ]o---
    AddIngredientsPrompt = PromptRegisterBegin()
    PromptSetControlAction(AddIngredientsPrompt, Config.InteractKeys.IngredientsAddingKey)
    PromptSetText(AddIngredientsPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.IngredientsAddingPrompt))
    PromptSetEnabled(AddIngredientsPrompt, true)
    PromptSetVisible(AddIngredientsPrompt, false)
    PromptSetStandardMode(AddIngredientsPrompt, true)
    PromptSetGroup(AddIngredientsPrompt, PromptGroups, 0)
    PromptRegisterEnd(AddIngredientsPrompt)

    ---o[ Pressure Vent Prompt ]o---
    VentPrompt = PromptRegisterBegin()
    PromptSetControlAction(VentPrompt, Config.InteractKeys.BarrelVentKey)
    PromptSetText(VentPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelVentPrompt))
    PromptSetEnabled(VentPrompt, true)
    PromptSetVisible(VentPrompt, false)
    PromptSetHoldMode(VentPrompt, holdTime)
    PromptSetGroup(VentPrompt, PromptGroups, 0)
    PromptRegisterEnd(VentPrompt)

    ---o[ Scrub Barrel Prompt ]o---
    ScrubPrompt = PromptRegisterBegin()
    PromptSetControlAction(ScrubPrompt, Config.InteractKeys.BarrelScrubKey)
    PromptSetText(ScrubPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelScrubPrompt))
    PromptSetEnabled(ScrubPrompt, true)
    PromptSetVisible(ScrubPrompt, false)
    PromptSetHoldMode(ScrubPrompt, holdTime)
    PromptSetGroup(ScrubPrompt, PromptGroups, 0)
    PromptRegisterEnd(ScrubPrompt)

    ---o[ Repair Barrel Prompt ]o---
    RepairPrompt = PromptRegisterBegin()
    PromptSetControlAction(RepairPrompt, Config.InteractKeys.BarrelRepairKey)
    PromptSetText(RepairPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelRepairPrompt))
    PromptSetEnabled(RepairPrompt, true)
    PromptSetVisible(RepairPrompt, false)
    PromptSetHoldMode(RepairPrompt, holdTime)
    PromptSetGroup(RepairPrompt, PromptGroups, 0)
    PromptRegisterEnd(RepairPrompt)

    ---o[ Cooking Crew Prompt ]o---

    CrewLeavePrompt = PromptRegisterBegin()
    PromptSetControlAction(CrewLeavePrompt, Config.InteractKeys.BarrelCrewLeaveKey)
    PromptSetText(CrewLeavePrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelCrewLeavePrompt))
    PromptSetEnabled(CrewLeavePrompt, true)
    PromptSetVisible(CrewLeavePrompt, false)
    PromptSetHoldMode(CrewLeavePrompt, holdTime)
    PromptSetGroup(CrewLeavePrompt, PromptGroups, 0)
    PromptRegisterEnd(CrewLeavePrompt)

    ---o[ Steal A Bottle - strangers only, at a finished batch ]o---
    StealPrompt = PromptRegisterBegin()
    PromptSetControlAction(StealPrompt, Config.InteractKeys.BarrelStealKey)
    PromptSetText(StealPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelStealPrompt))
    PromptSetEnabled(StealPrompt, true)
    PromptSetVisible(StealPrompt, false)
    PromptSetHoldMode(StealPrompt, holdTime)
    PromptSetGroup(StealPrompt, PromptGroups, 0)
    PromptRegisterEnd(StealPrompt)

    ---o[ The law ]o---
    local law = Config.Law or {}

    SeizePrompt = PromptRegisterBegin()
    PromptSetControlAction(SeizePrompt, Config.InteractKeys.BarrelSeizeKey)
    PromptSetText(SeizePrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.SeizePrompt))
    PromptSetEnabled(SeizePrompt, true)
    PromptSetVisible(SeizePrompt, false)
    PromptSetHoldMode(SeizePrompt, (law.Seize or {}).HoldMs or 5000)
    PromptSetGroup(SeizePrompt, PromptGroups, 0)
    PromptRegisterEnd(SeizePrompt)

    PourPrompt = PromptRegisterBegin()
    PromptSetControlAction(PourPrompt, Config.InteractKeys.BarrelPourKey)
    PromptSetText(PourPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.PourPrompt))
    PromptSetEnabled(PourPrompt, true)
    PromptSetVisible(PourPrompt, false)
    PromptSetHoldMode(PourPrompt, (law.Pour or {}).HoldMs or 3000)
    PromptSetGroup(PourPrompt, PromptGroups, 0)
    PromptRegisterEnd(PourPrompt)

    ---o[ Pick Up Barrel - the owner, at an idle, cold, empty barrel ]o---
    PickupPrompt = PromptRegisterBegin()
    PromptSetControlAction(PickupPrompt, Config.InteractKeys.BarrelPickupKey)
    PromptSetText(PickupPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.BarrelPickupPrompt))
    PromptSetEnabled(PickupPrompt, true)
    PromptSetVisible(PickupPrompt, false)
    PromptSetHoldMode(PickupPrompt, (Config.BarrelPickup or {}).HoldMs or holdTime)
    PromptSetGroup(PickupPrompt, PromptGroups, 0)
    PromptRegisterEnd(PickupPrompt)

    ---o[ Still Tarp Prompt: rig one, or take it down ]o---
    TarpPrompt = PromptRegisterBegin()
    PromptSetControlAction(TarpPrompt, Config.InteractKeys.BarrelTarpKey)
    PromptSetText(TarpPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.TarpRigPrompt))
    PromptSetEnabled(TarpPrompt, true)
    PromptSetVisible(TarpPrompt, false)
    PromptSetHoldMode(TarpPrompt, holdTime)
    PromptSetGroup(TarpPrompt, PromptGroups, 0)
    PromptRegisterEnd(TarpPrompt)

    ---o[ Trouble at the still: renamed to whatever has gone wrong ]o---
    IncidentPrompt = PromptRegisterBegin()
    PromptSetControlAction(IncidentPrompt, Config.InteractKeys.BarrelIncidentKey)
    PromptSetText(IncidentPrompt, VarString(10, "LITERAL_STRING", Config.PromptsTxt.IncidentPrompt))
    PromptSetEnabled(IncidentPrompt, true)
    PromptSetVisible(IncidentPrompt, false)
    PromptSetHoldMode(IncidentPrompt, holdTime)
    PromptSetGroup(IncidentPrompt, PromptGroups, 0)
    PromptRegisterEnd(IncidentPrompt)

end)

---o[ Track sound state globally for this client ]o---
local isBubblingPlaying = false

---o[ Still ambience: a game sound at the nearest lit still ]o---
local Ambience = { uid = nil, soundId = nil, prepared = false }

---o[ keepSet: moving on to another still keeps the soundset loaded; only leaving them all releases it ]o---
local function StopAmbience(keepSet)
    if Ambience.soundId then
        Citizen.InvokeNative(0x3210BCB36AF7621B, Ambience.soundId) -- _STOP_SOUND_WITH_ID
        Citizen.InvokeNative(0x353FC880830B88FA, Ambience.soundId) -- RELEASE_SOUND_ID
    end
    if not keepSet and Ambience.prepared and Config.StillAmbience then
        Citizen.InvokeNative(0x531A78D6BF27014B, Config.StillAmbience.SoundSet) -- _RELEASE_SOUNDSET
        Ambience.prepared = false
    end
    Ambience.uid, Ambience.soundId = nil, nil
end

CreateThread(function()
    local conf = Config.StillAmbience
    if not (conf and conf.Enabled) then return end

    local stages = {}
    for _, stage in ipairs(conf.Stages or {}) do stages[stage] = true end
    local range = conf.Range or 12.0

    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local best, bestDist = nil, range

        for uid, info in pairs(barrelProps) do
            if info.entity and DoesEntityExist(info.entity)
                and stages[BarrelStage[uid] or Shared.BarrelStage.IDLE]
                and (not conf.OnlyWhenLit or (info.dressing and info.dressing.lit == true)) then
                local dist = #(info.pos - pos)
                if dist < bestDist then best, bestDist = uid, dist end
            end
        end

        if best ~= Ambience.uid then StopAmbience(best ~= nil) end

        if best then
            if not Ambience.prepared then
                Ambience.prepared = Citizen.InvokeNative(0xD9130842D7226045, conf.SoundSet, 0,
                    Citizen.ResultAsInteger()) == 1 -- PREPARE_SOUNDSET
            end

            ---o[ Start it, and start it again if the sound is a one-shot that ended ]o---
            if Ambience.prepared and (not Ambience.soundId
                    or Citizen.InvokeNative(0x84848E1C0FC67DBB, Ambience.soundId, Citizen.ResultAsInteger()) == 1) then -- _HAS_SOUND_ID_FINISHED
                if Ambience.soundId then Citizen.InvokeNative(0x353FC880830B88FA, Ambience.soundId) end -- RELEASE_SOUND_ID
                local id = GetSoundId()
                if id and id ~= -1 then
                    Citizen.InvokeNative(0xF1C5310FEAA36B48, id, conf.SoundName, barrelProps[best].entity,
                        conf.SoundSet, false, 0) -- _PLAY_SOUND_FROM_ENTITY_WITH_SET
                    Ambience.soundId = id
                else
                    Ambience.soundId = nil
                end
                Ambience.uid = best
            end
        end

        Wait(best and 500 or 1500)
    end
end)

local groupLabelCache = {}
---o[ A stage as the player reads it ]o---
local function StageInfo(stage)
    return (Config.Text.Stages or {})[stage] or { label = stage }
end

local function GetGroupLabel(stage)
    local text = groupLabelCache[stage] -- caches the text only: a VarString can't outlive its frame
    if not text then
        text = Config.KasiyaBarrelKitConf.KasiyaBarrelPromptTitle .. " [" .. StageInfo(stage).label .. "]"
        groupLabelCache[stage] = text
    end
    return VarString(10, 'LITERAL_STRING', text)
end

---oo[ The At-The-Barrel Gauge ]oo---
local gaugeVisible = false

local function HideBarrelGauge()
    if not gaugeVisible then return end

    gaugeVisible = false
    SendNUIMessage({ action = "hideGauge" })
end

local function ShowBarrelGauge(heat, stage, gauge)
    if stage == Shared.BarrelStage.COMPLETED then
        return HideBarrelGauge()
    end

    gaugeVisible = true
    gauge = gauge or {}

    local info = StageInfo(stage)

    SendNUIMessage({
        action = "showGauge",
        heat = heat,
        stage = info.label,
        hint = info.hint,
        mix = gauge.mix,
        maxHeat = Config.HeatManagement.MaxHeat,
        target = gauge.target,
        band = gauge.band,
        score = gauge.score,
        pushLeft = gauge.pushLeft,
        pressure = Config.Pressure.Enabled and gauge.pressure or nil,
        pressureWarn = gauge.pressureWarn or Config.Pressure.WarnAt, -- sooner with a gauge fitted
        upgrades = gauge.upgrades,
        condition = gauge.condition,
        residue = gauge.residue,
        conditionWarn = gauge.conditionWarn,
        crew = gauge.crew,
        ferment = gauge.ferment,
        cut = gauge.cut,
        cutText = gauge.cut and Config.Text.Cuts or nil,
        fire = gauge.fire,
        fireText = Config.Text.FireGauge,
        incident = gauge.incident,
        incidentTitle = Config.Text.IncidentGauge,
        condenser = gauge.condenser,
        condenserText = Config.Text.CondenserGauge,
        game = gauge.game,
        gameText = gauge.game and {
            Water = ((Config.Text.PushGame or {}).Gauge or {}).Water,
            Logs = ((Config.Text.PushGame or {}).Gauge or {}).Logs,
            TapOn = ((Config.Text.PushGame or {}).Gauge or {}).TapOn,
            flare = (Config.Text.PushGame or {}).WarnFlare,
            draught = (Config.Text.PushGame or {}).WarnDraught,
        } or nil,
    })
end

---o[ Fire a prompt once per press, not once per tick ]o---
local promptLatched = {}

local function ResetPromptLatches()
    for prompt in pairs(promptLatched) do promptLatched[prompt] = nil end
end

local function JustCompleted(prompt, completed)
    if not completed then
        promptLatched[prompt] = nil
        return false
    end

    if promptLatched[prompt] then return false end

    promptLatched[prompt] = true
    return true
end

local function HoldJustCompleted(prompt)
    return JustCompleted(prompt, UiPromptHasHoldModeCompleted(prompt))
end

local function StandardJustCompleted(prompt)
    return JustCompleted(prompt, UiPromptHasStandardModeCompleted(prompt))
end

local function ControlJustPressed(key)
    return IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key)
end

---o[ Which prompts each stage puts on screen ]o---
local function SetPromptLabel(prompt, current, text)
    if text == current then return current end
    PromptSetText(prompt, VarString(10, "LITERAL_STRING", text))
    return text
end

---o[ The fuel the wood prompt puts on ]o---
local fuelKinds = {}
for kind in pairs(Config.Fuel.Logs) do fuelKinds[#fuelKinds + 1] = kind end
table.sort(fuelKinds, function(a, b)
    local burnA, burnB = Config.Fuel.Logs[a].burnSeconds or 0, Config.Fuel.Logs[b].burnSeconds or 0
    if burnA ~= burnB then return burnA < burnB end
    return a < b
end)
local fuelIndex = 1

local function SelectedFuel()
    return fuelKinds[fuelIndex] or "wood"
end

local function FuelSelectLabel()
    local log = Config.Fuel.Logs[SelectedFuel()]
    return string.format(Config.PromptsTxt.FuelSelectPrompt, log and log.label or SelectedFuel())
end

local function SetPromptVisibility(ui, wood, water, ingredients, vent, scrub, repair, leave, steal, fuelChoiceToo)
    fuelChoiceShown = wood and fuelChoiceToo ~= false and #fuelKinds > 1
    if fuelChoiceShown then
        fuelSelectText = SetPromptLabel(FuelSelectPrompt, fuelSelectText, FuelSelectLabel())
    end

    PromptSetVisible(OpenBarrelUIPrompt, ui)
    PromptSetVisible(AddWoodPrompt, wood)
    PromptSetVisible(FuelSelectPrompt, fuelChoiceShown)
    PromptSetVisible(AddWaterPrompt, water)
    PromptSetVisible(AddIngredientsPrompt, ingredients)
    PromptSetVisible(VentPrompt, vent)
    PromptSetVisible(ScrubPrompt, scrub)
    PromptSetVisible(RepairPrompt, repair)
    PromptSetVisible(CrewLeavePrompt, leave)
    PromptSetVisible(StealPrompt, steal or false)

    crewLeaveShown, stealShown = leave, steal or false
end

local function SetLawPrompts(seize, pour)
    seizeShown, pourShown = seize, pour
    PromptSetVisible(SeizePrompt, seize)
    PromptSetVisible(PourPrompt, pour)
end

local function SetIncidentPrompt(visible, label)
    incidentShown = visible
    if visible then
        incidentPromptText = SetPromptLabel(IncidentPrompt, incidentPromptText, label or Config.PromptsTxt.IncidentPrompt)
    end
    PromptSetVisible(IncidentPrompt, visible)
end

local function SetPickupPrompt(visible)
    pickupShown = visible
    PromptSetVisible(PickupPrompt, visible)
end

local function SetTarpPrompt(visible, rigged)
    tarpShown = visible
    if visible then
        tarpPromptText = SetPromptLabel(TarpPrompt, tarpPromptText,
            rigged and Config.PromptsTxt.TarpTakeDownPrompt or Config.PromptsTxt.TarpRigPrompt)
    end
    PromptSetVisible(TarpPrompt, visible)
end

local function HideAllPrompts()
    SetPromptVisibility(false, false, false, false, false, false, false, false, false)
    SetLawPrompts(false, false)
    SetIncidentPrompt(false)
    SetPickupPrompt(false)
    SetTarpPrompt(false)
    menuHintShown = false
end

---o[ The crew rules, as far as the prompts go ]o---
local function CrewOn()
    return Config.BarrelCrew and Config.BarrelCrew.Enabled
end

local function RoleAt(uid)
    if not CrewOn() then return "owner" end
    local access = barrelAccess[uid]
    return access and access.role or "none"
end

local function CrewCount(uid)
    local access = barrelAccess[uid]
    return access and access.crew and #access.crew or 0
end

local function CanDo(uid, action)
    local role = RoleAt(uid)
    if role == "owner" or not Config.BarrelCrew.CrewOnly then return true end
    return role == "crew" and (Config.BarrelCrew.CrewCan or {})[action] == true
end

local function CanSteal(uid, stage)
    local theft = Config.BarrelTheft
    if not (theft and theft.Enabled and CrewOn() and Config.BarrelCrew.CrewOnly) then return false end
    if stage == Shared.BarrelStage.FERMENTING and not theft.SpikeEnabled then return false end
    if barrelAccess[uid] and barrelAccess[uid].law then return false end
    return barrelAccess[uid] ~= nil and barrelAccess[uid].role == "none"
end

---o[ The tarp ]o---
local function CanTarp(uid)
    local rain = Config.Fuel.Rain
    local role = RoleAt(uid)
    return (rain and rain.Enabled and rain.TarpEnabled and (role == "owner" or role == "crew")
        and CanDo(uid, "repair")) and true or false
end

local function TarpUp(uid)
    local info = barrelProps[uid]
    return info and info.dressing and info.dressing.tarp == true or false
end

local function TarpBookState(uid)
    if not CanTarp(uid) then return nil end
    return { up = TarpUp(uid), text = Config.Text.TarpBook }
end

---o[ The Fittings slip beside the book ]o---
local function FittingsBookState(uid)
    local conf = Config.Upgrades
    if not (conf and conf.Enabled) then return nil end
    local role = RoleAt(uid)
    if not ((role == "owner" or role == "crew") and CanDo(uid, "repair")) then return nil end

    local fitted = barrelFitted[uid] or {}
    local list = {}
    for key, up in pairs(conf.List or {}) do
        if up.item and Shared.UpgradeUsable(up) then
            list[#list + 1] = {
                key = key,
                label = up.label or key,
                desc = up.desc or "",
                fitted = fitted[key] == true,
                order = tonumber(up.order) or 99,
            }
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return { list = list, text = Config.Text.FittingsBook }
end

---o[ Hold The Heat as a game ]o---
local function PushGameOn()
    local game = Config.HeatSkill and Config.HeatSkill.Enabled and Config.HeatSkill.Game
    return game ~= nil and game.Enabled == true
end

---o[ What the barrel offers at this stage, to this player ]o---
local function BarrelOffer(stage, uid)
    local Stage = Shared.BarrelStage
    local P = Config.PromptsTxt
    local o = {}

    local canVent = Config.Pressure.Enabled and CanDo(uid, "vent")
    local canFuel = CanDo(uid, "fuel")
    local canCool = CanDo(uid, "cool")

    local wear = Config.BarrelCondition.Enabled and stage == Stage.IDLE
    local canScrub = wear and barrelNeedsScrub and CanDo(uid, "scrub")
    local canRepair = wear and barrelNeedsRepair and CanDo(uid, "repair")

    ---o[ The crew, at every stage ]o---
    local role = RoleAt(uid)
    local crewCount = CrewCount(uid)

    if CrewOn() and role == "owner" and crewCount > 0 then
        o.leaveText = P.BarrelCrewDismissPrompt
    elseif CrewOn() and role == "crew" then
        o.leaveText = P.BarrelCrewLeavePrompt
    end
    local leave = o.leaveText ~= nil

    ---o[ At a fermenting wash, wood lights the still and a stranger spikes it ]o---
    local fermenting = stage == Stage.FERMENTING
    local cutting = stage == Stage.BREWING and Config.Cuts.Enabled
    local cut = barrelCut[uid]

    o.woodText = P.WoodFuelAddingPrompt
    if stage == Stage.COMPLETED then
        o.woodText = P.CollectingProductsPrompt
    elseif fermenting then
        o.woodText = P.FermentLightPrompt
    elseif cutting then
        o.woodText = (cut and cut.keeping) and P.CutStopPrompt or P.CutStartPrompt
    end

    local condensing = stage == Stage.BREWING and Config.Condenser.Enabled
    o.waterText = condensing and P.CondenserPrompt or P.WaterAddingPrompt
    o.stealText = fermenting and P.BarrelSpikePrompt or P.BarrelStealPrompt

    ---o[ [G] stores ingredients at FREEZE, and tends the wash while it ferments ]o---
    local tendConf = Config.Fermentation.Enabled and Config.Fermentation.Tend or nil
    local canTend = fermenting and tendConf ~= nil and tendConf.Enabled == true
        and CanDo(uid, "mix") and not barrelTended[uid]
    o.ingredientsText = fermenting and P.TendWashPrompt or P.IngredientsAddingPrompt

    ---o[ ui, wood, water, ingredients, vent, scrub, repair, steal, fuel choice ]o---
    local function Set(ui, wood, water, ingredients, vent, scrub, repair, steal, fuelChoiceToo)
        o.ui, o.wood, o.water, o.ingredients = ui, wood, water, ingredients
        o.vent, o.scrub, o.repair, o.leave, o.steal = vent, scrub, repair, leave, steal or false
        o.fuelChoiceToo = fuelChoiceToo
    end

    if stage == Stage.COMPLETED then
        Set(true, CanDo(uid, "bottle"), false, false, false, false, false, CanSteal(uid, stage), false)
    elseif fermenting then
        Set(true, canFuel, false, canTend, false, false, false, CanSteal(uid, stage))
    elseif stage == Stage.IDLE then
        Set(true, canFuel, false, false, false, canScrub, canRepair)
    elseif stage == Stage.MID_CLIMB then
        Set(true, canFuel, false, false, false, false, false)
    elseif stage == Stage.FREEZE then
        Set(true, false, false, CanDo(uid, "ingredients"), false, false, false)
    elseif stage == Stage.BREWING then
        Set(true, cutting and CanDo(uid, "cuts"), condensing and CanDo(uid, "cool"), false, false, false, false, false, false)
    elseif stage == Stage.MIXING then
        Set(true, false, false, false, false, false, false)
    elseif stage == Stage.FINAL_PUSH and PushGameOn() then
        Set(true, false, false, false, false, false, false)
    else -- HEAT_PAUSE / FINAL_PUSH
        Set(true, canFuel, canCool, false, canVent, false, false)
    end

    ---o[ The law, at any stage with something to find ]o---
    local law = Config.Law or {}
    local info = barrelProps[uid]
    local lit = info and info.dressing and info.dressing.lit == true
    local evidence = stage ~= Stage.IDLE or lit
    local access = barrelAccess[uid]

    o.seize = (law.Enabled and (law.Seize or {}).Enabled and evidence
        and access ~= nil and access.law == true and access.role == "none") and true or false
    o.pour = (law.Enabled and (law.Pour or {}).Enabled and evidence
        and (role == "owner" or role == "crew") and CanDo(uid, "pour")) and true or false

    ---o[ Pack her up ]o---
    o.pickup = (Config.BarrelPickup and Config.BarrelPickup.Enabled
        and stage == Stage.IDLE and not lit and role == "owner") and true or false

    o.tarp, o.tarpUp = CanTarp(uid), TarpUp(uid)

    ---o[ Trouble ]o---
    local trouble = barrelIncident[uid]
    o.incident = (trouble ~= nil and (role == "owner" or role == "crew") and CanDo(uid, "fix")) and true or false
    o.incidentText = trouble and trouble.label or nil

    return o
end

local function ApplyStageVisibility(stage, uid)
    local o = BarrelOffer(stage, uid)

    if o.leaveText and o.leaveText ~= crewLeaveText then
        crewLeaveText = o.leaveText
        PromptSetText(CrewLeavePrompt, VarString(10, "LITERAL_STRING", o.leaveText))
    end

    woodPromptText = SetPromptLabel(AddWoodPrompt, woodPromptText, o.woodText)
    waterPromptText = SetPromptLabel(AddWaterPrompt, waterPromptText, o.waterText)
    stealPromptText = SetPromptLabel(StealPrompt, stealPromptText, o.stealText)
    ingredientsPromptText = SetPromptLabel(AddIngredientsPrompt, ingredientsPromptText, o.ingredientsText)

    SetPromptVisibility(o.ui, o.wood, o.water, o.ingredients, o.vent, o.scrub, o.repair, o.leave, o.steal,
        o.fuelChoiceToo)
    SetLawPrompts(o.seize, o.pour)
    SetPickupPrompt(o.pickup)
    SetTarpPrompt(o.tarp, o.tarpUp)
    SetIncidentPrompt(o.incident, o.incidentText)
end

---o[ Do one barrel action ]o---
local function DoBarrel(action, uid, stage, fuel)
    local S = Shared.BarrelStage

    if action == "ui" then
        Barrels.OpenUI()
    elseif action == "leave" then
        TriggerServerEvent('gsc_kassippu:server:crewLeave', uid)
    elseif action == "incident" then
        TriggerServerEvent('gsc_kassippu:server:fixIncident', uid)
    elseif action == "seize" then
        TriggerServerEvent('gsc_kassippu:server:seizeBarrel', uid)
    elseif action == "pour" then
        TriggerServerEvent('gsc_kassippu:server:pourOut', uid)
    elseif action == "pickup" then
        TriggerServerEvent('gsc_kassippu:server:pickupBarrel', uid)
    elseif action == "tarp" then
        TriggerServerEvent('gsc_kassippu:server:toggleTarp', uid)
    elseif action == "steal" then
        TriggerServerEvent('gsc_kassippu:server:tamperBarrel', uid)
    elseif action == "wood" then
        if stage == S.COMPLETED then
            TriggerServerEvent('gsc_kassippu:server:collectProduct', uid)
        elseif stage == S.BREWING then
            if Config.Cuts.Enabled then TriggerServerEvent('gsc_kassippu:server:switchJar', uid) end
        elseif stage ~= S.FREEZE and stage ~= S.MIXING then
            TriggerServerEvent('gsc_kassippu:server:addOneWood', uid, fuel or SelectedFuel())
        end
    elseif action == "water" then
        if stage ~= S.BREWING or Config.Condenser.Enabled then
            TriggerServerEvent('gsc_kassippu:server:addWater', uid)
        end
    elseif action == "ingredients" then
        if stage == S.FREEZE then
            TriggerServerEvent('gsc_kassippu:server:openBarrelInv', uid)
        elseif stage == S.FERMENTING then
            TriggerServerEvent('gsc_kassippu:server:tendWash', uid)
        end
    elseif action == "vent" then
        if Config.Pressure.Enabled then TriggerServerEvent('gsc_kassippu:server:ventBarrel', uid) end
    elseif action == "scrub" then
        TriggerServerEvent('gsc_kassippu:server:scrubBarrel', uid)
    elseif action == "repair" then
        TriggerServerEvent('gsc_kassippu:server:repairBarrel', uid)
    end
end

---o[ For GSC.Radial ]o---
function Barrels.IsBusy()
    return isUIOpen or isPlacing or isBusy
end

---o[ For GSC.PushGame / GSC.Stations ]o---
function Barrels.Here()
    if not inZone or not currentInteractingBarrel then return nil end
    local uid = currentInteractingBarrel
    return uid, BarrelStage[uid] or Shared.BarrelStage.IDLE, activeBarrels[uid]
end

function Barrels.Position(uid)
    return activeBarrels[uid]
end

function Barrels.CanDo(uid, action)
    return CanDo(uid, action)
end

function Barrels.Incident(uid)
    return barrelIncident[uid]
end

function Barrels.Act(action, uid)
    DoBarrel(action, uid, BarrelStage[uid] or Shared.BarrelStage.IDLE)
end

---o[ For GSC.Radial ]o---
function Barrels.RadialActions()
    if not (GSC.Radial ~= nil and GSC.Radial.Owns("barrel")) then return nil end -- the still is on its key prompts
    if not inZone or not currentInteractingBarrel then return nil end
    if isUIOpen or isPlacing or isBusy or GSC.Crew.IsInvitePending() then return nil end

    local uid = currentInteractingBarrel
    local stage = BarrelStage[uid] or Shared.BarrelStage.IDLE
    local S = Shared.BarrelStage
    local P, R = Config.PromptsTxt, Config.Text.Radial or {}
    local o = BarrelOffer(stage, uid)
    local list = {}

    local function Add(action, title, icon, holdMs, fuel)
        list[#list + 1] = {
            id = "gsc_barrel_" .. action .. (fuel and ("_" .. fuel) or ""),
            title = title, icon = icon, holdMs = holdMs,
            run = function() DoBarrel(action, uid, stage, fuel) end,
        }
    end

    if o.incident then Add("incident", o.incidentText or P.IncidentPrompt, "triangle-exclamation") end

    ---o[ Hold The Heat: open the Firebox panel again ]o---
    if stage == S.FINAL_PUSH and GSC.PushGame ~= nil and GSC.PushGame.CanOpen(uid) then
        list[#list + 1] = {
            id = "gsc_barrel_pushpanel", icon = "fire",
            title = (Config.Text.PushGame or {}).Open or "Work The Fire",
            run = function() GSC.PushGame.Open(uid) end,
        }
    end

    if o.wood then
        local burning = stage ~= S.COMPLETED and stage ~= S.BREWING
        if burning and #fuelKinds > 1 then
            ---o[ One fuel wedge ]o---
            local logs = {}
            for _, kind in ipairs(fuelKinds) do
                local log = Config.Fuel.Logs[kind] or {}
                logs[#logs + 1] = {
                    id = "gsc_barrel_wood_" .. kind, title = log.label or kind, icon = log.icon or "fire",
                    run = function() DoBarrel("wood", uid, stage, kind) end,
                }
            end
            list[#list + 1] = { id = "gsc_barrel_fuel", title = o.woodText, icon = "fire", items = logs }
        else
            local icon = (stage == S.COMPLETED and "wine-bottle") or (stage == S.BREWING and "jar") or "fire"
            Add("wood", o.woodText, icon)
        end
    end

    if o.water then Add("water", o.waterText, "droplet") end
    if o.ingredients then Add("ingredients", o.ingredientsText, stage == S.FERMENTING and "spoon" or "box-open") end
    if o.vent then Add("vent", P.BarrelVentPrompt, "wind") end
    if o.scrub then Add("scrub", P.BarrelScrubPrompt, "broom") end
    if o.repair then Add("repair", P.BarrelRepairPrompt, "hammer") end
    if o.pour then Add("pour", P.PourPrompt, "trash", ((Config.Law or {}).Pour or {}).HoldMs or 3000) end
    if o.seize then Add("seize", P.SeizePrompt, "gavel", ((Config.Law or {}).Seize or {}).HoldMs or 5000) end
    if o.steal then Add("steal", o.stealText, stage == S.FERMENTING and "flask" or "hand") end
    if o.tarp then Add("tarp", o.tarpUp and P.TarpTakeDownPrompt or P.TarpRigPrompt, "umbrella") end
    if o.pickup then Add("pickup", P.BarrelPickupPrompt, "box", (Config.BarrelPickup or {}).HoldMs or 1500) end
    if o.leave then Add("leave", o.leaveText, "user-xmark") end
    ---o[ The Water Barrel / Log Rack the player carries and this still lacks ]o---
    if GSC.Stations ~= nil and GSC.Stations.StillActions then
        for _, action in ipairs(GSC.Stations.StillActions(uid, stage)) do list[#list + 1] = action end
    end

    if o.ui then Add("ui", P.BarrelUIPrompt, "book") end

    return { title = R.Barrel or "Still", icon = "fire", actions = list }
end

---oo[ Interactions Main Loop (For Prompts) ]oo---
CreateThread(function()
    local promptsHidden = true
    local shownStage = nil
    local keyCheckedAt = 0
    local keyStage, keyUid = nil, nil
    local KEY_CHECK_MS = 200
    local yieldHidden = false

    while true do
        local sleep = 1000

        if inZone and currentInteractingBarrel then
            ---o[ Update Current Interacting Barrel To String UID ]o---
            local barrelUID = currentInteractingBarrel

            ---o[ Get Current Stage ]o---
            local stage = BarrelStage[barrelUID] or Shared.BarrelStage.IDLE

            if stage == Shared.BarrelStage.MIXING or stage == Shared.BarrelStage.FERMENTING
                or stage == Shared.BarrelStage.BREWING then
                if not isBubblingPlaying then
                    isBubblingPlaying = true
                    SendNUIMessage({
                        action = "playSound",
                        file = Config.Mixing.Sound,
                        volume = Config.Mixing.SoundVolume
                    })
                    Shared.Debug("^2[Audio]^7 Started bubbling for: " .. barrelUID)
                end
            else
                if isBubblingPlaying then
                    isBubblingPlaying = false
                    SendNUIMessage({ action = "stopSound" })
                    Shared.Debug("^1[Audio]^7 Stopped bubbling - Barrel stage is: " .. stage)
                end
            end

            ---o[ The recipe book and barrel placement both own the screen ]o---
            if isUIOpen or isPlacing or isBusy or GSC.Crew.IsInvitePending()
                or (GSC.Stations ~= nil and GSC.Stations.IsBusy()) then
                sleep = 200

                if not promptsHidden then
                    promptsHidden = true
                    shownStage = nil
                    keyCheckedAt = 0
                    HideAllPrompts()
                    HideBarrelGauge()
                end
            else
                sleep = 0
                promptsHidden = false

                ---o[ Hold The Heat's own prompts, or a station's, take the still ]o---
                local yielded = (GSC.PushGame ~= nil and GSC.PushGame.Running())
                    or (GSC.Stations ~= nil and GSC.Stations.HoldsPrompts())
                if yielded then
                    sleep = 100
                    if not yieldHidden then
                        HideAllPrompts()
                        yieldHidden = true
                    end
                    shownStage = nil
                    if GSC.Radial ~= nil and GSC.Radial.Owns("barrel") then GSC.Radial.Hint("barrel") end
                elseif (GSC.Radial ~= nil and GSC.Radial.Owns("barrel")) then
                    sleep = 100
                    yieldHidden = false
                    if not menuHintShown then
                        HideAllPrompts()
                        menuHintShown = true
                    end
                    GSC.Radial.Hint("barrel")
                else
                    yieldHidden = false
                    ---o[ Syncing Prompt With Current Stage ]o---
                    UiPromptSetActiveGroupThisFrame(PromptGroups, GetGroupLabel(stage))

                    ---o[ Which prompts to show ]o---
                    local nowMs = GetGameTimer()
                    if shownStage == nil or stage ~= keyStage or barrelUID ~= keyUid
                        or (nowMs - keyCheckedAt) >= KEY_CHECK_MS then
                        keyCheckedAt, keyStage, keyUid = nowMs, stage, barrelUID

                        local cutState = barrelCut[barrelUID]
                        local access = barrelAccess[barrelUID]
                        local info = barrelProps[barrelUID]
                        local visibilityKey = string.format("%s|%s|%s|%s|%s|%d|%s|%s|%s|%s", stage,
                            tostring(barrelNeedsScrub), tostring(barrelNeedsRepair), barrelUID,
                            RoleAt(barrelUID), CrewCount(barrelUID), tostring(access ~= nil),
                            tostring(cutState and cutState.keeping), tostring(access and access.law),
                            tostring(info and info.dressing and info.dressing.lit))
                            .. "|" .. tostring(barrelIncident[barrelUID] and barrelIncident[barrelUID].key)
                            .. "|" .. tostring(info and info.dressing and info.dressing.tarp)
                            .. "|" .. tostring(barrelTended[barrelUID])

                        if visibilityKey ~= shownStage then
                            shownStage = visibilityKey
                            ApplyStageVisibility(stage, barrelUID)
                        end
                    end

                    ---o[ Open the journal - offered by every stage ]o---
                    if HoldJustCompleted(OpenBarrelUIPrompt) then
                        Barrels.OpenUI()
                    end

                    ---o[ The crew - offered by every stage ]o---
                    if crewLeaveShown and HoldJustCompleted(CrewLeavePrompt) then
                        DoBarrel("leave", barrelUID, stage)
                    end

                    ---o[ Trouble at the still ]o---
                    if incidentShown and IncidentPrompt and HoldJustCompleted(IncidentPrompt) then
                        DoBarrel("incident", barrelUID, stage)
                    end

                    ---o[ The law's raid, and the cook's answer to it ]o---
                    if seizeShown and SeizePrompt and HoldJustCompleted(SeizePrompt) then
                        DoBarrel("seize", barrelUID, stage)
                    end

                    if pourShown and HoldJustCompleted(PourPrompt) then
                        DoBarrel("pour", barrelUID, stage)
                    end

                    if pickupShown and PickupPrompt and HoldJustCompleted(PickupPrompt) then
                        DoBarrel("pickup", barrelUID, stage)
                    end

                    if tarpShown and TarpPrompt and HoldJustCompleted(TarpPrompt) then
                        DoBarrel("tarp", barrelUID, stage)
                    end

                    ---o[ Choosing the fuel ]o---
                    if fuelChoiceShown and FuelSelectPrompt then
                        local keys, step = Config.InteractKeys, 0
                        if ControlJustPressed(keys.FuelSelectLeftKey) then step = -1 end
                        if ControlJustPressed(keys.FuelSelectRightKey) then step = 1 end

                        if step ~= 0 then
                            fuelIndex = ((fuelIndex - 1 + step) % #fuelKinds) + 1
                            fuelSelectText = SetPromptLabel(FuelSelectPrompt, fuelSelectText, FuelSelectLabel())
                            PlaySoundFrontend("SELECT", "RDRO_Character_Creator_Sounds", true, 0)
                        end
                    end

                    ---o[ A stranger's chance: steal a bottle, or spike a wash ]o---
                    if stealShown and StealPrompt and HoldJustCompleted(StealPrompt) then
                        DoBarrel("steal", barrelUID, stage)
                    end

                    ---o[ Stage "COMPLETED" ]o---
                    if stage == Shared.BarrelStage.COMPLETED then
                        if HoldJustCompleted(AddWoodPrompt) then
                            DoBarrel("wood", barrelUID, stage)
                        end

                        ---o[ Stages "IDLE" / "FERMENTING" / "MID_CLIMB" ]o---
                    elseif stage == Shared.BarrelStage.IDLE or stage == Shared.BarrelStage.FERMENTING
                        or stage == Shared.BarrelStage.MID_CLIMB then
                        if HoldJustCompleted(AddWoodPrompt) then
                            DoBarrel("wood", barrelUID, stage)
                        end

                        ---o[ Tend the fermenting wash ]o---
                        if stage == Shared.BarrelStage.FERMENTING and AddIngredientsPrompt
                            and StandardJustCompleted(AddIngredientsPrompt) then
                            DoBarrel("ingredients", barrelUID, stage)
                        end

                        ---o[ Cold-barrel maintenance ]o---
                        if stage == Shared.BarrelStage.IDLE and Config.BarrelCondition.Enabled then
                            if barrelNeedsScrub and HoldJustCompleted(ScrubPrompt) then
                                DoBarrel("scrub", barrelUID, stage)
                            end

                            if barrelNeedsRepair and HoldJustCompleted(RepairPrompt) then
                                DoBarrel("repair", barrelUID, stage)
                            end
                        end

                        ---o[ Stage "FREEZE" ]o---
                    elseif stage == Shared.BarrelStage.FREEZE then
                        if AddIngredientsPrompt and StandardJustCompleted(AddIngredientsPrompt) then
                            DoBarrel("ingredients", barrelUID, stage)
                        end

                        ---o[ Stage "BREWING": switch the jar while the spirit drips ]o---
                    elseif stage == Shared.BarrelStage.BREWING then
                        if Config.Cuts.Enabled and HoldJustCompleted(AddWoodPrompt) then
                            DoBarrel("wood", barrelUID, stage)
                        end

                        if Config.Condenser.Enabled and HoldJustCompleted(AddWaterPrompt) then
                            DoBarrel("water", barrelUID, stage)
                        end

                        ---o[ Stage "MIXING" offers nothing but the journal ]o---
                    elseif stage ~= Shared.BarrelStage.MIXING then
                        ---o[ Stages "HEAT_PAUSE" / "FINAL_PUSH" ]o---
                        if HoldJustCompleted(AddWoodPrompt) then
                            DoBarrel("wood", barrelUID, stage)
                        end

                        if HoldJustCompleted(AddWaterPrompt) then
                            DoBarrel("water", barrelUID, stage)
                        end

                        if Config.Pressure.Enabled and HoldJustCompleted(VentPrompt) then
                            DoBarrel("vent", barrelUID, stage)
                        end
                    end
                end
            end
        else
            ---o[ Cleanup Prompts AND Sound when out of Zone ]o---
            if isBubblingPlaying then
                isBubblingPlaying = false
                SendNUIMessage({ action = "stopSound" })
                Shared.Debug("^1[Audio]^7 Stopped bubbling - Player left zone.")
            end

            HideBarrelGauge()

            if not promptsHidden then
                promptsHidden = true
                shownStage = nil
                HideAllPrompts()
                ResetPromptLatches()
            end
        end

        Wait(sleep)
    end
end)

---oo[ Ask for every barrel ourselves once our scripts are up ]oo---
CreateThread(function()
    Wait(3000)
    TriggerServerEvent('gsc_kassippu:server:requestBarrels')
end)

---oo[ Sync All Barrels ]oo---
RegisterNetEvent('gsc_kassippu:client:syncAllBarrels')
AddEventHandler('gsc_kassippu:client:syncAllBarrels', function(serverBarrels, serverStages)
    for uid in pairs(barrelProps) do
        if not serverBarrels[uid] then ForgetBarrel(uid) end
    end

    for uid, coords in pairs(serverBarrels) do
        RegisterBarrel(uid, coords, coords.h)
        BarrelStage[uid] = serverStages[uid] or Shared.BarrelStage.IDLE
    end
end)

---oo[ Barrel UI Section ]oo---

---o[ The Character Reads The Book ]o---
local journalAnim = false
local journalAt = nil

local function StartJournalAnim()
    local scenario = Config.AnimConf.JournalScenario
    local ped = PlayerPedId()
    if not scenario or journalAnim or IsPedInAnyVehicle(ped, false) or IsPedOnMount(ped) then return end

    if pcall(TaskStartScenarioInPlace, ped, GetHashKey(scenario), -1, true, false, false, false) then
        journalAnim = true
    end
end

local function StopJournalAnim()
    if not journalAnim then return end
    journalAnim = false
    CreateThread(function() EndScenario(PlayerPedId(), Config.AnimConf.JournalScenario) end)
end

---o[ Barrel UI ]o---
function Barrels.OpenUI()
    if not currentInteractingBarrel or isUIOpen then return end
    TriggerServerEvent('gsc_kassippu:server:openBook', currentInteractingBarrel)
end

---o[ The receipt: what goes in, item by item ]o---
local function BuildReceipt(recipe)
    local txt = Config.Text.Receipt
    local lines = {}

    local function Add(icons, name, note, amount)
        lines[#lines + 1] = { icons = icons, name = name, note = note, amount = amount }
    end

    local function CountsAs(ing)
        if (tonumber(ing.sugar) or 0) > 0 then return string.format(txt.NeedSugar, ing.sugar) end
        if (tonumber(ing.flavour) or 0) > 0 then return txt.NeedFruit end
        return nil
    end

    local function Icons(list)
        local icons = {}
        for i, ing in ipairs(list) do icons[i] = ing.item end
        return icons
    end

    ---o[ The batch ingredient, and what every batch needs ]o---
    local sugars, fruits, others = {}, {}, {}
    local requiredSugar = false

    for _, ing in ipairs(recipe.ingredients or {}) do
        if type(ing) == 'table' and ing.item then
            local amount = tonumber(ing.amount) or 0
            local label = ing.label or ing.item

            if ing.batch then
                Add({ ing.item }, label, ing.fullMl and string.format(txt.FullPot, ing.fullMl) or nil,
                    string.format(txt.PerBatch, 1))
            elseif amount > 0 then
                Add({ ing.item }, label, CountsAs(ing), string.format(txt.PerBatch, amount))
                if (tonumber(ing.sugar) or 0) > 0 then requiredSugar = true end
            elseif (tonumber(ing.sugar) or 0) > 0 then
                sugars[#sugars + 1] = ing
            elseif (tonumber(ing.flavour) or 0) > 0 then
                fruits[#fruits + 1] = ing
            else
                others[#others + 1] = ing
            end
        end
    end

    local coconutMl = tonumber(recipe.coconutMl) or 0
    if coconutMl > 0 then
        Add({ Config.Items.FilledPot }, txt.CoconutWater, txt.InSatchel, string.format(txt.MlPerBatch, coconutMl))
    end

    ---o[ A second run: bottles of the first run's spirit ]o---
    local spiritPer = tonumber(recipe.spiritPerBatch) or 0
    if spiritPer > 0 then
        local base = Config.Recipes[recipe.spiritOf or ""]
        local reward = base and base.rewards and (base.rewards.GOOD or base.rewards.PERFECT)
        local grade = Config.Product.Qualities[recipe.minGrade or ""]

        Add({ reward and reward.item }, string.format(txt.Spirit, base and base.label or recipe.spiritOf or "?"),
            grade and string.format(txt.SpiritNote, grade.label) or nil, string.format(txt.PerBatch, spiritPer))
    end

    ---o[ Sugar ]o---
    if #sugars > 0 or requiredSugar then
        table.sort(sugars, function(a, b) return (tonumber(a.sugar) or 0) > (tonumber(b.sugar) or 0) end)

        local worth = {}
        for i, ing in ipairs(sugars) do
            worth[i] = string.format(txt.SugarWorth, ing.label or ing.item, tonumber(ing.sugar) or 0)
        end

        local own = coconutMl > 0 and (tonumber(recipe.coconutSugar) or 0) or 0
        for _, ing in ipairs(recipe.ingredients or {}) do -- the batch item's own sugar (a pot of sap)
            if type(ing) == 'table' and ing.batch then own = own + (tonumber(ing.sugar) or 0) end
        end
        local tiers = {}
        local strengths = recipe.strengths or {}
        for i = #strengths, 1, -1 do -- weakest first
            local need = (strengths[i].sugar or 0) - own
            if need > 0 then
                tiers[#tiers + 1] = string.format(own > 0 and txt.SugarExtra or txt.SugarFor, need, strengths[i].label)
            end
        end

        if #tiers > 0 then
            Add(Icons(sugars), txt.Sugar, #worth > 0 and table.concat(worth, " · ") or nil, table.concat(tiers, " · "))
        end
    end

    if #fruits > 0 then
        Add(Icons(fruits), txt.Fruit, txt.FruitNote, string.format(txt.UpToPerBatch, Config.Mash.FruitBest or 2))
    end

    for _, ing in ipairs(others) do
        Add({ ing.item }, ing.label or ing.item, nil, txt.Optional)
    end

    return lines
end

RegisterNetEvent('gsc_kassippu:client:openBook')
AddEventHandler('gsc_kassippu:client:openBook', function(uid, known)
    if isUIOpen or isPlacing or isBusy or not inZone or uid ~= currentInteractingBarrel then return end

    local recipes, order = {}, {}
    for _, key in ipairs(type(known) == 'table' and known or {}) do
        local recipe = Config.Recipes[key]
        if recipe then
            local page = {}
            for field, value in pairs(recipe) do page[field] = value end
            page.receipt = BuildReceipt(recipe)

            recipes[key] = page
            order[#order + 1] = key
        end
    end

    isUIOpen = true
    journalAt = currentInteractingBarrel
    SetNuiFocus(true, true)
    StartJournalAnim()

    local stage = BarrelStage[currentInteractingBarrel] or Shared.BarrelStage.IDLE

    SendNUIMessage({
        action = "openMyUI",
        recipies = recipes,
        recipeOrder = order,
        itemImages = (Config.RecipeBook or {}).ItemImages,
        stage = stage,
        stages = Config.Text.Stages,
        barrelId = currentInteractingBarrel,
        defaultRecipe = Config.DefaultRecipe,
        tarp = TarpBookState(currentInteractingBarrel),
        fittings = FittingsBookState(currentInteractingBarrel),
    })

    ---o[ Specific Barrel's Data Sync ]o---
    TriggerServerEvent('gsc_kassippu:server:requestSync', currentInteractingBarrel)

    ---o[ The crew slip ]o---
    if CrewOn() and RoleAt(uid) == "owner" then
        CreateThread(function()
            while isUIOpen and currentInteractingBarrel == uid do
                TriggerServerEvent('gsc_kassippu:server:crewRoster', uid)
                Wait(3000)
            end
        end)
    end
end)

---o[ A recipe card used from the satchel ]o---
RegisterNetEvent('gsc_kassippu:client:readRecipeCard')
AddEventHandler('gsc_kassippu:client:readRecipeCard', function(recipeKey)
    local recipe = Config.Recipes[recipeKey]
    if not recipe or isUIOpen or isPlacing or isBusy then return end

    local page = {}
    for field, value in pairs(recipe) do page[field] = value end
    page.receipt = BuildReceipt(recipe)

    isUIOpen = true
    journalAt = nil -- a recipe card: not tied to a still
    SetNuiFocus(true, true)
    StartJournalAnim()

    SendNUIMessage({
        action = "openMyUI",
        readOnly = true,
        recipies = { [recipeKey] = page },
        recipeOrder = { recipeKey },
        itemImages = (Config.RecipeBook or {}).ItemImages,
        stages = Config.Text.Stages,
        defaultRecipe = recipeKey,
    })
end)

---o[ Barrel UI Stages Update Event ]o---
RegisterNetEvent('gsc_kassippu:client:updateStage')
AddEventHandler('gsc_kassippu:client:updateStage', function(uid, stage)
    ---o[ Update the stage tracking from key ]o---
    BarrelStage[uid] = stage

    Shared.Debug("^2[Sync]^7 Barrel UID: " .. uid .. " moved to stage: " .. stage)

    ---o[ Check the UI is Open And Current Interacting Barrel And UID Is Same Sent Stage ]o---
    if isUIOpen and currentInteractingBarrel == uid then
        SendNUIMessage({
            action = "updateStatus",
            stage = stage
        })

        if stage == Shared.BarrelStage.MIXING then
            Shared.Debug("^5[NUI-DEBUG]^7 Sent MIXING stage update to NUI for UID: " .. uid)
        end
    end
end)

---o[ Barrel UI Heat Update Event ]o---
RegisterNetEvent('gsc_kassippu:client:updateHeat')
AddEventHandler('gsc_kassippu:client:updateHeat', function(uid, currentHeat, progress, bottles, gauge)
    if currentInteractingBarrel == uid then
        if currentHeat >= 95.0 and currentHeat < 110.0 then
            local shakeIntensity = (currentHeat - 90.0) / 90.0
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', shakeIntensity)
            PlaySoundFrontend("Core_Fill_Up", "Consumption_Sounds", true, 0)
        end

        if gauge and gauge.pressure and gauge.pressure >= (Config.Pressure.WarnAt or 70.0) then
            ShakeGameplayCam('SKY_DIVING_SHAKE', 0.25)
        end

        local stage = BarrelStage[uid] or Shared.BarrelStage.IDLE

        barrelCut[uid] = gauge and gauge.cut or nil

        barrelIncident[uid] = gauge and gauge.incident or nil

        ---o[ Tended already? ]o---
        if gauge then barrelTended[uid] = (gauge.ferment and gauge.ferment.tended) or nil end

        ---o[ The fittings on her ]o---
        if gauge and type(gauge.fitted) == 'table' then
            local set, keys = {}, {}
            for _, key in ipairs(gauge.fitted) do
                set[key] = true
                keys[#keys + 1] = tostring(key)
            end
            local sig = table.concat(keys, ",")
            if barrelFittedSig[uid] ~= sig then
                barrelFitted[uid], barrelFittedSig[uid] = set, sig
                if isUIOpen and journalAt == uid then
                    SendNUIMessage({ action = "fittingsState", fittings = FittingsBookState(uid) })
                end
            end
        end

        if gauge and gauge.condition ~= nil then
            barrelNeedsRepair = gauge.condition < Config.BarrelCondition.Max
                and (gauge.repairsLeft == nil or gauge.repairsLeft > 0) -- nil = no limit (MaxRepairs = 0)
            barrelNeedsScrub = (gauge.residue or 0) > 0
        end

        if isUIOpen then
            SendNUIMessage({
                action = "updateHeatUI",
                heat = math.floor(currentHeat),
                progress = progress,
                bottles = bottles,
                currentStage = stage
            })

            Shared.Debug("^5[Heat Sync]^7 Barrel: " ..
                uid .. " | Heat: " .. math.floor(currentHeat) .. "% | Progress: " .. (progress or 0) .. "%")
        else
            ---o[ The at-the-barrel gauge ]o---
            if gauge and barrelAccess[uid] then gauge.crew = barrelAccess[uid].crew end
            if GSC.PushGame ~= nil and GSC.PushGame.OnHeat(uid, currentHeat, gauge) then
                HideBarrelGauge()
            else
                ShowBarrelGauge(currentHeat, stage, gauge)
            end
        end
    end
end)

---o[ Where This Player Stands With A Barrel ]o---
RegisterNetEvent('gsc_kassippu:client:barrelAccess')
AddEventHandler('gsc_kassippu:client:barrelAccess', function(uid, access)
    if type(access) ~= 'table' then return end
    barrelAccess[uid] = { role = access.role or "none", crew = access.crew or {} }
end)

---o[ The Game Clock, For The Server ]o---
RegisterNetEvent('gsc_kassippu:client:askClock')
AddEventHandler('gsc_kassippu:client:askClock', function()
    local ok, hour = pcall(GetClockHours)
    if ok and hour then TriggerServerEvent('gsc_kassippu:server:clock', hour) end
end)

---o[ The nearest object of each ScenarioProps model around the player ]o---
local function NearestScenarioProps(anim)
    local found, pos = {}, GetEntityCoords(PlayerPedId())
    local radius = anim.ScenarioPropRadius or 1.5
    for _, model in ipairs(anim.ScenarioProps or {}) do
        local prop = GetClosestObjectOfType(pos.x, pos.y, pos.z, radius, GetHashKey(model), false, false, false)
        if DoesEntityExist(prop) then found[model] = prop end
    end
    return found
end

---o[ Remove only what the scenario left behind ]o---
local function RemoveScenarioLeftovers(anim, before)
    for model, prop in pairs(NearestScenarioProps(anim)) do
        if prop ~= before[model] then
            NetworkRequestControlOfEntity(prop)
            local timeout = 0
            while not NetworkHasControlOfEntity(prop) and timeout < 20 do
                Wait(5)
                timeout = timeout + 1
            end
            SetEntityAsMissionEntity(prop, true, true)
            DeleteObject(prop)
            if DoesEntityExist(prop) then Shared.Debug("^3[Cleanup]^7 Could not remove a stray " .. model) end
        end
    end
end

---o[ The Server Confirmed An Action ]o---
local barrelAnimBusy = false
RegisterNetEvent('gsc_kassippu:client:barrelAnim')
AddEventHandler('gsc_kassippu:client:barrelAnim', function(kind)
    if barrelAnimBusy then return end
    local anim = Config.AnimConf

    local play = nil
    if kind == "wood" then
        play = { anim.AddWoodAnimDict, anim.AddWoodAnimName, anim.AddWoodScenario, anim.AddWoodAnimTime, true, anim.AddWoodProp }
    elseif kind == "water" then
        play = { nil, nil, anim.AddWaterScene, anim.AddWaterSceneTime }
    elseif kind == "bottle" then
        play = { anim.BrewProductAnimDict, anim.BrewProductAnimName, nil, anim.BrewProductAnimTime }
    elseif type(kind) == 'string' and anim.Actions then
        local a = anim.Actions[kind] or (kind:sub(1, 6) == "place_" and anim.Actions.place) or nil
        if a then play = { a.dict, a.anim, a.scenario, a.time, a.flag ~= nil, a.prop } end
    end
    if not play or not (play[1] or play[3]) then return end

    barrelAnimBusy = true
    CreateThread(function()
        if play[3] then
            local before = NearestScenarioProps(anim)
            PlayAdvancedAnim(nil, play[3], play[4] or 3000, false, play[6])

            ---o[ The scenario's own prop can stay stuck in the hand once it is stopped ]o---
            Wait(anim.ScenarioPropDelay or 800)
            RemoveScenarioLeftovers(anim, before)
        else
            PlayAdvancedAnim(play[1], play[2], play[4] or 3000, play[5] == true, play[6])
        end
        barrelAnimBusy = false
    end)
end)

---o[ For GSC.Stations ]o---
local WATCH_START_MS = 2000
local WATCH_END_SLACK = 600

function Barrels.PlayWatched(kind, ms, maxMove, onEnd)
    local anim = Config.AnimConf
    local a = anim.Actions and anim.Actions[kind]
    local scenario = a and a.scenario or nil

    if barrelAnimBusy then return onEnd(false) end
    barrelAnimBusy = true

    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local hash = scenario and GetHashKey(scenario) or nil
    local before = scenario and NearestScenarioProps(anim) or nil
    if hash then TaskStartScenarioInPlace(ped, hash, ms, true, false, false, false) end

    local began, ok = false, true
    local from = GetGameTimer()
    local ends = from + ms
    while GetGameTimer() < ends do
        Wait(100)
        ped = PlayerPedId()
        if IsEntityDead(ped) or IsPedRagdoll(ped) or #(GetEntityCoords(ped) - start) > maxMove then
            ok = false
            break
        end
        if hash then
            if IsPedUsingScenarioHash(ped, hash) then
                began = true
            elseif began then
                ok = ends - GetGameTimer() <= WATCH_END_SLACK
                break
            elseif GetGameTimer() - from > WATCH_START_MS then
                ok = false
                Shared.Debug("^3[Anim]^7 " .. scenario .. " never started")
                break
            end
        end
    end

    onEnd(ok)

    if hash then
        EndScenario(ped, scenario)
        Wait(anim.ScenarioPropDelay or 800)
        RemoveScenarioLeftovers(anim, before)
    end
    barrelAnimBusy = false
end

---o[ What A Barrel's Props Should Show ]o---
RegisterNetEvent('gsc_kassippu:client:barrelDressing')
AddEventHandler('gsc_kassippu:client:barrelDressing', function(uid, dressing)
    local info = barrelProps[uid]
    if not info or type(dressing) ~= 'table' then return end

    info.dressing = dressing
    info.dressingDirty = true
    if info.fire and DoesEntityExist(info.fire) then SetEntityVisible(info.fire, dressing.lit == true, false) end

    if isUIOpen and uid == currentInteractingBarrel then
        SendNUIMessage({ action = "tarpState", tarp = TarpBookState(uid) })
    end
end)

---o[ The Sky Over The Barrel ]o---
local rainHashes = nil

local function NormalHash(h)
    return h and (h & 0xFFFFFFFF) or nil
end

local function IsRaining()
    if not rainHashes then
        rainHashes = {}
        for _, name in ipairs(Config.Fuel.Rain.Weathers or {}) do
            rainHashes[NormalHash(GetHashKey(name))] = true
        end
    end

    local ok, current = pcall(Citizen.InvokeNative, 0x4BEB42AEBCA732E9, Citizen.ResultAsInteger())
    if not ok or not current then return false end
    return rainHashes[NormalHash(current)] == true
end

local function IsCovered(pos)
    local okInt, interior = pcall(GetInteriorFromEntity, PlayerPedId())
    if okInt and interior and interior ~= 0 then return true end

    local ok, handle = pcall(StartShapeTestRay, pos.x, pos.y, pos.z + 1.5, pos.x, pos.y, pos.z + 25.0,
        1 | 16 | 256, PlayerPedId(), 7)
    if not ok or not handle then return false end

    for _ = 1, 20 do
        local okResult, status, hit = pcall(GetShapeTestResult, handle)
        if not okResult then return false end
        if status ~= 1 then return hit == true or hit == 1 end
        Wait(0)
    end
    return false
end

CreateThread(function()
    local lastUid, lastRain, lastCovered, lastSent = nil, nil, nil, 0

    while true do
        local rain = Config.Fuel.Rain or {}
        Wait(math.max(1, rain.CheckSeconds or 5) * 1000)

        local uid = currentInteractingBarrel
        local info = uid and barrelProps[uid]

        if rain.Enabled and inZone and info then
            local raining = IsRaining()
            local covered = IsCovered(info.pos)
            local now = GetGameTimer()

            local refresh = (now - lastSent) >= ((rain.ReportSeconds or 20) * 500)
            if uid ~= lastUid or raining ~= lastRain or covered ~= lastCovered or refresh then
                lastUid, lastRain, lastCovered, lastSent = uid, raining, covered, now
                TriggerServerEvent('gsc_kassippu:server:barrelWeather', uid, raining, covered)
            end
        end
    end
end)

---o[ Dealing With Trouble ]o---
RegisterNetEvent('gsc_kassippu:client:incidentGame')
AddEventHandler('gsc_kassippu:client:incidentGame', function(uid, key, game, title)
    if isBusy then return end
    isBusy = true

    CreateThread(function()
        local ped = PlayerPedId()
        local scenario = Config.AnimConf.IncidentScenario

        if scenario then
            TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1, true, false, false, false)
        end

        local passed = GSC.Minigame.Play(game, title)

        TriggerServerEvent('gsc_kassippu:server:incidentResult', uid, key, passed == true)
        if scenario then EndScenario(ped, scenario) end
        isBusy = false
    end)
end)

---o[ A pot game with its words from text.lua and this batch's own ingredients on the tray ]o---
local function PotGame(minigame, recipeKey)
    local game = {}
    for k, v in pairs(minigame or {}) do game[k] = v end
    if game.type ~= "spoon" and game.type ~= "pot" then return game end

    game.ingredients = Config.Text.TendWashIngredients
    game.call = Config.Text.TendWashReverse
    game.labels = Config.Text.TendWashLabels
    game.calls = {
        add = Config.Text.TendWashCall,
        fast = Config.Text.TendWashTooFast,
        wrongWay = Config.Text.TendWashWrongWay,
        spoiled = Config.Text.TendWashSpoiled,
        flip = Config.Text.TendWashReverse,
        lumps = Config.Text.TendWashLumps,
        smooth = Config.Text.TendWashSmooth,
    }

    local recipe = Config.Recipes[recipeKey or ""]
    local imageUrl = (Config.RecipeBook or {}).ItemImages
    local tints = (Config.Fermentation.Tend or {}).Tints or {}
    local tray = {}
    for _, ing in ipairs(recipe and recipe.ingredients or {}) do
        if type(ing) == 'table' and ing.item and ing.label then
            tray[#tray + 1] = {
                label = ing.label,
                item = ing.item,
                tint = tints[ing.item],
                img = imageUrl and string.format(imageUrl, ing.item) or nil,
            }
        end
    end
    if #tray < 4 then
        tray = {}
        for _, label in ipairs(Config.Text.TendWashIngredients or {}) do tray[#tray + 1] = { label = label } end
    end
    game.tray = tray
    return game
end

---o[ Stirring The Mash ]o---
RegisterNetEvent('gsc_kassippu:client:stirMash')
AddEventHandler('gsc_kassippu:client:stirMash', function(uid, recipeKey)
    if isBusy then return end
    isBusy = true

    CreateThread(function()
        local ped = PlayerPedId()
        local scenario = Config.AnimConf.MixStirScenario

        if scenario then
            TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1, true, false, false, false)
        end

        local passed = GSC.Minigame.Play(PotGame(Config.Mixing.Stir.Minigame, recipeKey), Config.Text.StirTitle)

        TriggerServerEvent('gsc_kassippu:server:stirResult', uid, passed == true)
        if scenario then EndScenario(ped, scenario) end
        isBusy = false
    end)
end)

---o[ Tending The Fermenting Wash: the pot minigame ]o---
RegisterNetEvent('gsc_kassippu:client:tendWash')
AddEventHandler('gsc_kassippu:client:tendWash', function(uid, recipeKey)
    local conf = Config.Fermentation.Tend
    if isBusy or not conf then return end
    isBusy = true

    CreateThread(function()
        local ped = PlayerPedId()
        local scenario = Config.AnimConf.MixStirScenario

        if scenario then
            TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1, true, false, false, false)
        end

        local passed = GSC.Minigame.Play(PotGame(conf.Minigame, recipeKey), Config.Text.TendWashTitle)

        TriggerServerEvent('gsc_kassippu:server:tendWashResult', uid, passed == true)
        if scenario then EndScenario(ped, scenario) end
        isBusy = false
    end)
end)

---o[ Bottling ]o---
RegisterNetEvent('gsc_kassippu:client:bottleGame')
AddEventHandler('gsc_kassippu:client:bottleGame', function(uid, rounds, recipeKey)
    local conf = Config.Bottling
    if isBusy or not conf or type(rounds) ~= 'number' or rounds < 1 then return end
    isBusy = true

    CreateThread(function()
        local ped = PlayerPedId()
        local anim = Config.AnimConf

        ---o[ Bent over the jugs while it plays ]o---
        local dict = anim.BrewProductAnimDict
        if dict then
            RequestAnimDict(dict)
            local started = GetGameTimer()
            while not HasAnimDictLoaded(dict) and GetGameTimer() - started < 3000 do Wait(10) end
            if HasAnimDictLoaded(dict) then
                TaskPlayAnim(ped, dict, anim.BrewProductAnimName, 8.0, -8.0, -1, 1, 0, false, false, false)
            else
                dict = nil
            end
        end

        local game = {}
        for k, v in pairs(conf.Minigame or {}) do game[k] = v end
        game.rounds = math.floor(rounds)
        game.time = game.rounds * ((game.bottleTime or 7) + (game.corkTime or 3) + 1.2) + 1
        game.labels = Config.Text.BottlingLabels

        local passed, _, outcomes = GSC.Minigame.Play(game, Config.Text.BottlingTitle)

        if dict then ClearPedTasks(ped) end

        if passed ~= nil and type(outcomes) == 'table' then
            TriggerServerEvent('gsc_kassippu:server:bottleResult', uid, outcomes)
        end
        isBusy = false
    end)
end)

---o[ Stealing A Bottle, Or Spiking A Wash ]o---
RegisterNetEvent('gsc_kassippu:client:tamperBarrel')
AddEventHandler('gsc_kassippu:client:tamperBarrel', function(uid, kind)
    if isBusy then return end
    isBusy = true

    CreateThread(function()
        local conf = Config.BarrelTheft
        local ped = PlayerPedId()
        local spike = kind == "spike"

        if conf.Scenario then
            TaskStartScenarioInPlace(ped, GetHashKey(conf.Scenario), -1, true, false, false, false)
        end

        local passed = GSC.Minigame.Play(spike and (conf.SpikeMinigame or conf.Minigame) or conf.Minigame,
            spike and Config.Text.SpikeTitle or Config.Text.TheftTitle)

        TriggerServerEvent('gsc_kassippu:server:tamperBarrelResult', uid, passed == true)
        if conf.Scenario then EndScenario(ped, conf.Scenario) end
        isBusy = false
    end)
end)

---o[ Barrel UI Brewing Status Update Event ]o---
RegisterNetEvent('gsc_kassippu:client:updateBrewUI')
AddEventHandler('gsc_kassippu:client:updateBrewUI', function(barrelId, progress, bottles)
    SendNUIMessage({
        action = "updateStatus",
        barrelId = barrelId,
        progress = progress,
        bottles = bottles
    })
end)

---o[ The Recipe Book's Mash Slip ]o---
RegisterNUICallback('previewMix', function(data, cb)
    cb('ok')
    if currentInteractingBarrel and type(data) == 'table' and data.recipeId then
        TriggerServerEvent('gsc_kassippu:server:previewMix', currentInteractingBarrel, data.recipeId)
    end
end)

RegisterNetEvent('gsc_kassippu:client:mixPreview')
AddEventHandler('gsc_kassippu:client:mixPreview', function(uid, recipeKey, preview)
    if not isUIOpen or uid ~= currentInteractingBarrel then return end
    SendNUIMessage({ action = "mixPreview", recipeId = recipeKey, preview = preview })
end)

---o[ The Recipe Book's Crew Slip ]o---
RegisterNetEvent('gsc_kassippu:client:crewRoster')
AddEventHandler('gsc_kassippu:client:crewRoster', function(uid, roster)
    if not isUIOpen or uid ~= currentInteractingBarrel then return end
    SendNUIMessage({ action = "crewRoster", roster = roster, text = Config.Text.CrewSlip })
end)

---o[ The book's tarp line: rig one, or take it down ]o---
RegisterNUICallback('toggleTarp', function(data, cb)
    cb('ok')
    local uid = currentInteractingBarrel
    if uid and CanTarp(uid) then
        TriggerServerEvent('gsc_kassippu:server:toggleTarp', uid)
    end
end)

---o[ The Fittings slip ]o---
RegisterNUICallback('fitUpgrade', function(data, cb)
    cb('ok')
    local uid = currentInteractingBarrel
    if not uid or type(data) ~= 'table' or type(data.key) ~= 'string' then return end
    if not FittingsBookState(uid) then return end
    TriggerServerEvent('gsc_kassippu:server:fitUpgrade', uid, data.key)
end)

RegisterNUICallback('crewInvite', function(data, cb)
    cb('ok')
    local uid = currentInteractingBarrel
    if not uid or type(data) ~= 'table' or not tonumber(data.target) then return end

    TriggerServerEvent('gsc_kassippu:server:crewInvite', uid, tonumber(data.target))
    SetTimeout(500, function()
        if isUIOpen and currentInteractingBarrel == uid then
            TriggerServerEvent('gsc_kassippu:server:crewRoster', uid)
        end
    end)
end)

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    isUIOpen = false
    StopJournalAnim()
    cb('ok')
end)

---o[ For GSC.UiGuard ]o---
function Barrels.IsJournalOpen()
    return isUIOpen, journalAt
end

---o[ For GSC.UiGuard: put the book away (the page too) ]o---
function Barrels.CloseJournal()
    if not isUIOpen then return end
    isUIOpen = false
    journalAt = nil
    StopJournalAnim()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeUI" })
end

local function StartBarrelPlacement()
    if isPlacing then return end

    local playerPed = PlayerPedId()
    local modelHash = LoadPropModel(Config.Models.KasiyaBarrelKitModel)
    if not modelHash then return end

    isPlacing = true
    ghostEntity = CreateObject(modelHash, GetEntityCoords(playerPed), false, false, false)
    SetEntityAlpha(ghostEntity, 150, false)
    SetEntityCollision(ghostEntity, false, false)
    FreezeEntityPosition(ghostEntity, true)

    GSC.Notify.Objective(Config.Text.KasiyaBarrelPlacementHint, 10000)

    CreateThread(function()
        local rotZ = 0.0

        while isPlacing do
            Wait(0)

            if IsControlPressed(1, Config.InteractKeys.KasiyaBarrelRotateLeftKey) then rotZ = rotZ + 2.0 end
            if IsControlPressed(1, Config.InteractKeys.KasiyaBarrelRotateRightKey) then rotZ = rotZ - 2.0 end

            local playerPos = GetEntityCoords(playerPed)
            local forwardVec = GetEntityForwardVector(playerPed)
            local targetPos = playerPos + (forwardVec * 2.0)

            SetEntityCoords(ghostEntity, targetPos.x, targetPos.y, targetPos.z, false, false, false, false)
            PlaceObjectOnGroundProperly(ghostEntity)
            SetEntityRotation(ghostEntity, 0.0, 0.0, rotZ, 2, true)

            local currentGhostCoords = GetEntityCoords(ghostEntity)

            local _, waterHeight = GetWaterHeight(currentGhostCoords.x, currentGhostCoords.y, currentGhostCoords.z)
            local isSubmerged = IsEntityInWater(ghostEntity)
            local isInWater = (waterHeight > (currentGhostCoords.z - 0.5)) or isSubmerged

            if isInWater then
                SetEntityAlpha(ghostEntity, 50, false)
            else
                SetEntityAlpha(ghostEntity, 200, false)
            end

            if IsControlJustPressed(0, Config.InteractKeys.KasiyaBarrelPlacmenteKey) then
                if isInWater then
                    GSC.Notify.Objective("This ground is too wet! Find dry land.", 3000)
                else
                    local finalCoords = GetEntityCoords(ghostEntity)
                    local finalHeading = GetEntityHeading(ghostEntity)
                    local uid = Shared.GenerateBarrelUID(finalCoords)

                    DeleteEntity(ghostEntity)
                    ghostEntity, isPlacing = nil, false

                    TriggerServerEvent('gsc_kassippu:server:saveBarrel', uid,
                        { x = finalCoords.x, y = finalCoords.y, z = finalCoords.z }, finalHeading)
                    break
                end
            end

            if IsControlJustPressed(0, Config.InteractKeys.KasiyaBarrelPlacementCanselKey) then
                DeleteEntity(ghostEntity)
                ghostEntity, isPlacing = nil, false
                GSC.Notify.Objective(Config.Text.KasiyaBarrelPlacementCansel, 3000)
                break
            end
        end
    end)
end

---oo[ Start To Barrel Placement Calling To Function ]oo---
RegisterNetEvent('gsc_kassippu:client:startPlacement')
AddEventHandler('gsc_kassippu:client:startPlacement', function() StartBarrelPlacement() end)

---oo[ Sync All New Barrels To Players to Interact with PolyZones ]oo---
RegisterNetEvent('gsc_kassippu:client:syncNewBarrel')
AddEventHandler('gsc_kassippu:client:syncNewBarrel', function(uid, coords, heading)
    RegisterBarrel(uid, coords, heading)
    BarrelStage[uid] = Shared.BarrelStage.IDLE
end)

---oo[ Barrel Mixing NUI Update Event ]oo---
RegisterNUICallback('startMixingNUI', function(data, cb)
    if currentInteractingBarrel then
        Shared.Debug("^5[NUI]^7 Requesting Mix for UID: " ..
            currentInteractingBarrel .. " | Recipe: " .. tostring(data.recipeId))

        local info = barrelProps[currentInteractingBarrel]
        local climate = info and GSC.Crates.ReadClimate(PlayerPedId(), info.pos) or nil

        TriggerServerEvent('gsc_kassippu:server:startMixing', currentInteractingBarrel, data.recipeId, climate)

        isUIOpen = false
        StopJournalAnim()
        SetNuiFocus(false, false)

        SendNUIMessage({ action = "closeUI" })
    else
        Shared.Debug("^1[NUI Error]^7 startMixingNUI called but currentInteractingBarrel is nil!")
    end

    cb('ok')
end)

---oo[ Barrel Exploide Event ]oo---
RegisterNetEvent('gsc_kassippu:client:barrelBoom')
AddEventHandler('gsc_kassippu:client:barrelBoom', function(uid, coords)
    ---o[ Create the Explosion Effect ]o---
    AddExplosion(coords.x, coords.y, coords.z, 25, 1.5, true, false, 1.2)

    ---o[ Player Damage Logic ]o---
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    if #(coords - playerCoords) < 4.0 then
        ApplyDamageToPed(playerPed, 50, false)
    end

    ---o[ What is left of her ]o---
    local wreck = Config.StillDressing and Config.StillDressing.Enabled and Config.StillDressing.Wreck
    local streamIn = Config.KasiyaBarrelKitConf.StreamDistance or 80.0
    if wreck and wreck.model and #(coords - playerCoords) <= streamIn then
        CreateThread(function()
            local hash = LoadPropModel(wreck.model)
            if not hash then return end

            local debris = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
            SnapToGround(debris)
            FreezeEntityPosition(debris, true)
            wreckage[#wreckage + 1] = debris

            Wait(math.max(1, wreck.seconds or 600) * 1000)
            DeleteLocalProp(debris)
            for i, entity in ipairs(wreckage) do
                if entity == debris then table.remove(wreckage, i) break end
            end
        end)
    end

    ---o[ Close the journal if it was this barrel's ]o---
    if currentInteractingBarrel == uid and isUIOpen then
        isUIOpen = false
        StopJournalAnim()
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closeUI" })
    end

    ForgetBarrel(uid)
    SweepLegacyProps(coords)

    Shared.Debug("^2[Cleanup]^7 UID: " .. uid .. " Full cleanup completed.")
end)

---oo[ Barrel Cleanup Event ]oo---
RegisterNetEvent('gsc_kassippu:client:BarrelCleanup')
AddEventHandler('gsc_kassippu:client:BarrelCleanup', function(uid, coords)
    Shared.Debug("^3[Cleanup]^7 Starting silent removal for: " .. uid)

    if currentInteractingBarrel == uid and isUIOpen then
        isUIOpen = false
        StopJournalAnim()
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closeUI" })
    end

    ForgetBarrel(uid)
    if coords then SweepLegacyProps(coords) end

    Shared.Debug("^2[Cleanup]^7 Silent removal complete for: " .. uid)
end)

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if ghostEntity and DoesEntityExist(ghostEntity) then
        DeleteObject(ghostEntity)
        if DoesEntityExist(ghostEntity) then DeleteEntity(ghostEntity) end
    end
    ghostEntity = nil
    isPlacing = false

    StopAmbience()
    for _, info in pairs(barrelProps) do DespawnBarrelProp(info) end
    for _, debris in ipairs(wreckage) do DeleteLocalProp(debris) end

    if isUIOpen then
        SetNuiFocus(false, false)
        isUIOpen = false
        StopJournalAnim()
    end

    HideBarrelGauge()

    ---o[ Hand the prompts back to the game ]o---
    for _, prompt in ipairs({ OpenBarrelUIPrompt, AddWoodPrompt, AddWaterPrompt,
        VentPrompt, ScrubPrompt, RepairPrompt,
        CrewLeavePrompt, PourPrompt, FuelSelectPrompt, AddIngredientsPrompt, StealPrompt, SeizePrompt,
        PickupPrompt, IncidentPrompt, TarpPrompt }) do
        if prompt then
            PromptSetVisible(prompt, false)
            PromptDelete(prompt)
        end
    end
end)

---oo[ Spent Mash: feeding the horse ]oo---
local function NearbyHorse()
    local ped = PlayerPedId()
    if IsPedOnMount(ped) then return GetMount(ped) end

    local ok, horse = pcall(function() return Citizen.InvokeNative(0x4C8B59171957BCF7, ped) end) -- GetLastMount
    if not ok or not horse or horse == 0 or not DoesEntityExist(horse) or IsEntityDead(horse) then return nil end

    local range = (Config.SpentMash or {}).HorseRange or 4.0
    if #(GetEntityCoords(ped) - GetEntityCoords(horse)) > range then return nil end
    return horse
end

RegisterNetEvent('gsc_kassippu:client:feedHorse')
AddEventHandler('gsc_kassippu:client:feedHorse', function()
    if not NearbyHorse() then
        return GSC.Notify.Show(Config.Text.SpentMashNoHorse, 3000)
    end
    TriggerServerEvent('gsc_kassippu:server:fedHorse')
end)

RegisterNetEvent('gsc_kassippu:client:horseFed')
AddEventHandler('gsc_kassippu:client:horseFed', function()
    local horse = NearbyHorse()
    if not horse then return end
    local conf = Config.SpentMash or {}
    local ped = PlayerPedId()

    if not IsPedOnMount(ped) then
        pcall(function() Citizen.InvokeNative(0xCD181A959CFDD7F4, ped, horse, -224471938, 0, 0) end)
    end

    pcall(function()
        for core, add in pairs({ [0] = conf.HorseHealth or 0, [1] = conf.HorseStamina or 0 }) do
            if add > 0 then
                local now = Citizen.InvokeNative(0x36731AC041289BB1, horse, core, Citizen.ResultAsInteger()) or 0
                Citizen.InvokeNative(0xC6258F41D86676E0, horse, core, math.min(100, now + add))
            end
        end
    end)
end)
