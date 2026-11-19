local AdminPanel = GSC.module('AdminPanel')
local ConfigLive = GSC.ConfigLive

---oo[ Settings panel: change the config files in game, saved to gsc_kasippu_config ]oo---

local Overrides = {} -- [key] = { path, value } - the DB rows
local Ready = false  -- the DB has been read

local function Conf()
    return Config.AdminPanel or {}
end

local function Text()
    return (Config.Text or {}).AdminPanel or {}
end

---o[ The files the panel shows, in this order (text.lua and webhooks.lua never) ]o---
local FILES = {
    { key = "main",           path = "config/main.lua" },
    { key = "items",          path = "config/items.lua" },
    { key = "controls",       path = "config/controls.lua" },
    { key = "animations",     path = "config/animations.lua" },
    { key = "trees",          path = "config/trees.lua" },
    { key = "tree_locations", path = "config/tree_locations.lua" },
    { key = "guards",         path = "config/guards.lua" },
    { key = "recipes",        path = "config/recipes.lua" },
    { key = "still",          path = "config/still.lua" },
    { key = "crew",           path = "config/crew.lua" },
    { key = "law",            path = "config/law.lua" },
    { key = "crates",         path = "config/crates.lua" },
    { key = "tasting",        path = "config/tasting.lua" },
    { key = "market",         path = "config/market.lua" },
}
local FILE_BY_KEY = {}
for _, f in ipairs(FILES) do FILE_BY_KEY[f.key] = f end

---o[ Read only when the script starts: marked "restart" in the panel ("*" = any one key) ]o---
local RESTART = {
    "Items", "InteractKeys", "VersionCheck", "ClimbTrees", "TreeZones",
    "Radial.Command", "Radial.KeyMapping", "UiGuard.ResetCommand", "GiveCommand.Name",
    "CrateAging.ItemName", "KasiyaBarrelKitConf.KasiyaBarrelItemName", "KasiyaBarrelKitConf.KasiyaBarrelPromptsHoldTime",
    "SpentMash.Item", "Upgrades.*.item", "Recipes.*.recipeItem",
    "TreeClimbConf.ClimbMaxSteps", "TreeClimbConf.StreamDistance", "TreeClimbConf.DespawnDistance",
    "TreeClimbConf.TreeGrowingTime", "GuardSpawnConf.AlertCoolDown",
    "Market.Saloons", "Market.Traveller.Camps", -- the client keeps its buyer list from the first look
}
---o[ "A.B.C" -> { "A", "B", "C" } ]o---
local function SplitPatterns(list)
    local out = {}
    for _, pattern in ipairs(type(list) == "table" and list or {}) do
        if type(pattern) == "string" and pattern ~= "" then
            local parts = {}
            for part in pattern:gmatch("[^%.]+") do parts[#parts + 1] = part end
            out[#out + 1] = parts
        end
    end
    return out
end

---o[ Does the path start with any of these? ("*" = any one key) ]o---
local function MatchesAny(list, path)
    for _, parts in ipairs(list) do
        if #path >= #parts then
            local match = true
            for i, part in ipairs(parts) do
                if part ~= "*" and part ~= tostring(path[i]) then match = false break end
            end
            if match then return true end
        end
    end
    return false
end

local RESTART_PARTS = SplitPatterns(RESTART)

local function NeedsRestart(path)
    return MatchesAny(RESTART_PARTS, path)
end

---oo[ Config.AdminPanel.Hide / HideNamed: settings the panel never shows or changes ]oo---
local HIDE_PARTS = SplitPatterns(Conf().Hide)
local HIDE_NAMED = {}
for _, word in ipairs(Conf().HideNamed or {}) do
    if type(word) == "string" and word ~= "" then HIDE_NAMED[#HIDE_NAMED + 1] = word:lower() end
end

local function Hidden(path)
    if MatchesAny(HIDE_PARTS, path) then return true end

    ---o[ HideNamed is for names typed as text (a model, an anim): numbers and on / off stay ]o---
    local _, kind, extra = ConfigLive.Default(path)
    if not (kind == "str" or (kind == "list" and extra == "str")) then return false end
    for _, key in ipairs(path) do
        if type(key) == "string" then
            local lower = key:lower()
            for _, word in ipairs(HIDE_NAMED) do
                if lower:find(word, 1, true) then return true end
            end
        end
    end
    return false
end

AdminPanel.Hidden = Hidden

---oo[ Who may open it: Config.AdminPanel.SteamIds / CharIds only ]oo---
local function SteamHex(id)
    id = tostring(id or ""):lower():gsub("%s", "")
    if id:find("^steam:%x+$") then return id end
    if #id == 17 and id:match("^%d+$") then -- steam64
        local n = math.tointeger(tonumber(id))
        if n then return string.format("steam:%x", n) end
    end
    if id:match("^%x+$") then return "steam:" .. id end
    return nil
end

local function Allowed(src)
    local conf = Conf()
    if conf.Enabled ~= true or not src or src <= 0 then return false end

    local steam = GetPlayerIdentifierByType(src, 'steam')
    if steam then
        steam = steam:lower()
        for _, id in ipairs(conf.SteamIds or {}) do
            if SteamHex(id) == steam then return true end
        end
    end

    local Character = Shared.GetChar(src)
    local charId = Character and Character.charIdentifier
    if charId then
        for _, id in ipairs(conf.CharIds or {}) do
            if tostring(id) == tostring(charId) then return true end
        end
    end
    return false
end

function AdminPanel.Allowed(src)
    return Allowed(src)
end

local LastAsk = {}
local function TooFast(src, ms)
    local now = GetGameTimer()
    if LastAsk[src] and now - LastAsk[src] < ms then return true end
    LastAsk[src] = now
    return false
end

AddEventHandler('playerDropped', function()
    LastAsk[source] = nil
end)

---oo[ What one file looks like in the panel ]oo---

---o[ Where a key is written in the file, and the comment at the end of that line ]o---
local function FindKey(text, key, from, limit)
    if type(key) ~= "string" then return nil end
    local pattern = "%f[%w_]" .. key:gsub("%W", "%%%0") .. "%s*=[^=]"
    local pos = text:find(pattern, from)
    if not pos or pos > limit then return nil end
    return pos
end

local function LineHint(text, pos)
    if not pos then return nil end
    local lineEnd = text:find("\n", pos, true) or (#text + 1)
    local hint = text:sub(pos, lineEnd - 1):match("%-%-%-*%s*(.-)%s*$")
    if hint and hint ~= "" and not hint:find("^o+%[") then return hint end
    return nil
end

local function SectionTitle(text, pos)
    local title = nil
    for found in text:sub(1, pos):gmatch("%-%-%-o+%[%s*(.-)%s*%]o+%-%-%-") do title = found end
    return title
end

local BuildNode

local function ByFilePosition(a, b)
    if a.pos and b.pos then return a.pos < b.pos end
    if a.pos or b.pos then return a.pos ~= nil end
    return tostring(a.k) < tostring(b.k)
end

---o[ An entry's shape for the panel: its keys in file order, with their comments and RESTART marks ]o---
-- path uses "*" for "any entry", to match the RESTART list.
local function UiSchema(schema, ctx, from, path)
    local function Child(key)
        local p = { table.unpack(path) }
        p[#p + 1] = key
        return p
    end
    if schema.t == "rows" or schema.t == "dict" then
        return { t = schema.t, item = UiSchema(schema.item, ctx, from, Child("*")) }
    end
    if schema.t == "list" then return { t = "list", it = schema.it } end
    if schema.t ~= "obj" then return { t = schema.t } end

    local keys = {}
    for k in pairs(schema.f) do keys[#keys + 1] = { k = k, pos = FindKey(ctx.text, k, from, ctx.limit) } end
    table.sort(keys, ByFilePosition)

    local out = { t = "obj", f = {}, o = {}, h = {}, r = {} }
    for i, key in ipairs(keys) do
        local childPath = Child(key.k)
        out.o[i] = key.k
        out.f[key.k] = UiSchema(schema.f[key.k], ctx, key.pos or from, childPath)
        out.h[key.k] = LineHint(ctx.text, key.pos)
        if NeedsRestart(childPath) then out.r[key.k] = true end
    end
    return out
end

---o[ The children of a table, in the order the file writes them; returns them and the last place seen ]o---
local function BuildChildren(tbl, path, ctx, from, depth)
    local entries = {}
    local lastPos = from

    local n = #tbl
    local isArray = n > 0
    if isArray then
        for k in pairs(tbl) do
            if math.type(k) ~= "integer" or k < 1 or k > n then isArray = false break end
        end
    end

    if isArray then
        local cursor = from
        for i = 1, n do
            local childPath = { table.unpack(path) }
            childPath[#childPath + 1] = i
            local node, last = BuildNode(i, tbl[i], childPath, ctx, nil, cursor, depth)
            if node then entries[#entries + 1] = node end
            if last and last > cursor then cursor = last + 1 end
        end
        return entries, cursor
    end

    local keys = {}
    for k in pairs(tbl) do
        if not (type(k) == "string" and ConfigLive.SkipLeaf[k]) then
            keys[#keys + 1] = { k = k, pos = FindKey(ctx.text, k, from, ctx.limit) }
        end
    end
    table.sort(keys, ByFilePosition)

    for _, key in ipairs(keys) do
        local childPath = { table.unpack(path) }
        childPath[#childPath + 1] = key.k
        local node, last = BuildNode(key.k, tbl[key.k], childPath, ctx, key.pos, key.pos or from, depth)
        if node then entries[#entries + 1] = node end
        if key.pos and key.pos > lastPos then lastPos = key.pos end
        if last and last > lastPos then lastPos = last end
    end
    return entries, lastPos
end

BuildNode = function(key, value, path, ctx, pos, from, depth)
    if Hidden(path) then return nil end
    local kind, item = ConfigLive.Kind(value)
    if kind == nil then return nil end
    if kind == "obj" and ConfigLive.IsDict(path) then kind = "dict" end -- named entries: one unit

    local node = { k = key, t = kind, h = LineHint(ctx.text, pos) }
    if NeedsRestart(path) then node.r = true end

    if kind == "obj" then
        if depth >= ConfigLive.MaxDepth then return nil end
        local children, last = BuildChildren(value, path, ctx, from, depth + 1)
        if #children == 0 then return nil end
        node.c = children
        return node, last
    end

    ---o[ Only what the file itself has can be changed ]o---
    local default, _, extra = ConfigLive.Default(path)
    if default == nil then return nil end

    node.v = ConfigLive.Encode(value)
    if kind == "list" then node.it = item end
    if kind == "rows" or kind == "dict" then node.s = UiSchema(extra, ctx, pos or from, path) end
    if kind == "dict" then
        node.fk = {} -- the names the config file has: they can't be removed
        for k in pairs(default) do node.fk[#node.fk + 1] = k end
        table.sort(node.fk)
    end
    if Overrides[ConfigLive.Key(path)] then
        node.o = true
        node.d = ConfigLive.Encode((ConfigLive.Default(path)))
    end
    return node, pos
end

local function BuildFile(fileKey)
    local file = FILE_BY_KEY[fileKey]
    if not file then return nil end
    local text = LoadResourceFile(GetCurrentResourceName(), file.path) or ""

    ---o[ Every top-level Config.X in the file, in file order ]o---
    local tops = {}
    for pos, key in text:gmatch("()Config%.([%w_]+)%s*=[^=]") do
        local atLineStart = pos == 1 or text:sub(pos - 1, pos - 1) == "\n"
        if atLineStart and not ConfigLive.Skip[key] then tops[#tops + 1] = { key = key, pos = pos } end
    end

    local sections = {}
    for i, top in ipairs(tops) do
        local limit = tops[i + 1] and tops[i + 1].pos or #text
        local ctx = { text = text, limit = limit }
        local node = BuildNode(top.key, Config[top.key], { top.key }, ctx, top.pos, top.pos, 1)
        if node then
            node.title = SectionTitle(text, top.pos)
            sections[#sections + 1] = node
        end
    end
    return { key = fileKey, path = file.path, sections = sections }
end

---o[ The files with anything left to show (Hide can empty one, like items.lua) ]o---
local FileListCache = nil

local function FileList()
    if FileListCache then return FileListCache end
    local names = Text().Files or {}
    local list = {}
    for _, f in ipairs(FILES) do
        local data = BuildFile(f.key)
        if data and #data.sections > 0 then
            list[#list + 1] = { key = f.key, title = names[f.key] or f.key, path = f.path }
        end
    end
    FileListCache = list
    return list
end

---o[ For checks outside the game (tools/ preview) ]o---
AdminPanel.BuildFile = BuildFile
AdminPanel.FileList = FileList

local function SendFile(src, fileKey)
    local data = BuildFile(fileKey)
    if not data then return end
    TriggerLatentClientEvent('gsc_kassippu:client:cfgPanelFile', src, 100000, data)
end

---oo[ Saving ]oo---
local function AwaitQuery(sql, params)
    local p = promise.new()
    exports.oxmysql:execute(sql, params or {}, function(result, err)
        if err then print("^1[Settings]^7 " .. tostring(err)) end
        p:resolve(not err and (result or {}) or nil)
    end, GetCurrentResourceName(), true)
    return Citizen.Await(p)
end

---o[ Tell the server's own Config, every player, joiners (GlobalState) and the start-up copy ]o---
local function Publish()
    local map = ConfigLive.ApplyAll(Overrides)
    GlobalState[ConfigLive.StateKey] = map
    TriggerClientEvent('gsc_kassippu:client:cfgSync', -1, map)
    if not SaveResourceFile(GetCurrentResourceName(), ConfigLive.CacheFile, json.encode(map), -1) then
        print("^3[Settings]^7 Could not write " .. ConfigLive.CacheFile .. " - saved values still load from the DB")
    end
end

local function Describe(path)
    local parts = {}
    for i, key in ipairs(path) do parts[i] = type(key) == "number" and ("[" .. key .. "]") or key end
    return (table.concat(parts, "."):gsub("%.%[", "["))
end

local function Short(value)
    local s = json.encode(ConfigLive.Encode(value))
    if #s > 120 then s = s:sub(1, 117) .. "..." end
    return s
end

local Saving = false

RegisterServerEvent('gsc_kassippu:server:cfgPanelSave')
AddEventHandler('gsc_kassippu:server:cfgPanelSave', function(fileKey, changes)
    local _source = source
    if not Allowed(_source) then return end
    if TooFast(_source, 750) then return end
    local T = Text()
    local function Result(ok, msg, errors)
        TriggerClientEvent('gsc_kassippu:client:cfgPanelResult', _source, { ok = ok, msg = msg, errors = errors or {} })
    end

    if not Ready then return Result(false, T.NotReady or "The settings are still loading - try again in a moment.") end
    if Saving then return Result(false, T.Busy or "Another save is running - try again in a moment.") end
    if type(changes) ~= 'table' or #changes == 0 then return Result(false, T.NoChanges or "Nothing to save.") end
    if #changes > 200 then return Result(false, T.TooMany or "Too many changes at once - save in parts.") end

    ---o[ Check everything before saving anything ]o---
    local writes, errors = {}, {}
    for _, change in ipairs(changes) do
        if type(change) == 'table' then
            local cleaned = ConfigLive.CleanPath(change.path)
            if cleaned and Hidden(cleaned) then
                errors[#errors + 1] = { path = change.path, err = "hidden by Config.AdminPanel.Hide" }
            elseif change.reset == true then
                local path = cleaned
                if path and ConfigLive.Default(path) ~= nil then
                    writes[#writes + 1] = { path = path, reset = true }
                else
                    errors[#errors + 1] = { path = change.path, err = "not a setting the panel can change" }
                end
            else
                local path, value, err = ConfigLive.Check(change.path, change.value)
                if path then
                    writes[#writes + 1] = { path = path, value = value, reset = ConfigLive.IsDefault(path, value) }
                else
                    errors[#errors + 1] = { path = change.path, err = err }
                end
            end
        end
    end
    ---o[ A recipe a still is brewing right now can't go (a reset takes the panel's own recipes away too) ]o---
    for _, w in ipairs(writes) do
        if #w.path == 1 and w.path[1] == "Recipes" and GSC.Distillery and GSC.Distillery.RecipeInUse then
            local after = w.reset and ConfigLive.Default(w.path) or w.value
            for key in pairs(Config.Recipes or {}) do
                if after[key] == nil and GSC.Distillery.RecipeInUse(key) then
                    errors[#errors + 1] = { path = w.path, err = string.format(T.RecipeInUse or "%s is brewing in a still right now - remove it later", key) }
                end
            end
        end
    end

    if #errors > 0 then return Result(false, T.Invalid or "Some values are not valid - nothing was saved.", errors) end

    local Character = Shared.GetChar(_source)
    local by = Character and (tostring(Character.firstname) .. " " .. tostring(Character.lastname) .. " #" .. Shared.CharId(Character))
        or GetPlayerName(_source) or tostring(_source)

    Saving = true
    local saved, lines = 0, {}
    local okRun, runErr = pcall(function()
        for _, w in ipairs(writes) do
            local key = ConfigLive.Key(w.path)
            local ok
            if w.reset then
                ok = AwaitQuery('DELETE FROM gsc_kasippu_config WHERE path = ?', { key }) ~= nil
                if ok then Overrides[key] = nil end
            else
                local encoded = ConfigLive.Encode(w.value)
                ok = AwaitQuery([[
                    INSERT INTO gsc_kasippu_config (path, value, updated_by, updated_at) VALUES (?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE value = VALUES(value), updated_by = VALUES(updated_by), updated_at = VALUES(updated_at)
                ]], { key, json.encode({ v = encoded }), by:sub(1, 100), os.time() }) ~= nil
                if ok then Overrides[key] = { path = w.path, value = encoded } end
            end
            if ok then
                saved = saved + 1
                lines[#lines + 1] = Describe(w.path) .. " = " .. (w.reset and "(file value)" or Short(w.value))
            end
        end
    end)
    Saving = false
    if not okRun then print("^1[Settings]^7 Save failed: " .. tostring(runErr)) end

    Publish()

    if saved > 0 then
        GSC.Logs.Send("admin", T.LogTitle or "Settings changed", {
            { name = "By", value = by .. " (" .. tostring(GetPlayerName(_source)) .. ")" },
            { name = "Changes", value = table.concat(lines, "\n"):sub(1, 1000) },
        })
    end

    if saved < #writes then
        Result(false, string.format(T.PartSaved or "Saved %d of %d - see the server console.", saved, #writes))
    else
        Result(true, string.format(T.Saved or "Saved %d change(s).", saved))
    end
    if FILE_BY_KEY[fileKey] then SendFile(_source, fileKey) end
end)

---oo[ Opening it ]oo---
RegisterServerEvent('gsc_kassippu:server:cfgPanelFile')
AddEventHandler('gsc_kassippu:server:cfgPanelFile', function(fileKey)
    local _source = source
    if not Allowed(_source) or TooFast(_source, 300) then return end
    if FILE_BY_KEY[fileKey] then SendFile(_source, fileKey) end
end)

CreateThread(function()
    local name = Conf().Command
    if Conf().Enabled ~= true or type(name) ~= "string" or name == "" then return end

    RegisterCommand(name, function(source)
        local _source = source
        if _source == 0 then return print("[kasippu] /" .. name .. " is used in game.") end
        if not Allowed(_source) then
            return GSC.Notify.Send(_source, Config.Text.AdminNoAccess, 3000)
        end
        TriggerClientEvent('gsc_kassippu:client:cfgPanelOpen', _source, { files = FileList(), file = FILES[1].key })
    end, false)
end)

---oo[ Every player gets the saved values (late joiners also read GlobalState at start) ]oo---
local LastSync = {}

AddEventHandler('playerDropped', function()
    LastSync[source] = nil
end)

RegisterServerEvent('gsc_kassippu:server:cfgSyncRequest')
AddEventHandler('gsc_kassippu:server:cfgSyncRequest', function()
    local _source = source
    local now = GetGameTimer()
    if LastSync[_source] and now - LastSync[_source] < 10000 then return end
    LastSync[_source] = now
    TriggerClientEvent('gsc_kassippu:client:cfgSync', _source, ConfigLive.Current())
end)

---oo[ The DB is the truth: read it once the tables exist ]oo---
CreateThread(function()
    local waited = 0
    while not (GSC.Distillery and GSC.Distillery.TablesReady) and waited < 60000 do
        Wait(250)
        waited = waited + 250
    end

    local rows = AwaitQuery('SELECT path, value FROM gsc_kasippu_config', {})
    if not rows then
        print("^1[Settings]^7 Could not read gsc_kasippu_config - using " .. ConfigLive.CacheFile .. " for now")
        GlobalState[ConfigLive.StateKey] = ConfigLive.Current()
        return
    end

    Overrides = {}
    local hiddenRows = 0
    for _, row in ipairs(rows) do
        local okPath, path = pcall(json.decode, row.path)
        local okValue, wrapped = pcall(json.decode, row.value)
        if okPath and okValue and type(wrapped) == 'table' then
            path = ConfigLive.CleanPath(path)
            if path and Hidden(path) then
                hiddenRows = hiddenRows + 1 -- hidden later on: the file's value wins again
            elseif path then
                Overrides[ConfigLive.Key(path)] = { path = path, value = wrapped.v }
            end
        end
    end
    if hiddenRows > 0 then
        print(string.format("^3[Settings]^7 %d saved setting(s) ignored: now in Config.AdminPanel.Hide (the file's value is used)", hiddenRows))
    end
    Ready = true
    Publish()
    if next(Overrides) then
        print(string.format("^2[Settings]^7 %d setting(s) from the panel laid over the config files", Shared.TableCount(Overrides)))
    end
end)
