--[[ lib.getResourceState / hasResource / getResources — query which HELIX packages ("resources") are loaded in the world.
     HELIX exposes its package loader as the global `_G.__PackageLoader` (a UHPackageLoaderSubsystem; the blessed idiom, used
     in Engine/Content/LuaScript/API/Exports.lua). This module wraps it as the FiveM-familiar `GetResourceState` contract so
     scripts (and converted FiveM resources) can feature-detect optional integrations.

       lib.getResourceState(name) -> 'started' (package loaded) | 'missing' (not loaded / unknown). Mirrors FiveM's contract:
         `if lib.getResourceState('ox_inventory') ~= 'missing' then ... end`.
       lib.hasResource(name)      -> boolean (sugar over the above).
       lib.getResources()         -> array of loaded package names (best-effort via GetPackageMap; may be empty on builds
                                     whose TMap iteration shape differs — getResourceState/hasResource are the reliable path).

     ⚠ `__PackageLoader:HasPackage(name)` returns true for a LOADED package but THROWS (catchable) for an unknown one, so every
     call is pcall-wrapped. Live-confirmed in HELIX_Dev PIE 2026-07-14 (HasPackage('vox_lib')=true). "Loaded" = present in the
     world's Scripts/config.json package list (vault-available-but-unstarted packages read as 'missing'). ]]

local function _loader()
    local pl = rawget(_G, "__PackageLoader")
    if pl then return pl end
    -- fallback acquire (if the global is ever absent) — GameInstance subsystem by class path
    local ok, sub = pcall(function()
        return UE.USubsystemBlueprintLibrary.GetGameInstanceSubsystem(HWorld,
            UE.UClass.Load("/Script/HelixSystem.HPackageLoaderSubsystem"))
    end)
    return ok and sub or nil
end

function lib.getResourceState(name)
    local pl = _loader()
    if not pl then return "missing" end
    local ok, loaded = pcall(function() return pl:HasPackage(tostring(name)) end)
    return (ok and loaded) and "started" or "missing"
end

function lib.hasResource(name)
    return lib.getResourceState(name) == "started"
end

function lib.getResources()
    local pl = _loader()
    if not pl then return {} end
    local out = {}
    -- best-effort enumeration of the GetPackageMap() TMap; guarded so an unexpected shape never throws.
    pcall(function()
        local map = pl:GetPackageMap()
        if not map then return end
        -- try UnLua TMap access patterns (Keys/Num) then a plain pairs() fallback
        local ok, keys = pcall(function() return map:Keys() end)
        if ok and keys then
            local n = (pcall(function() return keys:Length() end)) and keys:Length() or 0
            for i = 1, n do out[#out + 1] = tostring(keys:Get(i)) end
        else
            for k in pairs(map) do out[#out + 1] = tostring(k) end
        end
    end)
    return out
end

return lib.getResourceState
