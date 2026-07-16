--[[ lib.*Kvp — FiveM Resource-KVP parity store (per-resource persistent key-value).
     WHY: converted resources call Set/Get/DeleteResourceKvp* (real corpus: es_extended server migration markers,
     ox_lib client settings cache). HELIX has no KVP system; this module IS that store.

     MODEL (mirrors FiveM's split):
       • SERVER store — per-resource, scope '@server'. Persisted through vox_sqlite (the server's single-owner DB
         broker: `Database.Initialize` is once-per-file + files lock exclusively, so vox_lib does NOT open its own
         db) in table `vox_kvp(scope, resource, key, value, vtype)`. vox_sqlite absent -> in-memory with a one-time
         warn (KVP still works, values don't survive a restart — honest degrade, surfaced in the console).
       • CLIENT store — per-PLAYER per-resource (FiveM client KVP is player-local storage). In-memory cache,
         lazily hydrated from the server on first access (a yield across the export boundary survives —
         probe-verified 2026-07-01), writes are cache-immediate + fire-and-forget persisted (FiveM KVP itself
         is async-flush, so this matches the native contract).
     Client identity = the stable account identifier (`GetPlayerIdentifier(src)`, server-side resolve — same key
     permissions.lua uses), so client settings survive sessions/reconnects.

     CONVERTER WIRING: kb/fivem_compat.lua (converter repo) forwards the KVP natives here with the calling
     package's own name: SetResourceKvp(k,v) -> exports.vox_lib:setKvp(GetCurrentResourceName(), k, v). Typed
     getters mirror FiveM defaults exactly: string -> nil, int -> 0, float -> 0.0 when unset.

     ⚠ UNVALIDATED IN-ENGINE (built 2026-07-16; the Lua probe is staged in the converter's VALIDATION_RUNBOOK).
     Do not claim works until probed: server set/get round-trip + restart persistence + client hydrate path. ]]

local SIDE = _VOX_SIDE or "server"

local function asInt(v) return math.floor(tonumber(v) or 0) end
local function asFloat(v) return tonumber(v) or 0.0 end

if SIDE == "server" then
    local SERVER_SCOPE = "@server"
    local _mem      = {}    -- scope -> resource -> key -> { v = string, t = 'string'|'int'|'float' }
    local _hydrated = {}    -- scope -> resource -> true (SQL page-in done)
    local _sqlOk    = nil   -- nil unknown | false unavailable | true ready (table ensured)

    local function sqlReady()
        if _sqlOk ~= nil then return _sqlOk end
        local ok, has = pcall(function() return __PackageLoader and __PackageLoader:HasPackage("vox_sqlite") end)
        if ok and has then
            local ok2 = pcall(function()
                exports["vox_sqlite"]:Execute([[CREATE TABLE IF NOT EXISTS vox_kvp (
                    scope    TEXT NOT NULL,
                    resource TEXT NOT NULL,
                    key      TEXT NOT NULL,
                    value    TEXT,
                    vtype    TEXT NOT NULL DEFAULT 'string',
                    PRIMARY KEY (scope, resource, key))]], {})
            end)
            _sqlOk = ok2 == true
        else
            _sqlOk = false
        end
        if not _sqlOk then
            pcall(print, "[vox_lib] kvp: vox_sqlite unavailable — KVP is IN-MEMORY ONLY (no restart persistence)")
        end
        return _sqlOk
    end

    local function bucket(scope, resource)
        _mem[scope] = _mem[scope] or {}
        _mem[scope][resource] = _mem[scope][resource] or {}
        return _mem[scope][resource]
    end

    -- page a (scope, resource) store in from SQL once; afterwards memory is authoritative (write-through keeps SQL in step)
    local function page(scope, resource)
        local h = _hydrated[scope]
        if h and h[resource] then return bucket(scope, resource) end
        _hydrated[scope] = h or {}
        _hydrated[scope][resource] = true
        local b = bucket(scope, resource)
        if sqlReady() then
            local ok, rows = pcall(function()
                return exports["vox_sqlite"]:Query(
                    "SELECT key, value, vtype FROM vox_kvp WHERE scope = ? AND resource = ?", { scope, resource })
            end)
            if ok and type(rows) == "table" then
                for i = 1, #rows do
                    local r = rows[i]
                    if r and r.key ~= nil then b[tostring(r.key)] = { v = r.value, t = r.vtype or "string" } end
                end
            end
        end
        return b
    end

    local function rawSet(scope, resource, key, value, vtype)
        page(scope, resource)[key] = { v = tostring(value), t = vtype }
        if sqlReady() then
            pcall(function()
                exports["vox_sqlite"]:Execute(
                    "INSERT OR REPLACE INTO vox_kvp (scope, resource, key, value, vtype) VALUES (?, ?, ?, ?, ?)",
                    { scope, resource, key, tostring(value), vtype })
            end)
        end
    end

    local function rawDel(scope, resource, key)
        page(scope, resource)[key] = nil
        if sqlReady() then
            pcall(function()
                exports["vox_sqlite"]:Execute(
                    "DELETE FROM vox_kvp WHERE scope = ? AND resource = ? AND key = ?", { scope, resource, key })
            end)
        end
    end

    local function rawFind(scope, resource, prefix)
        local b = page(scope, resource)
        local out = {}
        prefix = tostring(prefix or "")
        for k in pairs(b) do
            if k:sub(1, #prefix) == prefix then out[#out + 1] = k end
        end
        table.sort(out)
        return out
    end

    -- public server API (the '@server' scope = FiveM's server-side KVP store)
    function lib.setKvp(resource, key, value)      rawSet(SERVER_SCOPE, tostring(resource), tostring(key), tostring(value), "string") end
    function lib.setKvpInt(resource, key, value)   rawSet(SERVER_SCOPE, tostring(resource), tostring(key), asInt(value),   "int")    end
    function lib.setKvpFloat(resource, key, value) rawSet(SERVER_SCOPE, tostring(resource), tostring(key), asFloat(value), "float")  end

    function lib.getKvp(resource, key)
        local e = page(SERVER_SCOPE, tostring(resource))[tostring(key)]
        if e == nil then return nil end
        return tostring(e.v)
    end
    function lib.getKvpInt(resource, key)
        local e = page(SERVER_SCOPE, tostring(resource))[tostring(key)]
        if e == nil then return 0 end
        return asInt(e.v)
    end
    function lib.getKvpFloat(resource, key)
        local e = page(SERVER_SCOPE, tostring(resource))[tostring(key)]
        if e == nil then return 0.0 end
        return asFloat(e.v)
    end

    function lib.deleteKvp(resource, key)  rawDel(SERVER_SCOPE, tostring(resource), tostring(key)) end
    function lib.findKvp(resource, prefix) return rawFind(SERVER_SCOPE, tostring(resource), prefix) end

    -- ── client-store plumbing (per-player scopes) ────────────────────────────────────────────────
    local function scopeOf(source)
        local ok, id = pcall(function() return GetPlayerIdentifier and GetPlayerIdentifier(source) or nil end)
        if ok and id and id ~= "" then return tostring(id) end
        return "src:" .. tostring(source)   -- session-stable fallback; persistence then only spans this session
    end

    lib.callback.register("vox_kvp:hydrate", function(source, resource)
        local b = page(scopeOf(source), tostring(resource))
        local out = {}
        for k, e in pairs(b) do out[k] = { v = e.v, t = e.t } end
        return out
    end)

    RegisterServerEvent("vox_kvp:set", function(source, resource, key, value, vtype)
        rawSet(scopeOf(source), tostring(resource), tostring(key), value, vtype or "string")
    end)

    RegisterServerEvent("vox_kvp:del", function(source, resource, key)
        rawDel(scopeOf(source), tostring(resource), tostring(key))
    end)

else -- ── client: per-player cache, server-persisted ──────────────────────────────────────────────
    local _store = {}   -- resource -> key -> { v, t }
    local _ready = {}   -- resource -> true once hydrated

    -- hydrate once per resource; yields (safe across the export boundary). If the callback can't run
    -- (no thread context / timeout) we serve the un-hydrated cache WITHOUT marking ready, so a later
    -- call retries instead of silently dropping persisted values.
    local function ensure(resource)
        resource = tostring(resource)
        _store[resource] = _store[resource] or {}
        if _ready[resource] then return _store[resource] end
        local ok, map = pcall(function() return lib.callback.await("vox_kvp:hydrate", false, resource) end)
        if ok and type(map) == "table" then
            for k, e in pairs(map) do
                if _store[resource][k] == nil then _store[resource][k] = { v = e.v, t = e.t or "string" } end
            end
            _ready[resource] = true
        end
        return _store[resource]
    end

    local function put(resource, key, value, vtype)
        resource, key = tostring(resource), tostring(key)
        ensure(resource)[key] = { v = tostring(value), t = vtype }
        TriggerServerEvent("vox_kvp:set", resource, key, tostring(value), vtype)
    end

    function lib.setKvp(resource, key, value)      put(resource, key, tostring(value), "string") end
    function lib.setKvpInt(resource, key, value)   put(resource, key, asInt(value),   "int")    end
    function lib.setKvpFloat(resource, key, value) put(resource, key, asFloat(value), "float")  end

    function lib.getKvp(resource, key)
        local e = ensure(resource)[tostring(key)]
        if e == nil then return nil end
        return tostring(e.v)
    end
    function lib.getKvpInt(resource, key)
        local e = ensure(resource)[tostring(key)]
        if e == nil then return 0 end
        return asInt(e.v)
    end
    function lib.getKvpFloat(resource, key)
        local e = ensure(resource)[tostring(key)]
        if e == nil then return 0.0 end
        return asFloat(e.v)
    end

    function lib.deleteKvp(resource, key)
        resource, key = tostring(resource), tostring(key)
        ensure(resource)[key] = nil
        TriggerServerEvent("vox_kvp:del", resource, key)
    end

    function lib.findKvp(resource, prefix)
        local b = ensure(resource)
        local out = {}
        prefix = tostring(prefix or "")
        for k in pairs(b) do
            if k:sub(1, #prefix) == prefix then out[#out + 1] = k end
        end
        table.sort(out)
        return out
    end
end

return lib.getKvp
