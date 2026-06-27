--[[ lib.string — standard string library + extras (clean-room from the ox_lib String contract).
     string.random(pattern, length): pattern chars -> '1'=digit, 'A'=A-Z, 'a'=a-z, '.'=letter-or-digit, '^X'=literal X,
     anything else = itself. length pads/truncates the result. lib.string indexes through to the standard string lib. ]]

local libstring = setmetatable({}, { __index = string })

local DIGITS = "0123456789"
local UPPER  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local LOWER  = "abcdefghijklmnopqrstuvwxyz"
local ALNUM  = DIGITS .. UPPER .. LOWER

local function pick(set)
    local i = math.random(1, #set)
    return set:sub(i, i)
end

function libstring.random(pattern, length)
    assert(type(pattern) == "string", "pattern must be a string")
    local out = {}
    local i, n = 1, #pattern
    while i <= n do
        local c = pattern:sub(i, i)
        if c == "^" then
            i = i + 1
            out[#out + 1] = pattern:sub(i, i)   -- literal next char
        elseif c == "1" then
            out[#out + 1] = pick(DIGITS)
        elseif c == "A" then
            out[#out + 1] = pick(UPPER)
        elseif c == "a" then
            out[#out + 1] = pick(LOWER)
        elseif c == "." then
            out[#out + 1] = pick(ALNUM)
        else
            out[#out + 1] = c
        end
        i = i + 1
    end
    local result = table.concat(out)
    if length then
        if #result > length then
            result = result:sub(1, length)
        elseif #result < length then
            result = result .. string.rep(" ", length - #result)
        end
    end
    return result
end

lib.string = libstring
return libstring
