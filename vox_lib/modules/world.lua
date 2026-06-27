--[[ lib.worldToScreen / lib.spawnMarker — world-anchored helpers (the primitives behind in-world labels & markers).
     Built on probe-verified API: HPlayer:GetViewportSize() + HPlayer:ProjectWorldLocationToScreen(worldVec, Vector2D, false)
     (the hl-target label loop), and StaticMesh(Vector, Rotator, assetPath, CollisionType.NoCollision) for markers. CLIENT-side. ]]

local function toVec(c)
    if c == nil then return Vector() end
    if type(c) == "userdata" then return c end
    local v = Vector(); v.X = c.x or c.X or c[1] or 0; v.Y = c.y or c.Y or c[2] or 0; v.Z = c.z or c.Z or c[3] or 0
    return v
end

-- Project a world position to the local screen. Returns { ok, onScreen = bool, x, y } where x,y are 0-1 screen fractions.
function lib.worldToScreen(worldCoords)
    if not HPlayer then return { ok = false, error = "HPlayer unavailable (client only)" } end
    local w, h, screenPos, success
    local ok = pcall(function()
        w, h = HPlayer:GetViewportSize()
        screenPos = Vector2D()
        success = HPlayer:ProjectWorldLocationToScreen(toVec(worldCoords), screenPos, false)
    end)
    if not ok then return { ok = false, error = "ProjectWorldLocationToScreen failed" } end
    if not success or not w or w == 0 then return { ok = true, onScreen = false } end
    return { ok = true, onScreen = true, x = screenPos.X / w, y = screenPos.Y / h }
end

-- Spawn a marker mesh at coords. opts: { asset = path (default a cylinder), scale = number|{x,y,z}, rotation, collision = bool }.
-- Returns the mesh actor (or nil). Remove with lib.deleteEntity. (Markers are real spawned meshes, not immediate-mode draws.)
local DEFAULT_MARKER = "/Game/HL_assets/InventoryItems/SM_MarkerCylinder.SM_MarkerCylinder"
function lib.spawnMarker(coords, opts)
    if StaticMesh == nil then return nil end
    opts = opts or {}
    local asset = opts.asset or DEFAULT_MARKER
    local rot = opts.rotation or Rotator(0, 0, 0)
    if type(rot) == "number" then rot = Rotator(0, rot, 0) end
    local coll = (opts.collision and (CollisionType and CollisionType.QueryOnly)) or (CollisionType and CollisionType.NoCollision)
    local mesh
    local ok = pcall(function() mesh = StaticMesh(toVec(coords), rot, asset, coll) end)
    if not ok or not mesh then return nil end
    if opts.scale then
        local s = opts.scale
        local sv = type(s) == "number" and Vector(s, s, s) or toVec(s)
        pcall(function() mesh:SetActorScale3D(sv) end)
    end
    return mesh
end

return lib.worldToScreen
