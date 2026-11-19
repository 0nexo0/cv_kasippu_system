local ConfigLive = GSC.module('ConfigLive')

---oo[ Values changed in the settings panel, laid over the config files (server and every client) ]oo---

---o[ Never shown or changed by the panel ]o---
local SKIP = {
    Text = true, PromptsTxt = true, -- config/text.lua
    Webhooks = true, AdminPanel = true, -- server-only files
    Admin = true, TreeAdmin = true,     -- who is an admin
}
local SKIP_LEAF = { Ace = true, Groups = true } -- permission settings stay in the files

local MAX_STR, MAX_LIST, MAX_ROWS, MAX_DEPTH, MAX_KEY = 256, 200, 100, 12, 64

---o[ Named entries that can be added in the panel (a new recipe, its price) - each saved whole ]o---
local DICTS = { "Recipes", "Market.Base" }
local MAX_DICT, DICT_KEY = 50, "^[%a_][%w_]*$"

ConfigLive.Skip = SKIP
ConfigLive.SkipLeaf = SKIP_LEAF
ConfigLive.MaxDepth = MAX_DEPTH
ConfigLive.CacheFile = "database/config_overrides.json" -- copy of the DB rows, read at start before the DB is up
ConfigLive.StateKey = GetCurrentResourceName() .. ":config"

---oo[ What a value is ]oo---
-- bool / int / float / str / vec2-4  : one value
-- list                               : values of one kind ("wood", "hardwood")
-- rows                               : entries (tables, or vectors) - saved whole, so entries can be added / removed
-- obj                                : a group of settings, each changed on its own
local function IsArray(t)
    local n = #t
    if n == 0 then return false end
    local count = 0
    for k in pairs(t) do
        if math.type(k) ~= "integer" or k < 1 or k > n then return false end
        count = count + 1
    end
    return count == n
end

local LEAF = { bool = true, int = true, float = true, str = true }
local VEC = { vec2 = true, vec3 = true, vec4 = true }

function ConfigLive.Kind(v)
    local t = type(v)
    if t == "boolean" then return "bool" end
    if t == "number" then return math.type(v) == "integer" and "int" or "float" end
    if t == "string" then return "str" end
    if t == "vector2" then return "vec2" end
    if t == "vector3" then return "vec3" end
    if t == "vector4" then return "vec4" end
    if t ~= "table" then return nil end

    if IsArray(v) then
        local item = ConfigLive.Kind(v[1])
        if LEAF[item] then
            for i = 2, #v do
                local k = ConfigLive.Kind(v[i])
                if k ~= item then
                    if (k == "int" or k == "float") and (item == "int" or item == "float") then
                        item = "float"
                    else
                        return "obj"
                    end
                end
            end
            return "list", item
        end
        if VEC[item] or item == "obj" then
            for i = 2, #v do
                if ConfigLive.Kind(v[i]) ~= item then return "obj" end
            end
            return "rows"
        end
    end
    return "obj"
end

---o[ Lua value -> what travels (vectors as plain tables, all the way down) ]o---
function ConfigLive.Encode(v)
    local t = type(v)
    if t == "vector2" then return { __vec = 2, x = v.x, y = v.y } end
    if t == "vector3" then return { __vec = 3, x = v.x, y = v.y, z = v.z } end
    if t == "vector4" then return { __vec = 4, x = v.x, y = v.y, z = v.z, w = v.w } end
    if t == "table" then
        local out = {}
        for k, x in pairs(v) do out[k] = ConfigLive.Encode(x) end
        return out
    end
    return v
end

---oo[ The shape of a list's entries, from the file's own entries ]oo---
local Schema

local function Merge(a, b)
    if a == nil then return b end
    if b == nil then return a end
    if a.t ~= b.t then
        if (a.t == "int" or a.t == "float") and (b.t == "int" or b.t == "float") then return { t = "float" } end
        return false
    end
    if a.t == "list" and a.it ~= b.it then
        if (a.it == "int" or a.it == "float") and (b.it == "int" or b.it == "float") then return { t = "list", it = "float" } end
        return false
    end
    if a.t == "rows" then
        local item = Merge(a.item, b.item)
        if not item then return false end
        return { t = "rows", item = item }
    end
    if a.t == "obj" then
        local f = {}
        for k, s in pairs(a.f) do f[k] = s end
        for k, s in pairs(b.f) do
            local m = Merge(f[k], s)
            if m == false then return false end
            f[k] = m
        end
        return { t = "obj", f = f }
    end
    return a
end

Schema = function(v, depth)
    depth = depth or 1
    if depth > MAX_DEPTH then return nil end
    local kind, item = ConfigLive.Kind(v)
    if kind == nil then return nil end
    if LEAF[kind] or VEC[kind] then return { t = kind } end
    if kind == "list" then return { t = "list", it = item } end
    if kind == "rows" then
        local s = nil
        for _, x in ipairs(v) do
            s = Merge(s, Schema(x, depth + 1))
            if not s then return nil end
        end
        return { t = "rows", item = s }
    end
    local f = {}
    for k, x in pairs(v) do
        if type(k) == "string" and not SKIP_LEAF[k] and #k <= MAX_KEY then
            local s = Schema(x, depth + 1)
            if s then f[k] = s end
        end
    end
    return { t = "obj", f = f }
end

ConfigLive.Schema = Schema

---oo[ What arrived -> a Lua value of the kind the file has, or nil + why ]oo---
local function Finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function CoerceLeaf(kind, raw)
    if kind == "bool" then
        if type(raw) == "boolean" then return raw end
        return nil, "expected true or false"
    elseif kind == "int" then
        local n = tonumber(raw) -- hashes may arrive as "0x..." text
        local i = Finite(n) and math.tointeger(n) or nil
        if not i or i > 2 ^ 53 or i < -(2 ^ 53) then return nil, "expected a whole number" end
        return i
    elseif kind == "float" then
        local n = tonumber(raw)
        if not Finite(n) then return nil, "expected a number" end
        return n + 0.0
    elseif kind == "str" then
        if type(raw) ~= "string" then return nil, "expected text" end
        raw = raw:gsub("%c", "")
        if #raw > MAX_STR then return nil, "text is too long (" .. MAX_STR .. " max)" end
        return raw
    end
    return nil, "not editable"
end

local function CoerceVec(kind, raw)
    if type(raw) ~= "table" then return nil, "expected x / y / z" end
    local x, y, z, w = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z), tonumber(raw.w)
    if not Finite(x) or not Finite(y) then return nil, "expected numbers" end
    if kind == "vec2" then return vector2(x, y) end
    if not Finite(z) then return nil, "expected numbers" end
    if kind == "vec3" then return vector3(x, y, z) end
    if not Finite(w) then return nil, "expected numbers" end
    return vector4(x, y, z, w)
end

local function ArrayOf(raw, max)
    if type(raw) ~= "table" then return nil, "expected a list" end
    local n = #raw
    if n > max then return nil, "list is too long (" .. max .. " max)" end
    for k in pairs(raw) do
        if math.type(k) ~= "integer" and not (type(k) == "number" and math.tointeger(k)) then return nil, "expected a list" end
    end
    return n
end

local CoerceBy

CoerceBy = function(schema, raw, depth)
    depth = depth or 1
    if depth > MAX_DEPTH then return nil, "too deep" end
    local t = schema.t
    if LEAF[t] then return CoerceLeaf(t, raw) end
    if VEC[t] then return CoerceVec(t, raw) end

    if t == "list" then
        local n, err = ArrayOf(raw, MAX_LIST)
        if not n then return nil, err end
        local out = {}
        for i = 1, n do
            local v, e = CoerceLeaf(schema.it, raw[i])
            if v == nil then return nil, "item " .. i .. ": " .. tostring(e) end
            out[i] = v
        end
        return out
    end

    if t == "rows" then
        local n, err = ArrayOf(raw, MAX_ROWS)
        if not n then return nil, err end
        if n < 1 then return nil, "keep at least one entry" end
        local out = {}
        for i = 1, n do
            local v, e = CoerceBy(schema.item, raw[i], depth + 1)
            if v == nil then return nil, "entry " .. i .. ": " .. tostring(e) end
            out[i] = v
        end
        return out
    end

    if t == "dict" then
        if type(raw) ~= "table" then return nil, "expected named entries" end
        local out, n = {}, 0
        for k, x in pairs(raw) do
            if type(k) ~= "string" or #k > 32 or not k:find(DICT_KEY) then
                return nil, "bad name " .. tostring(k) .. " (letters, numbers and _ only, 32 max)"
            end
            n = n + 1
            if n > MAX_DICT then return nil, "too many entries (" .. MAX_DICT .. " max)" end
            local v, e = CoerceBy(schema.item, x, depth + 1)
            if v == nil then return nil, k .. ": " .. tostring(e) end
            out[k] = v
        end
        if n < 1 then return nil, "keep at least one entry" end
        return out
    end

    if t == "obj" then
        if type(raw) ~= "table" then return nil, "expected a group of settings" end
        local out = {}
        for k, x in pairs(raw) do
            local s = type(k) == "string" and schema.f[k] or nil
            if not s then return nil, "unknown setting " .. tostring(k) end
            local v, e = CoerceBy(s, x, depth + 1)
            if v == nil then return nil, k .. ": " .. tostring(e) end
            out[k] = v
        end
        return out
    end
    return nil, "not editable"
end

function ConfigLive.Coerce(kind, extra, raw)
    if kind == "list" then return CoerceBy({ t = "list", it = extra }, raw) end
    if kind == "rows" or kind == "dict" then return CoerceBy(extra, raw) end
    return CoerceBy({ t = kind }, raw)
end

---oo[ Paths ]oo---
-- { "Stations", "LogRack", "Capacity" } / { "Market", "Saloons" } (a whole list of entries)
function ConfigLive.CleanPath(path)
    if type(path) ~= "table" or #path < 1 or #path > MAX_DEPTH then return nil end
    local out = {}
    for i = 1, #path do
        local key = path[i]
        if type(key) == "number" then
            key = math.tointeger(key)
            if not key then return nil end
        elseif type(key) ~= "string" or key == "" or #key > MAX_KEY or SKIP_LEAF[key] then
            return nil
        end
        out[i] = key
    end
    if type(out[1]) ~= "string" or SKIP[out[1]] then return nil end
    return out
end

function ConfigLive.Key(path)
    return json.encode(path)
end

---oo[ The config files' own values, kept from before anything is laid over them ]oo---
local function DeepCopy(v)
    if type(v) ~= "table" then return v end -- vectors are values
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

local function DeepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, x in pairs(a) do
        if not DeepEqual(x, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local Defaults = {}
for key, value in pairs(Config) do
    if not SKIP[key] then Defaults[key] = DeepCopy(value) end
end

local function Walk(root, path, last)
    local node = root
    for i = 1, last do
        if type(node) ~= "table" then return nil end
        node = node[path[i]]
    end
    return node
end

local SchemaCache = {}

local DICT_PARTS = {}
for i, name in ipairs(DICTS) do
    local parts = {}
    for part in name:gmatch("[^%.]+") do parts[#parts + 1] = part end
    DICT_PARTS[i] = parts
end

---o[ Is path[1..n] one of the DICTS? ]o---
local function IsDictAt(path, n)
    for _, parts in ipairs(DICT_PARTS) do
        if #parts == n then
            local match = true
            for i = 1, n do
                if parts[i] ~= path[i] then match = false break end
            end
            if match then return true end
        end
    end
    return false
end

function ConfigLive.IsDict(path)
    return IsDictAt(path, #path)
end

---o[ The files' value at a path, its kind and its list kind / entry shape - nil unless the panel may set it ]o---
-- Inside a list of entries or named entries nothing is set on its own: the whole of it is.
function ConfigLive.Default(path)
    local node = Defaults
    for i = 1, #path do
        if type(node) ~= "table" then return nil end
        if i > 1 and (ConfigLive.Kind(node) == "rows" or IsDictAt(path, i - 1)) then return nil end
        node = node[path[i]]
    end
    if node == nil then return nil end

    if type(node) == "table" and IsDictAt(path, #path) then
        local key = ConfigLive.Key(path)
        local schema = SchemaCache[key]
        if schema == nil then
            local item = nil
            for _, x in pairs(node) do
                item = Merge(item, Schema(x))
                if not item then break end
            end
            schema = item and { t = "dict", item = item } or false
            SchemaCache[key] = schema
        end
        if not schema then return nil end
        return node, "dict", schema
    end

    local kind, item = ConfigLive.Kind(node)
    if kind == nil or kind == "obj" then return nil end
    if kind == "rows" then
        local key = ConfigLive.Key(path)
        local schema = SchemaCache[key]
        if schema == nil then
            schema = Schema(node) or false
            SchemaCache[key] = schema
        end
        if not schema then return nil end
        return node, kind, schema
    end
    return node, kind, item
end

---o[ Change Config in place (other scripts keep references to its tables) ]o---
local function SetAt(path, value, kind)
    local parent = Walk(Config, path, #path - 1)
    if type(parent) ~= "table" then return false end
    local key = path[#path]
    if (kind == "list" or kind == "rows") and type(parent[key]) == "table" then
        local list = parent[key]
        for i = #list, 1, -1 do list[i] = nil end
        for i, v in ipairs(value) do list[i] = v end
    elseif kind == "dict" and type(parent[key]) == "table" then
        local map = parent[key]
        for k in pairs(map) do
            if value[k] == nil then map[k] = nil end
        end
        for k, v in pairs(value) do map[k] = v end
    else
        parent[key] = value
    end
    return true
end

---o[ Check one change against the file; returns the clean path, the Lua value, nil + why, and the kind ]o---
function ConfigLive.Check(path, raw)
    path = ConfigLive.CleanPath(path)
    if not path then return nil, nil, "not a setting the panel can change" end
    local default, kind, extra = ConfigLive.Default(path)
    if default == nil then return nil, nil, "not a setting the panel can change" end
    local value, err = ConfigLive.Coerce(kind, extra, raw)
    if value == nil then return nil, nil, err end

    ---o[ Named entries the config file has can be changed, never removed ]o---
    if kind == "dict" then
        for k in pairs(default) do
            if value[k] == nil then return nil, nil, k .. " is in the config file and can't be removed" end
        end
    end
    return path, value, nil, kind
end

---o[ True when the value is what the file already has ]o---
function ConfigLive.IsDefault(path, value)
    local default = ConfigLive.Default(path)
    if default == nil then return false end
    return DeepEqual(default, value)
end

local Current = {} -- [key] = { path, value } as last applied

local function Restore(path)
    local default, kind = ConfigLive.Default(path)
    if default ~= nil then SetAt(path, DeepCopy(default), kind) end
end

---o[ Lay a whole set over the files: anything no longer in it goes back to the file's value ]o---
function ConfigLive.ApplyAll(map)
    map = type(map) == "table" and map or {}
    local applied = {}
    for _, entry in pairs(map) do
        if type(entry) == "table" then
            local path, value, err, kind = ConfigLive.Check(entry.path, entry.value)
            if path then
                SetAt(path, value, kind)
                local key = ConfigLive.Key(path)
                applied[key] = { path = path, value = ConfigLive.Encode(value) }
            else
                Shared.Debug("^3[Config]^7 Skipped a saved setting " .. json.encode(entry.path) .. ": " .. tostring(err))
            end
        end
    end
    for key, entry in pairs(Current) do
        if not applied[key] then Restore(entry.path) end
    end
    Current = applied
    return applied
end

function ConfigLive.Current()
    return Current
end

---o[ At start, before the other scripts read Config ]o---
do
    local initial = nil
    if IsDuplicityVersion() then
        local raw = LoadResourceFile(GetCurrentResourceName(), ConfigLive.CacheFile)
        if raw and raw ~= "" then
            local ok, decoded = pcall(json.decode, raw)
            if ok then initial = decoded end
        end
    else
        initial = GlobalState[ConfigLive.StateKey]
    end
    if type(initial) == "table" then ConfigLive.ApplyAll(initial) end
end
