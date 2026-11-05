local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local storage = require("src.storage")
local history = require("src.history")
local daily = require("src.daily")
local input = require("src.input")

-- Statistics, in pages: Sudoku's per-difficulty numbers and streaks, Solo's,
-- Pairlink's and Hoshi's per size and level, and recent solves of every kind.
-- L2 / R2 (see input.lua) or left / right switch pages.
local Stats = {}
Stats.__index = Stats

local LEVELS = {
    { key = "easy", name = "Easy" },
    { key = "medium", name = "Medium" },
    { key = "hard", name = "Hard" },
    { key = "expert", name = "Expert" },
    { key = "master", name = "Master" },
}

local COLUMNS = {
    { label = "Started", x = 270 },
    { label = "Solved", x = 362 },
    { label = "Perfect", x = 454 },
    { label = "Best", x = 556 },
    { label = "Average", x = 656 },
}

-- Solo, Pairlink and Hoshi pages: a row per size and level
local GAME_LEVELS = { { "easy", "Easy" }, { "medium", "Medium" }, { "hard", "Hard" } }
local GAME_COLUMNS = {
    { label = "Started", x = 256 },
    { label = "Solved", x = 330 },
    { label = "Best", x = 412 },
    { label = "Average", x = 498 },
    { label = "Streak", x = 574 },
    { label = "Longest", x = 656 },
}
local GAME_PAGES = { Solo = "solo", Pairlink = "pairlink", Hoshi = "hoshi" }

local PAGES = { "Sudoku", "Streaks", "Solo", "Pairlink", "Hoshi", "Recent" }
local RECENT_ROWS = 8

-- `page` (optional): the page to open on, by name.
function Stats.new(app, page)
    local self = setmetatable({ app = app, t = 0, page = 1, scroll = 1 }, Stats)
    for k, name in ipairs(PAGES) do
        if name == page then self.page = k end
    end
    return self
end

function Stats:update(dt)
    self.t = self.t + dt
end

function Stats:action(a)
    local app = self.app
    if a == "b" or a == "start" then
        sound.play("close")
        app.pop()
    elseif a == "l2" or a == "left" or a == "r2" or a == "right" then
        local dir = (a == "l2" or a == "left") and -1 or 1
        self.page = (self.page - 1 + dir) % #PAGES + 1
        sound.play("menu")
    elseif PAGES[self.page] == "Recent" and (a == "up" or a == "down") then
        local maxScroll = math.max(1, #app.history - RECENT_ROWS + 1)
        local s = math.max(1, math.min(maxScroll, self.scroll + (a == "up" and -1 or 1)))
        if s ~= self.scroll then
            self.scroll = s
            sound.play("move")
        end
    elseif a == "y" then
        sound.play("open")
        local kind = GAME_PAGES[PAGES[self.page]]
        if kind then
            local name = PAGES[self.page]
            app.push("confirm", {
                title = "Reset " .. name .. " statistics?",
                body = "Solve counts, best times and streaks for every " .. name
                    .. " size and level will be cleared. Recent solves stay.",
                yes = "Reset",
                onYes = function()
                    app.puzzleStats[kind] = storage.emptyPuzzleStats(app.PUZZLES[kind].sizes)
                    app.savePuzzleStats(kind)
                end,
            })
        elseif PAGES[self.page] == "Recent" then
            app.push("confirm", {
                title = "Clear recent solves?",
                body = "The list of recent solves will be emptied. Other statistics stay.",
                yes = "Clear",
                onYes = function()
                    app.history = {}
                    app.saveHistory()
                    self.scroll = 1
                end,
            })
        else
            app.push("confirm", {
                title = "Reset Sudoku statistics?",
                body = "Solve counts, best times and streaks for every difficulty will be cleared. "
                    .. "Daily puzzle records and recent solves stay.",
                yes = "Reset",
                onYes = function()
                    app.stats = storage.emptyStats()
                    app.saveStats()
                end,
            })
        end
    end
end

-- Page names on the title row, ending at the right margin, the current one
-- underlined. They shrink, if they must, to fit beside the title.
function Stats:drawTabs()
    local function weight(k) return k == self.page and "bold" or "regular" end
    local size, gap = 20, 24
    local width = gap * (#PAGES - 1)
    for k, name in ipairs(PAGES) do width = width + ui.width(name, size, weight(k)) end
    local room = 656 - (64 + ui.width("Statistics", 36, "bold") + 28)
    local scale = math.min(1, room / width)
    size, gap = size * scale, gap * scale
    local x = 656
    for k = #PAGES, 1, -1 do
        local name, current = PAGES[k], k == self.page
        local w = ui.width(name, size, weight(k))
        x = x - w
        theme.set(current and "text" or "muted")
        ui.centered(name, x, 64, size, weight(k), "left")
        if current then
            theme.set("accent")
            ui.rect("fill", x, 78, w, 3, 1.5)
        end
        x = x - gap
    end
end

function Stats:drawPuzzles()
    local stats = self.app.stats
    local y = 126
    theme.set("muted")
    for _, col in ipairs(COLUMNS) do
        ui.centered(col.label, col.x, y, 15, "regular", "right")
    end
    theme.set("line")
    love.graphics.setLineWidth(1)
    love.graphics.line(64, y + 18, 656, y + 18)

    local totals = { started = 0, solved = 0 }
    for k, level in ipairs(LEVELS) do
        local e = stats[level.key]
        local cy = y + 18 + k * 44 - 12
        totals.started = totals.started + e.started
        totals.solved = totals.solved + e.solved

        theme.set("text")
        ui.centered(level.name, 64, cy, 22, "bold", "left")
        local values = {
            tostring(e.started),
            tostring(e.solved),
            tostring(e.perfect),
            e.best > 0 and ui.formatTime(e.best) or "None",
            e.solved > 0 and ui.formatTime(e.total / e.solved) or "None",
        }
        for c, col in ipairs(COLUMNS) do
            local empty = values[c] == "None" or values[c] == "0"
            theme.set(empty and "muted" or "text")
            ui.centered(values[c], col.x, cy, 20, "regular", "right")
        end
        theme.set("line")
        love.graphics.line(64, cy + 22, 656, cy + 22)
    end

    theme.set("muted")
    local summary
    if totals.started == 0 then
        summary = "Solve a puzzle to start filling in this table."
    else
        summary = string.format("%d of %d puzzles solved. Perfect solves had no hints and no mistakes. "
            .. "Best times only count solves without hints.", totals.solved, totals.started)
    end
    ui.text(summary, 64, 392, 16, "regular", "left", 592)
end

-- Solo, Pairlink or Hoshi: a row per size and level, grouped by size.
function Stats:drawGame(kind)
    local stats, sizes = self.app.puzzleStats[kind], self.app.PUZZLES[kind].sizes
    local y = 126
    theme.set("muted")
    for _, col in ipairs(GAME_COLUMNS) do
        ui.centered(col.label, col.x, y, 15, "regular", "right")
    end
    theme.set("line")
    love.graphics.setLineWidth(1)
    love.graphics.line(64, y + 18, 656, y + 18)

    local cy = y + 18
    local started, solved = 0, 0
    for s, size in ipairs(sizes) do
        cy = cy + (s > 1 and 8 or 0)
        for _, level in ipairs(GAME_LEVELS) do
            cy = cy + 26
            local e = stats[storage.puzzleStatsKey(size, level[1])]
            started, solved = started + e.started, solved + e.solved
            theme.set("text")
            local w = ui.centered(size .. "×" .. size, 64, cy - 12, 18, "bold", "left")
            theme.set("muted")
            ui.centered(level[2], 64 + math.max(w, 44) + 12, cy - 12, 18, "regular", "left")
            local values = {
                tostring(e.started),
                tostring(e.solved),
                e.best > 0 and ui.formatTime(e.best) or "None",
                e.solved > 0 and ui.formatTime(e.total / e.solved) or "None",
                tostring(e.streak),
                tostring(e.bestStreak),
            }
            for c, col in ipairs(GAME_COLUMNS) do
                local empty = values[c] == "None" or values[c] == "0"
                theme.set(empty and "muted" or "text")
                ui.centered(values[c], col.x, cy - 12, 17, "regular", "right")
            end
        end
        theme.set("line")
        love.graphics.line(64, cy + 4, 656, cy + 4)
    end

    theme.set("muted")
    local summary
    if started == 0 then
        summary = "Solve a puzzle to start filling in this table."
    else
        summary = string.format("%d of %d puzzles solved. A streak counts puzzles solved in a row. "
            .. "Starting a new one first ends it.", solved, started)
    end
    ui.text(summary, 64, cy + 12, 15, "regular", "left", 592)
end

function Stats:drawStreaks()
    local stats, y = self.app.stats, 126
    theme.set("muted")
    ui.centered("Current", 470, y, 15, "regular", "right")
    ui.centered("Best", 656, y, 15, "regular", "right")
    theme.set("line")
    love.graphics.setLineWidth(1)
    love.graphics.line(64, y + 18, 656, y + 18)

    local rows = {}
    for _, level in ipairs(LEVELS) do
        local e = stats[level.key]
        rows[#rows + 1] = { level.name, e.streak, e.bestStreak, "" }
    end
    local days = self.app.daily.days
    local today = daily.today()
    rows[#rows + 1] = { "Daily", today and daily.streak(days, today.key) or 0, daily.bestStreak(days), " days" }

    for k, row in ipairs(rows) do
        local cy = y + 18 + k * 38 - 12
        theme.set("text")
        ui.centered(row[1], 64, cy, 22, "bold", "left")
        for c, x in ipairs({ 470, 656 }) do
            local n = row[c + 1]
            theme.set(n > 0 and "text" or "muted")
            local unit = row[4] ~= "" and (n == 1 and " day" or " days") or ""
            ui.centered(n .. unit, x, cy, 20, "regular", "right")
        end
        theme.set("line")
        love.graphics.line(64, cy + 19, 656, cy + 19)
    end

    theme.set("muted")
    ui.text("A streak counts puzzles solved in a row. Starting a new puzzle before finishing the one "
        .. "in progress ends that difficulty's streak. The daily streak counts days in a row.",
        64, 388, 15, "regular", "left", 592)
end

function Stats:drawRecent()
    local list = self.app.history
    local y = 126
    if #list == 0 then
        theme.set("muted")
        ui.text("Solved puzzles show up here, newest first, from every game: Sudoku (generated, daily and "
            .. "pack puzzles), Solo, Pairlink and Hoshi.", 64, y, 18, "regular", "left", 592)
        return
    end
    theme.set("muted")
    ui.centered("When", 64, y, 15, "regular", "left")
    ui.centered("Puzzle", 222, y, 15, "regular", "left")
    ui.centered("Time", 520, y, 15, "regular", "right")
    theme.set("line")
    love.graphics.setLineWidth(1)
    love.graphics.line(64, y + 18, 656, y + 18)

    local now = os.time()
    local last = math.min(#list, self.scroll + RECENT_ROWS - 1)
    for k = self.scroll, last do
        local e = list[k]
        local cy = y + 18 + (k - self.scroll + 1) * 36 - 14
        theme.set("muted")
        ui.centered(history.when(e.at, now), 64, cy, 16, "regular", "left")
        theme.set("text")
        ui.centered(ui.fit(history.label(e), 270, 18, "bold"), 222, cy, 18, "bold", "left")
        ui.centered(ui.formatTime(e.time), 520, cy, 18, "regular", "right")
        local note = history.note(e)
        theme.set(note == "Perfect" and "mark" or "muted")
        ui.centered(note, 656, cy, 15, "regular", "right")
    end

    -- arrows when the list goes on above or below
    theme.set("muted")
    local ax = 24
    if self.scroll > 1 then
        love.graphics.polygon("fill", ax, y + 34, ax + 12, y + 34, ax + 6, y + 27)
    end
    if last < #list then
        local by = y + 18 + RECENT_ROWS * 36
        love.graphics.polygon("fill", ax, by - 12, ax + 12, by - 12, ax + 6, by - 5)
    end
end

function Stats:draw()
    theme.set("text")
    ui.text("Statistics", 64, 40, 36, "bold")
    self:drawTabs()

    local page = PAGES[self.page]
    if page == "Recent" then self:drawRecent()
    elseif page == "Streaks" then self:drawStreaks()
    elseif GAME_PAGES[page] then self:drawGame(GAME_PAGES[page])
    else self:drawPuzzles() end

    local reset = (PAGES[self.page] == "Recent") and "Clear" or "Reset"
    ui.hints({ { input.pair("l2"), "Pages" } }, 24, 452, "left")
    ui.hints({ { "Y", reset }, { "B", "Back" } }, 696, 452, "right")
end

return Stats
