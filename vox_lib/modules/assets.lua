--[[ lib.enumerateAssets — runtime asset-POOL enumeration from the UE AssetRegistry (VERIFIED live 2026-07-14, HELIX_Dev).

     The engine behind "drop the converted resource in, run one command, the asset tables are ready": enumerate the
     world's ACTUAL UE-id pool (what ships with the engine + Vault packages added to THAT world) instead of hand-typing
     assets. This is the correct replacement for a FiveM hash-keyed asset table — you enumerate the real UE ids, you do
     NOT translate GTA hashes (the hash table IS the FiveMism).

     CACHE-FIRST (Matt's model): a file write would need a world rejoin / server restart to take effect, so the pool is
     enumerated ONCE and CACHED in-memory — resources consume it live, no restart. `lib.serializeAssetTable` produces a
     `.lua` source string if a dev wants a persistent, curatable data file (edited offline, loaded on next boot).

     Side-agnostic: the AssetRegistry is reachable client AND server (verified server-side; same API both sides).
     API shape (probe-verified): `UE.UAssetRegistryHelpers.GetAssetRegistry()` →
       `GetAssetsByPath(PackagePath, bRecursive, bIncludeOnlyOnDiskAssets)` — the OutAssetData TArray is UnLua's 2ND
       return; `bIncludeOnlyOnDiskAssets` MUST be true (weapon defs are unloaded until given). FAssetData: `.AssetName`,
       `.PackageName` (load path = `PackageName .. '.' .. AssetName`). Filter defs by AssetName prefix. ]]

local _cache = {}

-- Family config: content ROOT path(s) + the name filter that marks a DEFINITION asset (vs its meshes/textures/materials).
-- `prefix` and/or `suffix` on AssetName (both must match if both given). Each HELIX asset family uses a DIFFERENT identity
-- model, so a family = its own row (not a uniform ID_* sweep):
--   • weapon / item = HInventoryItemDefinition DATA ASSETS named `ID_Weapon_*` / `ID_Misc_*` (spawn/give by UObject.Load).
--   • vehicle = spawn BLUEPRINTS named `BP_*_Vehicle` (HVehicle spawns a vehicle BP class), not item defs.
--   • clothing/hair/beards = cosmetic skeletal meshes driven by `DA_CharacterCustomizationData` (a data-asset OPTION LIST,
--     NOT a path+prefix) → needs the cosmetics-specific reader, deferred (see lib.charcreator / reference-helix-cosmetics-api).
-- weapon VERIFIED live 2026-07-14 (37 defs). item/vehicle roots disk-confirmed; validate counts live before trusting.
local FAMILIES = {
    weapon  = { roots = { "/HelixWeapons/Weapons" },              prefix = "ID_Weapon_" },
    item    = { roots = { "/HelixRoleplay/Items" },               prefix = "ID_Misc_" },
    vehicle = { roots = { "/HelixVehicleAssets/Blueprints/Vehicles" }, prefix = "BP_", suffix = "_Vehicle" },
}

-- Register/override a family at runtime (so a resource can add its own Vault content root without editing this file).
function lib.registerAssetFamily(name, roots, prefix)
    if type(name) ~= "string" or type(prefix) ~= "string" then return false end
    FAMILIES[name] = { roots = (type(roots) == "table") and roots or { roots }, prefix = prefix }
    _cache[name] = nil
    return true
end

-- category from ID_<Family>_<Cat>_<Name> (e.g. ID_Weapon_Rifle_Patriot -> "Rifle"); nil if not parseable (vehicles/items
-- have no category segment → nil, which is fine).
local function categoryOf(id, prefix)
    local rest = id:sub(#prefix + 1)
    local cat = rest:match("^([^_]+)_")
    return cat
end

-- Does an AssetName match a family's def filter (prefix and/or suffix)?
local function matchesFilter(nm, cfg)
    if cfg.prefix and nm:sub(1, #cfg.prefix) ~= cfg.prefix then return false end
    if cfg.suffix and nm:sub(-#cfg.suffix) ~= cfg.suffix then return false end
    return cfg.prefix ~= nil or cfg.suffix ~= nil
end

-- Enumerate a family's definition pool -> { {id, path, category}, ... } (sorted by id), CACHED per family.
-- opts.refresh = force a rescan. Returns nil,err on unknown family / registry failure.
function lib.enumerateAssets(family, opts)
    opts = opts or {}
    if _cache[family] and not opts.refresh then return _cache[family] end
    local cfg = FAMILIES[family]
    if not cfg then return nil, "unknown asset family: " .. tostring(family) end
    local list, seen = {}, {}
    local ok, err = pcall(function()
        local ar = UE.UAssetRegistryHelpers.GetAssetRegistry()
        for _, root in ipairs(cfg.roots) do
            local _, assets = ar:GetAssetsByPath(root, true, true)   -- recursive + on-disk (unloaded) = the full pool
            if assets and assets.Length then
                for i = 1, assets:Length() do
                    local ad = assets:Get(i)
                    local nm = tostring(ad.AssetName)
                    if matchesFilter(nm, cfg) and not seen[nm] then
                        seen[nm] = true
                        local path; pcall(function() path = tostring(ad.PackageName) .. "." .. nm end)
                        list[#list + 1] = { id = nm, path = path, category = cfg.prefix and categoryOf(nm, cfg.prefix) or nil }
                    end
                end
            end
        end
    end)
    if not ok then return nil, "enumeration failed: " .. tostring(err) end
    table.sort(list, function(a, b) return a.id < b.id end)
    _cache[family] = list
    return list
end

-- Clear a family's cache (or all if nil) — force the next enumerate to rescan.
function lib.clearAssetCache(family)
    if family then _cache[family] = nil else _cache = {} end
end

-- Serialize an enumerated pool to a Lua-source data-table STRING (the optional curatable dump). Keyed by id; carries the
-- live path + category + a `label` stub the dev fills with economy metadata (weight/price/…). A dev saves this to a
-- `.lua` and loads it on next boot; runtime consumers can just call lib.enumerateAssets directly.
function lib.serializeAssetTable(family, opts)
    local list, err = lib.enumerateAssets(family, opts)
    if not list then return nil, err end
    local lines = {
        "-- Auto-generated by vox_lib lib.serializeAssetTable('" .. family .. "') — the LIVE " .. family ..
        " pool (ids + paths). Curate the metadata; ids/paths are the source of truth.",
        "return {",
    }
    for _, a in ipairs(list) do
        lines[#lines + 1] = string.format(
            "  ['%s'] = { path = '%s', category = %s, label = '%s' },",
            a.id, a.path or "",
            a.category and ("'" .. a.category .. "'") or "nil",
            a.id:gsub("^ID_%w-_", ""))
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

-- Write a family's serialized table to a `.lua` file on disk (the OPTIONAL curatable dump — standard Lua `io` is exposed
-- in the HELIX sandbox, verified 2026-07-14). The primary path is still runtime `lib.enumerateAssets` (no restart); this
-- is for a dev who wants a persistent, hand-editable data file (loaded on the NEXT boot). Returns ok,err.
-- ⚠ server/admin-gate the command that calls this — do not expose file writes to clients.
function lib.writeAssetTable(family, filepath, opts)
    if type(filepath) ~= "string" then return false, "filepath required" end
    local src, err = lib.serializeAssetTable(family, opts)
    if not src then return false, err end
    local f, ioerr = io.open(filepath, "w")
    if not f then return false, "cannot open file: " .. tostring(ioerr) end
    f:write(src)
    f:close()
    return true
end
