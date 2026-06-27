--[[ lib.progressBar / lib.progressCircle / lib.cancelProgress — timed action progress (clean-room from the ox_lib
     progress contract). RETURN-VALUE + BLOCKING: yields (Wait) until the bar fills (-> true) or is cancelled (-> false).
     MUST be called from a thread (CreateThread); Wait is the bundled coroutine+Timer scheduler. Client-side.
       lib.progressBar({ duration=ms, label, position?='bottom'|'middle', canCancel?, cancelKey?='X' }) -> bool
       lib.progressCircle({ ...same, position?='bottom'|'middle' }) -> bool
       lib.cancelProgress()   -- cancels the active bar (-> the call returns false)
     One bar at a time (ox_lib parity). hEvent reverse channel not needed — Lua owns the timing; the page is pure visual. ]]

local PAGE = "vox_lib/web/progress/index.html"
local _ui, _active, _cancelable = nil, nil, false
local _cancelBound = false

local function ensureUI()
    -- mode 0 = overlay, no input capture (progress must not steal the cursor; cancel is a keybind)
    if not _ui and WebUI then _ui = WebUI("vox_lib_progress", PAGE, 0) end
    return _ui
end

-- bind the cancel key ONCE; it cancels the current run only if that run is cancelable
local function ensureCancelKey(key)
    if _cancelBound or not (Input and Input.BindKey) then return end
    _cancelBound = true
    pcall(function() Input.BindKey(key or "X", function() if _cancelable then _active = nil end end, "Pressed") end)
end

local function runProgress(kind, opts)
    if type(opts) ~= "table" then return false end
    local ui = ensureUI(); if not ui then return false end
    if _active then return false end                 -- one at a time
    local duration = tonumber(opts.duration) or 5000
    local token = {}
    _active, _cancelable = token, (opts.canCancel and true or false)
    if _cancelable then ensureCancelKey(opts.cancelKey) end
    ui:SendEvent("progress:show", {
        kind = kind, duration = duration, label = opts.label or "",
        position = opts.position or "bottom", canCancel = _cancelable, cancelKey = opts.cancelKey or "X",
    })
    -- yield until the duration elapses or the run is cancelled (_active cleared by cancel key / cancelProgress)
    local elapsed = 0
    if type(Wait) == "function" then
        while elapsed < duration and _active == token do Wait(50); elapsed = elapsed + 50 end
    end
    local completed = (_active == token)
    _active, _cancelable = nil, false
    pcall(function() ui:SendEvent("progress:hide", { completed = completed }) end)
    return completed
end

function lib.progressBar(opts)    return runProgress("bar", opts) end
function lib.progressCircle(opts) return runProgress("circle", opts) end
function lib.cancelProgress()     _active = nil end

return lib.progressBar
