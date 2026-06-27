--[[ lib.math — standard math library + extras (clean-room from the ox_lib Math contract).
     Pure subset implemented now: clamp, round, groupdigits, hextorgb, tohex, toscalars.
     DEFERRED to Stage 5 (need HELIX Vector + per-game-frame iteration; not pure-Lua): tovector, torgba, normaltorotation,
     interp, lerp. Consumers calling those hit a surfaced nil (contain_guard reports it) until Stage 5 — intentional.
     lib.math indexes through to the standard math lib. ]]

local libmath = setmetatable({}, { __index = math })

-- clamp(n, lower, upper)
function libmath.clamp(n, lower, upper)
    if n < lower then return lower end
    if n > upper then return upper end
    return n
end

-- round(value, places): whole number, or to `places` decimals. Half rounds up.
function libmath.round(value, places)
    value = tonumber(value)
    places = tonumber(places)
    if not places or places == 0 then
        return math.floor(value + 0.5)
    end
    local mult = 10 ^ places
    return math.floor(value * mult + 0.5) / mult
end

-- groupdigits(number, sep=','): thousands separators, preserving sign + decimal part.
function libmath.groupdigits(number, sep)
    sep = sep or ","
    local sign, int, frac = tostring(number):match("^(%-?)(%d*)(%.?%d*)$")
    if not int or int == "" then return tostring(number) end
    local k
    repeat
        int, k = int:gsub("^(%d+)(%d%d%d)", "%1" .. sep .. "%2")
    until k == 0
    return sign .. int .. (frac or "")
end

-- hextorgb('eb4034' or '#eb4034') -> r, g, b
function libmath.hextorgb(input)
    input = tostring(input):gsub("^#", "")
    return tonumber(input:sub(1, 2), 16), tonumber(input:sub(3, 4), 16), tonumber(input:sub(5, 6), 16)
end

-- tohex(n, upper) -> hex string. NOTE: returns bare hex digits (no '0x' prefix); verify the prefix convention vs upstream.
function libmath.tohex(n, upper)
    return string.format(upper and "%X" or "%x", tonumber(n))
end

-- toscalars(input, min, max, round) -> varargs of numbers parsed from a string, optionally clamped + rounded.
function libmath.toscalars(input, min, max, doRound)
    local out = {}
    for num in tostring(input):gmatch("%-?%d*%.?%d+") do
        local v = tonumber(num)
        if min then v = math.max(min, v) end
        if max then v = math.min(max, v) end
        if doRound then v = math.floor(v + 0.5) end
        out[#out + 1] = v
    end
    return table.unpack(out)
end

lib.math = libmath
return libmath
