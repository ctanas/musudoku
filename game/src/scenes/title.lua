local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local daily = require("src.daily")
local input = require("src.input")

local Title = {}
Title.__index = Title

local DIFFICULTY_NAMES = { easy = "Easy", medium = "Medium", hard = "Hard", expert = "Expert", master = "Master" }

-- The games, in order. Each has a box on the left, two by two, showing a
-- small picture of it. Left / right (or L1 / R1) pick one, and the choice
-- is remembered; the chosen box plays a short demo of its game.
local GAMES = { { "sudoku", "Sudoku" }, { "solo", "Solo" }, { "pairlink", "Pairlink" }, { "hoshi", "Hoshi" } }

local CELL = 40                 -- a box is three cells across
local BOX = CELL * 3
local BOXES_X, BOXES_Y = 40, 78 -- the first box's top-left corner
local GAP_X, GAP_Y = 30, 52     -- between boxes (each name goes under its box)
local DEMO_TIME = 2.6
local STILL = 99                -- a moment after every demo has finished

-- Sudoku: givens appear, then the cursor fills the remaining cells, the way
-- a player would.
local SUDOKU_BOX = { 5, 2, 8, 6, 1, 4, 3, 7, 9 }
local GIVEN = { true, false, true, false, true, false, true, false, true }
local FILL_ORDER = { 2, 6, 4, 8 }

-- Solo: the corner 1 must be shaded (keeping it would shade both its
-- neighbours and cut it off), then the 1s beside it are kept.
local SOLO_BOX = { 1, 1, 2, 1, 2, 3, 2, 3, 1 }
local SOLO_SHADE, SOLO_KEEP = 1, { 2, 4 }

-- Pairlink: two lines that fill the box.
local PAIR_CLUES = { 1, 2, 0, 0, 2, 0, 0, 0, 1 }
local PAIR_LINES = { { 1, 4, 7, 8, 9 }, { 2, 3, 6, 5 } }
local PAIR_START = { 0.6, 1.3 } -- when each line starts drawing
local PAIR_STEP = 0.12          -- per cell

-- Hoshi: four islands at the corners. The top two take a double bridge, then
-- each side one. Each bridge is { from, to, side (for a double's two
-- lines), when it starts reaching across }.
local HOSHI_CLUES = { 3, 0, 3, 0, 0, 0, 1, 0, 1 }
local HOSHI_BRIDGES = { { 1, 3, -1, 0.8 }, { 1, 3, 1, 1.1 }, { 1, 7, 0, 1.45 }, { 3, 9, 0, 1.75 } }
local HOSHI_GROW = 0.18

function Title.new(app)
    local self = setmetatable({ app = app, t = 0, sel = 1 }, Title)
    self:build()
    return self
end

function Title:gameIndex()
    for k, game in ipairs(GAMES) do
        if game[1] == self.app.settings.game then return k end
    end
    return 1
end

function Title:build()
    local app = self.app
    local game = app.settings.game
    self.items = {}
    if game == "sudoku" then
        if app.hasGame() then
            local g = app.game
            local where = g.pack and (g.pack.name .. " " .. ui.number(g.pack.index)) or DIFFICULTY_NAMES[g.difficulty]
            if g.daily then where = "Daily puzzle" end
            self.items[#self.items + 1] = {
                label = "Continue",
                detail = where .. ", " .. ui.formatTime(g.elapsed),
                run = function() app.setScene("play") end,
            }
        end
        self.items[#self.items + 1] = { label = "New puzzle", run = function() app.push("difficulty") end }
        self.items[#self.items + 1] = { label = "Daily puzzle", detail = self:dailyDetail(), run = app.openDaily }
        self.items[#self.items + 1] = { label = "Puzzle packs", run = function() app.push("packs") end }
        self.items[#self.items + 1] = { label = "Statistics", run = function() app.push("stats") end }
    else
        local info = app.PUZZLES[game]
        if app.hasPuzzle(game) then
            local g = app.puzzles[game]
            self.items[#self.items + 1] = {
                label = "Continue",
                detail = g.size .. "×" .. g.size .. " " .. DIFFICULTY_NAMES[g.difficulty] .. ", "
                    .. ui.formatTime(g.elapsed),
                run = function() app.setScene(info.scene) end,
            }
        end
        self.items[#self.items + 1] = { label = "New puzzle", run = function() app.push("choose", game) end }
        self.items[#self.items + 1] = { label = "Statistics", run = function() app.push("stats", info.name) end }
    end
    self.items[#self.items + 1] = { label = "Settings", run = function() app.push("settings") end }
    self.items[#self.items + 1] = { label = "About", run = function() app.push("about") end }
    self.items[#self.items + 1] = { label = "Quit", run = function() app.quit() end }
    self.sel = math.min(self.sel, #self.items)
end

function Title:dailyDetail()
    local app = self.app
    local today = daily.today()
    if not today then return "Set the date first" end
    local streak = daily.streak(app.daily.days, today.key)
    local suffix = streak > 1 and (", " .. streak .. "-day streak") or ""
    if app.daily.days[today.key] then return "Solved" .. suffix end
    if app.game and app.game.daily == today.key and not app.game.solved then return "In progress" .. suffix end
    return DIFFICULTY_NAMES[today.difficulty] .. suffix
end

function Title:resume()
    self:build()
end

function Title:update(dt)
    self.t = self.t + dt
end

function Title:busy()
    return self.t < DEMO_TIME -- the chosen box's demo plays once
end

function Title:switchGame(dir)
    local k = (self:gameIndex() - 1 + dir) % #GAMES + 1
    self.app.settings.game = GAMES[k][1]
    self.app.saveSettings()
    self.sel, self.t = 1, 0
    self:build()
    sound.play("note")
end

function Title:action(a)
    if a == "up" then
        self.sel = (self.sel - 2) % #self.items + 1
        sound.play("menu")
    elseif a == "down" then
        self.sel = self.sel % #self.items + 1
        sound.play("menu")
    elseif a == "left" or a == "l1" then
        self:switchGame(-1)
    elseif a == "right" or a == "r1" then
        self:switchGame(1)
    elseif a == "a" or a == "start" then
        sound.play("open")
        self.items[self.sel].run()
    end
end

-- Demos -----------------------------------------------------------------------
-- Each draws its game's box at (bx, by) as it looks `t` seconds into the
-- demo, with the demo's cursor if `cursor` is set.

local bx, by = 0, 0 -- the box being drawn

local function cellXY(i)
    return bx + ((i - 1) % 3) * CELL, by + math.floor((i - 1) / 3) * CELL
end

local function cellCenter(i)
    local x, y = cellXY(i)
    return x + CELL / 2, y + CELL / 2
end

-- The box's surface, grid (unless `noGrid`) and border, around `inside`
-- (drawn under the grid).
local function drawFrame(inside, noGrid)
    theme.set("board")
    ui.rect("fill", bx, by, BOX, BOX, 8)
    if inside then inside() end
    if not noGrid then
        theme.set("line")
        love.graphics.setLineWidth(1.5)
        for k = 1, 2 do
            love.graphics.line(bx + k * CELL, by, bx + k * CELL, by + BOX)
            love.graphics.line(bx, by + k * CELL, bx + BOX, by + k * CELL)
        end
    end
    theme.set("boxLine")
    love.graphics.setLineWidth(2.5)
    ui.rect("line", bx, by, BOX, BOX, 8)
end

local function drawCursorAt(i)
    local x, y = cellXY(i)
    theme.set("mark")
    love.graphics.setLineWidth(2.5)
    ui.rect("line", x + 3, y + 3, CELL - 6, CELL - 6, 5)
end

-- A number popping in at time `at` (bigger at first unless `still`).
local function drawPopIn(str, i, t, at, slot, still, size)
    if t < at then return end
    local p = ui.ease((t - at) / 0.25)
    local cx, cy = cellCenter(i)
    theme.set(slot, p)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(still and 1 or (1 + 0.25 * (1 - p)))
    ui.centered(str, 0, 0, size or math.floor(CELL * 0.6), "bold", "center")
    love.graphics.pop()
end

-- When each Sudoku cell appears, and where the demo cursor is.
local function sudokuState(t)
    local appear = {}
    local k = 0
    for i = 1, 9 do
        if GIVEN[i] then
            appear[i] = 0.15 + k * 0.06
            k = k + 1
        end
    end
    local cursorAt = 5
    for n, i in ipairs(FILL_ORDER) do
        local at = 0.75 + (n - 1) * 0.32
        appear[i] = at + 0.12
        if t >= at then cursorAt = i end
    end
    return appear, cursorAt
end

local function drawSudokuBox(t, cursor)
    local appear, cursorAt = sudokuState(t)
    drawFrame(function()
        if cursor then
            local x, y = cellXY(cursorAt)
            theme.set("peer")
            ui.rect("fill", x, y, CELL, CELL, 0)
        end
    end)
    for i = 1, 9 do
        drawPopIn(tostring(SUDOKU_BOX[i]), i, t, appear[i], GIVEN[i] and "given" or "user", GIVEN[i])
    end
    if cursor then drawCursorAt(cursorAt) end
end

local function drawSoloBox(t, cursor)
    local shadeAt, keepAt = 0.9, { 1.35, 1.65 }
    local shade = t >= shadeAt and ui.ease((t - shadeAt) / 0.2) or 0
    drawFrame(function()
        if shade > 0 then
            local x, y = cellXY(SOLO_SHADE)
            local inset = (1 - shade) * CELL / 2
            theme.set("shade")
            ui.rect("fill", x + inset, y + inset, CELL - inset * 2, CELL - inset * 2, 3)
        end
    end)
    for i = 1, 9 do
        -- the shaded cell's number goes once the black has covered it
        if not (i == SOLO_SHADE and shade >= 1) then
            drawPopIn(tostring(SOLO_BOX[i]), i, t, 0.15 + (i - 1) * 0.05, "given", true)
        end
    end
    local cursorAt = SOLO_SHADE
    for n, i in ipairs(SOLO_KEEP) do
        if t >= keepAt[n] - 0.15 then cursorAt = i end
        if t >= keepAt[n] then
            local cx, cy = cellCenter(i)
            theme.set("mark", 0.9 * ui.ease((t - keepAt[n]) / 0.2))
            love.graphics.setLineWidth(2.5)
            love.graphics.circle("line", cx, cy, CELL * 0.36)
        end
    end
    if cursor and t >= 0.6 then drawCursorAt(cursorAt) end
end

local function drawPairBox(t, cursor)
    local width = math.floor(CELL * 0.14)
    local drawn, head = {}, nil
    for k, line in ipairs(PAIR_LINES) do
        local steps = math.floor((t - PAIR_START[k]) / PAIR_STEP)
        drawn[k] = math.max(0, math.min(#line - 1, steps)) + 1
        if t >= PAIR_START[k] then head = line[drawn[k]] end
    end
    drawFrame(function()
        for k, line in ipairs(PAIR_LINES) do
            if t >= PAIR_START[k] then
                for s = 1, drawn[k] do
                    local x, y = cellXY(line[s])
                    theme.setLine(k, 0.16)
                    ui.rect("fill", x, y, CELL, CELL, 0)
                end
            end
        end
    end)
    love.graphics.setLineWidth(width)
    for k, line in ipairs(PAIR_LINES) do
        if t >= PAIR_START[k] and drawn[k] >= 2 then
            theme.setLine(k)
            local points = {}
            for s = 1, drawn[k] do
                local cx, cy = cellCenter(line[s])
                points[#points + 1] = cx
                points[#points + 1] = cy
            end
            love.graphics.line(points)
            for p = 1, #points, 2 do love.graphics.circle("fill", points[p], points[p + 1], width / 2) end
        end
    end
    for i = 1, 9 do
        local k = PAIR_CLUES[i]
        local at = 0.15 + (i - 1) * 0.04
        if k ~= 0 and t >= at then
            local cx, cy = cellCenter(i)
            local p = ui.ease((t - at) / 0.25)
            -- a pop and a square ring when the line arrives
            local line = PAIR_LINES[k]
            local linkAt = PAIR_START[k] + (#line - 1) * PAIR_STEP
            local scale = 1
            if t >= linkAt then
                local pop, q = (t - linkAt) / 0.25, (t - linkAt) / 0.45
                if pop < 1 then scale = 1 + 0.14 * math.sin(math.pi * pop) end
                if q < 1 then
                    local half = CELL / 2 + 2 + 10 * ui.ease(q)
                    theme.setLine(k, 0.8 * (1 - q) ^ 2)
                    love.graphics.setLineWidth(2.5)
                    ui.rect("line", cx - half, cy - half, half * 2, half * 2, 5)
                end
            end
            local half = (CELL / 2 - 1) * scale
            theme.setLine(k, p)
            ui.rect("fill", cx - half, cy - half, half * 2, half * 2, 3)
            theme.set("board", p)
            ui.centered(tostring(k), cx, cy, math.floor(CELL * 0.5), "bold", "center")
        end
    end
    if cursor and head then drawCursorAt(head) end
end

local function drawHoshiBox(t, cursor)
    drawFrame(nil, true)
    theme.set("line")
    for i = 1, 9 do
        if HOSHI_CLUES[i] == 0 then
            local cx, cy = cellCenter(i)
            love.graphics.circle("fill", cx, cy, 2)
        end
    end

    -- bridges reach across from their first island; each island counts
    -- the ones that have arrived
    local arrived, lastAt = {}, {}
    local gap = math.floor(CELL * 0.16)
    love.graphics.setLineWidth(math.max(3, math.floor(CELL * 0.09)))
    theme.set("user")
    for _, b in ipairs(HOSHI_BRIDGES) do
        local from, to, side, at = b[1], b[2], b[3], b[4]
        if t >= at then
            local p = ui.ease(math.min(1, (t - at) / HOSHI_GROW))
            local x1, y1 = cellCenter(from)
            local x2, y2 = cellCenter(to)
            local ox, oy = 0, 0
            if y1 == y2 then oy = side * gap / 2 else ox = side * gap / 2 end
            love.graphics.line(x1 + ox, y1 + oy, x1 + ox + (x2 - x1) * p, y1 + oy + (y2 - y1) * p)
            if p >= 1 then
                for _, i in ipairs({ from, to }) do
                    arrived[i] = (arrived[i] or 0) + 1
                    lastAt[i] = math.max(lastAt[i] or 0, at + HOSHI_GROW)
                end
            end
        end
    end

    local r0 = CELL * 0.38
    for i = 1, 9 do
        local clue = HOSHI_CLUES[i]
        local at = 0.15 + (i - 1) * 0.05
        if clue ~= 0 and t >= at then
            local cx, cy = cellCenter(i)
            local p = ui.ease((t - at) / 0.25)
            local done = arrived[i] == clue
            local scale = 1
            if done then
                local q = (t - lastAt[i]) / 0.25
                if q < 1 then scale = 1 + 0.14 * math.sin(math.pi * q) end
            end
            local r = r0 * scale
            theme.set("board", p)
            love.graphics.circle("fill", cx, cy, r)
            if done then
                theme.set("user", 0.22)
                love.graphics.circle("fill", cx, cy, r)
            end
            theme.set(done and "user" or "given", p)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", cx, cy, r)
            theme.set("given", p)
            ui.centered(tostring(clue), cx, cy, math.floor(CELL * 0.46), "bold", "center")
        end
    end

    -- the cursor builds from the top-left island, then the top-right one
    if cursor and t >= 0.6 and t < 2.1 then
        local cx, cy = cellCenter(t < 1.6 and 1 or 3)
        theme.set("accent")
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", cx, cy, r0 + 5)
    end
end

local DEMOS = { sudoku = drawSudokuBox, solo = drawSoloBox, pairlink = drawPairBox, hoshi = drawHoshiBox }

-- The four boxes, two by two, each with its game's name under it. The
-- chosen one plays its demo and is outlined; the others show how theirs
-- end, dimmed.
function Title:drawBoxes()
    local current = self:gameIndex()
    for k, game in ipairs(GAMES) do
        bx = BOXES_X + ((k - 1) % 2) * (BOX + GAP_X)
        by = BOXES_Y + math.floor((k - 1) / 2) * (BOX + GAP_Y)
        local on = (k == current)
        DEMOS[game[1]](on and self.t or STILL, on)
        if on then
            theme.set("accent")
            love.graphics.setLineWidth(3)
            ui.rect("line", bx - 7, by - 7, BOX + 14, BOX + 14, 13)
        else
            theme.set("bg", 0.55)
            ui.rect("fill", bx - 2, by - 2, BOX + 4, BOX + 4, 10)
        end
        theme.set(on and "text" or "muted")
        ui.centered(game[2], bx + BOX / 2, by + BOX + 24, 20, on and "bold" or "regular", "center")
    end
end

function Title:draw()
    self:drawBoxes()

    local x = 352
    theme.set("text")
    ui.text("muSudoku", x - 3, 84, 64, "bold")

    local y, step = 182, 36
    if #self.items <= 7 then y, step = 190, 40 end
    for k, item in ipairs(self.items) do
        local selected = (k == self.sel)
        local cy = y + (k - 1) * step
        if selected then
            theme.set("accent")
            ui.rect("fill", x - 18, cy - 6, 8, 12, 2)
        end
        theme.set(selected and "text" or "muted")
        local w = ui.centered(item.label, x, cy, 26, selected and "bold" or "regular", "left")
        if item.detail then
            theme.set("muted")
            ui.centered(item.detail, x + w + 14, cy + 1, 16, "regular", "left")
        end
    end

    theme.set("muted")
    ui.centered("Version " .. self.app.version, 24, 452, 13, "regular", "left")
    ui.hints({ { input.pair("l1"), "Game" }, { "A", "Select" } }, 696, 452, "right")
end

return Title
