Shared = {}

function Shared.Debug(...)
    if Config and Config.DevMode then
        print(...)
    end
end

function Shared.PlainText(text)
    if type(text) ~= "string" then return text end
    text = text:gsub("~%a+~", ""):gsub("%s%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Shared.GenerateTreeUID(coords)
    return string.format("climb_tree_%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

function Shared.GenerateBarrelUID(coords)
    return string.format("barrel_%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

function Shared.GenerateCrateUID(coords)
    return string.format("crate_%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

function Shared.CrateClimate(temp, sheltered)
    local conf = Config.CrateAging and Config.CrateAging.Climate
    if not conf then return nil, 1.0, 1.0 end

    local band, fallback = nil, nil
    for _, entry in ipairs(conf.Bands or {}) do
        if entry.key == conf.Fallback then fallback = entry end
        if not band and conf.Enabled and temp and temp < entry.below then band = entry end
    end
    band = band or fallback
    if not band then return nil, 1.0, 1.0 end

    local keep = band.keepRate or 1.0
    if conf.Enabled and sheltered then keep = keep * (conf.ShelterKeepRate or 1.0) end

    return band, band.ageRate or 1.0, keep
end

Shared.BarrelStage = {
    IDLE       = "IDLE",
    FREEZE     = "FREEZE",
    MIXING     = "MIXING",
    FERMENTING = "FERMENTING",
    MID_CLIMB  = "MID_CLIMB",
    HEAT_PAUSE = "HEAT_PAUSE",
    FINAL_PUSH = "FINAL_PUSH",
    BREWING    = "BREWING",
    COMPLETED  = "COMPLETED",
}

---o[ The VORP core, fetched once ]o---
local VORPcore = nil

function Shared.GetChar(src)
    VORPcore = VORPcore or exports.vorp_core:GetCore()
    local user = VORPcore.getUser(src)
    if not user then return nil end
    return user.getUsedCharacter
end

function Shared.IsLawman(Character)
    return Character ~= nil and tostring(Character.job):lower() == tostring(Config.LawJob):lower()
end

function Shared.CharId(Character)
    return tostring(Character.charIdentifier or Character.identifier)
end

function Shared.Round(num, numDecimalPlaces)
    local mult = 10 ^ (numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function Shared.TableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

---o[ Does this barrel upgrade do anything here? `requires` names a Config section that must be Enabled ]o---
function Shared.UpgradeUsable(up)
    local need = up and up.requires
    if not need then return true end
    return type(Config[need]) == 'table' and Config[need].Enabled == true
end

---o[ Is this point inside the box? ]o---
function Shared.InZone(coords, zone)
    local size = zone.size
    if not size then return false end

    local dx = math.abs(coords.x - zone.coords.x)
    local dy = math.abs(coords.y - zone.coords.y)

    return dx <= size.x and dy <= size.y
end

---o[ ...and inside it with a margin added on every side? ]o---
function Shared.InZoneWithMargin(coords, zone, margin)
    local size = zone.size
    if not size then return false end

    local dx = math.abs(coords.x - zone.coords.x)
    local dy = math.abs(coords.y - zone.coords.y)

    return dx <= (size.x + margin) and dy <= (size.y + margin)
end

---o[ Flat distance to the zone CENTRE ]o---
function Shared.ZoneCentreDistance(coords, zone)
    local dx = coords.x - zone.coords.x
    local dy = coords.y - zone.coords.y
    return math.sqrt((dx * dx) + (dy * dy))
end

---o[ The heading that faces from one point towards another ]o---
function Shared.HeadingTowards(fromX, fromY, toX, toY)
    local dx, dy = toX - fromX, toY - fromY
    return math.deg(math.atan(-dx, dy)) % 360.0
end

---o[ Guard models ]o---
function Shared.GuardModels()
    return {
        (Config.GuardSpawnConf or {}).PedModel,
        "a_m_m_armymech_01",
        "a_m_m_broadsentry_01",
        "a_m_m_laborer_01",
    }
end

---o[ The guard posts a yard gets when it does not list its own ]o---
function Shared.BuildAutoPosts(zoneData)
    local conf = Config.GuardSpawnConf or {}
    local size = zoneData.size
    if conf.AutoPosts == false or not size then return {} end

    local c = zoneData.coords
    local m = conf.AutoPostMargin or 6.0
    local hx, hy = size.x + m, size.y + m

    local spots = {
        { c.x, c.y + hy }, -- N
        { c.x + hx, c.y }, -- E
        { c.x, c.y - hy }, -- S
        { c.x - hx, c.y }, -- W
    }

    if (conf.AutoPostLayout or 4) >= 8 then
        spots[5] = { c.x + hx, c.y + hy } -- NE
        spots[6] = { c.x + hx, c.y - hy } -- SE
        spots[7] = { c.x - hx, c.y - hy } -- SW
        spots[8] = { c.x - hx, c.y + hy } -- NW
    end

    local posts = {}
    for i, s in ipairs(spots) do
        posts[i] = { x = s[1], y = s[2], heading = Shared.HeadingTowards(s[1], s[2], c.x, c.y) }
    end

    ---o[ Inside the yard ]o---
    local inner = math.floor(tonumber(zoneData.innerPosts or conf.AutoPostInner) or 0)
    for ix = 1, inner do
        for iy = 1, inner do
            local x = c.x - size.x + ((2 * ix - 1) * size.x / inner)
            local y = c.y - size.y + ((2 * iy - 1) * size.y / inner)
            local atCentre = math.abs(x - c.x) < 0.01 and math.abs(y - c.y) < 0.01
            posts[#posts + 1] = {
                x = x, y = y,
                heading = atCentre and 0.0 or Shared.HeadingTowards(x, y, c.x, c.y), -- towards the centre
            }
        end
    end

    return posts
end

---o[ The walking circuit ]o---
function Shared.BuildZonePerimeter(zone, margin, perSide)
    local size = zone.size
    if not size then return {} end

    local hx, hy = size.x + margin, size.y + margin
    local cx, cy = zone.coords.x, zone.coords.y
    perSide = math.max(1, perSide or 3)

    local corners = {
        { x = cx - hx, y = cy + hy },
        { x = cx + hx, y = cy + hy },
        { x = cx + hx, y = cy - hy },
        { x = cx - hx, y = cy - hy },
    }

    local points = {}

    for i = 1, 4 do
        local from = corners[i]
        local to = corners[(i % 4) + 1]

        for step = 0, perSide - 1 do
            local t = step / perSide
            points[#points + 1] = {
                x = from.x + ((to.x - from.x) * t),
                y = from.y + ((to.y - from.y) * t),
            }
        end
    end

    return points
end
