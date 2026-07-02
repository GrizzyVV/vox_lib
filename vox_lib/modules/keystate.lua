--[[ lib.keystate — POLLABLE key state over HELIX's event-only input (Input.BindKey / HInputDispatcher delegates). CLIENT.

     WHY: GTA control natives POLL per frame (IsControlPressed/JustPressed/JustReleased); HELIX surfaces input only as
     Pressed/Released EVENTS (Input.lua — no IsKeyDown in the blessed API). So vox_lib maintains a key-state table fed by
     lazy per-key Input.BindKey registrations: polls read the table. Edge flags (just-pressed/just-released) are CONSUME-
     ON-READ (matching the GTA per-frame idiom: true once per press for the first poller that asks).

     GTA CONTROL-ID -> UE KEY: partial best-effort map of the ids the ESX corpus actually uses (default keyboard binds).
     Unknown ids -> nil -> every poll returns false (honest degradation, logged once). ⚠️ IN-ENGINE TEST OWED. ⚠️ Polling
     across the export boundary costs an IPC round-trip per call — fine for interaction prompts, heavy for per-frame loops.
     TODO(probe): stock UE PlayerController:IsInputKeyDown(FKey) — if callable via UnLua, swap internals to true polling. ]]

local held, justP, justR, watched, warned = {}, {}, {}, {}, {}

-- GTA control id (keyboard/mouse pad 0/1/2) -> UE key name (default GTA binds; extend as the corpus demands)
local GTA_KEY = {
    [8] = "S", [9] = "D", [18] = "Enter", [19] = "LeftAlt", [20] = "Z", [21] = "LeftShift", [22] = "SpaceBar",
    [23] = "F", [24] = "LeftMouseButton", [25] = "RightMouseButton", [26] = "C", [27] = "Up", [29] = "B",
    [32] = "W", [33] = "S", [34] = "A", [35] = "D", [36] = "LeftControl", [37] = "Tab", [38] = "E",
    [44] = "Q", [45] = "R", [46] = "E", [47] = "G", [56] = "F9", [57] = "F10", [73] = "X", [74] = "H",
    [137] = "CapsLock", [140] = "R", [141] = "Q", [166] = "F5", [167] = "F6", [168] = "F7", [170] = "F3",
    [176] = "Enter", [177] = "BackSpace", [178] = "Delete", [191] = "Enter", [194] = "BackSpace",
    [201] = "Enter", [217] = "CapsLock", [243] = "Tilde", [244] = "M", [245] = "T", [246] = "Y",
    [249] = "N", [288] = "F1", [289] = "F2", [303] = "U", [311] = "K", [318] = "F5", [322] = "Escape",
    [14] = "MouseScrollDown", [15] = "MouseScrollUp",
}

local function watch(key)
    if watched[key] or not (Input and Input.BindKey) then return end
    watched[key] = true
    Input.BindKey(key, function() held[key] = true; justP[key] = true end, "Pressed")
    Input.BindKey(key, function() held[key] = nil;  justR[key] = true end, "Released")
end

local function resolve(control)
    if type(control) == "string" then return control:lower() end
    local k = GTA_KEY[tonumber(control) or -1]
    if not k then
        if not warned[control] then warned[control] = true
            print("[vox_lib] keystate: unmapped GTA control id " .. tostring(control) .. " -> always false") end
        return nil
    end
    return k:lower()
end

--- isControlPressed(gtaIdOrKeyName) -> boolean (held right now).
--- PROBE-VERIFIED 2026-07-02: HPlayer:IsInputKeyDown(key) IS callable (string + FKey forms) -> TRUE polling for the
--- held-check (no binding needed); the BindKey table stays for the edge semantics + as fallback.
function lib.isControlPressed(control)
    local k = resolve(control); if not k then return false end
    if HPlayer and HPlayer.IsInputKeyDown then
        local ok, down = pcall(function() return HPlayer:IsInputKeyDown(k) end)
        if ok and down ~= nil then return down == true end
    end
    watch(k)
    return held[k] == true
end

--- isControlJustPressed(gtaIdOrKeyName) -> boolean ONCE per press (consume-on-read)
function lib.isControlJustPressed(control)
    local k = resolve(control); if not k then return false end
    watch(k)
    if justP[k] then justP[k] = nil; return true end
    return false
end

--- isControlJustReleased(gtaIdOrKeyName) -> boolean ONCE per release (consume-on-read)
function lib.isControlJustReleased(control)
    local k = resolve(control); if not k then return false end
    watch(k)
    if justR[k] then justR[k] = nil; return true end
    return false
end
