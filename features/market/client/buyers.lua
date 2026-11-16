local Buyers = GSC.module('Buyers')

---oo[ The buyers, on the client: their NPCs, the Talk prompt, the ledger ]oo---
-- The server keeps the prices, the demand and the trust (features/market/server/market.lua).
-- Here: a local (not networked) NPC for each buyer within SpawnDistance, a prompt to talk to
-- him, and the ledger page. Far from every buyer the loop sleeps 2 s.

local campIndex = nil   -- the travelling buyer's camp (the server says)
local peds = {}         -- [buyer id] = ped
local blips = {}        -- saloon blips
local ledgerOpen = false

local PromptGroup = CreateVarString(10, 'LITERAL_STRING', "Buyer")
local TalkPrompt = nil
local groupLabels = {}  -- [buyer id] = the prompt group's title, made once

local function Conf()
    return Config.Market or {}
end

---o[ Every buyer the client knows of: { id, name, coords, heading, model } - built once, again
--     only when the travelling buyer moves (never per frame) ]o---
local cachedList = nil

local function List()
    if cachedList then return cachedList end
    local conf = Conf()
    local list = {}
    for _, s in ipairs(conf.Saloons or {}) do
        list[#list + 1] = { id = "saloon:" .. s.id, name = s.name, coords = s.coords, heading = s.heading, model = s.model }
    end
    local tr = conf.Traveller or {}
    local camp = tr.Enabled and campIndex and (tr.Camps or {})[campIndex]
    if camp then
        list[#list + 1] = { id = "traveller", name = tr.Name, coords = camp.coords, heading = camp.heading, model = tr.model }
    end
    cachedList = list
    return list
end

---o[ His NPC: local, frozen, unhurt, at his scenario ]o---
local function LoadModel(name)
    local hash = GetHashKey(name)
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - started > 5000 then
            Shared.Debug("^1[Market]^7 Model failed to load: " .. tostring(name))
            return nil
        end
        Wait(0)
    end
    return hash
end

local function Spawn(buyer)
    local hash = LoadModel(buyer.model or Conf().Model or "re_fleeingfamily_males_01")
    if not hash then return nil end
    local c = buyer.coords
    local ped = CreatePed(hash, c.x, c.y, c.z - 1.0, buyer.heading or 0.0, false, false, true, true)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- outfit (as the guards do)
    SetEntityInvincible(ped, true)
    SetPedCanBeTargetted(ped, false)
    FreezeEntityPosition(ped, true)
    local scenario = Conf().Scenario
    if scenario then TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1, true, false, false, false) end
    return ped
end

local function Despawn(id)
    local ped = peds[id]
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    peds[id] = nil
end

---o[ Saloon markers (the traveller has to be found) ]o---
local function DrawBlips()
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
    blips = {}
    local conf = Conf().Blips
    if not (Conf().Enabled and conf and conf.Enabled) then return end
    for _, s in ipairs(Conf().Saloons or {}) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, s.coords.x, s.coords.y, s.coords.z)
        if conf.Sprite then SetBlipSprite(blip, GetHashKey(conf.Sprite), true) end
        SetBlipScale(blip, conf.Scale or 0.7)
        pcall(function()
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, "LITERAL_STRING", conf.Name or "Buyer")) -- SetBlipName
        end)
        blips[#blips + 1] = blip
    end
end

---oo[ The prompt ]oo---
CreateThread(function()
    if not Conf().Enabled then return end
    TalkPrompt = PromptRegisterBegin()
    PromptSetControlAction(TalkPrompt, Config.InteractKeys.BuyerTalkKey)
    PromptSetText(TalkPrompt, CreateVarString(10, "LITERAL_STRING", Config.PromptsTxt.BuyerTalkPrompt))
    PromptSetEnabled(TalkPrompt, true)
    PromptSetVisible(TalkPrompt, not (GSC.Radial ~= nil and GSC.Radial.Owns("buyer"))) -- menu only: the F2 tag instead
    PromptSetHoldMode(TalkPrompt, Config.KasiyaBarrelKitConf.KasiyaBarrelPromptsHoldTime)
    PromptSetGroup(TalkPrompt, PromptGroup, 0)
    PromptRegisterEnd(TalkPrompt)

    DrawBlips()
    TriggerServerEvent('gsc_kassippu:server:buyerCampAsk')
end)

local latched = false
local function TalkJustCompleted()
    if not UiPromptHasHoldModeCompleted(TalkPrompt) then
        latched = false
        return false
    end
    if latched then return false end
    latched = true
    return true
end

---oo[ The loop: spawn near, despawn far, prompt when close ]oo---
-- Far from every buyer it wakes every 2 s; within half the spawn distance every 0.5 s. At a
-- buyer only the prompt is drawn each frame, and the distance is rechecked every 250 ms.
---o[ For GSC.Radial: is the ledger holding the screen? ]o---
function Buyers.IsBusy()
    return ledgerOpen
end

---o[ For GSC.Radial: talk to the buyer in reach (the same rule and server event as the Talk prompt) ]o---
function Buyers.RadialActions()
    if not (GSC.Radial ~= nil and GSC.Radial.Owns("buyer")) then return nil end -- the buyers are on their Talk prompt
    local conf = Conf()
    if not conf.Enabled or ledgerOpen then return nil end

    local pos = GetEntityCoords(PlayerPedId())
    local talkAt = conf.TalkDistance or 2.5
    local close, closeDist = nil, math.huge
    for _, buyer in ipairs(List()) do
        local dist = #(pos - buyer.coords)
        if dist <= talkAt and dist < closeDist then close, closeDist = buyer, dist end
    end
    if not close then return nil end

    local buyerId = close.id
    return { title = (Config.Text.Radial or {}).Buyer or "Buyer", icon = "sack-dollar", actions = {
        { id = "gsc_buyer_talk", title = Config.PromptsTxt.BuyerTalkPrompt, icon = "comments",
            run = function() TriggerServerEvent('gsc_kassippu:server:buyerOpen', buyerId) end },
    } }
end

local function AtBuyer(buyer, talkAt)
    local label = groupLabels[buyer.id]
    if not label then
        label = CreateVarString(10, 'LITERAL_STRING', buyer.name or "Buyer")
        groupLabels[buyer.id] = label
    end

    local checkAt = 0
    while not ledgerOpen and not GSC.Minigame.IsActive() do
        local now = GetGameTimer()
        if now >= checkAt then
            checkAt = now + 250
            if #(GetEntityCoords(PlayerPedId()) - buyer.coords) > talkAt then return end
        end
        if (GSC.Radial ~= nil and GSC.Radial.Owns("buyer")) then
            GSC.Radial.Hint("buyer") -- Talk is in the F2 menu (Buyers.RadialActions): just the tag, no prompt box
        else
            UiPromptSetActiveGroupThisFrame(PromptGroup, label)
        end
        if not (GSC.Radial ~= nil and GSC.Radial.Owns("buyer")) and TalkJustCompleted() then
            TriggerServerEvent('gsc_kassippu:server:buyerOpen', buyer.id)
            return
        end
        Wait((GSC.Radial ~= nil and GSC.Radial.Owns("buyer")) and 100 or 0) -- menu mode: only the F2 tag, no prompt box
    end
end

CreateThread(function()
    while true do
        local sleep = 2000
        local conf = Conf()
        if conf.Enabled and TalkPrompt then
            local pos = GetEntityCoords(PlayerPedId())
            local spawnAt = conf.SpawnDistance or 60.0
            local talkAt = conf.TalkDistance or 2.5
            local list = List()
            local close, closeDist = nil, math.huge

            for i = 1, #list do
                local buyer = list[i]
                local dist = #(pos - buyer.coords)
                if dist <= spawnAt then
                    if not peds[buyer.id] or not DoesEntityExist(peds[buyer.id]) then peds[buyer.id] = Spawn(buyer) end
                    if dist < spawnAt * 0.5 then sleep = 500 end
                    if dist <= talkAt and dist < closeDist then close, closeDist = buyer, dist end
                elseif dist > spawnAt + 10.0 and peds[buyer.id] then
                    Despawn(buyer.id)
                end
            end

            if close and not ledgerOpen and not GSC.Minigame.IsActive() then
                AtBuyer(close, talkAt)
                sleep = 250
            end
        end
        Wait(sleep)
    end
end)

---oo[ From the server ]oo---
RegisterNetEvent('gsc_kassippu:client:buyerCamp')
AddEventHandler('gsc_kassippu:client:buyerCamp', function(index)
    local nextIndex = tonumber(index)
    if nextIndex == campIndex then return end
    campIndex = nextIndex
    cachedList = nil
    if peds.traveller then Despawn("traveller") end -- he moved on: the next pass spawns him at the new camp
end)

RegisterNetEvent('gsc_kassippu:client:buyerLedger')
AddEventHandler('gsc_kassippu:client:buyerLedger', function(ledger)
    if type(ledger) ~= 'table' or GSC.Minigame.IsActive() then return end
    local t = (Config.Text or {}).Market or {}
    ledgerOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "buyerLedger",
        buyer = ledger.buyer, name = ledger.name, trust = ledger.trust, rows = ledger.rows,
        left = ledger.left, soldBefore = ledger.soldBefore, drop = ledger.drop, floor = ledger.floor,
        rumour = ledger.rumour,
        refuse = ((Config.Market or {}).Trust or {}).RefuseBelow, -- the red tick on the trust scale
        text = {
            title = t.Title, trust = t.Trust, each = t.Each, total = t.Total, left = t.Left,
            sell = t.Sell, close = t.Close, sealed = t.Sealed,
            appetite = t.Appetite, offerAll = t.OfferAll, clear = t.Clear, all = t.All, bottles = t.Bottles,
            keys = t.Keys, tags = t.Tags,
        },
    })
end)

local function CloseLedger()
    if not ledgerOpen then return end
    ledgerOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "buyerLedgerClose" })
end

---o[ For GSC.UiGuard: take the ledger down ]o---
function Buyers.Close()
    CloseLedger()
end

RegisterNetEvent('gsc_kassippu:client:buyerResult')
AddEventHandler('gsc_kassippu:client:buyerResult', function(result)
    if not ledgerOpen then return end
    if type(result) == 'table' and (result.sold or 0) > 0 then
        SendNUIMessage({ action = "buyerLedgerDone", total = result.total, trust = result.trust })
        SetTimeout(1400, CloseLedger) -- the stamp, then the page goes
    else
        CloseLedger()
    end
end)

---oo[ From the ledger ]oo---
RegisterNUICallback('buyerSell', function(data, cb)
    cb('ok')
    if not ledgerOpen or type(data) ~= 'table' or type(data.lines) ~= 'table' then return end
    TriggerServerEvent('gsc_kassippu:server:buyerSell', data.buyer, data.lines)
end)

RegisterNUICallback('buyerCancel', function(_, cb)
    cb('ok')
    if not ledgerOpen then return end
    CloseLedger()
    TriggerServerEvent('gsc_kassippu:server:buyerClose')
end)

---oo[ Stopped: take the NPCs, the markers and the focus with it ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for id in pairs(peds) do Despawn(id) end
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
    if ledgerOpen then SetNuiFocus(false, false) end
end)
