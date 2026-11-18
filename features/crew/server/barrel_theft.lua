local BarrelTheft = GSC.module('BarrelTheft')

local Attempts = {}
local Cooldown = {} -- [src] = os.time() they may try again

local function Conf()
    return Config.BarrelTheft or {}
end

---o[ Is stealing a thing at all right now? ]o---
function BarrelTheft.Enabled()
    local crew = Config.BarrelCrew or {}
    return Conf().Enabled == true and crew.Enabled == true and crew.CrewOnly == true
end

local function Notify(src, text, ms)
    if src and text then GSC.Notify.Send(src, text, ms or 4000) end
end

---o[ The owner and online crew, minus the thief ]o---
local function AlertKeepers(uid, thief, text)
    if not Conf().AlertOwner then return end

    local told = { [thief] = true }
    local keepers = GSC.BarrelCrew.OnlineSources(uid)
    keepers[#keepers + 1] = GSC.Distillery.OwnerSource(uid)

    for _, src in ipairs(keepers) do
        if not told[src] then
            told[src] = true
            Notify(src, text, 6000)
        end
    end
end

---o[ Is the owner or a crew member standing at it? ]o---
local function Guarded(uid)
    for src in pairs(GSC.Distillery.Watchers(uid)) do
        if GSC.BarrelCrew.Role(src, uid) ~= "none" then return true end
    end
    return false
end

---o[ What a stranger can do to this barrel right now ]o---
local function KindFor(uid)
    local stage = GSC.Distillery.Stage(uid)
    if stage == Shared.BarrelStage.COMPLETED then return "bottle" end
    if stage == Shared.BarrelStage.FERMENTING and Conf().SpikeEnabled then return "spike" end
    return nil
end

---o[ Everything a theft needs, checked at the start and again at the end ]o---
local function CanTamper(src, uid, kind)
    local pos = GSC.Distillery.Position(uid)
    if not pos or not Shared.GetChar(src) then return false end

    if GSC.BarrelCrew.Role(src, uid) ~= "none" then return false end
    if Shared.IsLawman(Shared.GetChar(src)) then return false end

    if #(GetEntityCoords(GetPlayerPed(src)) - pos) > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        return false
    end

    if not kind or KindFor(uid) ~= kind
        or (kind == "bottle" and GSC.Distillery.RemainingBottles(uid) <= 0) then
        Notify(src, Config.Text.TheftNothing, 3000)
        return false
    end

    if Conf().WatchedBlocks and Guarded(uid) then
        Notify(src, Config.Text.TheftWatched, 3000)
        return false
    end

    ---o[ One wash only takes so many spikes ]o---
    local maxSpikes = tonumber(Conf().SpikeMaxPerBatch) or 0
    if kind == "spike" and maxSpikes > 0 and GSC.Distillery.SpikeCount(uid) >= maxSpikes then
        Notify(src, Config.Text.SpikeAlready, 3000)
        return false
    end

    if kind == "bottle" and exports.vorp_inventory:getItemCount(src, nil, Config.Product.FillingItem) < 1 then
        Notify(src, Config.Text.TheftNeedsBottle, 3000)
        return false
    end

    return true
end

---o[ Ask to try ]o---
RegisterServerEvent('gsc_kassippu:server:tamperBarrel')
AddEventHandler('gsc_kassippu:server:tamperBarrel', function(uid)
    local _source = source
    if not BarrelTheft.Enabled() or type(uid) ~= 'string' then return end

    local now = os.time()

    local pending = Attempts[_source]
    if pending and now - pending.started < 60 then return end

    if (Cooldown[_source] or 0) > now then
        return Notify(_source, string.format(Config.Text.TheftCooldown, Cooldown[_source] - now), 3000)
    end

    local kind = KindFor(uid)
    if not CanTamper(_source, uid, kind) then return end

    Attempts[_source] = { uid = uid, kind = kind, started = now, startedMs = GetGameTimer() }
    TriggerClientEvent('gsc_kassippu:client:tamperBarrel', _source, uid, kind)

    AlertKeepers(uid, _source, kind == "spike" and Config.Text.SpikeAttemptAlert or Config.Text.TheftAttemptAlert)

    Shared.Debug(string.format("^3[Theft]^7 (ID: %s) is trying to %s at %s", _source, kind, uid))
end)

---o[ ...and how it went ]o---
RegisterServerEvent('gsc_kassippu:server:tamperBarrelResult')
AddEventHandler('gsc_kassippu:server:tamperBarrelResult', function(uid, passed)
    local _source = source
    local attempt = Attempts[_source]
    Attempts[_source] = nil
    if not attempt or attempt.uid ~= uid then return end

    local now = os.time()
    Cooldown[_source] = now + (Conf().CooldownSeconds or 0)

    if now - attempt.started > 60 then return end

    ---o[ Sooner than a real game can be won: it counts as failed ]o---
    local took = (GetGameTimer() - (attempt.startedMs or 0)) / 1000.0
    if passed == true and took < (Conf().MinSeconds or 0) then
        Shared.Debug(string.format("^1[Theft]^7 (ID: %s) result after %.2fs - too fast, counted as failed", _source, took))
        passed = false
    end

    if passed ~= true then
        return Notify(_source, Config.Text.TheftFailed, 3000)
    end

    if not CanTamper(_source, uid, attempt.kind) then return end

    local L = Config.Text.Logs or {}
    local function LogTheft(title, withLeft)
        local fields = {
            { name = GSC.Logs.Label("Thief"), value = GSC.Logs.Player(_source), raw = true },
            { name = GSC.Logs.Label("Still"), value = uid, inline = true },
            { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(GSC.Distillery.OwnerId(uid)), raw = true },
            { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(GSC.Distillery.Position(uid)), inline = true },
        }
        if withLeft then
            fields[#fields + 1] = { name = GSC.Logs.Label("Left"), value = tostring(GSC.Distillery.RemainingBottles(uid)), inline = true }
        end
        GSC.Logs.Send("theft", title, fields)
    end

    if attempt.kind == "spike" then
        if GSC.Distillery.SpikeWash(uid, (Conf().SpikeMinutes or 0) * 60, true) then
            Notify(_source, Config.Text.SpikeDone, 4000)
            AlertKeepers(uid, _source, Config.Text.SpikedAlert)
            Shared.Debug(string.format("^1[Theft]^7 (ID: %s) spiked the wash in %s", _source, uid))
            LogTheft(L.WashSpiked, false)
        end
    elseif GSC.Distillery.DrawBottle(_source, uid) then
        AlertKeepers(uid, _source, string.format(Config.Text.TheftStolenAlert, GSC.Distillery.RemainingBottles(uid)))
        Shared.Debug(string.format("^1[Theft]^7 (ID: %s) stole a bottle from %s", _source, uid))
        LogTheft(L.BottleStolen, true)
    end
end)

AddEventHandler('playerDropped', function()
    Attempts[source] = nil
    Cooldown[source] = nil
end)
