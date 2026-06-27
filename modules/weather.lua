--[[ vox_lib weather/clock — HELIX port of a FiveM cinematic weather/clock slice.
     Built on the HELIX Sky API verified from real shipping HELIX code (qb-weathersync in the VaultCache):
        local sky = Sky()                          -- constructor; works client AND server
        sky:SetTimeOfDay(HHMM)                     -- 1400 = 14:00 ;  sky:GetTimeOfDay() reads it back
        sky:SetAnimateTimeOfDay(bool)              -- false = freeze the clock, true = run the day/night cycle
        sky:ChangeWeather(WeatherType.X, sec?)     -- global WeatherType enum, optional transition seconds
     Keeps THE CONTRACT: every verb FAILS GRACEFULLY with a result table — never hangs, never throws.
     PascalCase verb names preserve the source contract (cinematic/cutscene consumers consume these); the ox_lib-compat surface stays
     camelCase. PROBE-CONFIRM the exact time unit / animate behaviour in-world (real-code-derived, not yet self-probed). ]]

local function getSky()
    -- Sky is a callable CLASS TABLE (probe-verified 2026-06-26: type(Sky)=='table', Sky() returns an instance with
    -- SetTimeOfDay/GetTimeOfDay/SetAnimateTimeOfDay/ChangeWeather/GetWeather + sun/moon/fog/cloud controls), NOT a function.
    if Sky == nil then return nil end
    local ok, s = pcall(function() return Sky() end)
    if ok and s then return s end
    return nil
end

-- HELIX-native WeatherType names (the 13 from the enum)
local NATIVE = { "ClearSkies", "Cloudy", "Foggy", "Overcast", "PartlyCloudy", "Rain", "RainLight",
                 "RainThunderstorm", "SandDustCalm", "SandDustStorm", "Snow", "SnowBlizzard", "SnowLight" }
-- GTA-style aliases (FiveM ESX/qb resources use these) → closest HELIX type, so converted
-- resources calling SetWeather('THUNDER') still resolve. Preserve-don't-disable: alias, don't drop.
local ALIAS = {
    EXTRASUNNY = "ClearSkies", CLEAR = "ClearSkies", NEUTRAL = "ClearSkies", CLOUDS = "Cloudy",
    SMOG = "Foggy", FOGGY = "Foggy", OVERCAST = "Overcast", CLEARING = "PartlyCloudy", CLOUDY = "Cloudy",
    RAIN = "Rain", DRIZZLE = "RainLight", THUNDER = "RainThunderstorm", THUNDERSTORM = "RainThunderstorm",
    SNOW = "Snow", BLIZZARD = "SnowBlizzard", SNOWLIGHT = "SnowLight", XMAS = "Snow",
    HALLOWEEN = "Foggy", RAINHALLOWEEN = "Rain", SNOWHALLOWEEN = "Snow", SANDSTORM = "SandDustStorm",
}

local function resolveWeather(name)
    -- WeatherType is a probe-verified table whose values are UDS_Weather_Settings asset refs; index it by name.
    if name == nil or WeatherType == nil then return nil end
    local up = tostring(name):upper()
    for _, n in ipairs(NATIVE) do
        if up == n:upper() then return WeatherType and WeatherType[n], n end
    end
    local mapped = ALIAS[up]
    if mapped then return WeatherType and WeatherType[mapped], mapped end
    return nil
end

-- tracked state for GetSky readback (HELIX has no live server-weather authority to query for the active type)
local _state = { weather = "ClearSkies", forcingTime = false }
local _tween, _tweenActive = 0, false   -- monotonic tween id (a new time-tween supersedes the old) + active flag

function lib.SetWeather(weatherType, transitionSec)
    local sky = getSky(); if not sky then return { ok = false, error = "Sky() unavailable on this side/build" } end
    local enum, resolved = resolveWeather(weatherType)
    if not enum then return { ok = false, error = "unknown weather type: " .. tostring(weatherType) } end
    local ok = pcall(function() sky:ChangeWeather(enum, (type(transitionSec) == "number" and transitionSec) or 0) end)
    if not ok then return { ok = false, error = "ChangeWeather failed" } end
    _state.weather = resolved
    return { ok = true, value = resolved }
end

-- HELIX has no foreign server-weather to resync to (that's a future a future bridge resource concern per the scope boundary),
-- so "clear" = restore a clean default. Smooth transition so it doesn't snap.
function lib.ClearWeather()
    return lib.SetWeather("ClearSkies", 5)
end

-- parse a time arg → HHMM integer on the 0-2400 clock (1400 = 14:00)
local function toHHMM(t)
    if type(t) == "number" then return math.floor(t) % 2400 end
    if type(t) == "table" then
        local h = math.floor(tonumber(t.hour) or 0) % 24
        local m = math.floor(tonumber(t.minute) or 0) % 100   -- UDS minutes run 0-99 within an hour
        return h * 100 + m
    end
    return nil
end

local function ease(kind, x)
    if kind == "linear" then return x end
    if kind == "easeIn" then return x * x end
    if kind == "easeOut" then return 1 - (1 - x) * (1 - x) end
    return x < 0.5 and (2 * x * x) or (1 - ((-2 * x + 2) ^ 2) / 2)   -- easeInOut (default)
end

-- Smoothly interpolate the clock from NOW to `target` HHMM over durationSec (eased; shortest-path on the 0-2400 circle).
-- Async / fire-and-forget via the native Timer; freezes the day/night cycle for the move. This is the cinematic touch
-- the source FiveM lib couldn't do (GTA's NetworkOverrideClockTime is an instant snap).
function lib.InterpolateTime(target, durationSec, easing)
    local sky = getSky(); if not sky then return { ok = false, error = "Sky() unavailable" } end
    local hhmm = toHHMM(target); if not hhmm then return { ok = false, error = "bad target time" } end
    if type(Timer) ~= "table" or type(Timer.SetTimeout) ~= "function" then
        return lib.SetTime(hhmm)   -- no timer available → instant fallback
    end
    local from; pcall(function() from = sky:GetTimeOfDay() end); from = (from or hhmm) % 2400
    local delta = hhmm - from                                   -- shortest-path on the circle
    if delta > 1200 then delta = delta - 2400 elseif delta < -1200 then delta = delta + 2400 end
    local duration = math.max(0.05, tonumber(durationSec) or 1.5)
    local steps = math.max(1, math.floor(duration * 25))        -- ~25 fps
    local interval = (duration * 1000) / steps
    _tween = _tween + 1; local id = _tween; _tweenActive = true; _state.forcingTime = true
    pcall(function() if type(sky.SetAnimateTimeOfDay) == "function" then sky:SetAnimateTimeOfDay(false) end end)
    local i = 0
    local function stepFn()
        if id ~= _tween then return end                         -- superseded by a newer tween/instant set
        i = i + 1
        pcall(function() sky:SetTimeOfDay((from + delta * ease(easing, i / steps)) % 2400) end)
        if i < steps then
            Timer.SetTimeout(stepFn, interval)
        else
            pcall(function() sky:SetTimeOfDay(hhmm) end)         -- exact landing
            _tweenActive = false
        end
    end
    stepFn()
    return { ok = true, value = hhmm, transitioning = true }
end

function lib.IsTimeInterpolating() return _tweenActive end

-- t: {hour,minute} or HHMM number. transitionSec>0 → smooth eased interpolation; else instant. Freezes the clock.
function lib.SetTime(t, transitionSec)
    local hhmm = toHHMM(t)
    if not hhmm then return { ok = false, error = "SetTime expects {hour,minute} or an HHMM number" } end
    if type(transitionSec) == "number" and transitionSec > 0 then
        return lib.InterpolateTime(hhmm, transitionSec)
    end
    local sky = getSky(); if not sky then return { ok = false, error = "Sky() unavailable" } end
    _tween = _tween + 1; _tweenActive = false   -- cancel any running tween
    local ok = pcall(function()
        sky:SetTimeOfDay(hhmm)
        if type(sky.SetAnimateTimeOfDay) == "function" then sky:SetAnimateTimeOfDay(false) end
    end)
    if not ok then return { ok = false, error = "SetTimeOfDay failed" } end
    _state.forcingTime = true
    return { ok = true, value = hhmm }
end

-- release the time override → resume the live day/night cycle
function lib.ClearTime()
    local sky = getSky(); if not sky then return { ok = false, error = "Sky() unavailable" } end
    pcall(function() if type(sky.SetAnimateTimeOfDay) == "function" then sky:SetAnimateTimeOfDay(true) end end)
    _state.forcingTime = false
    return { ok = true }
end

-- diagnostic readback
function lib.GetSky()
    local sky = getSky(); if not sky then return { ok = false, error = "Sky() unavailable" } end
    local time
    pcall(function() time = sky:GetTimeOfDay() end)
    local hour = time and math.floor(time / 100) or nil
    local minute = time and (math.floor(time) % 100) or nil
    return { ok = true, value = { time = time, hour = hour, minute = minute,
                                  weather = _state.weather, forcingTime = _state.forcingTime } }
end

-- cinematic compositions (the source contract — cinematic consumers consume these unchanged): force a whole look atomically
function lib.SetCinematicSky(opts)
    if type(opts) ~= "table" then return { ok = false, error = "opts table required" } end
    if opts.time ~= nil then local r = lib.SetTime(opts.time); if not r.ok then return r end end
    if opts.weather ~= nil then local r = lib.SetWeather(opts.weather, opts.transition); if not r.ok then return r end end
    return { ok = true }
end

function lib.ClearCinematicSky()
    lib.ClearTime()
    lib.ClearWeather()
    return { ok = true }
end

-- expose the resolvable weather names (for a dev menu / validation)
lib.WeatherTypes = NATIVE

return lib.SetWeather
