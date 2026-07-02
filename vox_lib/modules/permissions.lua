--[[ lib.hasPermission / lib.isInRole — HELIX-side ACL. HELIX (current build) has NO native permission/ACE/role system:
     RegisterCommand has no `restricted` flag, HPlayer exposes no role, there is no ACL API. So gated access must be done
     GAME-SIDE, keyed on the stable account identifier from HELIX (`GetPlayerIdentifier` / `GetPlayerEmail`, Functions.lua).

     This module is the redundant HELIX-side shield: a role table keyed on identifier, checked in-handler. It protects even
     resources whose framework lacks (or the dev never wired) permissions. Server-side.

     BOUNDARY NOTE: `isInRole(identifier, group)` is pure STRING-in / bool-out -> safe as a vox_lib EXPORT across the package
     boundary. `hasPermission(src, group)` resolves src -> identifier LOCALLY (GetPlayerIdentifier is a native global present in
     every Lua state) and then checks — so a consumer either calls lib.hasPermission locally, or exports.vox_lib:isInRole with a
     pre-resolved identifier string. Do NOT pass the player object across an export for this.

     CONFIG: populate `lib.roleConfig` (identifier -> { group = true }). Ship a config file OR load dynamically from vox_sqlite.
     Wildcards: a group named `'*'` or `'superadmin'` on an identifier grants everything. ]]

lib.roleConfig = lib.roleConfig or {}     -- { ['<identifier>'] = { admin = true, police = true }, ... }

--- Optional: hydrate roles from a vox_sqlite table (call once on boot if you want dynamic roles).
--- Table shape: vox_roles(identifier TEXT, role TEXT).
function lib.loadRolesFromDB()
    local ok, rows = pcall(function() return exports.vox_sqlite:query("SELECT identifier, role FROM vox_roles") end)
    if not ok or type(rows) ~= "table" then return false end
    for _, r in ipairs(rows) do
        local id = r.identifier
        if id then
            lib.roleConfig[id] = lib.roleConfig[id] or {}
            lib.roleConfig[id][r.role] = true
        end
    end
    return true
end

--- isInRole(identifier, group) -> boolean. Pure data in/out (export-safe). identifier + group are STRINGS.
function lib.isInRole(identifier, group)
    if not identifier or not group then return false end
    local g = lib.roleConfig[identifier]
    if not g then return false end
    return (g[group] or g["*"] or g["superadmin"]) and true or false
end

--- hasPermission(src, group) -> boolean. Resolves src -> account identifier locally, then checks the role table. Server-side.
function lib.hasPermission(src, group)
    local id = GetPlayerIdentifier and GetPlayerIdentifier(src) or nil
    return lib.isInRole(id, group)
end
