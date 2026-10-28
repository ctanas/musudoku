-- Development only: measures how many frames are drawn while the player is
-- thinking. Run with:  MUSUDOKU_IDLETEST=1 love game
-- Prints frames drawn and CPU time for each phase, then quits.

local input = require("src.input")

local M = {}

function M.start(app)
    local phases = {
        { "start a puzzle", 1.5, function() app.newPuzzle("medium") end },
        { "settle", 1.0 },
        { "idle 10 s, timer shown", 10 },
        { "idle 10 s, timer hidden", 10, function() app.settings.timer = false end },
        { "one move", 1.0, function() input.handler("right") end },
        { "hold right 2 s", 2.0, function() input.keypressed("right") end },
        { "release", 0.5, function() input.keyreleased("right") end },
        { "pause menu idle 5 s", 5, function() input.handler("start") end },
    }
    local origUpdate = love.update
    local k, phaseEnd, frames0, cpu0, t0 = 0, 0, 0, 0, 0
    local results = {}
    local function nextPhase()
        if k > 0 then
            local p = phases[k]
            results[#results + 1] = string.format("%-26s %5.1f s  %4d frames  %5.3f s CPU",
                p[1], love.timer.getTime() - t0, app.framesDrawn - frames0, os.clock() - cpu0)
        end
        k = k + 1
        local p = phases[k]
        if not p then
            print("\nIdle rendering test")
            for _, line in ipairs(results) do print(line) end
            app.settings.timer = true
            love.event.quit()
            return
        end
        if p[3] then p[3]() end
        t0, frames0, cpu0 = love.timer.getTime(), app.framesDrawn, os.clock()
        phaseEnd = t0 + p[2]
    end
    love.update = function(dt)
        origUpdate(dt)
        if love.timer.getTime() >= phaseEnd then nextPhase() end
    end
end

return M
