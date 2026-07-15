--[[ lib.getConvar / getConvarInt / getConvarBool / setConvar — a server-config ("convar") store for HELIX.
     WHY: FiveM resources read server-wide settings via GTA's `GetConvar(name, default)` (set in server.cfg). HELIX has no
     convar system, so a converted resource has nowhere to read `inventory:slots` etc. This module IS that place: a simple
     key->value store with FiveM-compatible getters (string / int / bool), seeded from a dev-owned config, overridable at runtime.

     HOW A DEVELOPER SETS SERVER-WIDE VALUES (pick either):
       • a config table — define a global `VoxConvars` in a file loaded before/with vox_lib (bundled build), e.g.
             VoxConvars = { ['inventory:slots'] = 50, ['inventory:framework'] = 'esx' }
         vox_lib merges it into the store on load.
       • programmatically — `exports.vox_lib:setConvar('inventory:slots', 50)` (e.g. from a boot handler).

     GETTERS mirror FiveM's return types: getConvar -> string, getConvarInt -> number, getConvarBool -> boolean. An UNSET
     name returns the caller's `default` (exactly like FiveM). Values live per-side (client + server each load this module),
     so reads are synchronous — no cross-boundary round-trip. The converter maps GetConvar*/GetConvarInt/GetConvarBool onto
     these (via a crash-proof `__vox_getconvar*` bridge that defaults if vox_lib isn't present). ]]

local _store = {}

-- seed from an optional dev-provided config table (same package / bundled build)
if type(VoxConvars) == "table" then
    for k, v in pairs(VoxConvars) do _store[tostring(k)] = v end
end

function lib.setConvar(name, value)
    _store[tostring(name)] = value
end

function lib.getConvar(name, default)
    local v = _store[tostring(name)]
    if v == nil then return default end
    return tostring(v)                                   -- FiveM GetConvar returns a string
end

function lib.getConvarInt(name, default)
    local v = _store[tostring(name)]
    if v == nil then return default end
    return tonumber(v) or default
end

function lib.getConvarBool(name, default)
    local v = _store[tostring(name)]
    if v == nil then return default end
    if type(v) == "boolean" then return v end
    v = tostring(v):lower()
    return v == "true" or v == "1"
end

return lib.getConvar
