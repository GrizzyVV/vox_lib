--[[ lib.waitFor(cb, errMessage, timeout) — call cb each tick until it returns a non-nil value (returned), or until
     timeout (ms; default 1000; pass false for no timeout). Runs on the coroutine scheduler (Wait yields to Timer), so call
     it from inside a thread. DEVIATION (documented): on timeout we PRINT the message + return nil rather than throwing —
     a throw could halt the HELIX package; consumers check the return value. ]]

function lib.waitFor(cb, errMessage, timeout)
    local value = cb()
    if value ~= nil then return value end

    if timeout == nil then timeout = 1000 end
    local start = os.clock() * 1000

    while true do
        Wait(0)
        value = cb()
        if value ~= nil then return value end
        if timeout and (os.clock() * 1000 - start) >= timeout then
            print("[vox_lib:waitFor] " .. (errMessage or ("timed out after " .. tostring(timeout) .. "ms")))
            return nil
        end
    end
end

return lib.waitFor
