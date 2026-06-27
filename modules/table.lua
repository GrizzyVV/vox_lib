--[[ lib.table — standard table library + extras (clean-room from the ox_lib Table contract).
     contains / matches / deepclone / merge / freeze / isFrozen. lib.table indexes through to the standard table lib. ]]

local libtable = setmetatable({}, { __index = table })

-- contains(tbl, value): true if a simple value appears as a value in tbl (array or map). Unnested/simple values only.
function libtable.contains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

-- matches(a, b): deep structural equality (keys + values, recursing into tables).
local function matches(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        local bv = b[k]
        if bv == nil or not matches(v, bv) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
libtable.matches = matches

-- deepclone(tbl): recursive copy so no table references remain shared.
local function deepclone(tbl, seen)
    if type(tbl) ~= "table" then return tbl end
    seen = seen or {}
    if seen[tbl] then return seen[tbl] end
    local out = {}
    seen[tbl] = out
    for k, v in pairs(tbl) do
        out[deepclone(k, seen)] = deepclone(v, seen)
    end
    return out
end
libtable.deepclone = deepclone

-- merge(a, b, addDuplicateNumbers=true): merge b into a; nested tables merge recursively; on a duplicate key, numbers ADD
-- (unless addDuplicateNumbers==false), tables recurse, anything else takes b's value. Returns a.
local function merge(a, b, addDuplicateNumbers)
    if addDuplicateNumbers == nil then addDuplicateNumbers = true end
    for k, v in pairs(b) do
        local av = a[k]
        if type(av) == "table" and type(v) == "table" then
            merge(av, v, addDuplicateNumbers)
        elseif addDuplicateNumbers and type(av) == "number" and type(v) == "number" then
            a[k] = av + v
        else
            a[k] = v
        end
    end
    return a
end
libtable.merge = merge

-- freeze(tbl): read-only proxy. Nested tables stay mutable (per contract). isFrozen via the proxy marker.
local FROZEN = setmetatable({}, { __mode = "k" })
function libtable.freeze(tbl)
    local proxy = setmetatable({}, {
        __index = tbl,
        __newindex = function() error("cannot modify a frozen table", 2) end,
        __len = function() return #tbl end,
        __pairs = function() return pairs(tbl) end,
        __metatable = "frozen",
    })
    FROZEN[proxy] = true
    return proxy
end

function libtable.isFrozen(tbl)
    return FROZEN[tbl] == true or getmetatable(tbl) == "frozen"
end

lib.table = libtable
return libtable
