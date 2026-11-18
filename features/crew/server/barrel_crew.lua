local BarrelCrew = GSC.module('BarrelCrew')

local Crews = {}
local Pending = {}
local LastInvite = {}

local function Conf()
    return Config.BarrelCrew or {}
end

local function Enabled()
    return Conf().Enabled == true
end

local function NameOf(Character)
    local name = ((Character.firstname or "") .. " " .. (Character.lastname or "")):match("^%s*(.-)%s*$")
    return name ~= "" and name or "Someone"
end

local function Notify(src, text, ms)
    if src and text then GSC.Notify.Send(src, text, ms or 4000) end
end

---o[ Online crew members of a barrel, as server IDs ]o---
function BarrelCrew.OnlineSources(uid)
    local crew = Crews[uid]
    local found = {}
    if not crew then return found end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local Character = src and Shared.GetChar(src)
        if Character and crew[Shared.CharId(Character)] then
            found[#found + 1] = src
        end
    end

    return found
end

local function CrewNames(uid)
    local names = {}
    for _, name in pairs(Crews[uid] or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

---o[ The crew's names, for the logs ]o---
function BarrelCrew.Names(uid)
    return CrewNames(uid)
end

---o[ What this player is to this barrel ]o---
function BarrelCrew.Role(src, uid)
    local Character = Shared.GetChar(src)
    if not Character then return "none" end

    if GSC.Distillery.IsOwner(Character, uid) then return "owner" end

    local crew = Crews[uid]
    if crew and crew[Shared.CharId(Character)] then return "crew" end

    return "none"
end

---o[ May this player do this to this barrel? ]o---
function BarrelCrew.Can(src, uid, action)
    if not Enabled() then return true end

    local role = BarrelCrew.Role(src, uid)
    if role == "owner" then return true end

    if not Conf().CrewOnly then return true end

    return role == "crew" and (Conf().CrewCan or {})[action] == true
end

function BarrelCrew.Allow(src, uid, action)
    if BarrelCrew.Can(src, uid, action) then return true end

    if BarrelCrew.Role(src, uid) == "crew" then
        Notify(src, Config.Text.CrewNotAllowed, 3000)
    else
        Notify(src, Config.Text.CrewNoAccess, 3000)
    end
    return false
end

---o[ Tell one player where they stand with a barrel ]o---
function BarrelCrew.SendAccess(src, uid)
    if not uid then return end

    TriggerClientEvent('gsc_kassippu:client:barrelAccess', src, uid, {
        role = Enabled() and BarrelCrew.Role(src, uid) or "owner",
        crew = CrewNames(uid),
        law = Shared.IsLawman(Shared.GetChar(src)),
    })
end

local function RefreshBarrel(uid)
    for src in pairs(GSC.Distillery.Watchers(uid)) do
        BarrelCrew.SendAccess(src, uid)
    end
end

---oo[ Persistence ]oo---

function BarrelCrew.Load(uid, raw)
    Crews[uid] = nil
    if type(raw) ~= 'string' or raw == "" then return end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' and next(decoded) ~= nil then
        Crews[uid] = decoded
    end
end

function BarrelCrew.Serialize(uid)
    local crew = Crews[uid]
    if not crew or next(crew) == nil then return nil end
    return json.encode(crew)
end

---o[ The barrel is gone: its crew and any invite to it go with it ]o---
function BarrelCrew.Forget(uid)
    Crews[uid] = nil

    for target, invite in pairs(Pending) do
        if invite.uid == uid then
            Pending[target] = nil
            TriggerClientEvent('gsc_kassippu:client:crewInviteClosed', target)
        end
    end
end

---oo[ Inviting ]oo---

---o[ The owner, within reach of their own barrel ]o---
local function OwnerAtBarrel(src, uid)
    local Character = Shared.GetChar(src)
    local barrelPos = GSC.Distillery.Position(uid)
    if not Character or not barrelPos or BarrelCrew.Role(src, uid) ~= "owner" then return nil end

    local ownerPos = GetEntityCoords(GetPlayerPed(src))
    if #(ownerPos - barrelPos) > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then return nil end

    return Character, barrelPos
end

---o[ Everyone at the barrel the owner could ask, closest first ]o---
local function Candidates(uid, ownerSrc, barrelPos)
    local radius = Conf().InviteRadius or 6.0
    local found = {}

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local watching = src and GSC.Distillery.WatchedBy(src)
        local invite = src and Pending[src]
        local askedHere = invite ~= nil and invite.uid == uid and invite.from == ownerSrc

        if src and src ~= ownerSrc and (not invite or askedHere) and not (watching and watching ~= uid)
            and Shared.GetChar(src) and BarrelCrew.Role(src, uid) == "none" then
            local dist = #(GetEntityCoords(GetPlayerPed(src)) - barrelPos)
            if dist <= radius then
                found[#found + 1] = { src = src, dist = dist, asked = askedHere }
            end
        end
    end

    table.sort(found, function(a, b) return a.dist < b.dist end)
    return found
end

---o[ The crew slip: who is in, and who is standing by to be asked ]o---
RegisterServerEvent('gsc_kassippu:server:crewRoster')
AddEventHandler('gsc_kassippu:server:crewRoster', function(uid)
    local _source = source
    if not Enabled() or type(uid) ~= 'string' then return end

    local Character, barrelPos = OwnerAtBarrel(_source, uid)
    if not Character then
        return TriggerClientEvent('gsc_kassippu:client:crewRoster', _source, uid, nil)
    end

    local nearby = {}
    for _, candidate in ipairs(Candidates(uid, _source, barrelPos)) do
        nearby[#nearby + 1] = {
            id = candidate.src,
            name = NameOf(Shared.GetChar(candidate.src)),
            asked = candidate.asked,
        }
    end

    TriggerClientEvent('gsc_kassippu:client:crewRoster', _source, uid, {
        crew = CrewNames(uid),
        max = Conf().MaxCrew or 3,
        nearby = nearby,
    })
end)

RegisterServerEvent('gsc_kassippu:server:crewInvite')
AddEventHandler('gsc_kassippu:server:crewInvite', function(uid, target)
    local _source = source
    target = tonumber(target)
    if not Enabled() or type(uid) ~= 'string' or not target then return end

    local Character, barrelPos = OwnerAtBarrel(_source, uid)
    if not Character then
        return Notify(_source, Config.Text.CrewNoAccess, 3000)
    end

    local conf = Conf()

    local now = os.time()
    if LastInvite[_source] and now - LastInvite[_source] < (conf.InviteCooldownSeconds or 5) then
        return Notify(_source, Config.Text.CrewInviteWait, 3000)
    end

    if Shared.TableCount(Crews[uid] or {}) >= (conf.MaxCrew or 3) then
        return Notify(_source, Config.Text.CrewFull, 3000)
    end

    ---o[ The one they picked must still be standing by, and not asked yet ]o---
    local stillThere = false
    for _, candidate in ipairs(Candidates(uid, _source, barrelPos)) do
        if candidate.src == target and not candidate.asked then
            stillThere = true
            break
        end
    end

    if not stillThere then
        return Notify(_source, Config.Text.CrewInviteNotThere, 4000)
    end

    local timeout = conf.InviteTimeoutSeconds or 30
    local invite = { uid = uid, from = _source, fromName = NameOf(Character) }

    Pending[target] = invite
    LastInvite[_source] = now

    TriggerClientEvent('gsc_kassippu:client:crewInvite', target, uid, invite.fromName, timeout)
    Notify(_source, string.format(Config.Text.CrewInviteSent, NameOf(Shared.GetChar(target))), 4000)

    Shared.Debug(string.format("^5[Crew]^7 (ID: %s) invited (ID: %s) to %s", _source, target, uid))

    ---o[ Nobody answered ]o---
    SetTimeout((timeout * 1000) + 500, function()
        if Pending[target] ~= invite then return end

        Pending[target] = nil
        TriggerClientEvent('gsc_kassippu:client:crewInviteClosed', target)
        Notify(target, Config.Text.CrewInviteExpired, 3000)

        local TargetChar = Shared.GetChar(target)
        Notify(invite.from, string.format(Config.Text.CrewInviteNoAnswer,
            TargetChar and NameOf(TargetChar) or "They"), 4000)
    end)
end)

---o[ The invited player answers ]o---
RegisterServerEvent('gsc_kassippu:server:crewRespond')
AddEventHandler('gsc_kassippu:server:crewRespond', function(accepted)
    local _source = source
    local invite = Pending[_source]
    if not invite then return end
    Pending[_source] = nil

    local Character = Shared.GetChar(_source)
    if not Character then return end
    local name = NameOf(Character)

    if accepted ~= true then
        return Notify(invite.from, string.format(Config.Text.CrewDeclined, name), 4000)
    end

    if not GSC.Distillery.Position(invite.uid) then
        return Notify(_source, Config.Text.CrewInviteGone, 4000)
    end

    local crew = Crews[invite.uid] or {}
    if Shared.TableCount(crew) >= (Conf().MaxCrew or 3) then
        Notify(invite.from, Config.Text.CrewFull, 3000)
        return Notify(_source, Config.Text.CrewFull, 3000)
    end

    crew[Shared.CharId(Character)] = name
    Crews[invite.uid] = crew

    GSC.Distillery.Save(invite.uid)
    RefreshBarrel(invite.uid)

    Notify(_source, string.format(Config.Text.CrewJoined, invite.fromName), 4000)
    Notify(GSC.Distillery.OwnerSource(invite.uid), string.format(Config.Text.CrewMemberJoined, name), 4000)

    Shared.Debug(string.format("^2[Crew]^7 (ID: %s) %s joined the crew of %s", _source, name, invite.uid))
end)

---o[ Leaving ]o---
RegisterServerEvent('gsc_kassippu:server:crewLeave')
AddEventHandler('gsc_kassippu:server:crewLeave', function(uid)
    local _source = source
    if not Enabled() or type(uid) ~= 'string' or not Crews[uid] then return end

    local Character = Shared.GetChar(_source)
    if not Character then return end

    local role = BarrelCrew.Role(_source, uid)

    if role == "owner" then
        local ownerName = NameOf(Character)
        for _, src in ipairs(BarrelCrew.OnlineSources(uid)) do
            Notify(src, string.format(Config.Text.CrewDismissedMember, ownerName), 4000)
        end

        Crews[uid] = nil
        Notify(_source, Config.Text.CrewDismissed, 3000)
    elseif role == "crew" then
        Crews[uid][Shared.CharId(Character)] = nil
        if next(Crews[uid]) == nil then Crews[uid] = nil end

        Notify(_source, Config.Text.CrewLeft, 3000)
        Notify(GSC.Distillery.OwnerSource(uid), string.format(Config.Text.CrewMemberLeft, NameOf(Character)), 4000)
    else
        return
    end

    GSC.Distillery.Save(uid)
    RefreshBarrel(uid)
end)

---o[ Invites die with either end of them ]o---
AddEventHandler('playerDropped', function()
    local src = source

    Pending[src] = nil
    LastInvite[src] = nil

    for target, invite in pairs(Pending) do
        if invite.from == src then
            Pending[target] = nil
            TriggerClientEvent('gsc_kassippu:client:crewInviteClosed', target)
        end
    end
end)
