local Upkeep = GSC.module('Upkeep')

local Online = {} -- [src] = { charid, account } of the character he plays

local function Conf()
    return Config.Upkeep or {}
end

---o[ The ids a still or crate can be owned by: the character, and the account (very old stills) ]o---
local function IdsOf(Character)
    if not Character then return nil end
    return { charid = Shared.CharId(Character), account = Character.identifier and tostring(Character.identifier) or nil }
end

local function Query(sql, params)
    local p = promise.new()
    -- the last argument makes oxmysql call back on an error too (rows = nil): without it a failed
    -- query never answers and this thread (the whole upkeep sweep) waits forever
    exports.oxmysql:execute(sql, params or {}, function(rows, err)
        if err then print("^1[Database]^7 " .. tostring(err)) end
        p:resolve(rows or {})
    end, GetCurrentResourceName(), true)
    return Citizen.Await(p)
end

---o[ Stamp these owners as seen now (one statement for all) ]o---
local function MarkSeen(owners)
    if #owners == 0 then return end
    local now = os.time()
    local marks, params = {}, {}
    for _, owner in ipairs(owners) do
        marks[#marks + 1] = "(?, ?)"
        params[#params + 1] = owner
        params[#params + 1] = now
    end
    exports.oxmysql:execute("INSERT INTO gsc_kassippu_seen (owner, last_seen) VALUES " .. table.concat(marks, ", ")
        .. " ON DUPLICATE KEY UPDATE last_seen = VALUES(last_seen)", params)
end

local function IdsList(ids)
    local list = {}
    if ids then
        list[#list + 1] = ids.charid
        if ids.account and ids.account ~= ids.charid then list[#list + 1] = ids.account end
    end
    return list
end

---o[ Who is online now, and stamp them all ]o---
local function MarkOnline()
    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local ids = IdsOf(src and Shared.GetChar(src))
        if ids then
            Online[src] = ids
            for _, id in ipairs(IdsList(ids)) do list[#list + 1] = id end
        end
    end
    MarkSeen(list)
end

AddEventHandler("vorp:SelectedCharacter", function(source, character)
    if not Conf().Enabled then return end
    local ids = IdsOf(character)
    if not ids then return end
    Online[source] = ids
    MarkSeen(IdsList(ids))
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Conf().Enabled and Online[src] then MarkSeen(IdsList(Online[src])) end
    Online[src] = nil
end)

---o[ Clear the stills and crates of owners not seen for OwnerAwayDays ]o---
function Upkeep.Sweep()
    local conf = Conf()
    if not conf.Enabled then return 0 end

    local owners = {}
    for owner, n in pairs(GSC.Distillery.Owners()) do owners[owner] = { stills = n, crates = 0 } end
    for owner, n in pairs(GSC.Crates.Owners()) do
        owners[owner] = owners[owner] or { stills = 0, crates = 0 }
        owners[owner].crates = n
    end
    if next(owners) == nil then return 0 end

    local online = {}
    for _, ids in pairs(Online) do
        online[ids.charid] = true
        if ids.account then online[ids.account] = true end
    end

    local seen = {}
    for _, row in ipairs(Query("SELECT owner, last_seen FROM gsc_kassippu_seen")) do
        seen[tostring(row.owner)] = tonumber(row.last_seen) or 0
    end

    ---o[ An owner with no stamp yet (from before this existed) starts counting today: nothing goes on day one ]o---
    local unstamped = {}
    for owner in pairs(owners) do
        if not seen[owner] then unstamped[#unstamped + 1] = owner end
    end
    MarkSeen(unstamped)

    local limit = os.time() - math.max(1, tonumber(conf.OwnerAwayDays) or 14) * 86400
    local cleared = 0
    local L = Config.Text.Logs or {}

    for owner in pairs(owners) do
        if not online[owner] and seen[owner] and seen[owner] < limit then
            local stills = GSC.Distillery.ExpireOwner(owner)
            local crates = GSC.Crates.ExpireOwner(owner)
            cleared = cleared + 1

            Shared.Debug(string.format("^3[Upkeep]^7 %s last seen %d days ago: cleared %d still(s), %d crate(s)",
                owner, math.floor((os.time() - seen[owner]) / 86400), stills, crates))
            GSC.Logs.Send("admin", L.Abandoned, {
                { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(owner), raw = true },
                { name = GSC.Logs.Label("Stills"), value = tostring(stills), inline = true },
                { name = GSC.Logs.Label("Crates"), value = tostring(crates), inline = true },
            })
        end
    end

    return cleared
end

---o[ Stamp who is online every 15 min, sweep every CheckHours (first a few minutes after a start, once all is loaded) ]o---
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(1000) end
    Wait(10000)
    if Conf().Enabled then MarkOnline() end

    local nextSweep = GetGameTimer() + 5 * 60000
    while true do
        Wait(15 * 60000)
        if Conf().Enabled then
            MarkOnline()
            if GetGameTimer() >= nextSweep then
                nextSweep = GetGameTimer() + math.max(1, tonumber(Conf().CheckHours) or 6) * 3600000
                Upkeep.Sweep()
            end
        end
    end
end)
