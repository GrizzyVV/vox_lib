--[[ lib.hook (HookPipeline) + lib.registerHook (EventHook) — clean-room from the ox_lib Hooks contract.
     A pipeline runs registered hook callbacks in registration order on dispatch(payload); a hook returning false REJECTS
     the action (result.ok=false, dispatch stops). dispatch returns a to-be-closed finalisation handle (Lua 5.4 `<close>`)
     that fires :on(ok, payload) handlers when the variable closes. lib.registerHook adds a hook to a pipeline by event name
     and returns a management handle (on/off/remove).
     SCOPE: LOCAL (same-state) pipelines fully implemented + verified. CROSS-RESOURCE dispatch (pipeline in resource A, hooks
     registered from resource B) needs a SYNCHRONOUS cross-resource transport (dispatch must collect remote hook results before
     proceeding — harder than the async callback round-trip); RESIDUAL, deferred (see ox_lib_REBUILD_PLAN Stage 3 tail). ]]

local _pipelines = {}   -- event -> pipeline created in THIS state

local HookPipeline = lib.class("HookPipeline")

function HookPipeline:constructor(event, filter)
    self.event = event
    self.filter = filter
    self.private.hooks = {}     -- id -> { handler, options, resource, post }
    self.private.order = {}     -- registration order of ids
    self.private.nextId = 0
    _pipelines[event] = self
end

function HookPipeline:registerHook(handler, options)
    self.private.nextId = self.private.nextId + 1
    local id = self.private.nextId
    self.private.hooks[id] = { handler = handler, options = options or {}, resource = (cache and cache.resource) }
    self.private.order[#self.private.order + 1] = id
    return id
end

function HookPipeline:remove(hookId)
    if hookId ~= nil then
        self.private.hooks[hookId] = nil
    else                                            -- no id: remove all hooks for the invoking resource
        local res = cache and cache.resource
        for id, h in pairs(self.private.hooks) do
            if h.resource == res then self.private.hooks[id] = nil end
        end
    end
end

function HookPipeline:dispatch(payload)
    local ok = true
    for _, id in ipairs(self.private.order) do
        local h = self.private.hooks[id]
        if h then
            if (not self.filter) or self.filter(h, payload) then
                if h.handler(payload) == false then ok = false; break end
            end
        end
    end
    for _, id in ipairs(self.private.order) do       -- fire per-hook post handlers (EventHook :on)
        local h = self.private.hooks[id]
        if h and h.post then h.post(ok, payload) end
    end
    local handlers = {}                              -- finalisation handle (to-be-closed)
    return setmetatable({ ok = ok, payload = payload }, {
        __index = { on = function(_, fn) handlers[#handlers + 1] = fn end },
        __close = function(self) for _, fn in ipairs(handlers) do fn(self.ok, self.payload) end end,
    })
end

lib.hook = HookPipeline   -- lib.hook:new(event, filter)

-- EventHook: register a hook into a (local) pipeline by event name; return a management handle.
function lib.registerHook(eventName, handler, options)
    local pipeline = _pipelines[eventName]
    local id = pipeline and pipeline:registerHook(handler, options) or nil
    return {
        on     = function(_, fn) if pipeline and id and pipeline.private.hooks[id] then pipeline.private.hooks[id].post = fn end end,
        off    = function(_)     if pipeline and id and pipeline.private.hooks[id] then pipeline.private.hooks[id].post = nil end end,
        remove = function(_)     if pipeline and id then pipeline:remove(id) end end,
    }
end

return lib.hook
