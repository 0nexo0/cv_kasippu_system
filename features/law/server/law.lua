local Law = GSC.module('Law')

local GameHour = nil -- as a client last said
local LastTip = {}
local LastWarn = {}
local LastNotice = {}
local LastSaleTip = {}

local function Conf()
    return Config.Law or {}
end

---o[ Every lawman on duty, and where he is ]o---
local function Lawmen()
    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local Character = src and Shared.GetChar(src)
        if Shared.IsLawman(Character) then
            list[#list + 1] = { src = src, pos = GetEntityCoords(GetPlayerPed(src)) }
        end
    end
    return list
end

---oo[ The Clock ]oo---

---o[ Only the player the server asked, once, within a few seconds ]o---
local ClockAsked = nil

RegisterServerEvent('gsc_kassippu:server:clock')
AddEventHandler('gsc_kassippu:server:clock', function(hour)
    local asked = ClockAsked
    if not asked or asked.src ~= source or GetGameTimer() - asked.at > 10000 then return end
    ClockAsked = nil

    hour = tonumber(hour)
    if hour and hour >= 0 and hour < 24 then GameHour = math.floor(hour) end
end)

local function AskClock()
    local first = tonumber(GetPlayers()[1])
    if first then
        ClockAsked = { src = first, at = GetGameTimer() }
        TriggerClientEvent('gsc_kassippu:client:askClock', first)
    end
end

---o[ The game hour, as a client last said ]o---
function Law.Hour()
    return GameHour
end

function Law.IsNight()
    if not GameHour then return false end
    local t = Conf().TipOff or {}
    local from, to = t.NightFrom or 21, t.NightTo or 5
    return GameHour >= from or GameHour < to
end

---oo[ Tip-offs ]oo---

---o[ Where a still stands ]o---
local function PlaceFactor(pos)
    local t = Conf().TipOff or {}
    local nearest = math.huge

    for _, town in ipairs(t.Towns or {}) do
        local dist = #(pos - town.coords)
        if dist <= (town.radius or 300.0) then return t.TownFactor or 1.0, town.name end
        nearest = math.min(nearest, dist)
    end

    if nearest >= (t.WildsDistance or math.huge) then return t.WildsFactor or 1.0, nil end
    return 1.0, nil
end

---o[ The chance this still is reported this minute ]o---
function Law.TipChance(uid)
    local t = Conf().TipOff or {}
    local smoke = GSC.Distillery.SmokeLevel(uid)
    if smoke <= 0 then return 0.0 end

    local pos = GSC.Distillery.Position(uid)
    if not pos then return 0.0 end

    local chance = (t.ChancePerMinute or 0.0) * ((t.SmokeFactor or {})[smoke] or 1.0)
    chance = chance * PlaceFactor(pos)
    if Law.IsNight() then chance = chance * (t.NightFactor or 1.0) end
    if GSC.Distillery.Covered(uid) then chance = chance * (t.CoveredFactor or 1.0) end

    return math.min(t.MaxChance or 1.0, chance)
end

---o[ Tell every lawman on duty, with a marker somewhere near pos ]o---
local function TipOffAt(pos, message, lawmen, blipName)
    local t = Conf().TipOff or {}
    local angle = math.random() * math.pi * 2.0
    local dist = math.random() * (t.MarkerFuzz or 0.0)
    local markerAt = vector3(pos.x + math.cos(angle) * dist, pos.y + math.sin(angle) * dist, pos.z)

    for _, lawman in ipairs(lawmen) do
        GSC.Notify.Send(lawman.src, message, 8000, "alert", Config.Text.LawTipTitle)
        TriggerClientEvent('gsc_kassippu_alert:client:CreateTempBlip', lawman.src, markerAt, nil, blipName or t.BlipName)
    end
end

---o[ Somebody saw the smoke ]o---
local function TipOff(uid, lawmen)
    local pos = GSC.Distillery.Position(uid)
    if not pos then return end

    local _, town = PlaceFactor(pos)
    local message = town and string.format(Config.Text.LawTipNotifyTown, town) or Config.Text.LawTipNotify
    TipOffAt(pos, message, lawmen)

    Shared.Debug(string.format("^1[Law]^7 Still %s reported to %d lawmen", uid, #lawmen))
end

---o[ A sale to a buyer ]o---
function Law.ReportSale(src, pos)
    local m = (Config.Market or {}).Law or {}
    local t = Conf().TipOff or {}
    if not (Conf().Enabled and m.Enabled) or not pos then return false end

    local now = os.time()
    if LastSaleTip[src] and (now - LastSaleTip[src]) < (m.CooldownMinutes or 10) * 60 then return false end

    local lawmen = Lawmen()
    if #lawmen == 0 then return false end

    local factor, town = PlaceFactor(pos)
    local chance = (m.Chance or 0.0) * factor
    if Law.IsNight() then chance = chance * (t.NightFactor or 1.0) end
    if math.random() >= math.min(t.MaxChance or 1.0, chance) then return false end

    LastSaleTip[src] = now
    local text = (Config.Text.Market or {})
    local message = town and string.format(text.LawTipTown, town) or text.LawTip
    TipOffAt(pos, message, lawmen, text.LawBlip)
    Shared.Debug(string.format("^1[Law]^7 A sale by %s reported to %d lawmen", src, #lawmen))
    return true
end

---o[ One minute's rolls, for every lit still ]o---
function Law.RollTipOffs()
    local t = Conf().TipOff or {}
    if not (Conf().Enabled and t.Enabled) then return end

    local lawmen = Lawmen()
    if #lawmen == 0 and t.NeedLawOnline ~= false then return end

    local now = os.time()
    for uid in pairs(GSC.Distillery.List()) do
        local cooled = (now - (LastTip[uid] or 0)) >= (t.CooldownMinutes or 10) * 60
        if cooled and math.random() < Law.TipChance(uid) then
            LastTip[uid] = now
            TipOff(uid, lawmen)
        end
    end
end

---oo[ The Lookout ]oo---

---o[ Is anybody keeping watch over this still? ]o---
local function HasLookout(uid, pos, keepers)
    local conf = Conf().Lookout or {}
    for _, src in ipairs(keepers) do
        if GSC.Distillery.WatchedBy(src) ~= uid then
            local dist = #(GetEntityCoords(GetPlayerPed(src)) - pos)
            if dist > (conf.PostedOutside or 0.0) and dist <= (conf.LookoutRadius or 0.0) then
                return true
            end
        end
    end
    return false
end

function Law.CheckLookouts()
    local conf = Conf().Lookout or {}
    if not (Conf().Enabled and conf.Enabled) then return end
    if next(GSC.Distillery.List()) == nil then return end

    local lawmen = Lawmen()
    if #lawmen == 0 then return end

    local now = os.time()
    local cooldown = conf.CooldownSeconds or 45

    for uid, pos in pairs(GSC.Distillery.List()) do
        local nearest = math.huge
        for _, lawman in ipairs(lawmen) do
            if GSC.BarrelCrew.Role(lawman.src, uid) == "none" then
                nearest = math.min(nearest, #(lawman.pos - pos))
            end
        end

        if nearest <= (conf.WarnRadius or 0.0) then
            local keepers = GSC.Distillery.Keepers(uid)

            if #keepers > 0 and HasLookout(uid, pos, keepers) then
                if now - (LastWarn[uid] or 0) >= cooldown then
                    LastWarn[uid] = now
                    local text = string.format(Config.Text.LookoutWarn, math.floor(nearest))
                    for _, src in ipairs(keepers) do GSC.Notify.Send(src, text, 6000) end
                end
            elseif nearest <= (conf.NoticeRadius or 0.0) then
                if now - (LastNotice[uid] or 0) >= cooldown then
                    LastNotice[uid] = now
                    for src in pairs(GSC.Distillery.Watchers(uid)) do
                        GSC.Notify.Send(src, Config.Text.LookoutNotice, 5000)
                    end
                end
            end
        end
    end
end

---oo[ The Loops ]oo---

CreateThread(function()
    while true do
        Wait(60000)
        if Conf().Enabled or (Config.Market and Config.Market.Enabled) then AskClock() end -- the market's hours need it too
        if Conf().Enabled then Law.RollTipOffs() end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(1, (Conf().Lookout or {}).CheckSeconds or 3) * 1000)
        if Conf().Enabled then Law.CheckLookouts() end
    end
end)

AddEventHandler('playerDropped', function()
    LastSaleTip[source] = nil
end)
