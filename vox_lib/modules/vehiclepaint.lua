--[[ Vehicle paint — per-instance vehicle colouring on HELIX's instanced render. CLIENT-side (material/render is client-side).

  MECHANISM (probe-verified 2026-06-28). Gameplay vehicles are NOT drawn by their own actor mesh (it's hidden); they are
  rendered by an `HVehicleInstancesContainerActor` that holds one `InstancedStaticMeshComponent` (ISM) per body part. Setting a
  flat material parameter on an ISM recolours EVERY instance (the whole fleet of that model). To colour ONE vehicle — or one of
  its components — without touching the others, you set PER-INSTANCE CUSTOM DATA (RGB = custom-data floats 0,1,2) on the paint
  ISMs at that vehicle's instance index. That is exactly the instance handling proven in-engine and unchanged here.

  ⚠️ TWO STANDING LIMITATIONS (keep documented in README + docs/developer.md until each is resolved):
  (1) DEPENDENCY — the vehicle's paint material must READ per-instance custom data (a `PerInstanceCustomData3Vector` driving the
      paint colour). This is a HELIX-SIDE material change (proposed to HELIX); vox_lib can't ship it. Until a given material
      supports it, calls are harmless no-ops visually (the custom data is set but unread). `lib.setFleetColor(...,"flat")` offers a
      flat-parameter path that works on any paint material today.  ➜ remove once HELIX ships per-instance-reading vehicle materials.
  (2) STATIONARY — a vehicle loses its paint the moment it MOVES. This is a HELIX ENGINE behaviour, not a matching bug: when a
      vehicle moves, the instance container reassigns instance indices AND does not carry the per-instance custom data with it, so the
      moving car's colour is dropped (verified in-engine: a teleported car landed at a new index, black). Stationary cars keep colour.
      ➜ remove once HELIX keeps per-instance custom data bound to the vehicle across movement (can't be fixed from Lua — proposed to HELIX).

  COLOURS are 0..1 floats. Every function accepts a colour as: three numbers (0..1, or 0..255 if any value > 1), a table
  `{r,g,b}` / `{R,G,B}`, or a hex string `"#RRGGBB"`.
  TARGET (the `vehicle` arg) accepts an `HVehicle` handle, a raw vehicle actor, or anything with `.Object`. ]]

local CUSTOM_FLOATS = 3                       -- RGB
local MATCH_TOL2 = 250.0 * 250.0             -- instance<->vehicle match tolerance (cm^2); a car is ~uniquely near its instance
local PAINT_HINTS = { "carpaint", "vehiclepaint", "paint" }  -- material-name hints that mark a paintable ISM

-- ── colour normalisation ────────────────────────────────────────────────────
local function clamp01(n) if n < 0 then return 0 elseif n > 1 then return 1 else return n end end
local function normColor(a, b, c)
    local r, g, bl
    if type(a) == "string" then                                   -- "#RRGGBB" / "RRGGBB"
        local h = a:gsub("#", "")
        r = tonumber(h:sub(1, 2), 16) or 0; g = tonumber(h:sub(3, 4), 16) or 0; bl = tonumber(h:sub(5, 6), 16) or 0
        return clamp01(r / 255), clamp01(g / 255), clamp01(bl / 255)
    end
    if type(a) == "table" then r, g, bl = a.r or a.R or a[1] or 0, a.g or a.G or a[2] or 0, a.b or a.B or a[3] or 0
    else r, g, bl = a or 0, b or 0, c or 0 end
    if r > 1 or g > 1 or bl > 1 then r, g, bl = r / 255, g / 255, bl / 255 end   -- 0..255 -> 0..1
    return clamp01(r), clamp01(g), clamp01(bl)
end

-- HSV (h,s,v in 0..1) -> r,g,b in 0..1. Exposed for custom effects.
function lib.hsvToRgb(h, s, v)
    s = s or 1; v = v or 1
    local i = math.floor(h * 6) % 6; local f = h * 6 - math.floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v else return v, p, q end
end

-- ── engine plumbing ─────────────────────────────────────────────────────────
local function world() return HWorld or (GetWorld and GetWorld()) end

local function each(arr, fn)               -- iterate an UnLua TArray (0-indexed: valid indices are 0..n-1; nil-guarded)
    if not arr then return end
    local n = 0; pcall(function() n = arr:Length() end)
    for i = 0, n - 1 do local v; if pcall(function() v = arr:Get(i) end) and v then fn(v) end end
end

-- all vehicle instance containers. NOTE: GetAllActorsOfClass on the specific HELIX C++ class
-- (UE.AHVehicleInstancesContainerActor) is unreliable in UnLua (often returns empty), so we enumerate AActor and
-- filter by class name — the proven-reliable approach.
local function containers()
    local out = {}
    local w = world(); if not w then return out end
    local arr; pcall(function() arr = UE.UGameplayStatics.GetAllActorsOfClass(w, UE.AActor) end)
    each(arr, function(a)
        local cn; pcall(function() cn = tostring(a:GetClass():GetName()) end)
        if cn and cn:find("HVehicleInstancesContainer", 1, true) then out[#out + 1] = a end
    end)
    return out
end

local function ismMeshName(ism)
    local nm
    pcall(function()
        local sm = ism.StaticMesh                                 -- UnLua property (the GetStaticMesh() getter returns nil here)
        if not sm and ism.GetStaticMesh then sm = ism:GetStaticMesh() end
        if sm then nm = tostring(sm:GetName()) end
    end)
    return nm or ""
end

local function isPaintISM(ism)             -- ISM whose material is a paint material
    local n = 0; pcall(function() n = ism:GetNumMaterials() end)
    for i = 0, n - 1 do
        local m; pcall(function() m = ism:GetMaterial(i) end)
        if m then
            local mn; pcall(function() mn = tostring(m:GetName()):lower() end)
            if mn then for _, h in ipairs(PAINT_HINTS) do if mn:find(h, 1, true) then return true end end end
        end
    end
    return false
end

-- iterate (container, ism) for every paintable ISM, optionally filtered to a component (mesh-name substring, case-insensitive)
local function forEachPaintISM(component, fn)
    local filt = component and tostring(component):lower() or nil
    for _, c in ipairs(containers()) do
        local comps; pcall(function() comps = c:K2_GetComponentsByClass(UE.UInstancedStaticMeshComponent) end)
        each(comps, function(ism)
            if isPaintISM(ism) and (not filt or ismMeshName(ism):lower():find(filt, 1, true)) then fn(c, ism) end
        end)
    end
end

-- read a UE Vector's components regardless of UnLua casing
local function vget(v) if not v then return nil end return (v.X or v.x or 0), (v.Y or v.y or 0), (v.Z or v.z or 0) end

-- resolve a vehicle handle's world location -> x,y,z
local function vehicleLoc(vehicle)
    local actor = (type(vehicle) == "table" and vehicle.Object) or vehicle
    if not actor then return nil end
    local loc; pcall(function() loc = actor:K2_GetActorLocation() end)
    if not loc then pcall(function() loc = GetEntityCoords(actor) end) end
    return loc and { vget(loc) } or nil
end

-- index of the ISM instance nearest the vehicle's location (the vehicle's own instance), or nil
local function instanceIndexFor(ism, loc)
    if not loc then return nil end
    local lx, ly, lz = loc[1], loc[2], loc[3]
    local best, bestd2 = nil, MATCH_TOL2
    local cnt = 0; pcall(function() cnt = ism:GetInstanceCount() end)
    for i = 0, cnt - 1 do
        local px, py, pz
        pcall(function()
            -- GetInstanceTransform(index, OUT FTransform&, bWorldSpace): on this UnLua build the out-param FTransform must be
            -- PASSED IN (pre-allocated) and is filled in place — NOT returned. (Passing only (i,true) errors with
            -- "userdata needed but got boolean" and breaks instance matching. Verified in-engine PIE 2026-06-29.)
            local t = UE.FTransform()
            ism:GetInstanceTransform(i, t, true)
            local p = UE.UKismetMathLibrary.BreakTransform(t)         -- -> location Vector (proven idiom)
            px, py, pz = vget(p)
        end)
        if px then
            local dx, dy, dz = px - lx, py - ly, pz - lz
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 <= bestd2 then best, bestd2 = i, d2 end
        end
    end
    return best
end

-- set one instance's colour on an ISM. Returns true if written.
-- ⚠️ CRASH SAFETY: SetCustomDataValue on an ISM with fewer than 3 custom-data floats is an OUT-OF-BOUNDS native write that
-- HARD-CRASHES the client (uncatchable — pcall does NOT save it). A vehicle only has custom-data floats when its paint ISM is
-- set up for per-instance colour (the per-instance vehicle material). So we ONLY write when NumCustomDataFloats >= 3; otherwise
-- we skip (harmless no-op) rather than crash. We do NOT raise NumCustomDataFloats at runtime (reallocating a live ISM's
-- per-instance buffer is itself crash-prone) — that setup belongs to the vehicle material/asset.
local function applyInstance(ism, idx, r, g, b)
    local nf = 0; pcall(function() nf = ism.NumCustomDataFloats or 0 end)
    if nf < CUSTOM_FLOATS then
        -- The HELIX vehicle instance container creates paint ISMs with NumCustomDataFloats=0, so the per-instance
        -- colour channel doesn't exist yet. ALLOCATE it (3 floats = RGB) so the write below is in-bounds. We only do
        -- this once per ISM (subsequent calls see nf>=3). Setting it on a populated ISM preserves existing instances
        -- (their custom data defaults to 0). Try the method first, then the property. (in-engine verified 2026-06-29)
        local set = false
        pcall(function() ism:SetNumCustomDataFloats(CUSTOM_FLOATS); set = true end)
        if not set then pcall(function() ism.NumCustomDataFloats = CUSTOM_FLOATS end) end
        pcall(function() nf = ism.NumCustomDataFloats or 0 end)
        if nf < CUSTOM_FLOATS then return false end   -- allocation failed -> skip (never write out of bounds)
    end
    return pcall(function()
        ism:SetCustomDataValue(idx, 0, r, false)
        ism:SetCustomDataValue(idx, 1, g, false)
        ism:SetCustomDataValue(idx, 2, b, true)   -- last call marks the render state dirty
    end)
end

-- A vehicle occupies the SAME per-instance INDEX in every body-part ISM of its container (probe-verified: the container
-- adds a vehicle's parts together, so body[idx]/hood[idx]/door[idx]/… are all the same car). The BODY ISM's instance sits
-- at the vehicle's origin, so we resolve the index THERE (a reliable, on-origin match) and reuse it for every other part.
-- This is why matching each component ISM by raw proximity failed: offset parts (hood/far doors) sit beyond the match
-- tolerance from the vehicle origin. Anchoring on the body fixes whole-vehicle AND per-component painting.
local function vehicleInstanceIndex(loc)
    -- The body instance sits at the vehicle's origin, so the instance nearest `loc` across ALL paint ISMs is this
    -- vehicle's body — and its index is the vehicle's index in every other body-part ISM. Name-independent (UnLua's
    -- static-mesh name access is unreliable), so it works regardless of how components are named.
    local best, bestd2 = nil, MATCH_TOL2
    forEachPaintISM(nil, function(_, ism)
        local cnt = 0; pcall(function() cnt = ism:GetInstanceCount() end)
        for i = 0, cnt - 1 do
            local px, py, pz
            pcall(function()
                local t = UE.FTransform(); ism:GetInstanceTransform(i, t, true)
                px, py, pz = vget(UE.UKismetMathLibrary.BreakTransform(t))
            end)
            if px then
                local dx, dy, dz = px - loc[1], py - loc[2], pz - loc[3]
                local d2 = dx*dx + dy*dy + dz*dz
                if d2 <= bestd2 then best, bestd2 = i, d2 end
            end
        end
    end)
    return best
end

-- core: paint one vehicle (optionally one component). returns count of ISMs written (only those set up for per-instance
-- colour; see applyInstance). Resolves the vehicle's instance index once (via the body), then writes that index everywhere.
local function paintVehicle(vehicle, r, g, b, component)
    local loc = vehicleLoc(vehicle); if not loc then return 0 end
    local idx = vehicleInstanceIndex(loc)
    local painted = 0
    forEachPaintISM(component, function(_, ism)
        local i = idx
        if i == nil then i = instanceIndexFor(ism, loc) end   -- fallback if no body ISM resolved
        local cnt = 0; pcall(function() cnt = ism:GetInstanceCount() end)
        if i and i < cnt and applyInstance(ism, i, r, g, b) then painted = painted + 1 end
    end)
    return painted
end

-- ── public: direct colour ───────────────────────────────────────────────────
-- Paint the WHOLE BODY of ONE vehicle (every paintable component of that vehicle), leaving all other vehicles untouched.
function lib.setVehicleColor(vehicle, a, b, c)
    local r, g, bl = normColor(a, b, c)
    return paintVehicle(vehicle, r, g, bl, nil)
end

-- Paint ONE COMPONENT of one vehicle. `component` is a mesh-name substring: e.g. "Body"/"Door"/"Hood"/"Trunk" (case-insensitive).
function lib.setVehicleComponentColor(vehicle, component, a, b, c)
    local r, g, bl = normColor(a, b, c)
    return paintVehicle(vehicle, r, g, bl, component)
end

-- Paint the ENTIRE FLEET (every vehicle of every model) one colour.
--   mode "instance" (default): set per-instance custom data on all instances (needs the per-instance material).
--   mode "flat": set the flat "Paint Color" material parameter on every paint ISM — works on ANY paint material TODAY, but
--                it is uniform per ISM (so genuinely every car of a model). Useful as a no-dependency fallback / global tint.
function lib.setFleetColor(a, b, c, mode)
    local r, g, bl = normColor(a, b, c)
    local n = 0
    if mode == "flat" then
        forEachPaintISM(nil, function(_, ism)
            pcall(function() ism:SetVectorParameterValueOnMaterials("Paint Color", Vector(r, g, bl)) end); n = n + 1
        end)
    else
        forEachPaintISM(nil, function(_, ism)
            local cnt = 0; pcall(function() cnt = ism:GetInstanceCount() end)
            for i = 0, cnt - 1 do applyInstance(ism, i, r, g, bl); n = n + 1 end
        end)
    end
    return n
end

-- Read a vehicle's current colour (from its instance custom data on the first paint ISM). Returns r,g,b (0..1) or nil.
function lib.getVehicleColor(vehicle)
    local loc = vehicleLoc(vehicle); if not loc then return nil end
    local r, g, b
    forEachPaintISM(nil, function(_, ism)
        if r then return end
        local idx = instanceIndexFor(ism, loc); if not idx then return end
        pcall(function() r = ism:GetCustomDataValue(idx, 0); g = ism:GetCustomDataValue(idx, 1); b = ism:GetCustomDataValue(idx, 2) end)
    end)
    return r, g, b
end

-- Reset a vehicle to a neutral colour (default white; pass a colour to choose). Convenience wrapper.
function lib.resetVehicleColor(vehicle, a, b, c)
    if a == nil then a = 1 end
    lib.stopVehicleEffect(vehicle)
    return lib.setVehicleColor(vehicle, a, b or a, c or a)
end

-- ── effects: interp + party (Timer-driven; one active effect per vehicle) ────
local effects = setmetatable({}, { __mode = "k" })   -- vehicle-actor -> { stop = fn }
local function effectKey(vehicle) return (type(vehicle) == "table" and vehicle.Object) or vehicle end

-- stop any running interp/party effect on a vehicle.
function lib.stopVehicleEffect(vehicle)
    local k = effectKey(vehicle); local e = effects[k]
    if e then e.running = false; effects[k] = nil; return true end
    return false
end

-- Smoothly INTERPOLATE a vehicle (or one component) from its current colour to a target over `duration` ms.
-- opts: { component = name, steps_ms = tick interval (default 33 ≈ 30fps), from = colour (override start), onDone = fn }.
-- Returns a handle { stop = fn }.
function lib.interpVehicleColor(vehicle, a, b, c, duration, opts)
    opts = opts or {}; duration = duration or 1000
    local r2, g2, b2 = normColor(a, b, c)
    local r1, g1, b1
    if opts.from then r1, g1, b1 = normColor(opts.from) else r1, g1, b1 = lib.getVehicleColor(vehicle) end
    if not r1 then r1, g1, b1 = r2, g2, b2 end                 -- no readable start -> snap target as start
    lib.stopVehicleEffect(vehicle)
    local k = effectKey(vehicle); local e = { running = true }; effects[k] = e
    local dt = opts.steps_ms or 33
    local elapsed = 0
    local function step()
        if not e.running then return end
        elapsed = elapsed + dt
        local p = duration > 0 and math.min(elapsed / duration, 1) or 1
        paintVehicle(vehicle, r1 + (r2 - r1) * p, g1 + (g2 - g1) * p, b1 + (b2 - b1) * p, opts.component)
        if p >= 1 then e.running = false; effects[k] = nil; if opts.onDone then pcall(opts.onDone) end; return end
        Timer.SetTimeout(step, dt)
    end
    e.stop = function() lib.stopVehicleEffect(vehicle) end
    Timer.SetTimeout(step, dt)
    return e
end

-- PARTY MODE: continuously cycle a vehicle (or one component) through the colour wheel.
-- opts: { component = name, speed = hue/second (default 0.25 ≈ 4s/cycle), saturation = 1, value = 1, steps_ms = 33 }.
-- Returns a handle { stop = fn }. Call handle.stop() or lib.stopVehicleEffect(vehicle) to end it.
function lib.vehicleParty(vehicle, opts)
    opts = opts or {}
    lib.stopVehicleEffect(vehicle)
    local k = effectKey(vehicle); local e = { running = true }; effects[k] = e
    local dt = opts.steps_ms or 33
    local speed = opts.speed or 0.25
    local s, v = opts.saturation or 1, opts.value or 1
    local hue = opts.startHue or 0
    local function step()
        if not e.running then return end
        local r, g, b = lib.hsvToRgb(hue % 1, s, v)
        paintVehicle(vehicle, r, g, b, opts.component)
        hue = hue + speed * (dt / 1000)
        Timer.SetTimeout(step, dt)
    end
    e.stop = function() lib.stopVehicleEffect(vehicle) end
    Timer.SetTimeout(step, dt)
    return e
end
