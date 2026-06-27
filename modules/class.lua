--[[ lib.class(name, super) — OxClass-style classes (clean-room from the ox_lib Class contract).
     Contract: Class:new(...) instantiates and calls Class:constructor(...); self:super(...) invokes the parent constructor
     (chaining through multiple inheritance levels); self.private holds per-instance private data; class.__name is the name.
     Implementation is our own, metatable-based, written from the documented behavior (no ox source read).
     NOTE: strict "private is hidden outside class methods" enforcement is a Stage-1.5 refinement; today self.private is a
     functional per-instance store carrying the documented 'private' metatable marker. ]]

local PRIVATE_MT = { __metatable = "private" }

-- Returns the self:super(...) function for a given class level, rebinding to the next parent as the chain unwinds.
local function makeSuper(klass, obj)
    local parent = klass.__super
    return function(_, ...)
        if parent and parent.constructor then
            local saved = rawget(obj, "super")
            rawset(obj, "super", makeSuper(parent, obj))   -- inside parent ctor, self:super -> grandparent
            parent.constructor(obj, ...)
            rawset(obj, "super", saved)
        end
    end
end

local function class(name, super)
    assert(type(name) == "string", "class name must be a string")

    local c = { __name = name }
    c.__index = c

    if super then
        assert(type(super) == "table" and super.__name, "super must be a class")
        c.__super = super
        setmetatable(c, { __index = super })   -- methods/fields inherit up the chain
    end

    function c.new(self, ...)
        local obj = setmetatable({}, self)
        rawset(obj, "private", setmetatable({}, PRIVATE_MT))
        rawset(obj, "super", makeSuper(self, obj))
        local ctor = self.constructor          -- resolves up the inheritance chain
        if ctor then ctor(obj, ...) end
        rawset(obj, "super", nil)              -- super is only meaningful during construction
        return obj
    end

    return c
end

lib.class = class
return class
