--[[ lib.callback — bidirectional request/response callbacks (clean-room from the ox_lib Callback contract).
     ox_lib callbacks RETURN their result (unlike ESX's reply-cb). Rides a net-event transport by design — NOT native
     Callbacks. Native `RegisterCallback`/`TriggerCallback` round-trip fine for SYNC handlers (probe-verified 2026-07-08),
     but they are LESS capable: the responder runs in a non-yieldable context (a yielding handler ERRORS) and only a
     SINGLE return value is marshalled. This net-event transport preserves MULTI-VALUE returns + adds a timeout, matching
     ox_lib's contract. (Post-conversion sync DB means handlers rarely yield; if one does, it must stay synchronous here.)

     API:
       lib.callback.register(name, fn)            -- server: fn(source, ...) -> result ; client: fn(...) -> result
       lib.callback(name, arg2, cb, ...)          -- arg2 = playerId (server→client) | delay/false (client→server)
       lib.callback.await(name, arg2, ...)        -- yields (via scheduler Wait-poll) until the response; returns result

     SIDE: HELIX has no runtime side test, so direction comes from `_VOX_SIDE` ('server'|'client'), set per side at bundle time
     from package.json placement (mirrors ox_lib's per-side build). Both receivers are registered regardless — the wrong-side
     ones simply never get a matching request. `await` polls with Wait (cooperates with the coroutine scheduler) instead of a
     raw coroutine.yield (which the scheduler would misread as a timed Wait). Call await inside a thread. ]]

local _registry = {}   -- name -> fn (callbacks registered in THIS state; fns can't cross the package boundary)
local _pending  = {}   -- reqId -> resolver function
local _cooldown = {}   -- name -> next-allowed-time (ms), for the client `delay`
local _reqId    = 0
local SIDE = _VOX_SIDE or "server"
local AWAIT_TIMEOUT = 5000   -- ms; await returns nil if no response by then

local SREQ, SRES = "vox_cb:sreq", "vox_cb:sres"   -- client → server request / response
local CREQ, CRES = "vox_cb:creq", "vox_cb:cres"   -- server → client request / response

local function nextId() _reqId = _reqId + 1; return _reqId end

-- Receivers (both directions registered — no runtime side test). The responder runs the registered fn and ships its RETURN.
RegisterServerEvent(SREQ, function(source, name, reqId, ...)
    local fn = _registry[name]; if not fn then return end
    local res = table.pack(fn(source, ...))   -- table.pack/.n preserves nil holes + arity (`{...}` truncates at the 1st nil)
    TriggerClientEvent(source, SRES, reqId, table.unpack(res, 1, res.n))
end)
RegisterClientEvent(SRES, function(reqId, ...)
    local resolve = _pending[reqId]; if not resolve then return end
    _pending[reqId] = nil; resolve(...)
end)
RegisterClientEvent(CREQ, function(name, reqId, ...)
    local fn = _registry[name]; if not fn then return end
    local res = table.pack(fn(...))
    TriggerServerEvent(CRES, reqId, table.unpack(res, 1, res.n))
end)
RegisterServerEvent(CRES, function(source, reqId, ...)
    local resolve = _pending[reqId]; if not resolve then return end
    _pending[reqId] = nil; resolve(...)
end)

local function onCooldown(name, delay)
    if not delay then return false end
    local now = os.clock() * 1000
    if _cooldown[name] and now < _cooldown[name] then return true end
    _cooldown[name] = now + delay
    return false
end

-- dispatch a request the correct direction for this side. arg2 = playerId (server) | ignored-delay (client).
local function send(name, arg2, reqId, ...)
    if SIDE == "server" then
        TriggerClientEvent(arg2, CREQ, name, reqId, ...)
    else
        TriggerServerEvent(SREQ, name, reqId, ...)
    end
end

local callback = setmetatable({
    register = function(name, fn) _registry[name] = fn end,

    await = function(name, arg2, ...)
        if SIDE ~= "server" and onCooldown(name, arg2) then return end
        local id, result, done = nextId(), nil, false
        _pending[id] = function(...) result = table.pack(...); done = true end
        send(name, arg2, id, ...)
        local start = os.clock() * 1000
        while not done do
            Wait(1)   -- Wait(0) BUSY-SPINS on HELIX (doesn't yield -> 100% CPU lockup); Wait(1) yields ~1 frame
            if os.clock() * 1000 - start >= AWAIT_TIMEOUT then
                _pending[id] = nil
                return nil
            end
        end
        return table.unpack(result, 1, result.n)
    end,
}, {
    __call = function(_, name, arg2, cb, ...)
        if SIDE ~= "server" and onCooldown(name, arg2) then return end
        local id = nextId()
        _pending[id] = function(...) if cb then cb(...) end end
        send(name, arg2, id, ...)
    end,
})

lib.callback = callback
return callback
