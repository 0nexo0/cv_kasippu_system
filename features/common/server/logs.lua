local Logs = GSC.module('Logs')

---oo[ Discord Logs (server only) ]oo---
-- Staff get a record of what causes disputes or hides cheating: explosions, thefts, the law,
-- crate lock-picks and admin actions. GSC.Logs.Send is a plain server function - never a net
-- event - so no client can write a log line.
--
-- The webhook comes only from server-side sources (the shared config/*.lua is sent to every player):
--   config/webhooks.lua (a server_script, never sent to players): Config.Webhooks.Main / .<category>
--   or a server convar, which wins over the file:
--   set gsc_kasippu_webhook "https://discord.com/api/webhooks/..."
--   set gsc_kasippu_webhook_<category> "..."  (optional: explosion / theft / law / lockpick / admin / market)
--
-- Lines are queued per webhook and sent up to 10 at a time every 2 s (Discord's limits), a
-- "slow down" (429) is waited out, and nothing in a message can ping anyone.

local COLORS = {
    explosion = 0xC0392B, -- fire red
    theft     = 0xD9822B, -- ember
    law       = 0x7A1E14, -- dried blood
    lockpick  = 0x8E6B3A, -- brass
    admin     = 0x4D7385, -- slate blue
    market    = 0x3F7A4A, -- money green
}
local BATCH = 10        -- embeds per Discord message (Discord's limit)
local QUEUE_MAX = 50    -- lines kept waiting per webhook; past that the oldest go
local FLUSH_MS = 2000   -- one message per webhook at most this often

local queues = {} -- [url] = { items = { embed... }, waitUntil = ms, busy = bool }

local function Conf()
    return Config.Logs or {}
end

local function T()
    return (Config.Text or {}).Logs or {}
end

---o[ A field label from Config.Text.Logs.Fields ]o---
function Logs.Label(key)
    return ((T().Fields or {})[key]) or key
end

---o[ The webhook for a category: its own convar, else the main one (a bad override never mutes it) ]o---
local function Valid(url)
    return url ~= nil and url:match('^https://') ~= nil
end

-- Order: group convar -> group in config/webhooks.lua -> main convar -> Main in config/webhooks.lua
local function WebhookFor(category)
    local hooks = Config.Webhooks or {}
    local key = tostring(category)
    local candidates = {
        GetConvar('gsc_kasippu_webhook_' .. key, ''),
        hooks[key],
        GetConvar('gsc_kasippu_webhook', ''),
        hooks.Main,
    }
    for i = 1, 4 do -- fixed count: a missing entry is nil, and # is unreliable with gaps
        local url = candidates[i]
        if type(url) == 'string' and Valid(url) then return url end
    end
    return nil
end

---o[ Text that cannot ping, break the layout or run too long ]o---
local function Clean(value, max)
    local s = tostring(value == nil and "-" or value)
    s = s:gsub("@", "@\u{200B}")              -- @everyone, <@id>, <@&role>: all broken
    s = s:gsub("`", "'")                       -- no code blocks
    s = s:gsub("([%*_~|%[%]\\>])", "\\%1")     -- no markdown tricks
    max = max or 1000
    if #s > max then
        local ok, cut = pcall(utf8.offset, s, 0, max - 2) -- start of the letter holding that byte: never cut one in half
        s = s:sub(1, (ok and cut and cut - 1) or (max - 3)) .. "..."
    end
    return s ~= "" and s or "-"
end
Logs.Clean = Clean

local function CharName(Character)
    if not Character then return "?" end
    local name = ((Character.firstname or "") .. " " .. (Character.lastname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or "?"
end

---o[ Who did it: character, server id, account, character and Discord ids ]o---
function Logs.Player(src)
    src = tonumber(src)
    if not src or src <= 0 then return T().Console or "Server console" end

    local Character = Shared.GetChar(src)
    local lines = {
        string.format("**%s** (id %d)", Clean(CharName(Character), 100), src),
        "Account: " .. Clean(GetPlayerName(src) or "?", 100),
    }
    if Character then
        lines[#lines + 1] = "Char: " .. Clean(Shared.CharId(Character), 60) .. " · " .. Clean(Character.identifier, 80)
    end
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == "discord:" then lines[#lines + 1] = "Discord: " .. Clean(id:sub(9), 40) end
    end
    return table.concat(lines, "\n")
end

---o[ An owner (character id string): their name if they are on, else marked offline ]o---
function Logs.Owner(ownerId)
    if not ownerId or ownerId == "" or ownerId == "Unknown" then return "-" end
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local Character = src and Shared.GetChar(src)
        if Character and (Shared.CharId(Character) == ownerId or Character.identifier == ownerId) then
            return string.format("**%s** (id %d) · %s", Clean(CharName(Character), 100), src, Clean(ownerId, 60))
        end
    end
    return string.format("%s · %s", Clean(T().Offline or "offline", 20), Clean(ownerId, 60))
end

---o[ A position, for a map look-up ]o---
function Logs.Where(pos)
    if not pos or not pos.x then return "-" end
    return string.format("%.1f, %.1f, %.1f", pos.x, pos.y, pos.z or 0.0)
end

---o[ One log line. fields = { { name =, value =, inline =, raw = } } - raw: value is already safe ]o---
function Logs.Send(category, title, fields)
    local conf = Conf()
    if conf.Enabled == false or (conf.Events or {})[category] == false then return end

    title = tostring(title or category)

    if conf.Console ~= false then
        local parts = {}
        for _, f in ipairs(fields or {}) do
            parts[#parts + 1] = tostring(f.name) .. "=" .. (tostring(f.value):gsub("%*%*", ""):gsub("\n", " | "))
        end
        print(string.format("^3[Kasippu log]^7 [%s] %s - %s", category, title, table.concat(parts, "; ")))
    end

    local url = WebhookFor(category)
    if not url then return end

    local embed = {
        title = Clean(title, 250),
        color = COLORS[category] or 0x6B5434,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        footer = { text = Clean(((conf.ServerName and conf.ServerName ~= "") and conf.ServerName or "Kasippu") .. " · " .. category, 200) },
    }

    local list = {}
    for i, f in ipairs(fields or {}) do
        if i > 25 then break end -- Discord's limit per embed
        list[#list + 1] = {
            name = Clean(f.name, 250),
            value = f.raw and tostring(f.value or "-") or Clean(f.value, 1000),
            inline = f.inline == true,
        }
    end
    if #list > 0 then embed.fields = list end -- (an empty table would encode as an object, not a list)

    local q = queues[url]
    if not q then
        q = { items = {}, waitUntil = 0, busy = false }
        queues[url] = q
    end
    q.items[#q.items + 1] = embed
    while #q.items > QUEUE_MAX do table.remove(q.items, 1) end
end

---o[ Post up to BATCH waiting lines in one message ]o---
local function Post(url, q)
    local batch = {}
    for i = 1, math.min(BATCH, #q.items) do batch[i] = table.remove(q.items, 1) end

    local conf = Conf()
    local payload = json.encode({
        username = Clean(conf.Username or "Kasippu Logs", 80),
        avatar_url = (conf.Avatar and conf.Avatar ~= "") and conf.Avatar or nil,
        embeds = batch,
    })
    -- no pings, written by hand so it is a real empty list whatever the JSON library does with {}
    payload = payload:sub(1, -2) .. ',"allowed_mentions":{"parse":[]}}'

    q.busy = true
    PerformHttpRequest(url, function(status, body)
        q.busy = false
        status = tonumber(status) or 0

        if status == 429 then
            -- slow down: wait as long as Discord says, then send this batch again first
            local ok, data = pcall(json.decode, body or "")
            local wait = (ok and type(data) == 'table' and tonumber(data.retry_after)) or 2
            if wait > 100 then wait = wait / 1000 end -- some API versions answer in ms
            q.waitUntil = GetGameTimer() + math.ceil(wait * 1000) + 250
            for i = #batch, 1, -1 do table.insert(q.items, 1, batch[i]) end
            while #q.items > QUEUE_MAX do table.remove(q.items) end
        elseif status < 200 or status >= 300 then
            -- a bad webhook or payload: say so once per failure, and drop the batch (no endless retries)
            print(string.format("^1[Kasippu log]^7 Discord answered %d - check the URL in config/webhooks.lua (or the gsc_kasippu_webhook convar)", status))
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

function Logs.Flush(now)
    now = now or GetGameTimer()
    for url, q in pairs(queues) do
        if #q.items > 0 and not q.busy and now >= q.waitUntil then Post(url, q) end
    end
end

CreateThread(function()
    Wait(2000)
    if Conf().Enabled ~= false then
        local any = false
        for category in pairs(COLORS) do any = any or WebhookFor(category) ~= nil end
        if not any then
            print('^3[Kasippu]^7 Discord logs: no webhook set - paste it into config/webhooks.lua (Main = "https://discord.com/api/webhooks/...")')
        end
    end

    while true do
        Wait(FLUSH_MS)
        if next(queues) ~= nil then Logs.Flush() end
    end
end)
