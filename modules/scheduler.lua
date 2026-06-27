--[[ OPTIONAL scheduler — provides global `Wait` + `CreateThread` (+ `SetTimeout`) ON TOP OF HELIX's `Timer`, but ONLY if the
     host hasn't already defined them. HELIX has no native Wait/CreateThread; vox_lib's blocking pieces (lib.timer and the
     return-value UI: alertDialog/progressBar/inputDialog/skillCheck) yield through these.

     LOAD MODEL:
     - STANDALONE (vox_lib loaded as its own HELIX package): include this module — it supplies the scheduler so the library
       is self-sufficient.
     - SOURCE-BUNDLED into a host package: the host already provides Wait/CreateThread (via its own compat layer), so the
       `type(Wait) ~= "function"` guard makes this a no-op and the host's scheduler wins.

     Coroutine-based: CreateThread runs fn on a coroutine; each `Wait(ms)` yields the delay, and we reschedule the resume via
     Timer.SetTimeout. Standard Lua 5.4 (probe-verified HELIX runtime). ]]

if type(Wait) ~= "function" then
    function CreateThread(fn)
        if type(fn) ~= "function" then return end
        local co = coroutine.create(fn)
        local function resume(...)
            if coroutine.status(co) == "dead" then return end
            local ok, delay = coroutine.resume(co, ...)
            if not ok then pcall(print, "[vox_lib/scheduler] thread error: " .. tostring(delay)); return end
            if coroutine.status(co) ~= "dead" and Timer and Timer.SetTimeout then
                Timer.SetTimeout(function() resume() end, math.max(1, tonumber(delay) or 1))   -- Timer rejects 0
            end
        end
        resume()
    end

    function Wait(ms) return coroutine.yield(ms or 0) end

    SetTimeout = SetTimeout or function(ms, fn) if Timer then Timer.SetTimeout(fn, math.max(1, ms or 1)) end end
end
