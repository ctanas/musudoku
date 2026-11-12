-- Small sound effects synthesized at startup, so the game ships no audio
-- files. If audio isn't available the game stays silent.

local sound = { enabled = true }

local RATE = 22050
local sources = {}

-- Build a sound from a list of tones: { freq, start, length, volume, shape,
-- glide }. shape "noise" ignores freq (a crack or click); glide, if given,
-- is the frequency the tone slides to by its end.
local function synth(tones, length)
    local samples = math.floor(length * RATE)
    local data = love.sound.newSoundData(samples, RATE, 16, 1)
    local buffer = {}
    for n = 0, samples - 1 do buffer[n] = 0 end
    local seed = 12345 -- the same noise every time
    for _, tone in ipairs(tones) do
        local freq, start, len, vol, shape = tone[1], tone[2], tone[3], tone[4], tone[5] or "sine"
        local ratio = tone[6] and (tone[6] / freq)
        local s0 = math.floor(start * RATE)
        local count = math.floor(len * RATE)
        local attack = math.max(1, math.floor(0.004 * RATE))
        for k = 0, count - 1 do
            local n = s0 + k
            if n >= samples then break end
            local t = k / RATE
            local env = math.exp(-t * (5.5 / len))
            if k < attack then env = env * (k / attack) end
            local phase
            if ratio then
                -- the frequency moves exponentially from freq to the glide's
                phase = 2 * math.pi * freq * len / math.log(ratio) * (ratio ^ (t / len) - 1)
            else
                phase = 2 * math.pi * freq * t
            end
            local v
            if shape == "noise" then
                seed = (seed * 16807) % 2147483647 -- stays exact in a double
                v = seed / 1073741823.5 - 1
            elseif shape == "soft" then
                v = math.sin(phase) * 0.8 + math.sin(phase * 2) * 0.2
            elseif shape == "tri" then
                v = (2 / math.pi) * math.asin(math.sin(phase))
            else
                v = math.sin(phase)
            end
            buffer[n] = buffer[n] + v * env * vol
        end
    end
    for n = 0, samples - 1 do
        data:setSample(n, math.max(-1, math.min(1, buffer[n])))
    end
    return data
end

local DEFS = {
    move   = function() return synth({ { 1320, 0, 0.025, 0.10 } }, 0.03) end,
    menu   = function() return synth({ { 990, 0, 0.035, 0.14 } }, 0.04) end,
    open   = function() return synth({ { 740, 0, 0.05, 0.16, "soft" }, { 1110, 0.025, 0.05, 0.10 } }, 0.08) end,
    close  = function() return synth({ { 1110, 0, 0.05, 0.10 }, { 740, 0.025, 0.05, 0.14, "soft" } }, 0.08) end,
    place  = function() return synth({ { 587, 0, 0.09, 0.30, "soft" }, { 1175, 0, 0.05, 0.08 } }, 0.10) end,
    note   = function() return synth({ { 1568, 0, 0.04, 0.12 } }, 0.05) end,
    erase  = function() return synth({ { 660, 0, 0.05, 0.16, "soft" }, { 440, 0.03, 0.06, 0.14, "soft" } }, 0.10) end,
    wrong  = function() return synth({ { 196, 0, 0.16, 0.26, "tri" }, { 185, 0.07, 0.16, 0.20, "tri" } }, 0.24) end,
    blocked = function() return synth({ { 247, 0, 0.07, 0.18, "tri" } }, 0.08) end,
    unit   = function()
        return synth({ { 1047, 0, 0.22, 0.14 }, { 1319, 0.06, 0.22, 0.12 }, { 1568, 0.12, 0.26, 0.12 } }, 0.40)
    end,
    unitBig = function()
        return synth({
            { 1047, 0, 0.26, 0.13 }, { 1319, 0.05, 0.26, 0.12 },
            { 1568, 0.10, 0.28, 0.12 }, { 2093, 0.15, 0.36, 0.11 },
            { 523, 0, 0.40, 0.10, "soft" },
        }, 0.55)
    end,
    hint   = function() return synth({ { 880, 0, 0.12, 0.16 }, { 1319, 0.05, 0.16, 0.12 } }, 0.22) end,
    -- Pairlink: a pair's line reaches its other number
    link   = function()
        return synth({
            { 659, 0, 0.16, 0.16, "soft" }, { 988, 0.05, 0.18, 0.14, "soft" },
            { 1319, 0.10, 0.24, 0.12 }, { 1976, 0.10, 0.20, 0.05 },
        }, 0.36)
    end,
    -- Pairlink: a linked line breaks; a crack, and an elastic twanging back
    snap   = function()
        return synth({
            { 0, 0, 0.03, 0.34, "noise" },
            { 1500, 0, 0.13, 0.15, "tri", 260 },
            { 760, 0.008, 0.17, 0.11, "soft", 150 },
        }, 0.19)
    end,
    win    = function()
        return synth({
            { 523, 0.00, 0.30, 0.18, "soft" }, { 659, 0.11, 0.30, 0.18, "soft" },
            { 784, 0.22, 0.30, 0.18, "soft" }, { 1047, 0.33, 0.60, 0.20, "soft" },
            { 1319, 0.33, 0.60, 0.08 },
        }, 1.0)
    end,
}

-- Builds the sounds the first time it's called. conf.lua leaves the audio
-- modules out when sound effects were off at launch (their mixer runs even
-- when silent), so they're loaded here if sound is turned on later.
local loaded = false

-- The audio device while nothing plays --------------------------------------
-- For as long as the device is open, OpenAL's mixer keeps waking the CPU and
-- the sound hardware stays on, even in silence. A puzzle is mostly silence,
-- so after sound.idleAfter seconds without one the device is paused, and the
-- next sound resumes it. LÖVE has no call for this: it's OpenAL Soft's
-- ALC_SOFT_pause_device extension, reached through LuaJIT's FFI. Where the
-- FFI, the library or the extension isn't there, the device just stays open.
-- (LÖVE's own audio thread can't be stopped, and keeps ticking either way.)
--
-- The game runs on many systems, each with its own OpenAL and sound driver,
-- and on some a paused device doesn't come back by itself (OpenAL Soft 1.20
-- and later, on an ALSA device without mmap access: its mixer never restarts
-- the stream it dropped). So this takes nothing on trust:
--   * The first pause of a session is a trial, in silence: the device is
--     paused, resumed at once, and a silent sound is played and watched. Only
--     if that sound moves is the device paused for real from then on.
--   * The sound that resumes the device waits LEAD_IN seconds, so hardware
--     that takes a moment to come back doesn't swallow its start, and it is
--     watched in the same way.
--   * A watched sound that hasn't moved after WATCH_AFTER seconds means the
--     device didn't come back: it's resumed again and reset (which does
--     restart it), pausing is turned off, and sound.onStall() is called so
--     the setting is saved off and it never happens on that system again.
--   * Settings → Audio power saving turns it off by hand (for hardware that
--     pops when its sound stream starts).

sound.idlePause = true -- the setting; see sound.setIdlePause
sound.idleAfter = 10   -- seconds of silence before the device is paused
sound.onStall = nil    -- called when a resumed device turned out stuck
local LEAD_IN = 0.06
-- Long enough for a sound server that takes its time waking its output: a
-- false alarm would turn the setting off where it works.
local WATCH_AFTER = 1.0
local PROBE_RATE, PROBE_SECONDS = 8000, 3 -- the trial's silent sound

local device          -- nil: not looked for yet; false: it can't be paused
local paused = false
local lastPlay = 0    -- when a sound was last asked for
local held, holdUntil = nil, 0 -- the sound waiting out the lead-in
local verify = false  -- the next sound started is the first since a resume
local watch           -- { src, at, trial }: a sound to look at, and when
local tried = false   -- the trial has been run
local probe           -- its silent sound

local function findDevice()
    device = false
    pcall(function()
        local ffi = require("ffi")
        ffi.cdef([[
            typedef struct ALCdevice_struct ALCdevice;
            typedef struct ALCcontext_struct ALCcontext;
            ALCcontext *alcGetCurrentContext(void);
            ALCdevice *alcGetContextsDevice(ALCcontext *context);
            char alcIsExtensionPresent(ALCdevice *device, const char *extname);
            void alcDevicePauseSOFT(ALCdevice *device);
            void alcDeviceResumeSOFT(ALCdevice *device);
            char alcResetDeviceSOFT(ALCdevice *device, const int *attribs);
        ]])
        -- the library LÖVE itself uses: already loaded on Linux and macOS,
        -- by name on Windows
        local lib
        for _, name in ipairs({ false, "OpenAL32" }) do
            local ok, found = pcall(function()
                local l = name and ffi.load(name) or ffi.C
                return l.alcDevicePauseSOFT and l.alcDeviceResumeSOFT and l
            end)
            if ok and found then
                lib = found
                break
            end
        end
        if not lib then return end
        local context = lib.alcGetCurrentContext()
        if context == nil then return end
        local dev = lib.alcGetContextsDevice(context)
        if dev == nil or lib.alcIsExtensionPresent(dev, "ALC_SOFT_pause_device") == 0 then return end
        device = {
            pause = function() lib.alcDevicePauseSOFT(dev) end,
            resume = function() lib.alcDeviceResumeSOFT(dev) end,
        }
        -- a full restart of the device, for when resuming wasn't enough
        -- (older OpenAL Soft doesn't have it)
        if pcall(function() return lib.alcResetDeviceSOFT end) then
            device.reset = function() lib.alcResetDeviceSOFT(dev, nil) end
        end
    end)
end

local function resumeDevice()
    paused = false
    if not sound.failResume then pcall(device.resume) end -- failResume: for dev/scenetest.lua
end

-- The trial: pause, resume, and play a silent sound to watch. False if it
-- couldn't be set up (then the device is simply paused, and the first sound
-- to resume it is the one watched).
local function tryOut(now)
    local ok = pcall(function()
        if not probe then
            local data = love.sound.newSoundData(PROBE_RATE * PROBE_SECONDS, PROBE_RATE, 16, 1)
            probe = love.audio.newSource(data, "static")
        end
        device.pause()
        resumeDevice()
        probe:stop()
        probe:play()
    end)
    if ok then watch = { src = probe, at = now + WATCH_AFTER, trial = true } end
    return ok
end

-- The device didn't come back from a pause: bring it back by every means,
-- and don't pause it again.
local function recover()
    watch = nil
    pcall(device.resume)
    if device.reset then pcall(device.reset) end
    sound.idlePause = false
    if sound.onStall then sound.onStall() end
end

-- Starts a sound now.
local function start(name)
    local src = sources[name]
    if not (src and sound.enabled) then return end
    local function play()
        local s = src
        if src:isPlaying() then s = src:clone() end
        s:play()
        return s, s:isPlaying()
    end
    local ok, playing, started = pcall(play)
    if not ok then return end
    if verify then
        verify = false
        if started then
            watch = { src = playing, at = love.timer.getTime() + WATCH_AFTER }
        else
            -- a device that failed to restart drops every sound at once
            recover()
            pcall(play)
        end
    elseif watch and watch.src == playing then
        watch.at = love.timer.getTime() + WATCH_AFTER -- started over: look later
    end
end

-- WATCH_AFTER seconds after the first sound since a resume: if it's still
-- "playing" but hasn't moved, nothing is mixing.
local function checkWatch()
    local src, trial = watch.src, watch.trial
    watch = nil
    local ok, stuck = pcall(function()
        return src:isPlaying() and src:tell("samples") == 0
    end)
    if trial then pcall(function() src:stop() end) end
    if ok and stuck then recover() end
end

-- Called every pass of the main loop.
function sound.update()
    if not (loaded and love.audio) then return end
    local now = love.timer.getTime()
    if held and now >= holdUntil then
        local name = held
        held = nil
        start(name)
    end
    if watch and now >= watch.at then checkWatch() end

    if paused or not sound.idlePause or device == false then return end
    if now - lastPlay < sound.idleAfter or held or watch then return end
    if device == nil then findDevice() end
    if not device then return end
    local ok, playing = pcall(love.audio.getActiveSourceCount)
    if not ok or playing > 0 then return end
    if not tried then
        tried = true
        if tryOut(now) then return end -- paused for real once the trial has passed
    end
    paused = pcall(device.pause)
end

-- Settings → Audio power saving. Turning it off wakes a paused device.
function sound.setIdlePause(on)
    sound.idlePause = on and true or false
    if not on and paused then resumeDevice() end
end

-- "paused", "running", "unavailable" (it can't be paused here) or "unknown"
-- (not looked for yet). For the development tests.
function sound.deviceState()
    if paused then return "paused" end
    if device == nil then return "unknown" end
    return device and "running" or "unavailable"
end

function sound.load()
    if loaded then return end
    loaded = true
    local ok = pcall(function()
        if not love.audio then require("love.audio") end
        if not love.sound then require("love.sound") end
        for name, make in pairs(DEFS) do
            sources[name] = love.audio.newSource(make(), "static")
        end
    end)
    if not ok then sources = {} end
    lastPlay = love.timer.getTime()
end

function sound.play(name)
    if not sound.enabled then return end
    if not sources[name] then return end
    local now = love.timer.getTime()
    lastPlay = now
    if paused then
        resumeDevice()
        holdUntil = now + LEAD_IN
        verify = true
    end
    if now < holdUntil then
        held = name -- only the latest sound waits; an earlier one is dropped
        return
    end
    start(name)
end

return sound
