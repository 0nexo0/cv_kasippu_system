local Crates = GSC.module('Crates')

local crates = {}
local myCrates = {}
local currentCrate = nil -- uid the player is stood at
local gauge = nil        -- last gauge payload for currentCrate
local selected = nil
local selectedId = nil
local busy = false       -- an animation or minigame is running
local isPlacing = false
local ghostEntity = nil

local PromptGroup = CreateVarString(10, 'LITERAL_STRING', "Aging Crate")
local StorePrompt, TakePrompt, TendPrompt, PickupPrompt, SelectPrompt, LockPrompt
local tendPromptActivity = nil
local lockPromptText = nil

---oo[ Props ]oo---

local function LoadModel(name)
    local hash = GetHashKey(name)
    if HasModelLoaded(hash) then return hash end

    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - started > 5000 then
            Shared.Debug("^1[Crate]^7 Model failed to load: " .. tostring(name))
            return nil
        end
        Wait(0)
    end
    return hash
end

local function DeleteLocal(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end

---o[ Where slot i sits, in the crate's own axes ]o---
local function SlotOffset(i)
    local conf = Config.CrateAging
    local cols = math.max(1, conf.SlotColumns or 4)
    local rows = math.max(1, conf.SlotRows or 3)
    local base = conf.SlotOffset or vector3(0.0, 0.0, 0.0)

    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)

    return vector3(
        base.x + (col - (cols - 1) / 2) * (conf.SlotSpacingX or 0.115),
        base.y + (row - (rows - 1) / 2) * (conf.SlotSpacingY or 0.12),
        base.z
    )
end

---o[ Seat bottle i in its slot ]o---
local function AttachBottle(crate, i)
    local bottle = crate.bottles[i]
    if not bottle or not DoesEntityExist(bottle) then return end

    local off = SlotOffset(i)
    local lift = (crate.lifted == i) and (Config.CrateAging.SelectedLift or 0.0) or 0.0

    AttachEntityToEntity(bottle, crate.entity, 0, off.x, off.y, off.z + lift, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true)
end

---o[ Raise the picked bottle, and set the last one back down ]o---
local function LiftBottle(crate, index)
    if not crate or crate.lifted == index then return end

    local previous = crate.lifted
    crate.lifted = index

    if previous then AttachBottle(crate, previous) end
    if index then AttachBottle(crate, index) end
end

---o[ Stand as many bottles in the crate as it holds ]o---
local function RefreshBottleProps(crate)
    local conf = Config.CrateAging
    crate.bottles = crate.bottles or {}

    local wanted = 0
    if conf.ShowBottleProps and crate.entity and DoesEntityExist(crate.entity) then
        local slots = math.max(1, conf.SlotColumns or 4) * math.max(1, conf.SlotRows or 3)
        wanted = math.min(crate.count or 0, slots)
    end

    for i = #crate.bottles, wanted + 1, -1 do
        DeleteLocal(crate.bottles[i])
        crate.bottles[i] = nil
    end
    if crate.lifted and crate.lifted > wanted then crate.lifted = nil end

    if #crate.bottles >= wanted then return end

    local model = LoadModel(Config.Models.AgingBottleModel)
    if not model then return end

    for i = #crate.bottles + 1, wanted do
        local pos = GetEntityCoords(crate.entity)
        local bottle = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)

        SetEntityCollision(bottle, false, false)
        crate.bottles[i] = bottle
        AttachBottle(crate, i)
    end
end

local function SpawnCrate(crate)
    local model = LoadModel(Config.Models.AgingCrateModel)
    if not model then return end

    local entity = CreateObject(model, crate.pos.x, crate.pos.y, crate.pos.z, false, false, false)
    SetEntityHeading(entity, crate.heading or 0.0)
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)

    crate.entity = entity
    RefreshBottleProps(crate)
end

local function DespawnCrate(crate)
    for i = #(crate.bottles or {}), 1, -1 do
        DeleteLocal(crate.bottles[i])
        crate.bottles[i] = nil
    end

    DeleteLocal(crate.entity)
    crate.entity = nil
    crate.lifted = nil
end

---oo[ Sync From The Server ]oo---

local function ClearSelection()
    local crate = currentCrate and crates[currentCrate]
    if crate then LiftBottle(crate, nil) end
    selected, selectedId = nil, nil
end

local function AddCrate(uid, data)
    local known = crates[uid]
    local pos = vector3(data.x, data.y, data.z)

    ---o[ Already here, same place ]o---
    if known and #(known.pos - pos) < 0.01 then
        known.count = data.count or 0
        if (data.heading or 0.0) ~= known.heading then
            known.heading = data.heading or 0.0
            if known.entity and DoesEntityExist(known.entity) then SetEntityHeading(known.entity, known.heading) end
        end
        RefreshBottleProps(known)
        return
    end

    if known then DespawnCrate(known) end

    crates[uid] = {
        pos = vector3(data.x, data.y, data.z),
        heading = data.heading or 0.0,
        count = data.count or 0,
        bottles = {},
    }
end

local function RemoveCrate(uid)
    local crate = crates[uid]
    if not crate then return end

    DespawnCrate(crate)
    crates[uid] = nil

    if currentCrate == uid then
        currentCrate = nil
        gauge = nil
        selected, selectedId = nil, nil
        TriggerServerEvent('gsc_kassippu:server:watchCrate', nil)
    end
end

---o[ Ask for every crate ourselves once our scripts are up ]o---
CreateThread(function()
    Wait(3500)
    if Config.CrateAging and Config.CrateAging.Enabled then TriggerServerEvent('gsc_kassippu:server:requestCrates') end
end)

RegisterNetEvent('gsc_kassippu:client:syncCrates')
AddEventHandler('gsc_kassippu:client:syncCrates', function(list)
    for uid in pairs(crates) do
        if not list[uid] then RemoveCrate(uid) end
    end

    for uid, data in pairs(list) do
        AddCrate(uid, data)
    end
end)

RegisterNetEvent('gsc_kassippu:client:crateAdded')
AddEventHandler('gsc_kassippu:client:crateAdded', function(uid, data)
    AddCrate(uid, data)
end)

RegisterNetEvent('gsc_kassippu:client:crateRemoved')
AddEventHandler('gsc_kassippu:client:crateRemoved', function(uid)
    RemoveCrate(uid)
end)

RegisterNetEvent('gsc_kassippu:client:crateCount')
AddEventHandler('gsc_kassippu:client:crateCount', function(uid, count)
    local crate = crates[uid]
    if not crate then return end

    crate.count = count
    RefreshBottleProps(crate)
end)

---o[ Keep the pick on the same bottle as the slots shift under it ]o---
local function ReconcileSelection()
    local slots = gauge and gauge.slots or {}
    local count = #slots

    if count == 0 then
        ClearSelection()
        return
    end

    if selectedId then
        for i, slot in ipairs(slots) do
            if slot.id == selectedId then
                selected = i
                return
            end
        end
    end

    selected = math.max(1, math.min(selected or 1, count))
    selectedId = slots[selected].id
end

RegisterNetEvent('gsc_kassippu:client:crateGauge')
AddEventHandler('gsc_kassippu:client:crateGauge', function(uid, payload)
    if uid ~= currentCrate then return end
    gauge = payload
    ReconcileSelection()
end)

---oo[ Owner Map Blips ]oo---

local function DropBlip(entry)
    if entry.blip and DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
    entry.blip = nil
end

---o[ draw one of my crates on the map, coloured by what it needs ]o---
local function DrawBlip(entry)
    DropBlip(entry)

    local conf = Config.CrateAging.Blips
    if not conf or not conf.Enabled then return end

    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, entry.pos.x, entry.pos.y, entry.pos.z)
    if conf.Sprite then SetBlipSprite(blip, GetHashKey(conf.Sprite), true) end
    SetBlipScale(blip, conf.Scale or 0.8)

    local suffix = (Config.Text.CrateBlipStates or {})[entry.state]
    local name = (conf.Name or "Aging Crate") .. (suffix and (" - " .. suffix) or "")

    pcall(function()
        local colour = (conf.Colours or {})[entry.state]
        if colour then Citizen.InvokeNative(0x662D364ABF16DE2F, blip, GetHashKey(colour)) end -- BlipAddModifier
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, "LITERAL_STRING", name)) -- SetBlipName
    end)

    entry.blip = blip
end

local function SetMyCrate(uid, data)
    local entry = myCrates[uid]

    if not data then
        if entry then DropBlip(entry) end
        myCrates[uid] = nil
        return
    end

    entry = entry or {}
    entry.pos = vector3(data.x, data.y, data.z)
    entry.state = data.state or "idle"
    myCrates[uid] = entry
    DrawBlip(entry)
end

RegisterNetEvent('gsc_kassippu:client:myCrates')
AddEventHandler('gsc_kassippu:client:myCrates', function(list)
    for uid, entry in pairs(myCrates) do
        DropBlip(entry)
        myCrates[uid] = nil
    end

    for uid, data in pairs(list or {}) do SetMyCrate(uid, data) end
end)

RegisterNetEvent('gsc_kassippu:client:myCrate')
AddEventHandler('gsc_kassippu:client:myCrate', function(uid, data)
    SetMyCrate(uid, data)
end)

---oo[ Streaming And Proximity ]oo---
CreateThread(function()
    while true do
        local sleep = 1500
        local conf = Config.CrateAging

        if conf.Enabled and next(crates) ~= nil then
            local pCoords = GetEntityCoords(PlayerPedId())
            local streamIn = conf.StreamDistance or 60.0
            local streamOut = streamIn + 10.0
            local radius = conf.InteractRadius or 1.8
            local nearestUid, nearestDist = nil, math.huge

            for uid, crate in pairs(crates) do
                local dist = #(pCoords - crate.pos)

                if dist <= streamIn and not crate.entity then
                    SpawnCrate(crate)
                    ---o[ Counts only go to players near a crate: ask for the current one as it comes into view ]o---
                    if crate.entity then TriggerServerEvent('gsc_kassippu:server:crateCountAsk', uid) end
                elseif dist > streamOut and crate.entity then
                    DespawnCrate(crate)
                end

                if dist <= radius and dist < nearestDist then
                    nearestUid, nearestDist = uid, dist
                end

                if dist < 20.0 then sleep = 250 end
            end

            if nearestUid ~= currentCrate then
                ClearSelection()
                currentCrate = nearestUid
                gauge = nil
                TriggerServerEvent('gsc_kassippu:server:watchCrate', nearestUid)
            end
        elseif currentCrate then
            ClearSelection()
            currentCrate = nil
            gauge = nil
            TriggerServerEvent('gsc_kassippu:server:watchCrate', nil)
        end

        Wait(sleep)
    end
end)

---oo[ Animations ]oo---

---o[ Play one animation spec, optionally with a bottle in hand ]o---
local function PlayCrateAnim(spec, holdBottle)
    if not spec then return end

    local ped = PlayerPedId()
    local time = spec.time or 2000
    local dict = spec.dict

    if spec.scenario then
        TaskStartScenarioInPlace(ped, GetHashKey(spec.scenario), time, true, false, false, false)
    elseif dict then
        RequestAnimDict(dict)
        local started = GetGameTimer()
        while not HasAnimDictLoaded(dict) and GetGameTimer() - started < 3000 do Wait(10) end

        if not HasAnimDictLoaded(dict) then
            Shared.Debug("^1[Crate]^7 Anim dict failed to load: " .. tostring(dict))
            return
        end

        TaskPlayAnim(ped, dict, spec.anim, 8.0, -8.0, time, spec.flag or 31, 0, false, false, false)
    end

    local prop = nil
    if holdBottle then
        local model = LoadModel(Config.Models.AgingBottleModel)
        if model then
            local anim = Config.AnimConf
            local pCoords = GetEntityCoords(ped)
            local off = anim.CrateBottleHandOffset or vector3(0.0, 0.0, 0.0)
            local rot = anim.CrateBottleHandRotation or vector3(0.0, 0.0, 0.0)

            prop = CreateObject(model, pCoords.x, pCoords.y, pCoords.z, false, false, false)
            AttachEntityToEntity(prop, ped, GetEntityBoneIndexByName(ped, anim.CrateBottleHandBone or "PH_R_Hand"),
                off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
        end
    end

    Wait(time)

    DeleteLocal(prop)
    if spec.scenario and GSC.Barrels ~= nil and GSC.Barrels.EndScenario then
        GSC.Barrels.EndScenario(ped, spec.scenario)
    else
        ClearPedTasks(ped)
    end
    if dict then RemoveAnimDict(dict) end
end

---o[ The server confirmed an action - show it ]o---
RegisterNetEvent('gsc_kassippu:client:crateAction')
AddEventHandler('gsc_kassippu:client:crateAction', function(uid, kind, activityKey)
    if busy and kind ~= "activity" then return end

    busy = true
    local anim = Config.AnimConf

    if kind == "bottle" then
        PlayCrateAnim({
            dict = anim.CrateBottleAnimDict,
            anim = anim.CrateBottleAnimName,
            flag = anim.CrateBottleAnimFlag,
            time = anim.CrateBottleAnimTime,
        }, true)
    elseif kind == "activity" then
        local spec = (anim.CrateActivities or {})[activityKey]
        PlayCrateAnim(spec, spec and spec.holdBottle)
    elseif kind == "lock" then
        PlayCrateAnim(anim.CrateLockAnim, false)
    end

    busy = false
end)

---o[ An activity or a hazard, by key ]o---
local function FindActivity(key)
    local conf = Config.CrateAging
    for _, list in ipairs({ conf.Activities or {}, conf.Hazards or {} }) do
        for _, entry in ipairs(list) do
            if entry.key == key then return entry end
        end
    end
    return nil
end

---oo[ Minigames ]oo---
local function PlayMinigame(game, title, missingResult)
    game = game or {}

    if Config.CrateAging.MinigameProvider == "syn_minigame" then
        local ok, result = pcall(function()
            return exports['syn_minigame']:taskBar(game.Duration or 4000, game.Size or 7)
        end)

        if not ok then
            Shared.Debug("^1[Crate]^7 syn_minigame errored: " .. tostring(result))
            return missingResult
        end
        return result == 100
    end

    return GSC.Minigame.Play(game, title) == true
end

---o[ Run the activity the crate is asking for ]o---
local function RunActivity(uid, activityKey)
    local activity = FindActivity(activityKey)
    if not activity then return end

    busy = true

    local passed = PlayMinigame(activity.minigame, activity.label, false) -- a broken minigame is no free pass

    busy = false
    TriggerServerEvent('gsc_kassippu:server:tendCrate', uid, activityKey, passed)
end

---o[ The server has started a crate job for us ]o---
RegisterNetEvent('gsc_kassippu:client:crateRunActivity')
AddEventHandler('gsc_kassippu:client:crateRunActivity', function(uid, activityKey)
    if busy then return end
    RunActivity(uid, activityKey)
end)

---o[ The server has cleared a lockpick attempt - run it ]o---
RegisterNetEvent('gsc_kassippu:client:crateLockpick')
AddEventHandler('gsc_kassippu:client:crateLockpick', function(uid)
    if busy then return end
    busy = true

    local ped = PlayerPedId()
    local scenario = Config.AnimConf.CrateLockpickScenario
    if scenario then TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1, true, false, false, false) end

    local passed = PlayMinigame((Config.CrateAging.Lock or {}).PickMinigame, Config.PromptsTxt.CratePickLockPrompt, false)

    TriggerServerEvent('gsc_kassippu:server:pickCrateLockResult', uid, passed)
    if scenario and GSC.Barrels ~= nil and GSC.Barrels.EndScenario then
        GSC.Barrels.EndScenario(ped, scenario)
    else
        ClearPedTasks(ped)
    end
    busy = false
end)

---oo[ Prompts ]oo---

local function RegisterCratePrompt(key, text)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, key)
    PromptSetText(prompt, VarString(10, "LITERAL_STRING", text))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, false)
    PromptSetHoldMode(prompt, Config.KasiyaBarrelKitConf.KasiyaBarrelPromptsHoldTime)
    PromptSetGroup(prompt, PromptGroup, 0)
    PromptRegisterEnd(prompt)
    return prompt
end

CreateThread(function()
    local keys, txt = Config.InteractKeys, Config.PromptsTxt

    StorePrompt = RegisterCratePrompt(keys.CrateStoreKey, txt.CrateStorePrompt)
    TakePrompt = RegisterCratePrompt(keys.CrateTakeKey, txt.CrateTakePrompt)
    TendPrompt = RegisterCratePrompt(keys.CrateTendKey, "...")
    PickupPrompt = RegisterCratePrompt(keys.CratePickupKey, txt.CratePickupPrompt)
    LockPrompt = RegisterCratePrompt(keys.CrateLockKey, txt.CrateLockPrompt)

    SelectPrompt = PromptRegisterBegin()
    PromptSetControlAction(SelectPrompt, keys.CrateSelectLeftKey)
    PromptSetControlAction(SelectPrompt, keys.CrateSelectRightKey)
    PromptSetText(SelectPrompt, VarString(10, "LITERAL_STRING", txt.CrateSelectPrompt))
    PromptSetEnabled(SelectPrompt, true)
    PromptSetVisible(SelectPrompt, false)
    PromptSetStandardMode(SelectPrompt, true)
    PromptSetGroup(SelectPrompt, PromptGroup, 0)
    PromptRegisterEnd(SelectPrompt)

end)

---o[ Same once-per-press latch the barrel prompts use ]o---
local promptLatched = {}

local function HoldJustCompleted(prompt)
    if not UiPromptHasHoldModeCompleted(prompt) then
        promptLatched[prompt] = nil
        return false
    end

    if promptLatched[prompt] then return false end
    promptLatched[prompt] = true
    return true
end

local function SetCratePromptVisibility(store, take, tend, pickup, select, lock)
    PromptSetVisible(StorePrompt, store)
    PromptSetVisible(TakePrompt, take)
    PromptSetVisible(TendPrompt, tend)
    PromptSetVisible(PickupPrompt, pickup)
    PromptSetVisible(SelectPrompt, select)
    PromptSetVisible(LockPrompt, lock)
end

local groupLabels = {}
local lastLabelCount, lastLabelCapacity, lastLabelLocked, lastLabel = nil, nil, nil, nil -- skips the key string per frame
local function GroupLabel(count, capacity, locked)
    -- caches the text only: a VarString points into a reused buffer and can't outlive its frame
    if count == lastLabelCount and capacity == lastLabelCapacity and locked == lastLabelLocked then
        return VarString(10, 'LITERAL_STRING', lastLabel)
    end

    local key = count .. "/" .. capacity .. (locked and "|L" or "")
    if not groupLabels[key] then
        groupLabels[key] = string.format("%s [%s]%s", Config.PromptsTxt.CratePromptTitle, count .. "/" .. capacity,
            locked and Config.PromptsTxt.CrateLockedTag or "")
    end

    lastLabelCount, lastLabelCapacity, lastLabelLocked = count, capacity, locked
    lastLabel = groupLabels[key]
    return VarString(10, 'LITERAL_STRING', lastLabel)
end

local function ControlPressed(key)
    return IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key)
end

---oo[ The Crate Gauge ]oo---
local gaugeVisible = false
local sentGauge, sentSelected = nil, nil

local function HideCrateGauge()
    if not gaugeVisible then return end
    gaugeVisible = false
    sentGauge, sentSelected = nil, nil
    SendNUIMessage({ action = "hideCrateGauge" })
end

---o[ The scales the card draws its bars and rings against ]o---
local function CrateGaugeLimits()
    local conf = Config.CrateAging
    local ageMax, keepMax = 1.0, 1.0
    local bands = conf.Climate and conf.Climate.Bands or {}
    for _, band in ipairs(bands) do
        ageMax = math.max(ageMax, band.ageRate or 1.0)
        keepMax = math.max(keepMax, band.keepRate or 1.0)
    end

    return {
        every = conf.TendEverySeconds,
        window = conf.TendWindowSeconds,
        careMax = conf.CareMax,
        goodCare = conf.GoodCare,
        poorCare = conf.PoorCare,
        spoilMinutes = conf.SpoilMinutes,
        rhythmMax = 1.0 + (conf.RhythmStep or 0) * (conf.RhythmMaxSteps or 0),
        ageMax = ageMax,
        keepMax = keepMax * ((conf.Climate and conf.Climate.ShelterKeepRate) or 1.0),
    }
end

local function ShowCrateGauge()
    local first = not gaugeVisible
    gaugeVisible = true
    sentGauge, sentSelected = gauge, selected
    SendNUIMessage({
        action = "showCrateGauge",
        gauge = gauge,
        selected = selected,
        tiers = Config.CrateAging.Tiers,
        text = first and Config.Text.CrateGauge or nil,
        limits = first and CrateGaugeLimits() or nil,
    })
end

---o[ Nothing else owns the player right now ]o---
local function CrateBlocked()
    return isPlacing or busy or (GSC.Barrels.IsAtBarrel and GSC.Barrels.IsAtBarrel())
        or (GSC.Crew.IsInvitePending and GSC.Crew.IsInvitePending())
end

---o[ What this crate offers this player right now ]o---
local function CrateOffer(crate)
    local conf = Config.CrateAging
    local P = Config.PromptsTxt
    local o = {}

    o.capacity = conf.Capacity
    o.count = gauge and gauge.count or crate.count or 0
    o.tendDue = gauge and gauge.tendDue and gauge.activity ~= nil
    o.mine = gauge and gauge.mine or false
    o.locked = gauge and gauge.locked or false
    local lockOn = conf.Lock and conf.Lock.Enabled and gauge ~= nil

    local handles = o.mine or not o.locked
    o.canTend = (o.tendDue and handles) and true or false -- a locked crate's jobs are the owner's
    o.canTake = o.count > 0 and handles and (o.mine or not conf.TakeOwnerOnly)
    o.canStore = o.count < o.capacity and handles
    o.canPickup = o.count == 0 and (o.mine or not conf.PickupOwnerOnly)

    if lockOn and o.mine then
        o.lockText = o.locked and P.CrateUnlockPrompt or P.CrateLockPrompt
    elseif lockOn and o.locked then
        o.lockText = P.CratePickLockPrompt
    end

    return o
end

---o[ Do one crate action ]o---
local function DoCrate(action, uid, mine, slotId)
    if action == "store" then
        TriggerServerEvent('gsc_kassippu:server:storeCrateBottle', uid)
    elseif action == "take" then
        TriggerServerEvent('gsc_kassippu:server:takeCrateBottle', uid, slotId)
    elseif action == "pickup" then
        TriggerServerEvent('gsc_kassippu:server:pickupCrate', uid)
    elseif action == "tend" then
        TriggerServerEvent('gsc_kassippu:server:startTendCrate', uid)
    elseif action == "lock" then
        if mine then
            TriggerServerEvent('gsc_kassippu:server:toggleCrateLock', uid)
        else
            TriggerServerEvent('gsc_kassippu:server:pickCrateLock', uid)
        end
    end
end

---o[ For GSC.Radial ]o---
function Crates.RadialActions()
    if not (GSC.Radial ~= nil and GSC.Radial.Owns("crate")) then return nil end -- the crate is on its key prompts
    local crate = currentCrate and crates[currentCrate]
    if not crate then return nil end
    ---o[ Not CrateBlocked ]o---
    if isPlacing or busy or (GSC.Crew.IsInvitePending and GSC.Crew.IsInvitePending()) then return nil end

    local uid = currentCrate
    local o = CrateOffer(crate)
    local P, R = Config.PromptsTxt, Config.Text.Radial or {}
    local list = {}

    local function Add(action, title, icon, slotId)
        list[#list + 1] = {
            id = "gsc_crate_" .. action, title = title, icon = icon,
            run = function() DoCrate(action, uid, o.mine, slotId) end,
        }
    end

    if o.canTend then
        Add("tend", gauge.activityLabel or gauge.activity, gauge.hazard and "triangle-exclamation" or "hand")
    end

    if o.canStore then Add("store", P.CrateStorePrompt, "wine-bottle") end

    ---o[ Take ]o---
    if o.canTake then
        local bottles = {}
        for _, slot in ipairs(gauge and gauge.slots or {}) do
            local slotId = slot.id
            local title = slot.tierLabel and string.format(R.BottleTag or "%s (%s)", slot.name or "?", slot.tierLabel)
                or (slot.name or "?")
            bottles[#bottles + 1] = {
                id = "gsc_crate_take_" .. tostring(slotId), title = title, icon = slot.sour and "ban" or "wine-bottle",
                run = function() DoCrate("take", uid, o.mine, slotId) end,
            }
        end

        if #bottles > 1 then
            list[#list + 1] = { id = "gsc_crate_takeall", title = R.TakeAll or P.CrateTakePrompt, icon = "box-open", items = bottles }
        else
            Add("take", P.CrateTakePrompt, "box-open", bottles[1] and gauge.slots[1].id or nil)
        end
    end

    if o.lockText then Add("lock", o.lockText, o.mine and (o.locked and "lock-open" or "lock") or "key") end
    if o.canPickup then Add("pickup", P.CratePickupPrompt, "box") end

    return { title = R.Crate or "Crate", icon = "box", actions = list }
end

---oo[ Interaction Loop ]oo---
CreateThread(function()
    local shownKey = nil
    local lastGaugeSend = 0
    local offer, offerAt, offerGauge, offerCrate = nil, 0, nil, nil

    while true do
        local sleep = 1000 -- at no crate
        local crate = currentCrate and crates[currentCrate]

        local blocked = crate ~= nil and CrateBlocked()
        if crate then sleep = 500 end

        if crate and not blocked then
            sleep = 0

            ---o[ What the crate offers ]o---
            local nowMs = GetGameTimer()
            local fresh = false
            if not offer or nowMs - offerAt >= 200 or gauge ~= offerGauge or currentCrate ~= offerCrate then
                offer, offerAt, offerGauge, offerCrate = CrateOffer(crate), nowMs, gauge, currentCrate
                fresh = true
            end

            local o = offer
            local capacity, count, mine, locked = o.capacity, o.count, o.mine, o.locked
            local tendDue, canTend, canTake = o.tendDue, o.canTend, o.canTake
            local canStore, canPickup, lockText = o.canStore, o.canPickup, o.lockText

            UiPromptSetActiveGroupThisFrame(PromptGroup, GroupLabel(count, capacity, locked))
            local radialHere = (GSC.Radial ~= nil and GSC.Radial.Owns("crate"))

            ---o[ Prompt set ]o---
            local key = fresh and string.format("%d|%s|%s|%s|%s|%s", count, tostring(canTend), tostring(gauge and gauge.activity),
                tostring(canTake), tostring(canStore), tostring(lockText)) or shownKey
            if key ~= shownKey then
                shownKey = key

                if tendDue and tendPromptActivity ~= gauge.activity then
                    tendPromptActivity = gauge.activity
                    PromptSetText(TendPrompt, VarString(10, "LITERAL_STRING", gauge.activityLabel or gauge.activity))
                end

                if lockText and lockText ~= lockPromptText then
                    lockPromptText = lockText
                    PromptSetText(LockPrompt, VarString(10, "LITERAL_STRING", lockText))
                end

                if radialHere then
                    SetCratePromptVisibility(false, false, false, false, count > 1, false)
                else
                    SetCratePromptVisibility(canStore, canTake, canTend, canPickup,
                        count > 1, lockText ~= nil)
                end
            end
            if radialHere then GSC.Radial.Hint("crate") end -- the "F2 Kasippu Menu" tag
            if radialHere and count <= 1 then sleep = 100 end

            ---o[ Choosing a bottle ]o---
            local keys = Config.InteractKeys
            if count > 1 and selected then
                local step = 0
                if ControlPressed(keys.CrateSelectLeftKey) then step = -1 end
                if ControlPressed(keys.CrateSelectRightKey) then step = 1 end

                if step ~= 0 then
                    selected = ((selected - 1 + step) % count) + 1
                    selectedId = gauge.slots[selected] and gauge.slots[selected].id or nil
                    PlaySoundFrontend("SELECT", "RDRO_Character_Creator_Sounds", true, 0)
                    lastGaugeSend = 0
                end
            end
            LiftBottle(crate, selected)

            if not radialHere then
                if canStore and HoldJustCompleted(StorePrompt) then
                    DoCrate("store", currentCrate, mine)
                end

                if canTake and HoldJustCompleted(TakePrompt) then
                    DoCrate("take", currentCrate, mine, selectedId)
                end

                if canPickup and HoldJustCompleted(PickupPrompt) then
                    DoCrate("pickup", currentCrate, mine)
                end

                if canTend and HoldJustCompleted(TendPrompt) then
                    DoCrate("tend", currentCrate, mine)
                end

                if lockText and HoldJustCompleted(LockPrompt) then
                    DoCrate("lock", currentCrate, mine)
                end
            end

            ---o[ Gauge ]o---
            if gauge and (not gaugeVisible or gauge ~= sentGauge or selected ~= sentSelected)
                and GetGameTimer() - lastGaugeSend > 100 then
                lastGaugeSend = GetGameTimer()
                ShowCrateGauge()
            end
        else
            offer = nil
            if shownKey then
                shownKey = nil
                SetCratePromptVisibility(false, false, false, false, false, false)
                for prompt in pairs(promptLatched) do promptLatched[prompt] = nil end
            end

            if not (crate and busy) then HideCrateGauge() end
        end

        Wait(sleep)
    end
end)

---oo[ Placement ]oo---

---o[ What the ground under the ghost would make of a crate ]o---
local function ReadClimate(ped, pos)
    local okTemp, temp = pcall(GetTemperatureAtCoords, pos.x, pos.y, pos.z)
    local okInt, interior = pcall(GetInteriorFromEntity, ped)

    local reading = {
        temp = okTemp and tonumber(temp) or nil,
        sheltered = okInt and interior ~= nil and interior ~= 0,
    }
    local band, ageRate, keepRate = Shared.CrateClimate(reading.temp, reading.sheltered)
    return reading, band, ageRate, keepRate
end

function Crates.ReadClimate(ped, pos)
    return ReadClimate(ped, pos)
end

local function ClimatePreviewText(reading, band, ageRate, keepRate)
    if not band or not reading.temp then return nil end
    return string.format(Config.Text.CrateClimate, band.label or band.key, math.floor(reading.temp + 0.5),
        reading.sheltered and Config.Text.CrateClimateIndoors or "", ageRate, keepRate)
end

local function StartCratePlacement()
    if isPlacing then return end

    local model = LoadModel(Config.Models.AgingCrateModel)
    if not model then return end

    local ped = PlayerPedId()
    local keys = Config.InteractKeys

    isPlacing = true
    ghostEntity = CreateObject(model, GetEntityCoords(ped), false, false, false)
    SetEntityAlpha(ghostEntity, 170, false)
    SetEntityCollision(ghostEntity, false, false)
    FreezeEntityPosition(ghostEntity, true)

    GSC.Notify.Objective(Config.Text.CratePlacementHint, 10000)

    CreateThread(function()
        local rotZ = GetEntityHeading(ped)
        local climateConf = Config.CrateAging.Climate or {}
        local lastRead, shownBand = 0, nil

        while isPlacing do
            Wait(0)

            if IsControlPressed(1, keys.KasiyaBarrelRotateLeftKey) then rotZ = rotZ + 2.0 end
            if IsControlPressed(1, keys.KasiyaBarrelRotateRightKey) then rotZ = rotZ - 2.0 end

            local target = GetEntityCoords(ped) + (GetEntityForwardVector(ped) * 1.5)
            SetEntityCoords(ghostEntity, target.x, target.y, target.z, false, false, false, false)
            PlaceObjectOnGroundProperly(ghostEntity)
            SetEntityRotation(ghostEntity, 0.0, 0.0, rotZ, 2, true)

            local ghostPos = GetEntityCoords(ghostEntity)
            local _, waterHeight = GetWaterHeight(ghostPos.x, ghostPos.y, ghostPos.z)
            local wet = (waterHeight > (ghostPos.z - 0.3)) or IsEntityInWater(ghostEntity)

            SetEntityAlpha(ghostEntity, wet and 60 or 200, false)

            ---o[ Live climate preview: told again whenever the band changes ]o---
            if climateConf.Enabled and GetGameTimer() - lastRead > 1000 then
                lastRead = GetGameTimer()
                local reading, band, ageRate, keepRate = ReadClimate(ped, ghostPos)
                local bandKey = band and (band.key .. tostring(reading.sheltered)) or nil

                if bandKey and bandKey ~= shownBand then
                    shownBand = bandKey
                    local text = ClimatePreviewText(reading, band, ageRate, keepRate)
                    if text then GSC.Notify.Objective(text, 4000) end
                end
            end

            if IsControlJustPressed(0, keys.KasiyaBarrelPlacmenteKey) then
                if wet then
                    GSC.Notify.Objective(Config.Text.CratePlacementWet, 3000)
                else
                    local heading = GetEntityHeading(ghostEntity)
                    local reading = ReadClimate(ped, ghostPos)
                    DeleteLocal(ghostEntity)
                    ghostEntity, isPlacing = nil, false

                    TriggerServerEvent('gsc_kassippu:server:placeCrate',
                        { x = ghostPos.x, y = ghostPos.y, z = ghostPos.z }, heading, reading)
                    break
                end
            end

            if IsControlJustPressed(0, keys.KasiyaBarrelPlacementCanselKey) then
                DeleteLocal(ghostEntity)
                ghostEntity, isPlacing = nil, false
                GSC.Notify.Objective(Config.Text.CratePlacementCancel, 3000)
                break
            end
        end
    end)
end

RegisterNetEvent('gsc_kassippu:client:startCratePlacement')
AddEventHandler('gsc_kassippu:client:startCratePlacement', function()
    StartCratePlacement()
end)

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, crate in pairs(crates) do DespawnCrate(crate) end
    for _, entry in pairs(myCrates) do DropBlip(entry) end
    DeleteLocal(ghostEntity)
    ghostEntity, isPlacing = nil, false

    HideCrateGauge()

    for _, prompt in ipairs({ StorePrompt, TakePrompt, TendPrompt, PickupPrompt, SelectPrompt, LockPrompt }) do
        if prompt then
            PromptSetVisible(prompt, false)
            PromptDelete(prompt)
        end
    end
end)