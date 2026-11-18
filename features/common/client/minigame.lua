local Minigame = GSC.module('Minigame')

local pending = nil

local function Settle(result, score, outcomes)
    local p = pending
    pending = nil
    if p then p:resolve({ result, score, outcomes }) end
end

RegisterNUICallback('minigameResult', function(data, cb)
    cb('ok')
    local score = data and tonumber(data.score)
    local outcomes = data and type(data.outcomes) == 'table' and data.outcomes or nil -- per round (e.g. each bottle poured)
    Settle(data and data.passed == true, score and math.max(0, math.min(1, score)) or nil, outcomes)
end)

function Minigame.IsActive()
    return pending ~= nil
end

---o[ Take the running game off screen, unanswered ]o---
function Minigame.Cancel()
    if not pending then return end
    SendNUIMessage({ action = "cancelMinigame" })
    Settle(nil)
end

---o[ Play one and wait for the result ]o---
function Minigame.Play(game, title)
    game = game or {}
    if pending then Minigame.Cancel() end

    local p = promise.new()
    pending = p

    local hints = Config.Text.MinigameHints or {}

    SetNuiFocus(true, game.mouse == true)
    SendNUIMessage({
        action = "startMinigame",
        game = game,
        title = title,
        hint = hints[game.hint or game.type] or hints[game.type],
        text = Config.Text.MinigameBanners,
    })

    ---o[ Watchdog while it runs ]o---
    CreateThread(function()
        while pending == p do
            Wait(200)
            if pending ~= p then break end
            if IsEntityDead(PlayerPedId()) then -- died mid-game: take it down
                Minigame.Cancel()
                break
            end
            if not IsNuiFocused() then SetNuiFocus(true, game.mouse == true) end -- the focus was taken: take it back
        end
    end)

    SetTimeout(math.floor(((game.time or 15) + 5) * 1000), function()
        if pending == p then
            SendNUIMessage({ action = "cancelMinigame" })
            Settle(false)
        end
    end)

    local settled = Citizen.Await(p) or {}

    if not pending then SetNuiFocus(false, false) end
    return settled[1], settled[2], settled[3]
end

---o[ Stopped mid-game ]o---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if pending then
        pending = nil
        SetNuiFocus(false, false)
    end
end)
