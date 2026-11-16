local Radial = GSC.module('Radial')

local menuOpen = false -- the wheel is on screen and holds the focus
local openedAt = 0     -- GetGameTimer() it opened (the focus watchdog waits a moment)
local holding = false  -- a timed pick (seize, pour, pick up) is running

local function Conf()
    return Config.Radial or {}
end

local function Text()
    return Config.Text.Radial or {}
end

---o[ Who can offer actions, in the order their wedges appear (asked when the menu opens, never cached) ]o---
local PROVIDERS = { "Crew", "Barrels", "Stations", "Crates", "Climb", "Buyers" }
local PLACES = { Barrels = true, Stations = true, Crates = true, Climb = true, Buyers = true } -- each answers only within its own range

---o[ Nothing unless the player stands at a place: a crew invite alone keeps its own G / Backspace prompts ]o---
local function CollectSections()
    local sections, atPlace = {}, false
    for _, name in ipairs(PROVIDERS) do
        local mod = GSC[name]
        if mod and mod.RadialActions then
            local ok, section = pcall(mod.RadialActions)
            if not ok then
                Shared.Debug(string.format("^1[Radial]^7 %s.RadialActions failed: %s", name, tostring(section)))
            elseif section and section.actions and #section.actions > 0 then
                sections[#sections + 1] = section
                if PLACES[name] then atPlace = true end
            end
        end
    end
    if not atPlace then return {} end
    return sections
end

---o[ The items the NUI gets: id, title, icon and sub-rings only (no Lua functions) ]o---
local function ToNui(actions)
    local items = {}
    for i, action in ipairs(actions) do
        items[i] = { id = action.id, title = action.title, icon = action.icon }
        if action.items then items[i].items = ToNui(action.items) end
    end
    return items
end

---o[ One place offers something: its actions on the first ring. Several: one wedge per place ]o---
local function BuildItems(sections)
    if #sections == 1 then return ToNui(sections[1].actions) end

    local items = {}
    for i, section in ipairs(sections) do
        if #section.actions == 1 then
            items[#items + 1] = ToNui(section.actions)[1] -- a wedge with one action is just that action
        else
            items[#items + 1] = { id = "gsc_section_" .. i, title = section.title, icon = section.icon, items = ToNui(section.actions) }
        end
    end
    return items
end

local function FindAction(actions, id)
    for _, action in ipairs(actions) do
        if action.id == id then return action end
        if action.items then
            local found = FindAction(action.items, id)
            if found then return found end
        end
    end
    return nil
end

local function Busy(name)
    local mod = GSC[name]
    return mod and mod.IsBusy and mod.IsBusy() or false
end

---o[ Something else owns the screen or the player right now ]o---
local function Blocked()
    local ped = PlayerPedId()
    return holding
        or IsPauseMenuActive() or IsNuiFocused()
        or IsEntityDead(ped) or IsPedRagdoll(ped)
        or (GSC.Minigame and GSC.Minigame.IsActive())
        or Busy("Barrels") or Busy("Stations") or Busy("Buyers") or Busy("Tasting")
end

local function CloseMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "radialClose" })
end

function Radial.IsOpen()
    return menuOpen or holding
end

---o[ For GSC.UiGuard: is the wheel itself up (it holds the focus), and take it down ]o---
function Radial.MenuOpen()
    return menuOpen
end

function Radial.Close()
    CloseMenu()
end

---o[ Does the menu run this place (Config.Radial.Places)? If so its key prompts are hidden ]o---
function Radial.Owns(place)
    local conf = Conf()
    return conf.Enabled == true and (conf.Places or {})[place] == true
end

---o[ The "F2  Kasippu Menu" tag: a place's prompt loop calls Hint() each frame the player is at it ]o---
local hintSeenAt = 0   -- GetGameTimer() a place last said the player is at it
local hintShown = false

function Radial.Hint(place) -- place: "barrel" / "station" / "crate" / "buyer" (for reading the callers)
    hintSeenAt = GetGameTimer()
end

---o[ Shown while a place reports in, hidden the moment it stops, or while the menu or another screen is up ]o---
CreateThread(function()
    while true do
        local idle = not menuOpen and not hintShown and GetGameTimer() - hintSeenAt > 1000
        Wait(idle and 500 or 200) -- at no place: look less often (the tag still shows within half a second)
        ---o[ Something else took the focus while the menu was up: take the menu down too (never stuck on screen) ]o---
        if menuOpen and GetGameTimer() - openedAt > 600 and not IsNuiFocused() then CloseMenu() end
        local conf = Conf()
        local want = conf.Enabled == true and conf.ShowHint ~= false
            and GetGameTimer() - hintSeenAt < 400 and not menuOpen and not Blocked()
        if want ~= hintShown then
            hintShown = want
            SendNUIMessage({ action = "radialHint", show = want, key = conf.KeyMapping or "F6", label = Text().HintLabel or "Kasippu Menu" })
        end
    end
end)

function Radial.Open()
    local conf = Conf()
    if not conf.Enabled or menuOpen then return end

    ---o[ Busy, or not at a still / crate / buyer: F2 does nothing at all (no message) ]o---
    if Blocked() then return end
    local sections = CollectSections()
    if #sections == 0 then return end

    menuOpen = true
    openedAt = GetGameTimer()
    SetNuiFocus(true, true)
    local t = Text()
    SendNUIMessage({
        action = "radialOpen",
        size = conf.Size or 375,
        items = BuildItems(sections),
        sound = conf.Sound ~= false,
        text = {
            place = #sections == 1 and sections[1].title or t.MenuTitle or "Kasippu", -- small line over the pick's name
            hint = t.MenuHint,
        },
    })
    Shared.Debug(string.format("^5[Radial]^7 Opened with %d place(s) - a click should print \"picked\" next", #sections))
end

---o[ A pick that needs time (seize, pour, pick up): a bar, a pose, and moving breaks it off ]o---
function Radial.Timed(ms, title, run)
    if holding then return end
    holding = true

    local conf = Conf()
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local maxMove = conf.CancelDistance or 1.0

    SendNUIMessage({ action = "radialHold", ms = ms, label = title })
    if conf.HoldScenario then
        TaskStartScenarioInPlace(ped, GetHashKey(conf.HoldScenario), -1, true, false, false, false)
    end

    local ends = GetGameTimer() + ms
    local cancelled = false
    while GetGameTimer() < ends do
        Wait(0)
        ped = PlayerPedId()
        if IsEntityDead(ped) or IsPedRagdoll(ped) or #(GetEntityCoords(ped) - start) > maxMove then
            cancelled = true
            break
        end
    end

    if conf.HoldScenario then
        if GSC.Barrels ~= nil and GSC.Barrels.EndScenario then GSC.Barrels.EndScenario(ped, conf.HoldScenario) else ClearPedTasks(ped) end
    end
    SendNUIMessage({ action = "radialHoldEnd" })
    holding = false

    if cancelled then
        return GSC.Notify.Show(Text().Cancelled or "Stopped - you moved.", 2500)
    end
    run()
end

---o[ NUI: a wedge was picked - ask the places again, run it only if it is still on offer ]o---
RegisterNUICallback('radialSelect', function(data, cb)
    cb('ok')
    CloseMenu() -- before the action: it may open the book, which takes the focus back
    local id = data and data.id
    Shared.Debug("^5[Radial]^7 Picked: " .. tostring(id))
    if type(id) ~= 'string' then return end

    CreateThread(function()
        local action = nil
        for _, section in ipairs(CollectSections()) do
            action = FindAction(section.actions, id)
            if action then break end
        end

        if not action or not action.run then
            return GSC.Notify.Show(Text().Gone or "That can't be done now.", 2500)
        end

        if action.holdMs and action.holdMs > 0 then
            Radial.Timed(action.holdMs, action.title, action.run)
        else
            action.run()
        end
    end)
end)

---o[ NUI: closed with Esc / Backspace / the centre. Always answered, so the page never keeps a menu up ]o---
RegisterNUICallback('radialClose', function(_, cb)
    cb('ok')
    if menuOpen then return CloseMenu() end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "radialClose" })
end)

---o[ The key: a key mapping (Config.Radial.KeyMapping, any keyboard key) or, without one, a game control watched each frame ]o---
CreateThread(function()
    local key = Config.InteractKeys.RadialMenuKey
    if not key or not Conf().Enabled or Conf().KeyMapping then return end

    while true do
        Wait(0)
        if not menuOpen and (IsControlJustReleased(0, key) or IsDisabledControlJustReleased(0, key)) then
            Radial.Open()
        end
    end
end)

if Conf().Enabled then
    local command = Conf().Command or (Conf().KeyMapping and "kasippu")
    if command then
        RegisterCommand(command, function() Radial.Open() end, false)
        if Conf().KeyMapping and RegisterKeyMapping then
            RegisterKeyMapping(command, (Config.Text.Radial or {}).KeyBinding or "Kasippu: open the menu", 'keyboard', Conf().KeyMapping)
        end
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if menuOpen then SetNuiFocus(false, false) end
end)
