local Admin = GSC.module('Admin')

local VORPcore = exports.vorp_core:GetCore()

---o[ Does this player pass one permission block? ]o---
local function Passes(src, conf)
    if type(conf) ~= 'table' then return false end
    if conf.Ace and IsPlayerAceAllowed(src, conf.Ace) then return true end

    local user = VORPcore.getUser(src)
    local accountGroup = user and user.getGroup
    local Character = Shared.GetChar(src)

    for _, group in ipairs(conf.Groups or {}) do
        if group == accountGroup or (Character and group == Character.group) then return true end
    end
    return false
end

---o[ Is this player an admin? The console always is. ]o---
function Admin.Is(src, conf)
    if src == 0 then return true end
    return Passes(src, Config.Admin) or Passes(src, conf)
end

---o[ Commands that act on the admin's own game ]o---
local CLIENT_COMMANDS = { "clearguards", "treeview", "toggledebugzones", "cleartrees", "reloadtrees" }

for _, name in ipairs(CLIENT_COMMANDS) do
    RegisterCommand(name, function(source)
        local _source = source
        if _source == 0 then return print("[kasippu] /" .. name .. " is used in game.") end
        if not Admin.Is(_source) then
            return GSC.Notify.Send(_source, Config.Text.AdminNoAccess, 3000)
        end
        if name == "clearguards" then GSC.Roster.ResetAll() end
        TriggerClientEvent('gsc_kassippu:client:adminCommand', _source, name)
    end, false)
end
