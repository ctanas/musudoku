-- Development only: checks how the screens behave in the running game, which
-- the luajit tests can't reach (menus, undo at the ends of its history, what
-- the last frame drawn shows, the idle audio device). Run with:
--   MUSUDOKU_SCENETEST=1 love game      (or ./build.sh scenetest)
-- It prints PASS / FAIL lines and exits with 1 if anything failed. It plays
-- in a save folder of its own (musudoku-scenetest), so real saves, settings
-- and statistics are left alone.

local input = require("src.input")
local sound = require("src.sound")
local storage = require("src.storage")
local packs = require("src.packs")
local sudoku = require("src.sudoku")
local solo = require("src.solo")
local daily = require("src.daily")

local M = {}

local IDENTITY = "musudoku-scenetest"
local PACK_LINES = 30000 -- enough that reading the pack takes several frames

-- A 3x3 Hoshi: two bridges along the top (between the 3s), one down each side.
local HOSHI_SQUARE = {
    size = 3,
    clues = { 3, 0, 3, 0, 0, 0, 1, 0, 1 },
    bridges = { { 1, 3, 2 }, { 1, 7, 1 }, { 3, 9, 1 } },
}

-- Empties the save folder. (Listings also show the game's own files; those
-- are left alone, and couldn't be removed anyway.)
local function removeAll(path)
    local saves = love.filesystem.getSaveDirectory()
    for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do
        local item = (path == "" and "" or path .. "/") .. name
        if love.filesystem.getRealDirectory(item) == saves then
            if love.filesystem.getInfo(item, "directory") then removeAll(item) end
            love.filesystem.remove(item)
        end
    end
end

-- A fresh save folder, and the game's state as at a first launch.
local function freshStart(app)
    love.filesystem.setIdentity(IDENTITY)
    removeAll("")
    app.settings = storage.loadSettings()
    app.settings.sound = false -- turned on for the audio checks at the end
    app.settings.timer = false -- so an idle screen draws nothing
    app.stats = storage.loadStats()
    app.packProgress = packs.loadProgress(storage.loadPackProgress())
    app.daily = storage.loadDaily()
    app.history = storage.loadHistory()
    app.game, app.puzzles, app.puzzleDirty = nil, {}, {}
    for kind, info in pairs(app.PUZZLES) do
        app.puzzleStats[kind] = storage.loadPuzzleStats(kind, info.sizes)
    end
    app.packCache, app.lastChoice, app.lastDifficulty = {}, {}, nil
    app.titleGame = "sudoku"
    app.applySettings()
    app.setScene("title")
end

-- A pack of real puzzles, three of them over and over.
local function writePack()
    local lines = {}
    for seed = 1, 3 do
        lines[seed] = table.concat(sudoku.generate("easy", daily.rng(seed)).puzzle)
    end
    local out = {}
    for n = 1, PACK_LINES do out[n] = lines[(n - 1) % 3 + 1] end
    love.filesystem.createDirectory("packs")
    love.filesystem.write("packs/Scene test.txt", table.concat(out, "\n") .. "\n")
    packs.override = love.filesystem.getSaveDirectory() .. "/packs"
end

function M.start(app)
    love.focus = function() end -- a window that isn't focused stops the clock
    app.focused = true
    freshStart(app)
    writePack()

    local out, fails = {}, 0
    local function check(ok, ...)
        if not ok then fails = fails + 1 end
        out[#out + 1] = (ok and "PASS  " or "FAIL  ") .. string.format(...)
    end
    local function skip(...) out[#out + 1] = "SKIP  " .. string.format(...) end

    -- what the last frame drawn showed
    local last = {}
    local draw = love.draw
    love.draw = function()
        draw()
        local top = app.top()
        last = {
            fade = app.fade, scene = top.name, indexed = top.index ~= nil,
            flashing = top.flash ~= nil and next(top.flash) ~= nil,
            glow = top.cursorGlow and top:cursorGlow(),
        }
    end

    local function press(...)
        for _, a in ipairs({ ... }) do input.handler(a) end
    end
    -- Real key presses and releases, for buttons that are held (input.isDown)
    local function keyDown(k) input.keypressed(k) end
    local function keyUp(k) input.keyreleased(k) end
    local function key(k)
        keyDown(k)
        keyUp(k)
    end
    local function top() return app.top() end
    local function firstEmpty()
        for i = 1, 81 do
            if app.game.values[i] == 0 then return i end
        end
    end
    local function labels(list)
        local t = {}
        for _, item in ipairs(list) do t[#t + 1] = item.label end
        return table.concat(t, " | ")
    end
    -- Moves a menu's selection to the item with this label.
    local function select(label)
        local scene = top()
        for k, item in ipairs(scene.items) do
            if item.label == label then scene.sel = k end
        end
    end

    local frames, mathRandomUsed
    local steps = {
        function() return 0.2 end,

        -- Sudoku ------------------------------------------------------------
        function()
            app.startGame(sudoku.generate("easy", daily.rng(20261111)), "easy")
            return 1.0
        end,
        function()
            check(last.scene == "play" and last.fade == 0, "a new screen's fade is drawn to its end (last frame at %.3f)", last.fade or -1)
        end,
        function()
            local g = app.game
            local cell = firstEmpty()
            local digit = g.solution[cell]
            g.cursor = cell
            press("digit" .. digit, "l2")
            check(g.values[cell] == 0, "Sudoku: undo takes the number back")
            press("l2")
            check(g.values[cell] == 0 and #g.redoStack == 1, "Sudoku: undo with nothing left to undo does nothing")
            press("r2", "r2")
            check(g.values[cell] == digit and #g.undoStack == 1, "Sudoku: redo with nothing left to redo does nothing")
            return 0.8
        end,
        function()
            app.game.cursor = firstEmpty()
            press("x") -- pencil
            return 0.6
        end,
        function()
            frames = app.framesDrawn
            app.wake() -- as the event loop does for a button
            press("digit3")
            return 0.4
        end,
        function()
            check(app.framesDrawn - frames == 2, "a press that starts no animation draws 2 frames (%d)", app.framesDrawn - frames)
            press("x")
            return 0.5
        end,
        function()
            -- complete the top row: its cells flash
            local g = app.game
            local final
            for i = 9, 1, -1 do
                if not g.fixed[i] then final = i break end
            end
            for i = 1, 9 do
                if not g.fixed[i] then g.values[i], g.notes[i] = g.solution[i], 0 end
            end
            g.values[final] = 0
            g.cursor = final
            press("digit" .. g.solution[final])
            check(next(top().flash) ~= nil, "completing a row flashes it")
            return 1.6
        end,
        function()
            check(last.flashing == false, "the flash is drawn to its end")
            app.game.cursor = firstEmpty()
            press("a")
            check(top().pad ~= nil, "A opens the number pad")
            top().pad.t = top().t - 7.0 -- as if it had been open for 7 seconds
            frames = app.framesDrawn
            return 0.5
        end,
        function()
            check(app.framesDrawn - frames >= 5, "the cursor's glow breathes while a number is picked (%d frames)", app.framesDrawn - frames)
            return 1.0
        end,
        function()
            frames = app.framesDrawn
            return 1.0
        end,
        function()
            check(app.framesDrawn == frames and last.glow == 1, "after 8 seconds the glow stays lit and nothing is drawn (%d frames)",
                app.framesDrawn - frames)
            press("b")
        end,

        -- The pause menu, Settings and dialogs ------------------------------
        function()
            press("start")
            check(top().name == "pause" and not labels(top().items):find("Check board"), "pause menu with mistake checking on: no Check board")
            select("Settings")
            press("a")
            local s = top()
            check(s.name == "settings" and s.game == "sudoku", "Settings opens for Sudoku from Sudoku's pause menu")
            local rows = labels(s.rows)
            check(rows:find("Hints") and rows:find("Theme") and not rows:find("Show repeats"),
                "Sudoku's settings: its own and the shared ones, not Solo's")
            app.settings.mistakes = false
            press("b")
            check(top().name == "pause" and labels(top().items):find("Check board") ~= nil
                and top().items[top().sel].label == "Settings", "back in the pause menu: Check board is there, Settings still selected")
            app.settings.mistakes = true
            select("Restart puzzle")
            press("a")
            check(top().name == "confirm", "Restart puzzle asks first")
            press("start")
            check(top().name == "confirm", "Start doesn't answer a yes/no question")
            press("b")
            check(top().name == "pause", "B cancels it")
            press("b")
            check(top().name == "play", "B resumes")
            return 0.4
        end,

        -- Statistics --------------------------------------------------------
        function()
            app.push("stats")
            local s = top()
            local first = s.page
            for _ = 1, 5 do
                press("r2")
                s:draw()
            end
            check(s.page == first, "Statistics has five pages (back on page %d after five turns)", s.page)
            press("b")
        end,

        -- A puzzle pack -----------------------------------------------------
        function()
            app.setScene("title")
            return 0.3
        end,
        function()
            local files = packs.list()
            check(#files == 1, "the test pack is listed (%d)", #files)
            app.wake()
            app.push("pack", files[1])
            return 0.02
        end,
        function()
            if top().co then return 0.05, true end -- until it's read
            return 0.6
        end,
        function()
            check(last.indexed == true, "the pack's menu is drawn once the file is read")
            local random = math.random
            math.random = function(...)
                mathRandomUsed = true
                return random(...)
            end
            press("down", "a") -- Random unsolved, with a Sudoku in progress
            math.random = random
            check(top().name == "confirm", "starting a pack puzzle asks before replacing the one in progress")
            press("b")
            check(top().name == "pack" and app.game.pack == nil, "cancelled: the puzzle in progress is kept")
            math.random = function(...)
                mathRandomUsed = true
                return random(...)
            end
            press("a", "a")
            math.random = random
            check(top().name == "play" and app.game.pack ~= nil, "confirmed: the pack puzzle starts")
            check(not mathRandomUsed, "Random unsolved doesn't use the unseeded math.random")
            return 0.5
        end,

        -- Solo (boardscene.lua, shared with Pairlink and Hoshi) -------------
        function()
            app.startPuzzle("solo", solo.generate(5, "easy", daily.rng(7)), "easy")
            return 0.6
        end,
        function()
            local g = app.puzzles.solo
            local cell = g.cursor
            press("a", "l2")
            check(g.marks[cell] == 0, "Solo: undo takes the shading back")
            press("l2")
            check(g.marks[cell] == 0 and #g.redoStack == 1, "Solo: undo with nothing left to undo does nothing")
            press("r2", "r2")
            check(g.marks[cell] == 1 and #g.undoStack == 1, "Solo: redo with nothing left to redo does nothing")
            press("l2", "start")
            select("Settings")
            press("a")
            local s = top()
            local rows = s.rows and labels(s.rows) or ""
            check(s.game == "solo" and rows:find("Show repeats") and not rows:find("Hints") and not rows:find("Number pad"),
                "Solo's settings: its own and the shared ones, not Sudoku's")
            press("b", "b")
            return 0.3
        end,
        function()
            -- the title's Settings follows the game it shows
            app.setScene("title")
            app.titleGame = "hoshi"
            top():build()
            select("Settings")
            press("a")
            local s = top()
            check(s.game == "hoshi" and #s.rows == 5, "Hoshi's settings from the title: the five shared ones (%d)", s.rows and #s.rows or -1)
            s:draw()
            press("b")
            app.titleGame = "sudoku"
            top():build()
        end,

        -- Hoshi's controls, with real presses and releases ------------------
        -- (Space is A, Backspace B.)
        function()
            app.startPuzzle("hoshi", HOSHI_SQUARE, "easy")
            return 0.5
        end,
        function()
            local g, s = app.puzzles.hoshi, top()
            local across, side = g:linkToward(1, "right"), g:linkToward(1, "down")
            g.cursor = 1
            key("right")
            check(g.cursor == 3 and g.counts[across] == 0, "Hoshi: a direction moves to the next island")
            key("left")
            keyDown("space")
            key("right")
            key("right")
            key("down")
            check(g.cursor == 1 and g.counts[across] == 2 and g.counts[side] == 1 and s.mode == "build",
                "Hoshi: with A held, directions build bridges and the cursor stays (%d, %d)", g.counts[across], g.counts[side])
            key("right")
            check(g.counts[across] == 2 and #g.undoStack == 3, "Hoshi: no third bridge between two islands")
            keyUp("space")
            return 0.1
        end,
        function()
            local g, s = app.puzzles.hoshi, top()
            check(s.mode == nil, "Hoshi: letting go of A after building ends it")
            key("right")
            check(g.cursor == 3, "Hoshi: then directions move again")
            key("backspace")
            return 0.1
        end,
        function()
            local g, s = app.puzzles.hoshi, top()
            check(s.mode == "remove" and s.latched, "Hoshi: B pressed and let go waits for a direction")
            key("left")
            check(g.counts[g:linkToward(3, "left")] == 1 and g.cursor == 3 and s.mode == nil,
                "Hoshi: then a direction takes one bridge away, once")
            key("space")
            return 0.1
        end,
        function()
            local g, s = app.puzzles.hoshi, top()
            check(s.mode == "build" and s.latched, "Hoshi: A pressed and let go waits for a direction")
            key("space")
            check(s.mode == nil, "Hoshi: A again cancels")
            key("x")
            check(g:bridgesAt(3) == 0 and g:bridgesAt(1) == 1, "Hoshi: X takes away all the island's bridges")
            keyDown("space")
            keyDown("left")
            return 0.6 -- past the repeat delay: left repeats
        end,
        function()
            local g = app.puzzles.hoshi
            keyUp("left")
            keyUp("space")
            check(g.counts[g:linkToward(3, "left")] == 1, "Hoshi: a direction held down builds one bridge, not one per repeat (%d)",
                g.counts[g:linkToward(3, "left")])
            return 0.1
        end,
        function()
            local g, s = app.puzzles.hoshi, top()
            keyDown("space")
            key("left")
            key("down")
            keyUp("space")
            check(g.solved and s.winT ~= nil and s.mode == nil, "Hoshi: the last bridge solves it")
            return 2.5
        end,

        -- The audio device while idle ---------------------------------------
        function()
            app.settings.sound = true
            app.applySettings()
            sound.idleAfter = 0.3
            return 2.0 -- the silence, then the trial's second
        end,
        function()
            local state = sound.deviceState()
            if state ~= "paused" and app.settings.audioPause == false then
                -- this system's sound driver is one that doesn't come back
                check(storage.loadSettings().audioPause == false,
                    "the trial found that a paused device doesn't come back here: Audio power saving is off, and saved off")
                return 0, false, "end"
            elseif state ~= "paused" then
                skip("the audio device can't be paused here (%s): idle audio checks left out", state)
                return 0, false, "end"
            end
            check(true, "the audio device is paused after a silence, once the trial has passed")
            sound.play("win")
            check(sound.deviceState() == "running", "a sound resumes it")
            return 1.6 -- the sound, and the look at it
        end,
        function()
            check(app.settings.audioPause == true, "a device that came back leaves the setting on")
            check(sound.deviceState() == "paused", "it's paused again once the sound is over")
            sound.failResume = true -- a device that doesn't come back
            sound.play("win")
            sound.failResume = false
            return 1.5
        end,
        function()
            check(app.settings.audioPause == false and storage.loadSettings().audioPause == false,
                "a device that didn't come back turns Audio power saving off, and saves that")
            return 0.8
        end,
        function()
            check(sound.deviceState() == "running", "and it isn't paused again")
        end,
    }

    local k, wait = 1, 0
    local update = love.update
    love.update = function(dt)
        update(dt)
        wait = wait - dt
        if wait > 0 then return end
        local step = steps[k]
        if not step then
            print("\nScene test: " .. (fails == 0 and "all passed" or (fails .. " FAILED")))
            for _, line in ipairs(out) do print(line) end
            love.event.quit(fails == 0 and 0 or 1)
            love.update = update
            return
        end
        local delay, again, jump = step()
        wait = delay or 0
        if jump == "end" then k = #steps + 1 elseif not again then k = k + 1 end
    end
end

return M
