local Notify = GSC.module('Notify')

---oo[ The Script's Own Notifications ]oo---

local function Conf()
    return Config.Notify or {}
end

---o[ How long a note stays ]o---
local function NoteMs(text, ms)
    local conf = Conf()
    ms = tonumber(ms) or conf.DefaultMs or 4000
    if conf.ReadingTime then
        ms = math.max(ms, 1500 + #text * 45)
    end
    return math.floor(math.min(ms, tonumber(conf.MaxMs) or 8000))
end

---o[ The wax seal ]o---
function Notify.SealFor(text, kind)
    if kind == "alert" then return "law", kind end -- a dispatch is always the law's seal

    local lower = string.lower(text)
    for _, group in ipairs(Conf().Icons or {}) do
        for _, word in ipairs(group.words or {}) do
            if string.find(lower, string.lower(word), 1, true) then
                if group.kind and (kind == nil or kind == "info") then kind = group.kind end
                return group.icon or "note", kind
            end
        end
    end
    return "note", kind
end

---oo[ The Game's Right-Hand Feed (UseVorp = true) ]oo---
local FEED_SHOW_ADVANCED   = 0xB249EBCB30DD88E0
local FEED_SHOW_RIGHT_TIP  = 0xB2920B9760F0F36B
local FEED_CLEAR_MESSAGE   = 0x2F901291EF177B02
local FEED_CLEAR_CHANNEL   = 0xDD1232B332CBB9E7
local FEED_CURRENT_MESSAGE = 0xC17F69E1418CD11F

---o[ eUIFeedChannel ]o---
local FEED_CHANNELS = { 5, 6 }

---o[ Take one of our notes down ]o---
local function TakeDown(id)
    Citizen.InvokeNative(FEED_CLEAR_MESSAGE, id, true)
    for _, channel in ipairs(FEED_CHANNELS) do
        if Citizen.InvokeNative(FEED_CURRENT_MESSAGE, channel, Citizen.ResultAsInteger()) == id then
            Citizen.InvokeNative(FEED_CLEAR_CHANNEL, channel, 1, 0)
        end
    end
end

---o[ A zero-filled native struct of 8-byte slots ]o---
local function Struct(bytes, slots)
    local parts = {}
    for i = 0, (bytes // 8) - 1 do
        parts[#parts + 1] = string.pack("<i8", slots[i] or 0)
    end
    local blob = table.concat(parts)
    if #blob < 41 then blob = blob .. string.rep("\0", 41 - #blob) end -- the DataView's minimum size
    return blob
end

local function Str(text)
    return VarString(10, "LITERAL_STRING", text)
end

---o[ The icon textures stay loaded, so drawing a note never has to wait for one ]o---
local function DictReady(dict)
    if HasStreamedTextureDictLoaded(dict) then return true end
    RequestStreamedTextureDict(dict, true)
    return false
end

CreateThread(function()
    local conf = Conf()
    if not conf.UseVorp or conf.VorpStyle ~= "advanced" then return end

    local dicts = {}
    for _, ic in pairs(conf.VorpIcons or {}) do
        if ic.dict then dicts[ic.dict] = true end
    end
    dicts["generic_textures"] = true

    local untilMs = GetGameTimer() + 10000
    for dict in pairs(dicts) do
        while not DictReady(dict) and GetGameTimer() < untilMs do Wait(50) end
    end
end)

local shownId, shownUntil = nil, 0

local function FeedShow(text, ms, seal, kind)
    local conf = Conf()

    ---o[ The newest note takes the place of the one still up ]o---
    if shownId and shownId ~= 0 and GetGameTimer() < shownUntil then
        TakeDown(shownId)
        Wait(0)
    end
    shownId = nil

    local id, drawn = nil, false
    if conf.VorpStyle == "advanced" then
        local icons = conf.VorpIcons or {}
        local ic = icons[seal] or icons.note or { dict = "generic_textures", icon = "tick" }

        if DictReady(ic.dict) then
            local color = ((kind == "warning" or kind == "alert") and conf.VorpWarnColor)
                or conf.VorpColor or ic.color or "COLOR_WHITE"

            local config = Struct(8 * 7, {
                [0] = ms,
                [1] = Str("Transaction_Feed_Sounds"),
                [2] = Str("Transaction_Positive"),
            })
            local data = Struct(8 * 10, {
                [1] = Str(text),
                [2] = Str(ic.dict),
                [3] = joaat(ic.icon),
                [5] = joaat(color),
            })
            id = Citizen.InvokeNative(FEED_SHOW_ADVANCED, config, data, 1, Citizen.ResultAsInteger())
            drawn = true
        end
    end

    if not drawn then
        id = Citizen.InvokeNative(FEED_SHOW_RIGHT_TIP, Struct(8 * 7, { [0] = ms }), Struct(8 * 3, { [1] = Str(text) }), 1, Citizen.ResultAsInteger())
    end

    shownId, shownUntil = id, GetGameTimer() + ms

    if Config.DevMode then
        print(("^3[Notify]^7 feed message %s for %d ms: %s"):format(tostring(id), ms, text))
    end
end

---o[ Notes that land together become one note ]o---
local RANK = { info = 1, warning = 2, alert = 3 }
local batch = nil

local function Flush()
    local b = batch
    batch = nil
    if not b or #b.lines == 0 then return end

    local text = table.concat(b.lines, " | ")
    FeedShow(text, NoteMs(text, b.ms), b.seal, b.kind)
end

local function FeedQueue(text, ms, seal, kind)
    local conf = Conf()

    if not batch then
        batch = { lines = {}, seen = {}, ms = 0, rank = 0, seal = seal, kind = kind }
        SetTimeout(tonumber(conf.BatchMs) or 100, Flush)
    end

    if batch.seen[text] then return end
    batch.seen[text] = true

    batch.lines[#batch.lines + 1] = text
    while #batch.lines > (conf.MaxLines or 3) do table.remove(batch.lines, 1) end -- the newest lines win

    batch.ms = math.max(batch.ms, ms)

    local rank = RANK[kind or "info"] or 1
    if rank > batch.rank then
        batch.rank, batch.seal, batch.kind = rank, seal, kind
    end
end

---oo[ Show One Note ]oo---
function Notify.Show(text, ms, kind, title)
    if type(text) ~= 'string' then
        if type(text) ~= 'number' then return end
        text = tostring(text)
    end

    text = Shared.PlainText(text)
    if text == "" then return end

    local conf = Conf()
    ms = tonumber(ms) or conf.DefaultMs or 4000

    local seal
    seal, kind = Notify.SealFor(text, kind)

    if conf.UseVorp then
        local line = type(title) == 'string' and (Shared.PlainText(title) .. ": " .. text) or text
        FeedQueue(line, ms, seal, kind)
        return
    end

    SendNUIMessage({
        action = "notify",
        text = text,
        ms = NoteMs(text, ms),
        kind = (kind == "warning" or kind == "alert") and kind or "info",
        icon = seal,
        fuse = conf.Fuse ~= false,
        style = conf.Style == "paper" and "paper" or "black",
        title = type(title) == 'string' and Shared.PlainText(title) or nil,
        maxVisible = conf.MaxVisible or 4,
    })

    if conf.Sound then
        PlaySoundFrontend("SELECT", "RDRO_Character_Creator_Sounds", true, 0)
    end
end

---oo[ Placement Notes: VORP NotifyObjective ]oo---
local vorpCore = nil

function Notify.Objective(text, ms)
    if type(text) ~= 'string' then
        if type(text) ~= 'number' then return end
        text = tostring(text)
    end

    if Conf().PlacementObjective == false then return Notify.Show(text, ms) end

    text = Shared.PlainText(text)
    if text == "" then return end

    if not vorpCore then
        local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
        if ok then vorpCore = core end
    end
    if not vorpCore then return Notify.Show(text, ms) end -- vorp_core not up: never lose the note

    ms = NoteMs(text, ms)
    vorpCore.NotifyObjective(text, ms)

    if Config.DevMode then
        print(("^3[Notify]^7 objective for %d ms: %s"):format(ms, text))
    end
end

---o[ From the server (GSC.Notify.SendObjective) ]o---
RegisterNetEvent('gsc_kassippu:client:notifyObjective')
AddEventHandler('gsc_kassippu:client:notifyObjective', function(text, ms)
    Notify.Objective(text, ms)
end)

---o[ From the server (GSC.Notify.Send) ]o---
RegisterNetEvent('gsc_kassippu:client:notify')
AddEventHandler('gsc_kassippu:client:notify', function(text, ms, kind, title)
    Notify.Show(text, ms, kind, title)
end)
