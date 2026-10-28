-- Color themes. Cyanotype is the default: Prussian-blue paper with white
-- givens and mustard player digits (a nod to MustardOS). Paper is a light
-- theme for bright rooms. Walnut is a warm, low-blue theme for night play.

local theme = {}

local function hex(s)
    s = s:gsub("#", "")
    return {
        tonumber(s:sub(1, 2), 16) / 255,
        tonumber(s:sub(3, 4), 16) / 255,
        tonumber(s:sub(5, 6), 16) / 255,
    }
end

local PALETTES = {
    cyanotype = {
        name = "Cyanotype",
        bg = "#13274A",        -- screen background
        board = "#1A3361",     -- cell surface
        peer = "#21407A",      -- row, column and box of the cursor
        same = "#2C5597",      -- cells holding the same digit as the cursor
        line = "#2E4C82",      -- thin cell lines
        boxLine = "#A9C0E6",   -- thick box lines
        given = "#F4F7FB",     -- puzzle digits
        user = "#F2C14E",      -- player digits
        note = "#9DB4DB",      -- pencil marks
        error = "#FF7B6B",
        accent = "#F2C14E",    -- cursor, selections
        accentText = "#13274A",
        text = "#F4F7FB",
        muted = "#8FA6CF",
        panel = "#1A3361",
        chip = "#2C4A80",      -- button glyph fill
        chipText = "#F4F7FB",
        scrim = "#0A1630",
    },
    paper = {
        name = "Paper",
        bg = "#D9E0E8",
        board = "#F7F9FB",
        peer = "#E6ECF4",
        same = "#C9D9F1",
        line = "#C3CCD8",
        boxLine = "#2A3442",
        given = "#1E2733",
        user = "#2B57CF",
        note = "#5E6B7C",
        error = "#D23C3C",
        accent = "#2B57CF",
        accentText = "#F7F9FB",
        text = "#1E2733",
        muted = "#5E6B7C",
        panel = "#F7F9FB",
        chip = "#C3CCD8",
        chipText = "#1E2733",
        scrim = "#7D8896",
    },
    walnut = {
        name = "Walnut",
        bg = "#2B1F1A",
        board = "#35271F",
        peer = "#433126",
        same = "#5A402C",
        line = "#4C392E",
        boxLine = "#C9A27A",
        given = "#F1E4D2",
        user = "#FFB45C",
        note = "#BFA58A",
        error = "#FF8A73",
        accent = "#FFB45C",
        accentText = "#2B1F1A",
        text = "#F1E4D2",
        muted = "#A88E75",
        panel = "#35271F",
        chip = "#55402F",
        chipText = "#F1E4D2",
        scrim = "#140E0B",
    },
}

theme.ORDER = { "cyanotype", "paper", "walnut" }

local compiled = {}
for key, palette in pairs(PALETTES) do
    local c = { name = palette.name }
    for k, v in pairs(palette) do
        if k ~= "name" then c[k] = hex(v) end
    end
    compiled[key] = c
end

theme.current = compiled.cyanotype
theme.key = "cyanotype"

function theme.use(key)
    if compiled[key] then
        theme.current = compiled[key]
        theme.key = key
    end
end

function theme.name(key)
    return compiled[key] and compiled[key].name or key
end

-- Set the draw color from a theme slot, with optional alpha.
function theme.set(slot, alpha)
    local c = theme.current[slot]
    love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end

-- Blend two theme slots (t = 0 gives a, 1 gives b).
function theme.mix(a, b, t, alpha)
    local ca, cb = theme.current[a], theme.current[b]
    love.graphics.setColor(
        ca[1] + (cb[1] - ca[1]) * t,
        ca[2] + (cb[2] - ca[2]) * t,
        ca[3] + (cb[3] - ca[3]) * t,
        alpha or 1)
end

function theme.get(slot)
    return theme.current[slot]
end

return theme
