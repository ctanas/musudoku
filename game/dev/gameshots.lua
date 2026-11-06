-- Development only: plays through the Solo, Pairlink and Hoshi screens and
-- saves screenshots to the LÖVE save directory. Run with:
--   MUSUDOKU_GAMESHOTS=1 love game
-- Screenshots land in ~/.local/share/love/musudoku/shots/ on Linux.
--
-- MUSUDOKU_GAMESHOTS=readme takes the README pictures instead: puzzles part
-- way through, in a few themes. Run it at 1440x960 like the others:
--   MUSUDOKU_GAMESHOTS=readme love game 1440x960

local input = require("src.input")
local SoloGame = require("src.sologame")
local hoshi = require("src.hoshi")

local M = {}

function M.start(app)
    love.filesystem.createDirectory("shots")

    local function press(...)
        for _, a in ipairs({ ... }) do input.handler(a) end
    end
    local function shot(name)
        app.requestRedraw()
        love.graphics.captureScreenshot("shots/g" .. name .. ".png")
    end
    local function theme(key)
        app.settings.theme = key
        app.applySettings()
    end
    local function solo() return app.puzzles.solo end
    local function pairs_() return app.puzzles.pairlink end
    local function islands() return app.puzzles.hoshi end

    -- Hoshi: draw the answer's bridges the way a player would (A, across,
    -- and back again for a second bridge, A), the first `count` of them (all
    -- if nil).
    local function hoshiBuild(count, from)
        local g = islands()
        for k, b in ipairs(g.solution) do
            if count and k > count then break end
            if k >= (from or 1) then
                local link = g.P.links[hoshi.linkBetween(g.P, b[1], b[2])]
                g.cursor = link.a
                press("a", link.horizontal and "right" or "down")
                if b[3] == 2 then press(link.horizontal and "left" or "up") end
                press("a")
            end
        end
    end

    -- Two links that cross, both without bridges: a bridge on the first
    -- blocks the second. Returns { first, second }, each { a = island,
    -- dir }, or nil.
    local function crossingTry()
        local g = islands()
        local function from(l)
            local link = g.P.links[l]
            return { a = link.a, dir = link.horizontal and "right" or "down" }
        end
        for l = 1, #g.P.links do
            for _, m in ipairs(g.P.crosses[l]) do
                if g.counts[l] == 0 and g.counts[m] == 0 then return { first = from(m), second = from(l) } end
            end
        end
    end

    -- Solo: shade the solution's cells, all but the last one, and keep a few.
    local function soloAlmost()
        local g = solo()
        local last
        for i = 1, g.size * g.size do
            if g.solution[i] then
                if last then g.marks[last] = SoloGame.SHADE end
                last = i
            end
        end
        return last
    end

    -- Pairlink: draw pair k's line from the solution, `steps` cells of it
    -- (all of it if nil), leaving the drawing on unless it links.
    local function drawLine(k, steps)
        local g = pairs_()
        local line = g.solution[k]
        g.cursor = line[1]
        press("a")
        for s = 2, steps or #line do
            local from, to = line[s - 1], line[s]
            local d = to - from
            if d == 1 then press("right") elseif d == -1 then press("left")
            elseif d > 0 then press("down") else press("up") end
        end
    end

    -- Solo part way: the top rows shaded as in the solution, with rings on
    -- the cells beside them, the way a player marks what must stay.
    local function soloPartway(rows)
        local g = solo()
        local n = g.size
        for i = 1, rows * n do
            if g.solution[i] then g.marks[i] = SoloGame.SHADE end
        end
        for i = 1, rows * n do
            if not g.solution[i] then
                local r, c = math.floor((i - 1) / n), (i - 1) % n
                local nearShade = (c > 0 and g.marks[i - 1] == SoloGame.SHADE)
                    or (c < n - 1 and g.marks[i + 1] == SoloGame.SHADE)
                    or (r > 0 and g.marks[i - n] == SoloGame.SHADE)
                    or (i + n <= rows * n and g.marks[i + n] == SoloGame.SHADE)
                if nearShade then g.marks[i] = SoloGame.DOT end
            end
        end
        g.cursor = rows * n + math.floor(n / 2) + 1
    end

    -- Pairlink part way: all lines but the last `left`, and half of the
    -- next one still being drawn.
    local function pairlinkPartway(left)
        local g = pairs_()
        for k = 1, g.pairs - left do drawLine(k) end
        local k = g.pairs - left + 1
        drawLine(k, math.max(2, math.floor(#g.solution[k] / 2)))
    end

    local readme = {
        function() return 0.3 end,
        function()
            app.titleGame = "solo"
            app.setScene("title")
            return 2.6
        end,
        function() shot("r1_title_solo") end,
        function() app.newPuzzleOf("solo", 7, "medium") return 1.2 end,
        function()
            soloPartway(4)
            solo().elapsed = 207
            return 0.6
        end,
        function() shot("r2_solo") end,
        function()
            theme("paper")
            app.newPuzzleOf("solo", 9, "hard")
            return 1.2
        end,
        function()
            soloPartway(5)
            solo().elapsed = 498
            return 0.6
        end,
        function() shot("r3_solo_paper") end,
        function()
            theme("cyanotype")
            app.newPuzzleOf("pairlink", 8, "medium")
            return 1.2
        end,
        function()
            pairlinkPartway(3)
            pairs_().elapsed = 252
            return 1.4
        end,
        function() shot("r4_pairlink") end,
        -- the link effect, on the longest line
        function()
            app.newPuzzleOf("pairlink", 7, "hard")
            return 1.2
        end,
        function()
            local g = pairs_()
            local longest = 1
            for k = 2, g.pairs do
                if #g.solution[k] > #g.solution[longest] then longest = k end
            end
            for k = 1, g.pairs do
                if k ~= longest and k % 2 == 0 then drawLine(k) end
            end
            g.elapsed = 131
            return 1.2
        end,
        function()
            local g = pairs_()
            local longest = 1
            for k = 2, g.pairs do
                if #g.solution[k] > #g.solution[longest] then longest = k end
            end
            drawLine(longest)
            return 0.2
        end,
        function() shot("r5_pairlink_link") end,
        function()
            theme("chalkboard")
            app.newPuzzleOf("pairlink", 9, "easy")
            return 1.2
        end,
        function()
            pairlinkPartway(4)
            pairs_().elapsed = 333
            return 1.4
        end,
        function() shot("r6_pairlink_chalkboard") end,
        function()
            theme("cyanotype")
            app.titleGame = "pairlink"
            app.setScene("title")
            return 2.6
        end,
        function() shot("r7_title_pairlink") end,
        function()
            app.newPuzzleOf("hoshi", 9, "medium")
            return 1.2
        end,
        function()
            local g = islands()
            hoshiBuild(math.floor(#g.solution * 0.6))
            g.cursor = g:nextUnfinished(g.cursor, 1) or g.cursor
            press("a")
            g.elapsed = 274
            return 0.6
        end,
        function() shot("r8_hoshi") end,
        function()
            press("a")
            theme("paper")
            app.newPuzzleOf("hoshi", 7, "hard")
            return 1.2
        end,
        function()
            hoshiBuild(5)
            islands().elapsed = 149
            return 0.6
        end,
        function() shot("r9_hoshi_paper") end,
        function()
            theme("cyanotype")
            app.titleGame = "hoshi"
            app.setScene("title")
            return 2.8
        end,
        function() shot("r10_title_hoshi") end,
    }

    local steps = {
        function() return 0.3 end,
        function() press("r1") return 2.5 end,
        function() shot("01_title_solo") end,
        function() press("r1") return 2.5 end,
        function() shot("02_title_pairlink") end,
        function() press("l1") return 0.3 end,
        function() press("a") return 0.4 end, -- New puzzle (nothing to continue yet)
        function() shot("03_choose_solo") end,
        function() press("right", "down", "a") return 0.1 end,
        function() shot("04_generating_solo") return 1.0 end,
        function() shot("05_solo_start") end,
        function()
            local g = solo()
            local shaded, kept = 0, 0
            for i = 1, g.size * g.size do
                if g.solution[i] and shaded < 6 then
                    g.cursor = i
                    press("a")
                    shaded = shaded + 1
                elseif not g.solution[i] and kept < 4 and i % 3 == 0 then
                    g.cursor = i
                    press("x")
                    kept = kept + 1
                end
            end
            g.cursor = 25
            return 0.6
        end,
        function() shot("06_solo_play") end,
        function() input.keypressed("y") return 0.2 end,
        function() shot("06b_solo_peek") end,
        function() input.keyreleased("y") return 0.2 end,
        function() press("start") return 0.4 end,
        function() shot("07_solo_pause") end,
        function() press("b") return 0.3 end,
        function()
            local g = solo()
            app.puzzleStats.solo["9-medium"].streak = 2
            for i = 1, g.size * g.size do g.marks[i] = SoloGame.NONE end
            g.cursor = soloAlmost()
            press("a")
            return 0.45
        end,
        function() shot("08_solo_win_wave") return 1.6 end,
        function() shot("09_solo_win") end,
        function() press("b") return 0.4 end,
        function() app.push("stats", "Solo") return 0.4 end,
        function() shot("10_stats_solo") end,
        function() press("b") return 0.3 end,

        -- Pairlink
        function() press("r1") return 0.3 end,
        function() press("a") return 0.4 end,
        function() shot("11_choose_pairlink") end,
        function() press("left", "down", "down", "a") return 1.5 end,
        function() shot("12_pairlink_start") end,
        function()
            drawLine(1)
            drawLine(2, 3)
            return 0.15
        end,
        function() shot("13_pairlink_link_effect") return 0.8 end,
        function() shot("14_pairlink_drawing") end,
        function() press("a") return 0.3 end,
        function() press("start") return 0.4 end,
        function() shot("15_pairlink_pause") end,
        function() press("b") return 0.3 end,
        function()
            local g = pairs_()
            for k = 2, g.pairs - 1 do drawLine(k) end
            local line = g.solution[g.pairs]
            drawLine(g.pairs, #line - 1)
            return 0.8
        end,
        function() shot("16_pairlink_almost") end,
        function()
            local g = pairs_()
            local line = g.solution[g.pairs]
            local d = line[#line] - line[#line - 1]
            if d == 1 then press("right") elseif d == -1 then press("left")
            elseif d > 0 then press("down") else press("up") end
            return 0.4
        end,
        function() shot("17_pairlink_win_wave") return 1.6 end,
        function() shot("18_pairlink_win") end,
        function() press("b") return 0.4 end,
        function() app.push("stats", "Pairlink") return 0.4 end,
        function() shot("19_stats_pairlink") end,
        function() press("r2") return 0.3 end,
        function() shot("20_stats_recent") end,
        function() press("b") return 0.3 end,

        -- other themes and sizes
        function()
            theme("paper")
            app.newPuzzleOf("solo", 9, "hard")
            return 1.5
        end,
        function()
            local g = solo()
            for i = 1, 30 do
                if g.solution[i] then g.marks[i] = SoloGame.SHADE elseif i % 4 == 0 then g.marks[i] = SoloGame.DOT end
            end
            return 0.3
        end,
        function() shot("21_solo_paper_9") end,
        function()
            theme("chalkboard")
            app.newPuzzleOf("pairlink", 9, "easy")
            return 1.5
        end,
        function()
            drawLine(1)
            drawLine(3)
            drawLine(4, 2)
            return 1.0
        end,
        function() shot("22_pairlink_chalkboard_9") end,
        function()
            theme("solarizedLight")
            app.newPuzzleOf("solo", 5, "easy")
            return 1.5
        end,
        function()
            local g = solo()
            for i = 1, 25 do if g.solution[i] and i < 15 then g.marks[i] = SoloGame.SHADE end end
            return 0.3
        end,
        function() shot("23_solo_solarized_5") end,
        function()
            theme("nord")
            app.newPuzzleOf("pairlink", 7, "medium")
            return 1.5
        end,
        function()
            for k = 1, 3 do drawLine(k) end
            return 1.0
        end,
        function() shot("24_pairlink_nord_7") end,
        function()
            theme("cyanotype")
            app.setScene("title")
            return 2.5
        end,
        function() shot("25_title_continue") end,

        -- replacing a puzzle in progress, undo and redo, restarting
        function() press("l1") return 0.3 end, -- Solo, with a puzzle in progress
        function() press("down", "a", "a") return 0.4 end,
        function() shot("26_solo_replace_confirm") end,
        function() press("a") return 1.2 end,
        function()
            local g = solo()
            g.cursor = 1
            press("a", "right", "x", "l2", "l2", "r2")
            return 0.4
        end,
        function() shot("27_solo_undo_redo") end,
        function() press("start", "down", "a") return 0.4 end,
        function() shot("28_solo_restart_confirm") end,
        function() press("a") return 0.6 end,
        function() shot("29_solo_restarted") end,
        function()
            app.newPuzzleOf("pairlink", 8, "easy")
            return 1.2
        end,
        function()
            drawLine(1)
            press("l2", "r2", "r1")
            local g = pairs_()
            g.cursor = g.solution[1][2]
            press("b") -- erase line 1 from one of its cells
            press("start", "down", "down", "a")
            return 0.4
        end,
        function() shot("30_pairlink_pause_new") end,
        function() press("b", "b", "b") return 0.4 end,
        function() app.push("stats", "Solo") press("y") return 0.4 end,
        function() shot("31_stats_reset_confirm") end,
        function() press("a") return 0.4 end,
        function() shot("32_stats_after_reset") end,
        function() press("b") return 0.3 end,

    }

    -- Hoshi, also on its own with MUSUDOKU_GAMESHOTS=hoshi
    local hoshiSteps = {
        function() return 0.3 end,
        function()
            theme("cyanotype")
            app.titleGame = "hoshi"
            app.setScene("title")
            return 2.8
        end,
        function() shot("40_title_hoshi") end,
        function()
            app.titleGame = "sudoku"
            app.setScene("title")
            return 2.8
        end,
        function() shot("40b_title_sudoku") end,
        function() press("l1") return 0.4 end,
        function() press("a") return 0.4 end, -- New puzzle (nothing to continue)
        function() shot("41_choose_hoshi") end,
        function() press("left", "down", "a") return 0.1 end, -- 7x7 Medium
        function() shot("42_generating_hoshi") return 1.0 end,
        function() shot("43_hoshi_start") end,
        function() hoshiBuild(4) return 0.5 end,
        function() shot("44_hoshi_partway") end,
        function()
            local g = islands()
            g.cursor = g:nextUnfinished(g.cursor, 1) or g.cursor
            press("a")
            return 0.4
        end,
        function() shot("45_hoshi_drawing") end,
        function()
            press("a")
            return 0.3
        end,
        function()
            -- one bridge too many on a finished island
            local g = islands()
            for l, link in ipairs(g.P.links) do
                if g.counts[l] > 0 and g.counts[l] < link.max and g:state(link.a) == "done" then
                    g.cursor = link.a
                    press("a", link.horizontal and "right" or "down", "a")
                    break
                end
            end
            return 0.4
        end,
        function() shot("47_hoshi_over") end,
        function() press("l2") return 0.3 end,
        function() press("start") return 0.4 end,
        function() shot("48_hoshi_pause") end,
        function() press("b") return 0.3 end,
        function()
            local g = islands()
            g:restart()
            g.elapsed = 96
            app.puzzleStats.hoshi["7-medium"].streak = 2
            hoshiBuild(#g.solution - 1)
            return 0.6
        end,
        function() shot("49_hoshi_almost") end,
        function()
            local g = islands()
            hoshiBuild(nil, #g.solution)
            return 0.45
        end,
        function() shot("50_hoshi_win_wave") return 1.6 end,
        function() shot("51_hoshi_win") end,
        function() press("b") return 0.4 end,
        function() app.push("stats", "Hoshi") return 0.4 end,
        function() shot("52_stats_hoshi") end,
        function() press("b") return 0.3 end,
        function()
            theme("chalkboard")
            app.newPuzzleOf("hoshi", 9, "hard")
            return 1.5
        end,
        function()
            hoshiBuild(8)
            return 0.6
        end,
        function() shot("53_hoshi_chalkboard_9") end,
        function()
            theme("solarizedLight")
            app.newPuzzleOf("hoshi", 7, "easy")
            return 1.5
        end,
        function()
            hoshiBuild(3)
            return 0.6
        end,
        function() shot("54_hoshi_solarized_7") end,
        function()
            theme("frankfurt")
            app.titleGame = "hoshi"
            app.setScene("title")
            return 2.8
        end,
        function() shot("55_title_frankfurt") end,
        function()
            theme("chalkboard")
            app.setScene("title")
            return 2.8
        end,
        function() shot("56_title_chalkboard") end,
        -- a bridge in the way: a puzzle with links that cross, one built,
        -- then the other tried (set up directly, so it skips the statistics)
        function()
            theme("cyanotype")
            local HoshiGame = require("src.hoshigame")
            local gen
            repeat
                gen = hoshi.generate(9, "medium")
                local P = hoshi.analyze(9, gen.clues)
                local any = false
                for l = 1, #P.links do if #P.crosses[l] > 0 then any = true end end
            until any
            app.puzzles.hoshi = HoshiGame.new(gen, "medium")
            app.setScene("hoshiplay")
            return 0.5
        end,
        function()
            local g = islands()
            local try = crossingTry()
            g.cursor = try.first.a
            press("a", try.first.dir, "a")
            g.cursor = try.second.a
            press("a", try.second.dir)
            return 0.1
        end,
        function() shot("57_hoshi_crossing_blocked") end,
    }

    if os.getenv("MUSUDOKU_GAMESHOTS") == "readme" then
        steps = readme
    elseif os.getenv("MUSUDOKU_GAMESHOTS") == "hoshi" then
        steps = hoshiSteps
    else
        for _, step in ipairs(hoshiSteps) do steps[#steps + 1] = step end
    end

    local origUpdate = love.update
    local t, idx, waitUntil = 0, 1, 0
    love.update = function(dt)
        origUpdate(dt)
        t = t + dt
        if t >= waitUntil then
            if idx <= #steps then
                local step = steps[idx]
                idx = idx + 1
                waitUntil = t + (step() or 0.15)
            else
                love.event.quit()
            end
        end
    end
end

return M
