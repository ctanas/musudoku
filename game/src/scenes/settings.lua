local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local input = require("src.input")

-- Settings, for one game at a time: the settings every game shares, and that
-- game's own. It opens for the game it was reached from (the one on the
-- title screen, or the one that's paused), so Pairlink isn't offered
-- Sudoku's notes and hints.
local Settings = {}
Settings.__index = Settings

local NAMES = { sudoku = "Sudoku", solo = "Solo", pairlink = "Pairlink", hoshi = "Hoshi" }

local SUDOKU = { sudoku = true }
local SOLO = { solo = true }
local SUDOKU_AND_SOLO = { sudoku = true, solo = true }

-- What L1 / R1 do in each game (with the default shoulder buttons)
local SHOULDER_MOVES = {
    sudoku = "jump to empty cells or change the number",
    pairlink = "jump to the next pair",
    hoshi = "jump to the next island",
}

-- `games`: the games a row is for (without it, all of them). `about` is a
-- string, or a function of the game that builds it (for button names that
-- follow the Shoulder buttons setting, and rows that differ by game).
local ROWS = {
    { key = "theme", label = "Theme", about = "Light themes: Paper, Sakura, Frankfurt, Solarized Light. Dark: Cyanotype, Solarized Dark, Nord, Gruvbox, and Chalkboard with chalk dust and a wooden frame." },
    { key = "input", label = "Input", games = SUDOKU,
      choices = { { "cell", "Cell first" }, { "number", "Number first" } },
      about = function()
          return "Cell first: pick a cell, then its number from the pad. Number first: pick a number with "
              .. input.pair("l1") .. ", then press A on each cell it goes in."
      end },
    { key = "pad", label = "Number pad", games = SUDOKU,
      choices = { { "panel", "Side panel" }, { "popup", "Pop-up" } },
      about = "Where Cell first input picks the number: the tiles in the side panel, or a pad by the cell. Distraction-free mode always uses the pad." },
    { key = "shoulders", label = "Shoulder buttons",
      choices = { { "move", "L1 / R1 move" }, { "undo", "L1 / R1 undo" } },
      about = function(game)
          local moves = SHOULDER_MOVES[game]
          if not moves then
              return "L1 / R1 move: L2 / R2 undo and redo. L1 / R1 undo: L1 / R1 undo and redo instead. One setting for every game."
          end
          return "L1 / R1 move: they " .. moves .. ", and L2 / R2 undo and redo. L1 / R1 undo: the other way round"
              .. (game == "sudoku" and ", as before version 1.3.3." or ". One setting for every game.")
      end },
    { key = "mistakes", label = "Check mistakes", games = SUDOKU, about = "Wrong numbers turn red and are counted. With this off, Check board in the pause menu says how many are wrong, for the cost of a hint." },
    { key = "matching", label = "Highlight matching numbers", games = SUDOKU_AND_SOLO,
      about = function(game)
          if game == "solo" then return "The cursor's number lights up where it repeats in its row and column." end
          return "Cells and notes with the selected number light up."
      end },
    { key = "repeats", label = "Show repeats", games = SOLO, about = "Numbers that still repeat in their row or column are tinted a soft red, until their repeats are shaded." },
    { key = "autoclear", label = "Clear notes automatically", games = SUDOKU, about = "Placing a number removes it from notes in the same row, column and box." },
    { key = "largeNotes", label = "Large notes", games = SUDOKU, about = "Bigger note digits, easier to read on a small screen." },
    { key = "hints", label = "Hints", games = SUDOKU,
      choices = { { "off", "Off" }, { "explained", "Explained" }, { "instant", "Instant" } },
      about = "Off hides the hint button. Explained shows which technique to use next and why. Instant reveals a number straight away." },
    { key = "timer", label = "Show timer", about = "The clock still runs when hidden, so best times stay fair." },
    { key = "sound", label = "Sound effects", about = "Clicks and chimes as you play." },
    { key = "audioPause", label = "Audio power saving", about = "Rests the sound hardware after 10 seconds of silence, to save battery, and wakes it for the next sound. Turn this off if sounds pop or go missing after a pause." },
    { key = "generator", label = "Puzzle generator", games = SUDOKU,
      choices = { { "classic", "Classic" }, { "dlx", "Dancing Links" } },
      about = "Both make puzzles with exactly one solution, graded the same way. Classic uses a backtracking solver, Dancing Links uses Knuth's Algorithm X." },
}

local VISIBLE = 8 -- rows on screen; the list scrolls to keep the selection in view

-- `game`: "sudoku" (the default), "solo", "pairlink" or "hoshi".
function Settings.new(app, game)
    local self = setmetatable({ app = app, t = 0, sel = 1, top = 1 }, Settings)
    self.game = NAMES[game] and game or "sudoku"
    self.rows = {}
    for _, row in ipairs(ROWS) do
        if not row.games or row.games[self.game] then self.rows[#self.rows + 1] = row end
    end
    return self
end

function Settings:scrollToSelection()
    if self.sel < self.top then self.top = self.sel end
    if self.sel > self.top + VISIBLE - 1 then self.top = self.sel - VISIBLE + 1 end
end

function Settings:update(dt)
    self.t = self.t + dt
end

function Settings:change(dir)
    local s = self.app.settings
    local row = self.rows[self.sel]
    if row.key == "theme" then
        local idx = 1
        for k, key in ipairs(theme.ORDER) do
            if key == s.theme then idx = k end
        end
        idx = (idx - 1 + dir) % #theme.ORDER + 1
        s.theme = theme.ORDER[idx]
    elseif row.choices then
        local idx = 1
        for k, c in ipairs(row.choices) do
            if c[1] == s[row.key] then idx = k end
        end
        idx = (idx - 1 + dir) % #row.choices + 1
        s[row.key] = row.choices[idx][1]
    else
        s[row.key] = not s[row.key]
    end
    self.app.applySettings()
    self.app.saveSettings()
    sound.play("note")
end

function Settings:action(a)
    local count = #self.rows
    if a == "up" then
        self.sel = (self.sel - 2) % count + 1
        self:scrollToSelection()
        sound.play("menu")
    elseif a == "down" then
        self.sel = self.sel % count + 1
        self:scrollToSelection()
        sound.play("menu")
    elseif a == "left" then
        self:change(-1)
    elseif a == "right" or a == "a" then
        self:change(1)
    elseif a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Settings:value(row)
    local v = self.app.settings[row.key]
    if row.key == "theme" then return theme.name(v) end
    if row.choices then
        for _, c in ipairs(row.choices) do
            if c[1] == v then return c[2] end
        end
    end
    return v and "On" or "Off"
end

function Settings:draw()
    local rows = self.rows
    theme.set("text")
    ui.text(NAMES[self.game] .. " settings", 64, 40, 36, "bold")

    local x, w, y0, h = 64, 592, 92, 36
    local last = math.min(#rows, self.top + VISIBLE - 1)
    for k = self.top, last do
        local row = rows[k]
        local cy = y0 + (k - self.top) * h + h / 2
        local selected = (k == self.sel)
        if selected then
            theme.set("panel")
            ui.rect("fill", x - 16, cy - h / 2 + 3, w + 32, h - 6, 8)
            theme.set("accent")
            ui.rect("fill", x - 16, cy - 10, 4, 20, 2)
        end
        theme.set(selected and "text" or "muted")
        ui.centered(row.label, x, cy, 20, selected and "bold" or "regular", "left")

        local value = self:value(row)
        local current = self.app.settings[row.key]
        local on = (row.key == "theme") or (row.choices and current ~= "off") or (not row.choices and current)
        theme.set(on and (selected and "mark" or "text") or "muted")
        local vw = ui.centered(value, x + w - 22, cy, 20, "bold", "right")
        if selected then
            theme.set("muted")
            ui.centered("<", x + w - 22 - vw - 16, cy, 18, "bold", "center")
            ui.centered(">", x + w - 6, cy, 18, "bold", "center")
        end
    end

    -- small arrows on the left when rows are scrolled out of view
    theme.set("muted")
    local ax = x - 40
    if self.top > 1 then
        love.graphics.polygon("fill", ax, y0 + 12, ax + 12, y0 + 12, ax + 6, y0 + 5)
    end
    if last < #rows then
        local by = y0 + VISIBLE * h
        love.graphics.polygon("fill", ax, by - 12, ax + 12, by - 12, ax + 6, by - 5)
    end

    local about = rows[self.sel].about
    if type(about) == "function" then about = about(self.game) end
    ui.text(about, x, y0 + (last - self.top + 1) * h + 14, 16, "regular", "left", w)

    ui.hints({ { "B", "Back" }, { "A", "Change" } }, 696, 452, "right")
end

return Settings
