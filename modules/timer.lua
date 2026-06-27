--[[ lib.timer(time, onEnd, async) -> OxTimer (clean-room from the ox_lib Timer contract). Built on lib.class + the scheduler.
     Fires onEnd after `time` ms. async=true runs on its own thread (non-blocking); else it blocks the calling thread (so call
     a blocking timer from inside a thread). Methods: pause / play / isPaused / forceEnd(triggerOnEnd) / getTimeLeft(format) /
     restart. Elapsed is tracked via os.clock() deltas (HELIX has no ms game-timer); poll cadence = 50ms. ]]

local OxTimer = lib.class("OxTimer")
local POLL = 50  -- ms

function OxTimer:constructor(duration, onEnd, async)
    self.duration = duration
    self.onEnd = onEnd
    self.elapsed = 0
    self.paused = false
    self.done = false
    self:_run(async)
end

function OxTimer:_run(async)
    self.done = false
    local function loop()
        local last = os.clock() * 1000
        while not self.done do
            Wait(POLL)
            local now = os.clock() * 1000
            local delta = now - last
            last = now
            if not self.paused then
                self.elapsed = self.elapsed + delta
                if self.elapsed >= self.duration then
                    self.done = true
                    if self.onEnd then self.onEnd() end
                    return
                end
            end
        end
    end
    if async then CreateThread(loop) else loop() end
end

function OxTimer:pause() self.paused = true end
function OxTimer:play() self.paused = false end
function OxTimer:isPaused() return self.paused end

function OxTimer:forceEnd(triggerOnEnd)
    self.done = true
    if triggerOnEnd and self.onEnd then self.onEnd() end
end

function OxTimer:getTimeLeft(format)
    local left = self.duration - self.elapsed
    if left < 0 then left = 0 end
    local function r2(x) return tonumber(string.format("%.2f", x)) end
    if format == "ms" then return left end
    if format == "s" then return r2(left / 1000) end
    if format == "m" then return r2(left / 60000) end
    if format == "h" then return r2(left / 3600000) end
    return { ms = left, s = r2(left / 1000), m = r2(left / 60000), h = r2(left / 3600000) }
end

function OxTimer:restart()
    self.elapsed = 0
    self.paused = false
    if self.done then self:_run(true) end   -- relaunch (async) if it had already ended
end

lib.timer = function(time, onEnd, async) return OxTimer:new(time, onEnd, async) end
return lib.timer
