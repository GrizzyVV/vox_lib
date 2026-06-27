--[[ cache(key, func, timeout) — cached function results (clean-room from the ox_lib Cache contract).
     Global `cache` is callable: returns the stored value for `key`; if empty or expired, calls `func()`, stores, returns it.
     `timeout` (ms) clears the entry after that duration. `cache.resource` / `cache.game` are default keys.
     Time source: os.clock()*1000 (HELIX has no ms game-timer; CPU-seconds based — fine for cache expiry). ]]

local store = {}   -- key -> { value = any, expires = number|nil }

local function nowMs() return os.clock() * 1000 end

cache = setmetatable({}, {
    __call = function(_, key, func, timeout)
        local entry = store[key]
        if entry and (not entry.expires or nowMs() < entry.expires) then
            return entry.value
        end
        local value = func()
        store[key] = { value = value, expires = timeout and (nowMs() + timeout) or nil }
        return value
    end,
})

-- default cache keys (resource/game) — resolved via compat natives when present, else sensible fallbacks
cache.resource = (GetCurrentResourceName and GetCurrentResourceName()) or "unknown"
cache.game = (GetGameName and GetGameName()) or "helix"

lib.cache = cache
return cache
