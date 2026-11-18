local Tasting = GSC.module('Tasting')

---oo[ Tasting: the client half ]oo---

local picking = false
local busy = false    -- a tasting is running

local function T()
    return Config.Text.Tasting or {}
end

---o[ For GSC.Radial ]o---
function Tasting.IsBusy()
    return picking or busy
end

local function ClosePicker()
    if not picking then return end
    picking = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "tastePickerClose" })
end

---o[ For GSC.UiGuard: is the bottle picker up, and take it down ]o---
function Tasting.PickerOpen()
    return picking
end

function Tasting.Close()
    ClosePicker()
end

RegisterNetEvent('gsc_kassippu:client:tastePicker')
AddEventHandler('gsc_kassippu:client:tastePicker', function(list)
    if busy or picking or GSC.Minigame.IsActive() then return end
    if type(list) ~= 'table' or #list == 0 then return end

    local t = T()
    for _, bottle in ipairs(list) do
        if bottle.aged then bottle.aged = string.format(t.PickerAged, bottle.aged) end
    end

    local game = (Config.Tasting or {}).Minigame or {}
    picking = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "tastePicker",
        list = list,
        tint = game.tint,
        agedTint = game.agedTint, -- ...and one aged in a crate
        text = { title = t.PickerTitle, hint = t.PickerHint, taste = t.PickerTaste, keys = t.PickerKeys },
    })
end)

RegisterNUICallback('tastePick', function(data, cb)
    cb('ok')
    if not picking then return end
    ClosePicker()

    local id = data and data.id
    if type(id) == 'number' or type(id) == 'string' then
        TriggerServerEvent('gsc_kassippu:server:tastePick', id)
    end
end)

RegisterNUICallback('tasteCancel', function(_, cb)
    cb('ok')
    ClosePicker()
end)

---o[ The cup out of the satchel (Config.AnimConf.TastingAnim) ]o---
local function PlayCupAnim(ped)
    local spec = (Config.AnimConf or {}).TastingAnim
    if not spec or not spec.dict then return end

    RequestAnimDict(spec.dict)
    local started = GetGameTimer()
    while not HasAnimDictLoaded(spec.dict) and GetGameTimer() - started < 3000 do Wait(10) end
    if not HasAnimDictLoaded(spec.dict) then
        Shared.Debug("^1[Tasting]^7 Anim dict failed to load: " .. tostring(spec.dict))
        return
    end

    TaskPlayAnim(ped, spec.dict, spec.anim, 8.0, -8.0, spec.time or 1500, spec.flag or 31, 0, false, false, false)
    Wait(spec.time or 1500)
end

---o[ The tasting itself ]o---
RegisterNetEvent('gsc_kassippu:client:tasteGame')
AddEventHandler('gsc_kassippu:client:tasteGame', function(id, recipeKey, aged)
    if busy or GSC.Minigame.IsActive() then return end
    busy = true

    CreateThread(function()
        local ped = PlayerPedId()
        if IsEntityDead(ped) then
            busy = false
            return
        end
        PlayCupAnim(ped)

        local conf = Config.Tasting or {}
        local t = T()
        local game = {}
        for k, v in pairs(conf.Minigame or {}) do game[k] = v end
        game.type = "taste"
        game.muddled = conf.MuddledBelow
        game.tint = aged and game.agedTint or game.tint
        game.labels = {
            nose = t.NoseTitle,
            palate = t.PalateTitle,
            noseHint = t.NoseHint,
            palateHint = t.PalateHint,
            cough = t.Cough,
            zones = t.Zones,
            clear = t.GameClear,
            muddled = t.GameMuddled,
        }

        local passed, score = GSC.Minigame.Play(game, t.GameTitle)

        if passed ~= nil and score then
            TriggerServerEvent('gsc_kassippu:server:tasteResult', id, score)
        end
        busy = false
    end)
end)

---o[ What the sip revealed ]o---
RegisterNetEvent('gsc_kassippu:client:tastingCard')
AddEventHandler('gsc_kassippu:client:tastingCard', function(card)
    if type(card) ~= 'table' then return end
    local t = T()

    SendNUIMessage({
        action = "tastingCard",
        product = card.product,
        grade = card.grade,
        quality = card.quality,
        full = card.full == true,
        scoreText = (card.full and card.score) and string.format(t.CardScore, card.score) or nil,
        score = (card.full and tonumber(card.score)) or nil,
        notes = card.notes,
        flaws = card.flaws,
        ms = math.floor(((Config.Tasting or {}).CardSeconds or 10) * 1000),
        text = {
            title = t.CardTitle,
            notes = t.CardNotes,
            flaws = t.CardFlaws,
            none = t.CardNone,
            partial = t.CardPartial,
        },
    })
end)

---o[ Stopped with the picker up ]o---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if picking then SetNuiFocus(false, false) end
end)
