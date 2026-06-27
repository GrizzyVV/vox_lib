--[[ dev-only minimal scheduler — provides Wait + CreateThread for the STANDALONE vox_lib test package. Converted
     consumers get the real scheduler from the host build's compat; this is just so the return-value UI components
     (alert/progress/input/skillCheck) can be exercised by the /v* test commands here. Coroutine + Timer based. ]]

if type(Wait) ~= "function" then
    function CreateThread(fn)
        if type(fn) ~= "function" then return end
        local co = coroutine.create(fn)
        local function resume(...)
            if coroutine.status(co) == "dead" then return end
            local ok, delay = coroutine.resume(co, ...)
            if not ok then pcall(print, "[devsched] thread error: " .. tostring(delay)); return end
            if coroutine.status(co) ~= "dead" and Timer and Timer.SetTimeout then
                Timer.SetTimeout(function() resume() end, math.max(1, tonumber(delay) or 1))   -- Timer rejects 0
            end
        end
        resume()
    end
    function Wait(ms) return coroutine.yield(ms or 0) end
    SetTimeout = SetTimeout or function(ms, fn) if Timer then Timer.SetTimeout(fn, math.max(1, ms or 1)) end end
end
