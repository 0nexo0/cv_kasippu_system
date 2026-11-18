local Crew = GSC.module('Crew')

local PromptGroup = CreateVarString(10, 'LITERAL_STRING', "Still Invite")
local AcceptPrompt
local DeclinePrompt

local invite = nil

function Crew.IsInvitePending()
    return invite ~= nil
end

---o[ Prompts ]o---
local function RegisterPrompt(key, text)
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
    AcceptPrompt = RegisterPrompt(Config.InteractKeys.CrewInviteAcceptKey, Config.PromptsTxt.CrewInviteAcceptPrompt)
    DeclinePrompt = RegisterPrompt(Config.InteractKeys.CrewInviteDeclineKey, Config.PromptsTxt.CrewInviteDeclinePrompt)
end)

local function SetInvitePromptsVisible(visible)
    for _, prompt in ipairs({ AcceptPrompt, DeclinePrompt }) do
        if prompt then PromptSetVisible(prompt, visible) end
    end
end

local function Answer(accepted)
    if not invite then return end
    invite = nil
    TriggerServerEvent('gsc_kassippu:server:crewRespond', accepted)
end

---o[ For GSC.Radial ]o---
function Crew.RadialActions()
    if not invite then return nil end
    local P = Config.PromptsTxt
    return { title = (Config.Text.Radial or {}).Crew or "Invite", icon = "user-group", actions = {
        { id = "gsc_crew_join", title = P.CrewInviteAcceptPrompt, icon = "handshake", run = function() Answer(true) end },
        { id = "gsc_crew_decline", title = P.CrewInviteDeclinePrompt, icon = "xmark", run = function() Answer(false) end },
    } }
end

---o[ The strip, for as long as the invite stands ]o---
local function RunInvite(current)
    local shownLeft, label = nil, nil

    local armed = false

    SetInvitePromptsVisible(true)

    while invite == current do
        local left = math.ceil((current.endsAt - GetGameTimer()) / 1000)

        if left <= 0 then
            invite = nil
            break
        end

        if left ~= shownLeft then
            shownLeft = left
            label = string.format("%s - %s (%ds)", Config.PromptsTxt.CrewInviteTitle, current.from, left)
        end

        UiPromptSetActiveGroupThisFrame(PromptGroup, VarString(10, "LITERAL_STRING", label))

        local accept = UiPromptHasHoldModeCompleted(AcceptPrompt)
        local decline = UiPromptHasHoldModeCompleted(DeclinePrompt)

        if not armed then
            armed = not accept and not decline
        elseif accept then
            Answer(true)
        elseif decline then
            Answer(false)
        end

        Wait(0)
    end

    if invite == nil then SetInvitePromptsVisible(false) end
end

RegisterNetEvent('gsc_kassippu:client:crewInvite')
AddEventHandler('gsc_kassippu:client:crewInvite', function(uid, fromName, timeout)
    local current = {
        uid = uid,
        from = fromName or "",
        endsAt = GetGameTimer() + math.floor((tonumber(timeout) or 30) * 1000),
    }
    invite = current

    GSC.Notify.Show(string.format(Config.Text.CrewInviteReceived, current.from), 5000)
    PlaySoundFrontend("SELECT", "RDRO_Character_Creator_Sounds", true, 0)

    CreateThread(function() RunInvite(current) end)
end)

RegisterNetEvent('gsc_kassippu:client:crewInviteClosed')
AddEventHandler('gsc_kassippu:client:crewInviteClosed', function()
    invite = nil
end)

---o[ Hand the prompts back to the game ]o---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    invite = nil
    for _, prompt in ipairs({ AcceptPrompt, DeclinePrompt }) do
        if prompt then
            PromptSetVisible(prompt, false)
            PromptDelete(prompt)
        end
    end
end)
