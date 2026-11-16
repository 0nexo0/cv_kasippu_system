local Stations = GSC.module('Stations')

---oo[ The Water Barrel and the Log Rack beside a still (Config.Stations) ]oo---
-- Set down with a ghost, streamed in as local props, filled / stacked / picked up from the F2 menu
-- (Config.Radial.Places.station) or their own prompts. The server owns every number.

local sites = {}       -- [uid] = { water = { x, y, z, h, level, cap }, rack = { x, y, z, h, logs, cap, splits } }
local props = {}       -- [uid .. "|" .. kind] = entity
local placing = false
local inRange = {}     -- [uid] = true: stations within StreamDistance (the stream thread keeps it, the near check reads it)
local near = nil       -- { uid, kind, dist } the station the player stands at (refreshed 4 times a second)
local holding = false  -- key mode: this module's prompts hold the screen

local KINDS = { water = "WaterBarrel", rack = "LogRack" }
local MODELS = { water = "WaterBarrelModel", rack = "LogRackModel" }

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

local function MenuMode()
    return GSC.Radial ~= nil and GSC.Radial.Owns("station")
end

local badModels = {} -- a model that failed once is not asked for again every second

local function LoadModel(name)
    if not name or name == "" or badModels[name] then return nil end
    local hash = GetHashKey(name)
    if HasModelLoaded(hash) then return hash end

    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - started > 5000 then
            Shared.Debug("^1[Stations]^7 Model failed to load: " .. tostring(name))
            badModels[name] = true
            return nil
        end
        Wait(0)
    end
    return hash
end

local function DeleteProp(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end

function Stations.IsBusy()
    return placing
end

function Stations.HoldsPrompts()
    return holding
end

---oo[ The props: in within StreamDistance, out beyond it, gone when the server says so ]oo---
local function Drop(uid, kind)
    local key = uid .. "|" .. kind
    if props[key] then
        DeleteProp(props[key])
        props[key] = nil
    end
end

local function DropAll(uid)
    for kind in pairs(KINDS) do Drop(uid, kind) end
end

local function Spawn(uid, kind, spot)
    local key = uid .. "|" .. kind
    if props[key] then return end
    local hash = LoadModel(Config.Models[MODELS[kind]])
    if not hash then return end

    local entity = CreateObject(hash, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(entity, spot.h or 0.0)
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)
    SetModelAsNoLongerNeeded(hash)
    props[key] = entity
end

local function Moved(old, new)
    return not old or not new or old.x ~= new.x or old.y ~= new.y or old.z ~= new.z or old.h ~= new.h
end

RegisterNetEvent('gsc_kassippu:client:stations')
AddEventHandler('gsc_kassippu:client:stations', function(uid, data)
    if type(uid) ~= 'string' then return end
    local old = sites[uid] or {}
    data = type(data) == 'table' and data or nil
    for kind in pairs(KINDS) do
        if not (data and data[kind]) or Moved(old[kind], data[kind]) then Drop(uid, kind) end
    end
    sites[uid] = data
end)

RegisterNetEvent('gsc_kassippu:client:allStations')
AddEventHandler('gsc_kassippu:client:allStations', function(all)
    for uid in pairs(sites) do DropAll(uid) end
    sites = type(all) == 'table' and all or {}
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('gsc_kassippu:server:requestStations')

    local sleep = 1000
    while true do
        Wait(sleep)
        sleep = 1000
        if On() then
            local pos = GetEntityCoords(PlayerPedId())
            local range = Conf().StreamDistance or 80.0
            local rangeSq, wakeSq = range * range, (range + 50.0) * (range + 50.0)
            local nearestSq = math.huge
            local seen = {}
            for uid, site in pairs(sites) do
                for kind in pairs(KINDS) do
                    local spot = site[kind]
                    local distSq = math.huge
                    if spot then
                        local dx, dy, dz = pos.x - spot.x, pos.y - spot.y, pos.z - spot.z
                        distSq = dx * dx + dy * dy + dz * dz
                    end
                    if distSq < nearestSq then nearestSq = distSq end
                    if distSq <= rangeSq then
                        Spawn(uid, kind, spot)
                        seen[uid] = true
                    elseif inRange[uid] then -- streamed in last time: may have a prop to drop
                        Drop(uid, kind)
                    end
                end
            end
            inRange = seen
            if nearestSq > wakeSq then sleep = 3000 end -- none near: look again less often
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for key, entity in pairs(props) do
        DeleteProp(entity)
        props[key] = nil
    end
end)

---oo[ The still blew up: its water barrel and log rack go up after it, one by one ]oo---
RegisterNetEvent('gsc_kassippu:client:stationsBoom')
AddEventHandler('gsc_kassippu:client:stationsBoom', function(uid, spots)
    if type(uid) ~= 'string' then return end
    sites[uid] = nil
    local conf = Conf().Explosion or {}

    CreateThread(function()
        for i, spot in ipairs(type(spots) == 'table' and spots or {}) do
            Wait(math.floor(((tonumber(conf.Delay) or 0.35) * i) * 1000))
            if KINDS[spot.kind] and tonumber(spot.x) then
                Drop(uid, spot.kind)
                local pos = vector3(spot.x + 0.0, spot.y + 0.0, spot.z + 0.0)
                AddExplosion(pos.x, pos.y, pos.z, 25, tonumber(conf.Size) or 1.0, true, false, 0.8)

                local ped = PlayerPedId()
                if #(GetEntityCoords(ped) - pos) < (tonumber(conf.Radius) or 3.0) then
                    ApplyDamageToPed(ped, math.floor(tonumber(conf.Damage) or 25), false)
                end
            end
        end
        DropAll(uid)
    end)
end)

---oo[ Which station the player stands at ]oo---
CreateThread(function()
    while true do
        Wait(next(inRange) == nil and 1000 or 250) -- none streamed in: nothing can be in reach
        local found = nil
        if On() and not placing and next(inRange) ~= nil then
            local pos = GetEntityCoords(PlayerPedId())
            local radius = Conf().InteractRadius or 1.5
            for uid in pairs(inRange) do -- only what is streamed in, not every station on the server
                local site = sites[uid] or {}
                for kind in pairs(KINDS) do
                    local spot = site[kind]
                    if spot then
                        local dist = #(pos - vector3(spot.x, spot.y, spot.z))
                        if dist <= radius and (not found or dist < found.dist) then
                            found = { uid = uid, kind = kind, dist = dist }
                        end
                    end
                end
            end
        end
        near = found
    end
end)

---oo[ What a station offers: fill / stack, and pick up ]oo---
local function Actions(at)
    local site = sites[at.uid]
    local spot = site and site[at.kind]
    if not spot then return {} end

    local T, list = Text(), {}
    local uid, kind = at.uid, at.kind
    if kind == "water" then
        list[#list + 1] = {
            id = "gsc_station_fill", icon = "droplet",
            title = string.format("%s (%d/%d L)", T.Fill or "Fill", math.floor(spot.level or 0), spot.cap or 0),
            run = function() TriggerServerEvent('gsc_kassippu:server:fillStation', uid) end,
        }
    else
        list[#list + 1] = {
            id = "gsc_station_stack", icon = "boxes-stacked",
            title = string.format("%s (%d/%d)", T.Stack or "Stack", spot.logs or 0, spot.cap or 0),
            run = function() TriggerServerEvent('gsc_kassippu:server:stockStation', uid) end,
        }
    end
    list[#list + 1] = {
        id = "gsc_station_pickup", icon = "box", holdMs = 1000,
        title = string.format(T.PickUp or "Pick Up %s", Label(kind)),
        run = function() TriggerServerEvent('gsc_kassippu:server:pickupStation', uid, kind) end,
    }
    return list
end

---oo[ Set down from the still's F2 menu: only what the player carries, and what the still lacks ]oo---
local carried = { water = false, rack = false } -- from the server (client:stationItems)
local carriedFor = nil                             -- the still they were asked at
local carriedAt = 0

RegisterNetEvent('gsc_kassippu:client:stationItems')
AddEventHandler('gsc_kassippu:client:stationItems', function(data)
    if type(data) ~= 'table' then return end
    carried = { water = data.water == true, rack = data.rack == true }
end)

---o[ Asked when the player comes to a still, and every few seconds while there (the satchel changes) ]o---
CreateThread(function()
    while true do
        Wait(1000)
        local uid = (On() and GSC.Barrels ~= nil and GSC.Barrels.Here) and GSC.Barrels.Here() or nil
        if not uid then
            carriedFor = nil
        elseif uid ~= carriedFor or GetGameTimer() - carriedAt >= 5000 then
            carriedFor, carriedAt = uid, GetGameTimer()
            TriggerServerEvent('gsc_kassippu:server:stationItems')
        end
    end
end)

---o[ For Barrels.RadialActions: the "Set Down ..." wedges at this still ]o---
local RIGHTS = { water = "cool", rack = "fuel" }
local ICONS = { water = "droplet", rack = "boxes-stacked" }

function Stations.StillActions(uid, stage)
    if not On() or placing or not uid or stage == Shared.BarrelStage.FINAL_PUSH then return {} end
    local site, list = sites[uid] or {}, {}
    for _, kind in ipairs({ "water", "rack" }) do
        if carried[kind] and not site[kind] and GSC.Barrels.CanDo(uid, RIGHTS[kind]) then
            list[#list + 1] = {
                id = "gsc_station_setdown_" .. kind, icon = ICONS[kind],
                title = string.format(Text().SetDown or "Set Down %s", Label(kind)),
                run = function()
                    carriedAt = 0 -- ask again soon: it is no longer in the satchel
                    TriggerServerEvent('gsc_kassippu:server:placeStationFromMenu', uid, kind)
                end,
            }
        end
    end
    return list
end

---o[ For GSC.Radial: the station the player stands at ]o---
function Stations.RadialActions()
    if not On() or not near or placing or not MenuMode() then return nil end
    if GSC.PushGame ~= nil and GSC.PushGame.Running() then return nil end
    return { title = Text().Radial or "Water & Logs", icon = "boxes-stacked", actions = Actions(near) }
end

---oo[ Key mode (Config.Radial.Places.station = false): its own prompts, nearer than the still ]oo---
local group = GetRandomIntInRange(0, 0xffffff)
local groupLabel = nil
local FillPrompt, PickupPrompt

CreateThread(function()
    local keys, T = Config.InteractKeys, Text()
    local holdTime = Config.KasiyaBarrelKitConf.KasiyaBarrelPromptsHoldTime

    FillPrompt = PromptRegisterBegin()
    PromptSetControlAction(FillPrompt, keys.WaterPouringKey)
    PromptSetText(FillPrompt, VarString(10, "LITERAL_STRING", T.Fill or "Fill"))
    PromptSetEnabled(FillPrompt, true)
    PromptSetVisible(FillPrompt, false)
    PromptSetHoldMode(FillPrompt, holdTime)
    PromptSetGroup(FillPrompt, group, 0)
    PromptRegisterEnd(FillPrompt)

    PickupPrompt = PromptRegisterBegin()
    PromptSetControlAction(PickupPrompt, keys.BarrelPickupKey)
    PromptSetText(PickupPrompt, VarString(10, "LITERAL_STRING", T.PickUp or "Pick Up"))
    PromptSetEnabled(PickupPrompt, true)
    PromptSetVisible(PickupPrompt, false)
    PromptSetHoldMode(PickupPrompt, 1000)
    PromptSetGroup(PickupPrompt, group, 0)
    PromptRegisterEnd(PickupPrompt)

    groupLabel = VarString(10, "LITERAL_STRING", T.Prompts or "Still Supplies")
end)

local fillLatched, pickupLatched = false, false
local shownKind = nil
local pouring = false -- a pour into the Water Barrel is being played: no prompts until it is over

CreateThread(function()
    while true do
        local sleep = 250
        local at = near
        local busy = false
        if at then
            busy = pouring or placing or (GSC.PushGame ~= nil and GSC.PushGame.Running())
                or (GSC.Barrels ~= nil and GSC.Barrels.IsBusy()) or IsNuiFocused()
        elseif not holding then
            sleep = 1000 -- at no station: nothing to show
        end

        ---o[ Closer to the station than to the still: the station's prompts ]o---
        local claim = false
        if at and not busy and FillPrompt then
            local uid, _, stillPos = nil, nil, nil
            if GSC.Barrels ~= nil and GSC.Barrels.Here then uid, _, stillPos = GSC.Barrels.Here() end
            local stillDist = stillPos and #(GetEntityCoords(PlayerPedId()) - stillPos) or math.huge
            claim = at.dist < stillDist
        end

        if claim and MenuMode() then
            if GSC.Radial ~= nil then GSC.Radial.Hint("station") end
            claim = false
        end

        if claim then
            sleep = 0
            holding = true
            local T = Text()
            if shownKind ~= at.kind then
                shownKind = at.kind
                PromptSetControlAction(FillPrompt, at.kind == "water" and Config.InteractKeys.WaterPouringKey
                    or Config.InteractKeys.IngredientsAddingKey)
                PromptSetText(FillPrompt, VarString(10, "LITERAL_STRING", at.kind == "water" and T.Fill or T.Stack))
                PromptSetText(PickupPrompt, VarString(10, "LITERAL_STRING",
                    string.format(T.PickUp or "Pick Up %s", Label(at.kind))))
            end
            PromptSetVisible(FillPrompt, true)
            PromptSetVisible(PickupPrompt, true)
            if groupLabel then UiPromptSetActiveGroupThisFrame(group, groupLabel, 0, 0, 0, 0) end

            local filled = UiPromptHasHoldModeCompleted(FillPrompt)
            if filled and not fillLatched then
                TriggerServerEvent(at.kind == "water" and 'gsc_kassippu:server:fillStation'
                    or 'gsc_kassippu:server:stockStation', at.uid)
            end
            fillLatched = filled

            local picked = UiPromptHasHoldModeCompleted(PickupPrompt)
            if picked and not pickupLatched then
                TriggerServerEvent('gsc_kassippu:server:pickupStation', at.uid, at.kind)
            end
            pickupLatched = picked
        elseif holding then
            holding = false
            shownKind = nil
            PromptSetVisible(FillPrompt, false)
            PromptSetVisible(PickupPrompt, false)
        end

        Wait(sleep)
    end
end)

---oo[ Fill Water Barrel: the server started a pour - play it out, watched, and say how it went ]oo---
-- Broken off (X, moved away, ragdoll, dead) = no water: the server only fills on "played out".
local POUR_MAX_MOVE = 1.0 -- metres the player may shift during the pour

RegisterNetEvent('gsc_kassippu:client:stationPour')
AddEventHandler('gsc_kassippu:client:stationPour', function(uid, ms)
    if pouring or type(uid) ~= 'string' then return end
    pouring = true

    CreateThread(function()
        local function Report(done)
            TriggerServerEvent('gsc_kassippu:server:fillStationDone', uid, done == true)
        end

        if GSC.Barrels ~= nil and GSC.Barrels.PlayWatched then
            local ok, err = pcall(GSC.Barrels.PlayWatched, "fill", tonumber(ms) or 3500, POUR_MAX_MOVE, Report)
            if not ok then
                print("^1[Stations]^7 pour failed: " .. tostring(err))
                Report(false)
            end
        else
            Report(false)
        end

        pouring = false
    end)
end)

---oo[ Setting one down: a ghost of the prop, within reach of the still ]oo---
local function StartPlacement(uid, kind)
    if placing or not KINDS[kind] then return end
    local stillPos = GSC.Barrels ~= nil and GSC.Barrels.Position(uid) or nil
    if not stillPos then return GSC.Notify.Objective(Text().NotAtStill, 4000) end

    local hash = LoadModel(Config.Models[MODELS[kind]])
    if not hash then return GSC.Notify.Objective(Text().ModelMissing, 5000) end

    local ped = PlayerPedId()
    local keys = Config.InteractKeys
    local maxDist, minDist = Conf().MaxDistance or 3.0, Conf().MinDistance or 0.8

    placing = true
    local ghost = CreateObject(hash, GetEntityCoords(ped), false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    GSC.Notify.Objective(Text().PlaceHint, 10000)

    CreateThread(function()
        local rotZ = GetEntityHeading(ped)

        while placing do
            Wait(0)
            if IsControlPressed(1, keys.KasiyaBarrelRotateLeftKey) then rotZ = rotZ + 2.0 end
            if IsControlPressed(1, keys.KasiyaBarrelRotateRightKey) then rotZ = rotZ - 2.0 end

            local target = GetEntityCoords(ped) + GetEntityForwardVector(ped) * 1.5
            SetEntityCoords(ghost, target.x, target.y, target.z, false, false, false, false)
            PlaceObjectOnGroundProperly(ghost)
            SetEntityRotation(ghost, 0.0, 0.0, rotZ, 2, true)

            local spot = GetEntityCoords(ghost)
            local _, waterHeight = GetWaterHeight(spot.x, spot.y, spot.z)
            local wet = (waterHeight > (spot.z - 0.5)) or IsEntityInWater(ghost)
            local dist = #(spot - stillPos)
            local good = not wet and dist <= maxDist and dist >= minDist
            SetEntityAlpha(ghost, good and 200 or 60, false)

            if IsControlJustPressed(0, keys.KasiyaBarrelPlacmenteKey) then
                if wet then
                    GSC.Notify.Objective(Text().Wet, 3000)
                elseif dist > maxDist then
                    GSC.Notify.Objective(string.format(Text().TooFar, maxDist), 3000)
                elseif dist < minDist then
                    GSC.Notify.Objective(Text().TooClose, 3000)
                else
                    local heading = GetEntityHeading(ghost)
                    DeleteProp(ghost)
                    placing = false
                    TriggerServerEvent('gsc_kassippu:server:placeStation', uid, kind,
                        { x = spot.x, y = spot.y, z = spot.z }, heading)
                    break
                end
            end

            if IsControlJustPressed(0, keys.KasiyaBarrelPlacementCanselKey) then
                DeleteProp(ghost)
                placing = false
                GSC.Notify.Objective(Text().Cancelled, 3000)
                break
            end
        end
        if DoesEntityExist(ghost) then DeleteProp(ghost) end
        SetModelAsNoLongerNeeded(hash)
    end)
end

RegisterNetEvent('gsc_kassippu:client:placeStation')
AddEventHandler('gsc_kassippu:client:placeStation', function(uid, kind)
    if type(uid) ~= 'string' then return end
    StartPlacement(uid, kind)
end)
