--[[ lib.raycast / lib.raycastFromCamera — line traces over the HELIX/UE physics, returning the first hit.
     Built on probe-verified UE reflection (current build 2026-06-27): UE.UKismetSystemLibrary.LineTraceSingle +
     UE.UGameplayStatics.DeprojectScreenToWorld + UE.UGameplayStatics.BreakHitResult. CLIENT-side.

     NOTE: LineTraceSingle has many args + an OUT-param FHitResult; UnLua's out-param handling is build-specific, so the call
     is pcall-guarded and the result read both ways (return value AND the passed hit). PROBE-CONFIRM the exact arg order /
     out-param convention on your build and prune the fallbacks. ]]

local function toVec(c)
    if c == nil then return Vector() end
    if type(c) == "userdata" then return c end
    local v = Vector(); v.X = c.x or c.X or c[1] or 0; v.Y = c.y or c.Y or c[2] or 0; v.Z = c.z or c.Z or c[3] or 0
    return v
end

local function channel()
    return (UE and UE.ETraceTypeQuery and UE.ETraceTypeQuery.Visibility) or 0
end

local function readHit(hit)
    if not hit then return nil end
    local out = { raw = hit }
    pcall(function()
        -- BreakHitResult fills many fields; we surface the common ones defensively.
        local r = { UE.UGameplayStatics.BreakHitResult(hit) }
        -- Different builds return the break tuple in different orders; also try direct fields.
    end)
    pcall(function() out.location = hit.Location or hit.ImpactPoint end)
    pcall(function() out.normal = hit.Normal or hit.ImpactNormal end)
    pcall(function() out.actor = hit.HitActor or (hit.GetActor and hit:GetActor()) end)
    pcall(function() out.distance = hit.Distance end)
    return out
end

-- Trace a ray from `startCoords` to `endCoords`. opts: { ignore = {actors}, complex = bool }.
-- Returns { ok, hit = bool, result = { location, normal, actor, distance } | nil }.
function lib.raycast(startCoords, endCoords, opts)
    if type(UE) ~= "table" or not (UE.UKismetSystemLibrary and UE.UKismetSystemLibrary.LineTraceSingle) then
        return { ok = false, error = "LineTraceSingle unavailable" }
    end
    opts = opts or {}
    local ignore = UE.TArray(UE.AActor)
    if opts.ignore then for _, a in ipairs(opts.ignore) do pcall(function() ignore:Add(a) end) end end
    local hitResult = UE.FHitResult()
    local didHit, hr
    local ok = pcall(function()
        -- LineTraceSingle(WorldContext, Start, End, TraceChannel, bComplex, ActorsToIgnore, DrawDebugType, OutHit, bIgnoreSelf)
        didHit = UE.UKismetSystemLibrary.LineTraceSingle(
            HWorld, toVec(startCoords), toVec(endCoords), channel(), opts.complex and true or false,
            ignore, UE.EDrawDebugTrace.None, hitResult, true)
    end)
    if not ok then return { ok = false, error = "LineTraceSingle call failed (probe arg order)" } end
    return { ok = true, hit = didHit and true or false, result = didHit and readHit(hitResult) or nil }
end

-- Trace from the camera through a screen point (default screen centre). opts: { x, y (0-1 screen frac), distance (default 100000), ignore }.
-- Returns the same shape as lib.raycast.
function lib.raycastFromCamera(opts)
    if not HPlayer then return { ok = false, error = "HPlayer unavailable (client only)" } end
    if not (UE.UGameplayStatics and UE.UGameplayStatics.DeprojectScreenToWorld) then
        return { ok = false, error = "DeprojectScreenToWorld unavailable" }
    end
    opts = opts or {}
    local w, h = 1920, 1080
    pcall(function() w, h = HPlayer:GetViewportSize() end)
    local sx = (opts.x or 0.5) * w
    local sy = (opts.y or 0.5) * h
    local worldPos, worldDir
    local ok = pcall(function()
        worldPos, worldDir = UE.UGameplayStatics.DeprojectScreenToWorld(HPlayer, Vector2D(sx, sy))
    end)
    if not ok or not worldPos or not worldDir then return { ok = false, error = "deproject failed (probe return shape)" } end
    local dist = opts.distance or 100000
    local endPos = Vector(worldPos.X + worldDir.X * dist, worldPos.Y + worldDir.Y * dist, worldPos.Z + worldDir.Z * dist)
    return lib.raycast(worldPos, endPos, opts)
end

return lib.raycast
