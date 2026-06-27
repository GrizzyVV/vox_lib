--[[ lib.array — JS-like Array class (clean-room from the ox_lib Array contract). Built on lib.class.
     Every method takes the array as its first (self) arg, so both call styles work: arr:map(fn) AND lib.array.map(arr, fn).
     Methods that produce a new collection return an Array (chainable). Implementation is our own, from the documented API.
     AMBIGUITY FLAGGED: slice() treats start/finish as INCLUSIVE 1-based (Lua convention); verify vs upstream if a consumer
     relies on JS exclusive-end semantics. ]]

local Array = lib.class("Array")

local function newArray(t)
    return setmetatable(t, Array)
end

function Array:constructor(...)
    local n = select("#", ...)
    for i = 1, n do self[i] = (select(i, ...)) end
end

-- static: build from a table / string (per char) / iterator function
function Array.from(iter)
    local t, ty = {}, type(iter)
    if ty == "table" then
        for i = 1, #iter do t[i] = iter[i] end
    elseif ty == "string" then
        for i = 1, #iter do t[i] = iter:sub(i, i) end
    elseif ty == "function" then
        while true do
            local v = iter()
            if v == nil then break end
            t[#t + 1] = v
        end
    end
    return newArray(t)
end

-- static: is this an Array instance or an array-like table?
function Array.isArray(t)
    if type(t) ~= "table" then return false end
    if getmetatable(t) == Array then return true end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

function Array.at(self, index)
    if index < 0 then index = #self + index + 1 end
    return self[index]
end

function Array.push(self, ...)
    local base = #self
    for i = 1, select("#", ...) do self[base + i] = (select(i, ...)) end
    return #self
end

function Array.pop(self)
    local n = #self
    local v = self[n]
    self[n] = nil
    return v
end

function Array.shift(self)
    return table.remove(self, 1)
end

function Array.unshift(self, ...)
    for i = select("#", ...), 1, -1 do
        table.insert(self, 1, (select(i, ...)))
    end
    return #self
end

function Array.slice(self, start, finish)
    local len = #self
    start = start or 1
    finish = finish or len
    if start < 0 then start = len + start + 1 end
    if finish < 0 then finish = len + finish + 1 end
    local t = {}
    for i = start, finish do t[#t + 1] = self[i] end
    return newArray(t)
end

function Array.map(self, fn)
    local t = {}
    for i = 1, #self do t[i] = fn(self[i], i, self) end
    return newArray(t)
end

function Array.filter(self, testFn)
    local t = {}
    for i = 1, #self do
        if testFn(self[i]) then t[#t + 1] = self[i] end
    end
    return newArray(t)
end

function Array.forEach(self, cb, reverse)
    if reverse then
        for i = #self, 1, -1 do cb(self[i], i) end
    else
        for i = 1, #self do cb(self[i], i) end
    end
end

function Array.every(self, testFn)
    for i = 1, #self do
        if not testFn(self[i]) then return false end
    end
    return true
end

function Array.findIndex(self, testFn, reverse)
    if reverse then
        for i = #self, 1, -1 do if testFn(self[i]) then return i end end
    else
        for i = 1, #self do if testFn(self[i]) then return i end end
    end
    return nil
end

function Array.find(self, testFn, reverse)
    local i = Array.findIndex(self, testFn, reverse)
    if i then return self[i] end
    return nil
end

function Array.indexOf(self, value, reverse)
    if reverse then
        for i = #self, 1, -1 do if self[i] == value then return i end end
    else
        for i = 1, #self do if self[i] == value then return i end end
    end
    return nil
end

function Array.reduce(self, reducer, initialValue)
    local acc, startI
    if initialValue ~= nil then
        acc, startI = initialValue, 1
    else
        acc, startI = self[1], 2
    end
    for i = startI, #self do acc = reducer(acc, self[i], i) end
    return acc
end

function Array.join(self, separator)
    separator = separator or ","
    local t = {}
    for i = 1, #self do t[i] = tostring(self[i]) end
    return table.concat(t, separator)
end

function Array.fill(self, value, start, endIndex)
    start = start or 1
    endIndex = endIndex or #self
    for i = start, endIndex do self[i] = value end
    return self
end

function Array.reverse(self)
    local n = #self
    for i = 1, n // 2 do
        self[i], self[n - i + 1] = self[n - i + 1], self[i]
    end
    return self
end

function Array.toReversed(self)
    local n, t = #self, {}
    for i = 1, n do t[i] = self[n - i + 1] end
    return newArray(t)
end

-- static: merge multiple arrays into a new array
function Array.merge(...)
    local t = {}
    for _, a in ipairs({ ... }) do
        for i = 1, #a do t[#t + 1] = a[i] end
    end
    return newArray(t)
end

lib.array = Array
lib.isArray = Array.isArray
return Array
