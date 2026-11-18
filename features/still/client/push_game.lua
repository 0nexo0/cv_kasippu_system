local PushGame = GSC.module('PushGame')

---oo[ Hold The Heat as a game (Config.HeatSkill.Game) ]oo---

local running = false
local tapUid = nil
local lastStoke = 0
local group = GetRandomIntInRange(0, 0xffffff)
local groupLabel = nil
local StokePrompt, CoolPrompt, VentPrompt, TroublePrompt, OpenPrompt
local troubleText = nil

---o[ The panel ]o---
local panelOpen = false
local panelUid = nil
local suspended = false
local dismissed = {}
local lastReading = {}

local function Conf()
    local game = Config.HeatSkill and Config.HeatSkill.Enabled and Config.HeatSkill.Game
    return (game and game.Enabled) and game or nil
end

local function PanelMode()
    local conf = Conf()
    return conf ~= nil and conf.Panel == true
end

local function Text()
    return Config.Text.PushGame or {}
end

function PushGame.Running()
    return running or panelOpen
end

local function Pressed(key)
    return IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key)
end

local function Held(key)
    return IsControlPressed(0, key) or IsDisabledControlPressed(0, key)
end

local function MakePrompt(key, text)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, key)
    PromptSetText(prompt, VarString(10, "LITERAL_STRING", text or ""))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, false)
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, group, 0)
    PromptRegisterEnd(prompt)
    return prompt
end

CreateThread(function()
    local keys, T = Config.InteractKeys, Text()
    groupLabel = T.Group or "Hold The Heat" -- plain text; VarString is built per frame
    StokePrompt = MakePrompt(keys.WoodFuelAddingKey, T.Stoke)
    CoolPrompt = MakePrompt(keys.WaterPouringKey, T.Cool)
    VentPrompt = MakePrompt(keys.BarrelVentKey, T.Vent)
    TroublePrompt = MakePrompt(keys.BarrelIncidentKey, Config.PromptsTxt.IncidentPrompt)
    OpenPrompt = MakePrompt(keys.WoodFuelAddingKey, T.Open or "Work The Fire")
end)

local function ShowPrompts(stoke, cool, vent, trouble, open)
    if not StokePrompt then return end
    PromptSetVisible(StokePrompt, stoke)
    PromptSetVisible(CoolPrompt, cool)
    PromptSetVisible(VentPrompt, vent)
    PromptSetVisible(TroublePrompt, trouble)
    PromptSetVisible(OpenPrompt, open)
end

local function SetTap(uid)
    if uid == tapUid then return end
    if tapUid then TriggerServerEvent('gsc_kassippu:server:pushTap', tapUid, false) end
    tapUid = uid
    if uid then TriggerServerEvent('gsc_kassippu:server:pushTap', uid, true) end
end

local function Stoke(uid)
    local now = GetGameTimer()
    if now - lastStoke < (tonumber(Conf().StokeCooldown) or 1.0) * 1000 then return false end
    lastStoke = now
    TriggerServerEvent('gsc_kassippu:server:pushStoke', uid)
    return true
end

---o[ The still in FINAL_PUSH this player stands at and may work ]o---
local function Here(relaxed)
    if not Conf() or not GSC.Barrels or not GSC.Barrels.Here then return nil end
    local uid, stage = GSC.Barrels.Here()
    if not uid or stage ~= Shared.BarrelStage.FINAL_PUSH then return nil end
    if IsEntityDead(PlayerPedId()) then return nil end
    if not (GSC.Barrels.CanDo(uid, "fuel") or GSC.Barrels.CanDo(uid, "cool")) then return nil end
    if relaxed then return uid end
    if GSC.Barrels.IsBusy() or (GSC.Stations ~= nil and GSC.Stations.IsBusy()) then return nil end
    if (GSC.Radial ~= nil and GSC.Radial.IsOpen()) or IsNuiFocused() or IsPauseMenuActive() then return nil end
    return uid
end

---oo[ The Firebox panel ]oo---
local function Reading(uid)
    local r = lastReading[uid] or {}
    local g = r.gauge or {}
    local incident = g.incident
    return {
        heat = r.heat or 0,
        target = g.target, band = g.band, score = g.score, pushLeft = g.pushLeft,
        pressure = Config.Pressure.Enabled and g.pressure or nil,
        pressureWarn = g.pressureWarn or Config.Pressure.WarnAt,
        game = g.game,
        fireLit = g.fire ~= nil and (g.fire.fuel or 0) > 0,
        incident = (incident and GSC.Barrels.CanDo(uid, "fix")) and { label = incident.label, left = incident.left } or nil,
    }
end

function PushGame.Open(uid)
    if not PanelMode() or panelOpen or not uid then return end
    if Here(true) ~= uid then return end

    panelOpen, panelUid, suspended = true, uid, false
    dismissed[uid] = nil
    SetNuiFocus(true, true)

    local conf, words = Conf(), Text()
    local grades = Config.HeatSkill.Grades or {}
    SendNUIMessage({
        action = "pushPanel",
        open = true,
        text = words.Panel or {},
        warnText = { flare = words.WarnFlare, draught = words.WarnDraught },
        grades = { grades.NORMAL or 40, grades.GOOD or 60, grades.PERFECT or 82 },
        maxHeat = Config.HeatManagement.MaxHeat,
        cooldown = tonumber(conf.StokeCooldown) or 1.0,
        stokeSeconds = tonumber(conf.StokeSeconds) or 3,
        canFuel = GSC.Barrels.CanDo(uid, "fuel"),
        canCool = GSC.Barrels.CanDo(uid, "cool"),
        canVent = Config.Pressure.Enabled and GSC.Barrels.CanDo(uid, "vent"),
        sound = conf.Sound ~= false,
        volume = tonumber(conf.Volume) or 0.5,
        reading = Reading(uid),
    })
end

local function ClosePanel()
    if not panelOpen then return end
    panelOpen, panelUid, suspended = false, nil, false
    SetTap(nil)
    if not (GSC.Minigame ~= nil and GSC.Minigame.IsActive()) then SetNuiFocus(false, false) end -- an incident's game keeps the keys
    SendNUIMessage({ action = "pushPanel", open = false })
end

---o[ For GSC.UiGuard ]o---
function PushGame.IsPanelOpen()
    return panelOpen and not suspended
end

function PushGame.Close()
    if panelUid then dismissed[panelUid] = true end
    ClosePanel()
end

---o[ For barrels.lua ]o---
function PushGame.OnHeat(uid, heat, gauge)
    lastReading[uid] = { heat = heat, gauge = gauge }
    if not panelOpen or uid ~= panelUid then return false end
    if not suspended then
        SendNUIMessage({ action = "pushPanel", update = true, reading = Reading(uid) })
    end
    return true
end

---o[ For Barrels.RadialActions ]o---
function PushGame.CanOpen(uid)
    return PanelMode() and not panelOpen and Here(true) == uid
end

RegisterNUICallback('pushStoke', function(_, cb)
    cb('ok')
    if panelOpen and panelUid and GSC.Barrels.CanDo(panelUid, "fuel") then Stoke(panelUid) end
end)

RegisterNUICallback('pushTap', function(data, cb)
    cb('ok')
    local open = panelOpen and not suspended and type(data) == 'table' and data.open == true
    SetTap((open and GSC.Barrels.CanDo(panelUid, "cool")) and panelUid or nil)
end)

RegisterNUICallback('pushVent', function(_, cb)
    cb('ok')
    if panelOpen and panelUid then GSC.Barrels.Act("vent", panelUid) end
end)

RegisterNUICallback('pushTrouble', function(_, cb)
    cb('ok')
    if panelOpen and panelUid then GSC.Barrels.Act("incident", panelUid) end
end)

RegisterNUICallback('pushPanelClose', function(_, cb)
    cb('ok')
    if panelUid then dismissed[panelUid] = true end
    ClosePanel()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if panelOpen then SetNuiFocus(false, false) end
end)

---oo[ The loop: the panel's life, or the prompts ]oo---
local function PanelTick()
    if panelOpen then
        ---o[ Gone from the push ]o---
        if Here(true) ~= panelUid then
            ClosePanel()
        elseif (GSC.Minigame ~= nil and GSC.Minigame.IsActive()) or GSC.Barrels.IsBusy() then
            if not suspended then
                suspended = true
                SetTap(nil)
                SendNUIMessage({ action = "pushPanel", suspend = true })
            end
        elseif suspended then
            suspended = false
            SetNuiFocus(true, true)
            SendNUIMessage({ action = "pushPanel", resume = true, reading = Reading(panelUid) })
        end
        return 100
    end

    local uid = Here(false)
    if not uid then
        if running then
            running = false
            ShowPrompts(false, false, false, false, false)
        end
        if not Here(true) then dismissed = {} end
        return 250
    end

    if Conf().AutoOpen ~= false and not dismissed[uid] then
        PushGame.Open(uid)
        return 100
    end

    ---o[ Dismissed ]o---
    running = true
    ShowPrompts(false, false, false, false, true)
    if groupLabel then UiPromptSetActiveGroupThisFrame(group, VarString(10, "LITERAL_STRING", groupLabel), 0, 0, 0, 0) end
    if Pressed(Config.InteractKeys.WoodFuelAddingKey) then PushGame.Open(uid) end
    return 0
end

local function PromptTick()
    local uid = Here(false)
    if not uid then
        if running then
            running = false
            ShowPrompts(false, false, false, false, false)
            SetTap(nil)
        end
        return 250
    end

    running = true
    local canFuel = GSC.Barrels.CanDo(uid, "fuel")
    local canCool = GSC.Barrels.CanDo(uid, "cool")
    local canVent = Config.Pressure.Enabled and GSC.Barrels.CanDo(uid, "vent")
    local trouble = GSC.Barrels.Incident(uid)
    local canFix = trouble ~= nil and GSC.Barrels.CanDo(uid, "fix")

    if canFix and trouble.label ~= troubleText and TroublePrompt then
        troubleText = trouble.label
        PromptSetText(TroublePrompt, VarString(10, "LITERAL_STRING", troubleText or Config.PromptsTxt.IncidentPrompt))
    end

    ShowPrompts(canFuel, canCool, canVent, canFix, false)
    if groupLabel then UiPromptSetActiveGroupThisFrame(group, VarString(10, "LITERAL_STRING", groupLabel), 0, 0, 0, 0) end

    local keys = Config.InteractKeys
    if canFuel and Pressed(keys.WoodFuelAddingKey) then Stoke(uid) end
    SetTap((canCool and Held(keys.WaterPouringKey)) and uid or nil)
    if canVent and Pressed(keys.BarrelVentKey) then GSC.Barrels.Act("vent", uid) end
    if canFix and Pressed(keys.BarrelIncidentKey) then GSC.Barrels.Act("incident", uid) end
    return 0
end

CreateThread(function()
    while true do
        local sleep = 250
        local atStill = GSC.Barrels ~= nil and GSC.Barrels.IsAtBarrel and GSC.Barrels.IsAtBarrel()
        if Conf() and not panelOpen and not running and not atStill then
            sleep = 1000 -- not at a still: nothing to watch
            if next(dismissed) ~= nil then dismissed = {} end
            SetTap(nil)
        elseif Conf() then
            sleep = PanelMode() and PanelTick() or PromptTick()
        elseif panelOpen then
            ClosePanel()
        end
        Wait(sleep)
    end
end)
