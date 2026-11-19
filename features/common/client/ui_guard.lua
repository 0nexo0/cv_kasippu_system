local UiGuard = GSC.module('UiGuard')

---oo[ No Kasippu screen can stay stuck (Config.UiGuard) ]oo---

local function Conf()
    return Config.UiGuard or {}
end

local function Call(fn, ...)
    if not fn then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then Shared.Debug("^1[UiGuard]^7 " .. tostring(result)) return nil end
    return result
end

---o[ Every screen that takes the focus ]o---
local OWNERS = {
    {
        name = "journal",
        open = function() return GSC.Barrels ~= nil and GSC.Barrels.IsJournalOpen ~= nil and (GSC.Barrels.IsJournalOpen()) end,
        close = function() GSC.Barrels.CloseJournal() end,
    },
    {
        name = "radial",
        open = function() return GSC.Radial ~= nil and GSC.Radial.MenuOpen ~= nil and GSC.Radial.MenuOpen() end,
        close = function() GSC.Radial.Close() end,
    },
    {
        name = "firebox",
        open = function() return GSC.PushGame ~= nil and GSC.PushGame.IsPanelOpen ~= nil and GSC.PushGame.IsPanelOpen() end,
        close = function() GSC.PushGame.Close() end,
    },
    {
        name = "ledger",
        open = function() return GSC.Buyers ~= nil and GSC.Buyers.IsBusy ~= nil and GSC.Buyers.IsBusy() end,
        close = function() GSC.Buyers.Close() end,
    },
    {
        name = "picker",
        open = function() return GSC.Tasting ~= nil and GSC.Tasting.PickerOpen ~= nil and GSC.Tasting.PickerOpen() end,
        close = function() GSC.Tasting.Close() end,
    },
    {
        name = "settings",
        open = function() return GSC.AdminPanel ~= nil and GSC.AdminPanel.IsOpen ~= nil and GSC.AdminPanel.IsOpen() end,
        close = function() GSC.AdminPanel.Close() end,
    },
    {
        name = "minigame",
        open = function() return GSC.Minigame ~= nil and GSC.Minigame.IsActive() end,
        close = function() GSC.Minigame.Cancel() end,
        keepsFocus = true,
    },
}

local function AnyOpen()
    for _, owner in ipairs(OWNERS) do
        if Call(owner.open) then return true end
    end
    return false
end

local function CloseAll()
    for _, owner in ipairs(OWNERS) do
        if Call(owner.open) then
            Shared.Debug("^3[UiGuard]^7 Closing " .. owner.name)
            Call(owner.close)
        end
    end
end

---o[ Everything down ]o---
function UiGuard.ResetAll(all)
    CloseAll()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "uiReset", all = all == true })
end

---o[ The watch ]o---
CreateThread(function()
    local orphanSeen = 0
    local lostSince = {}
    local awaySeen = 0

    while true do
        local conf = Conf()
        local focused = IsNuiFocused()
        local busy = conf.Enabled ~= false and (focused or AnyOpen())

        if not busy then
            orphanSeen, awaySeen = 0, 0
            if next(lostSince) ~= nil then lostSince = {} end
            Wait(1000)
        else
            local now = GetGameTimer()
            local anyOpen = false
            local dead = IsEntityDead(PlayerPedId())

            for _, owner in ipairs(OWNERS) do
                if Call(owner.open) then
                    anyOpen = true
                    if dead then
                        Call(owner.close) -- died with it up
                    elseif not focused and not owner.keepsFocus then
                        lostSince[owner.name] = lostSince[owner.name] or now
                        if now - lostSince[owner.name] >= (conf.LostFocusMs or 1000) then
                            Shared.Debug("^3[UiGuard]^7 " .. owner.name .. " lost the focus - closed")
                            lostSince[owner.name] = nil
                            Call(owner.close)
                        end
                    else
                        lostSince[owner.name] = nil
                    end
                else
                    lostSince[owner.name] = nil
                end
            end

            ---o[ The focus is ours but no screen of ours is up ]o---
            if focused and not anyOpen then
                orphanSeen = orphanSeen + 1
                if orphanSeen == 2 then
                    Shared.Debug("^3[UiGuard]^7 Focus held with no screen up - freed")
                    SetNuiFocus(false, false)
                    SendNUIMessage({ action = "uiReset" })
                end
            else
                orphanSeen = 0
            end

            ---o[ The book opened at a still the player is no longer at ]o---
            local bookOpen, bookAt = false, nil
            if GSC.Barrels ~= nil and GSC.Barrels.IsJournalOpen then bookOpen, bookAt = GSC.Barrels.IsJournalOpen() end
            if bookOpen and bookAt and GSC.Barrels.Here and GSC.Barrels.Here() ~= bookAt then
                awaySeen = awaySeen + 1
                if awaySeen >= 2 then
                    awaySeen = 0
                    Call(GSC.Barrels.CloseJournal)
                end
            else
                awaySeen = 0
            end

            Wait(250)
        end
    end
end)

---o[ The last resort ]o---
CreateThread(function()
    local command = Conf().ResetCommand
    if Conf().Enabled == false or not command then return end

    RegisterCommand(command, function()
        UiGuard.ResetAll(true)
        local ped = PlayerPedId()
        if IsPedUsingAnyScenario(ped) then ClearPedTasksImmediately(ped) end -- out of a stuck pose too
        GSC.Notify.Show((Config.Text.Radial or {}).UiReset or "Kasippu screens closed.", 3000)
    end, false)
end)
