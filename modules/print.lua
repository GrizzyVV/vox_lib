--[[ lib.print.{error,warn,info,verbose,debug}(...) — level-filtered console logging (clean-room from the ox_lib Print
     contract). Level is read from convars `ox:printlevel:<resource>` then `ox:printlevel` (default "info"); a message at a
     level less severe than the current threshold is skipped. Tables are pretty-printed. Resource name is prefixed.
     Uses GetConvar from the compat layer when present; defaults to "info" otherwise. ]]

local LEVELS = { error = 1, warn = 2, info = 3, verbose = 4, debug = 5 }

local function resourceName()
    return (cache and cache.resource) or (GetCurrentResourceName and GetCurrentResourceName()) or "?"
end

local function threshold()
    local res = resourceName()
    local lvl = ""
    if GetConvar then
        lvl = GetConvar("ox:printlevel:" .. res, "")
        if lvl == "" then lvl = GetConvar("ox:printlevel", "info") end
    end
    return LEVELS[lvl] or LEVELS.info
end

-- pretty-print a value; tables are rendered recursively (cycle-safe), other types via tostring
local function pretty(v, seen, indent)
    if type(v) ~= "table" then return tostring(v) end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    indent = indent or ""
    local inner = indent .. "  "
    local parts = {}
    for k, val in pairs(v) do
        parts[#parts + 1] = inner .. "[" .. (type(k) == "string" and ("'" .. k .. "'") or tostring(k)) .. "] = " .. pretty(val, seen, inner)
    end
    seen[v] = nil
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function emitter(levelName)
    local sev = LEVELS[levelName]
    return function(...)
        if sev > threshold() then return end
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = pretty((select(i, ...))) end
        print(string.format("[%s] [%s] %s", resourceName(), levelName:upper(), table.concat(parts, " ")))
    end
end

lib.print = {
    error   = emitter("error"),
    warn    = emitter("warn"),
    info    = emitter("info"),
    verbose = emitter("verbose"),
    debug   = emitter("debug"),
}
return lib.print
