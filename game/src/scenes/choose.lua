local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local input = require("src.input")
local storage = require("src.storage")

-- New puzzle for Solo, Pairlink or Hoshi: the board size (left / right, or
-- L1 / R1) and the level (up / down).
local Choose = {}
Choose.__index = Choose

local LEVELS = {
    solo = {
        { key = "easy", name = "Easy", about = "Spot the repeats, and the cells beside shaded ones." },
        { key = "medium", name = "Medium", about = "Also keep the unshaded cells connected." },
        { key = "hard", name = "Hard", about = "Needs trying a cell and seeing it break a rule." },
    },
    pairlink = {
        { key = "easy", name = "Easy", about = "Lines with only one way to go." },
        { key = "medium", name = "Medium", about = "Also work out which pair can reach each cell." },
        { key = "hard", name = "Hard", about = "Needs trying a line's next step and seeing it fail." },
    },
    hoshi = {
        { key = "easy", name = "Easy", about = "Count each island's bridges: some can only go one way." },
        { key = "medium", name = "Medium", about = "Also keep groups of islands from closing themselves off." },
        { key = "hard", name = "Hard", about = "Needs trying a bridge and seeing it break a rule." },
    },
}

local function indexOf(list, x, key)
    for k, v in ipairs(list) do
        if (key and v[key] or v) == x then return k end
    end
end

function Choose.new(app, kind)
    local self = setmetatable({ app = app, kind = kind, t = 0 }, Choose)
    self.info = app.PUZZLES[kind]
    self.levels = LEVELS[kind]
    -- start on the last choice, or the puzzle in progress
    local last = app.lastChoice[kind] or app.puzzles[kind] or {}
    self.size = indexOf(self.info.sizes, last.size) or 2
    self.sel = indexOf(self.levels, last.difficulty, "key") or 1
    return self
end

function Choose:update(dt)
    self.t = self.t + dt
end

function Choose:action(a)
    local app, kind = self.app, self.kind
    if a == "up" then
        self.sel = (self.sel - 2) % #self.levels + 1
        sound.play("menu")
    elseif a == "down" then
        self.sel = self.sel % #self.levels + 1
        sound.play("menu")
    elseif a == "left" or a == "right" or a == "l1" or a == "r1" then
        local dir = (a == "left" or a == "l1") and -1 or 1
        self.size = (self.size - 1 + dir) % #self.info.sizes + 1
        sound.play("note")
    elseif a == "b" then
        sound.play("close")
        app.pop()
    elseif a == "a" or a == "start" then
        local size, key = self.info.sizes[self.size], self.levels[self.sel].key
        sound.play("open")
        if app.hasPuzzle(kind) then
            app.push("confirm", {
                title = "Start a new puzzle?",
                body = "The " .. self.info.name .. " puzzle in progress will be replaced.",
                yes = "New puzzle",
                onYes = function() app.newPuzzleOf(kind, size, key) end,
            })
        else
            app.newPuzzleOf(kind, size, key)
        end
    end
end

function Choose:draw()
    theme.set("text")
    ui.text("New " .. self.info.name .. " puzzle", 64, 40, 36, "bold")

    -- board sizes, as a row of chips
    local y = 122
    theme.set("muted")
    local x = 64 + ui.centered("Board", 64, y, 20, "regular", "left") + 20
    for k, n in ipairs(self.info.sizes) do
        local label = n .. "×" .. n
        local w = ui.width(label, 20, "bold") + 28
        local selected = (k == self.size)
        theme.set(selected and "accent" or "panel")
        ui.rect("fill", x, y - 18, w, 36, 8)
        theme.set(selected and "accentText" or "muted")
        ui.centered(label, x + w / 2, y, 20, "bold", "center")
        x = x + w + 10
    end

    local size = self.info.sizes[self.size]
    local stats = self.app.puzzleStats[self.kind]
    local w, h, y0 = 592, 64, 166
    for k, level in ipairs(self.levels) do
        local ly = y0 + (k - 1) * (h + 6)
        local selected = (k == self.sel)
        if selected then
            theme.set("panel")
            ui.rect("fill", 64 - 16, ly, w + 32, h, 10)
            theme.set("accent")
            ui.rect("fill", 64 - 16, ly + 12, 5, h - 24, 2)
        end
        theme.set(selected and "text" or "muted")
        ui.centered(level.name, 64, ly + 22, 24, "bold", "left")
        theme.set("muted")
        ui.centered(level.about, 64, ly + 46, 15, "regular", "left")

        local entry = stats[storage.puzzleStatsKey(size, level.key)]
        local right
        if entry and entry.best > 0 then
            right = "Best " .. ui.formatTime(entry.best)
        elseif entry and entry.solved > 0 then
            right = entry.solved .. " solved"
        end
        if right then
            theme.set(selected and "text" or "muted")
            ui.centered(right, 64 + w, ly + 22, 18, "regular", "right")
        end
    end

    ui.hints({ { input.pair("l1"), "Size" } }, 24, 452, "left")
    ui.hints({ { "B", "Back" }, { "A", "Start" } }, 696, 452, "right")
end

return Choose
