--[[ lib.spawnVehicle / lib.spawnObject / lib.deleteEntity — clean one-call entity spawning that packages the HELIX natives.
     SERVER-side (HVehicle / HWorld:SpawnActor are server-authoritative; spawned actors replicate to clients automatically —
     probe-verified: a bare HVehicle() is visible to clients with no extra registration).

     Coords accept a UE `Vector` OR a plain table `{x=,y=,z=}` / `{X=,Y=,Z=}` / `{n,n,n}`. Heading is a yaw number; rotation
     accepts a `Rotator`, a yaw number, or `{pitch=,yaw=,roll=}`. ]]

-- NOTE: build via the ARGS-constructor `Vector(x,y,z)` / `Rotator(p,y,r)`, NOT `Vector()` + `.X=` property-assignment.
-- In-engine 2026-06-30: on a TABLE input the construct-then-assign pattern did NOT persist the scalar writes (UnLua
-- value-struct gotcha) → produced a (0,0,0)+NaN transform that SpawnActor silently rejects (actor=nil, no error). The
-- args-form is probe-verified clean. (Latent: a real Vector userdata always worked via the passthrough branch — only
-- table coords hit the bug, so spawnVehicle/spawnObject/spawnPed were silently origin-spawning on table input.)
local function toVector(c)
    if c == nil then return Vector(0, 0, 0) end
    if type(c) == "userdata" then return c end          -- already a UE Vector
    return Vector(c.x or c.X or c[1] or 0, c.y or c.Y or c[2] or 0, c.z or c.Z or c[3] or 0)
end

local function toRotator(r)
    if r == nil then return Rotator(0, 0, 0) end
    if type(r) == "number" then return Rotator(0, r, 0) end   -- bare yaw
    if type(r) == "userdata" then return r end                -- already a Rotator
    return Rotator(r.pitch or r.Pitch or 0, r.yaw or r.Yaw or 0, r.roll or r.Roll or 0)
end

-- Spawn a vehicle. `asset` = the vehicle Blueprint path (e.g. "/HelixVehicles/Blueprints/Cars/H1/BP_H1.BP_H1_C").
-- opts (optional): { plate = string, tags = { "tag1", ... } }. Returns the vehicle actor (or nil).
function lib.spawnVehicle(asset, coords, heading, opts)
    if type(asset) ~= "string" or asset == "" then return nil end
    local ok, v = pcall(function() return HVehicle(toVector(coords), toRotator(heading), asset) end)
    if not ok or not v then return nil end
    opts = opts or {}
    if opts.plate and v.SetPlate then pcall(function() v:SetPlate(tostring(opts.plate)) end) end
    if opts.tags and v.Tags then for _, t in ipairs(opts.tags) do pcall(function() v.Tags:Add(t) end) end end
    return v
end

-- Spawn a generic actor. `class` = a UClass or a class path string (e.g. "/Script/Engine.CameraActor").
-- opts (optional): { tags = { ... } }. Returns the actor (or nil).
-- IN-ENGINE 2026-06-30: the `HWorld:SpawnActor(cls, vector, rotator)` overload HARD-CRASHED the client (Assertion
-- IsRotationNormalized — a C++ crash pcall can't catch): passing two struct-returning calls as adjacent UFUNCTION args
-- corrupts the rotation into a non-normalized quat. So spawn via the freecam-VERIFIED `SpawnActor(cls, Transform,
-- AlwaysSpawn)` form at IDENTITY (normalized) rotation, then orient post-spawn via K2_SetActorRotation (a valid-rotator
-- path, proven safe). Both primitives verified this session.
function lib.spawnObject(class, coords, rotation, opts)
    local cls = class
    if type(class) == "string" then cls = LoadClass(class) end
    if not cls or not HWorld then return nil end
    local a
    pcall(function()
        local t = Transform()
        t.Translation = toVector(coords)
        a = HWorld:SpawnActor(cls, t, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn)
    end)
    if not a then return nil end
    if rotation ~= nil then pcall(function() a:K2_SetActorRotation(toRotator(rotation), false) end) end
    opts = opts or {}
    if opts.tags and a.Tags then for _, t in ipairs(opts.tags) do pcall(function() a.Tags:Add(t) end) end end
    return a
end

-- Spawn an NPC/ped. `coords`/`rotation` as above. opts: { name = string (nameplate label), nameplate = bool,
-- invincible = bool (default true), frozen = bool (default true — NPCs usually stand still), tags = {...} }.
-- ASYNC: HPawn delivers the pawn via callback. Pass `cb(pawn)` to receive it; the call also returns nothing synchronously.
-- SERVER-side. (Probe-verified pattern: HPawn(coords, rot, fn(npc), { CharacterName=, bShowNameplate= }).)
function lib.spawnPed(coords, rotation, opts, cb)
    if type(opts) == "function" then cb, opts = opts, nil end
    opts = opts or {}
    if HPawn == nil then if cb then cb(nil) end return end
    local ok = pcall(function()
        HPawn(toVector(coords), toRotator(rotation), function(npc)
            if npc then
                if opts.frozen ~= false then pcall(function() npc.CharacterMovement:DisableMovement() end) end
                if opts.invincible ~= false then pcall(function() SetEntityInvincible(npc, true) end) end
                if opts.tags and npc.Tags then for _, t in ipairs(opts.tags) do pcall(function() npc.Tags:Add(t) end) end end
            end
            if cb then cb(npc) end
        end, { CharacterName = opts.name or "", bShowNameplate = opts.nameplate and true or false })
    end)
    if not ok and cb then cb(nil) end
end

-- ── vehicle occupancy: EXIT / WARP-IN (the seat-link controls; closes the "stranded seated pawn" gap) ──────────────
-- Eject a single occupant pawn from whatever vehicle it's in. opts: { skipAnimations = bool (default true) }.
function lib.exitVehicle(pawn, opts)
    if not pawn then return { ok = false, error = "pawn required" } end
    if type(UE) ~= "table" or not UE.UHGameplaySystemGlobals then return { ok = false, error = "vehicle-event globals unavailable" } end
    opts = opts or {}
    local ok = pcall(function()
        local p = UE.FHExitVehicleParams()
        p.bSkipAnimations = opts.skipAnimations ~= false
        UE.UHGameplaySystemGlobals.SendExitVehicleEventToActor(pawn, p)
    end)
    return ok and { ok = true } or { ok = false, error = "SendExitVehicleEventToActor failed" }
end

-- Eject EVERY occupant of a vehicle (iterates its SeatOccupancy). Use before deleteEntity to avoid stranding players.
function lib.ejectAll(vehicle, opts)
    if not vehicle or not vehicle.SeatOccupancy then return { ok = false, error = "not a seated vehicle" } end
    local n = 0
    pcall(function()
        for _, occ in pairs(vehicle.SeatOccupancy:ToTable()) do
            if occ then lib.exitVehicle(occ, opts); n = n + 1 end
        end
    end)
    return { ok = true, ejected = n }
end

-- Send a pawn an ENTER-VEHICLE event (the FiveM "warp into vehicle" intent).
-- ⛔ DISABLED — DANGEROUS on the current build. PROBE 2026-06-27: SendEnterVehicleEventToActor + FHEnterVehicleParams exist, but
-- FHEnterVehicleParams carries ONLY `bSkipAnimations` (no target vehicle/seat), and calling the native without a valid target
-- HARD-CRASHES the client (EXCEPTION_ACCESS_VIOLATION — null vehicle deref; reproduced live, crashed the world). A `pcall` does
-- NOT catch a C++ access violation, so we must NOT invoke it until the correct way to pass the target vehicle is found. This is a
-- guarded NO-OP returning an error; do not re-enable the native call without a verified-safe invocation. (Vehicle EXIT is fine —
-- see lib.exitVehicle.)
function lib.warpIntoVehicle(_pawn, _vehicle, _seat, _opts)
    return { ok = false, error = "warpIntoVehicle disabled: SendEnterVehicleEventToActor crashes the client without a valid " ..
             "target vehicle (FHEnterVehicleParams has no vehicle field on the current build). Targeting mechanism unresolved." }
end

-- ── vehicle readback helpers (direct HVehicle methods; pass an HVehicle or wrap a raw actor via HVehicle.wrap) ──────
local function asVehicle(v)
    if not v then return nil end
    if v.GetPlate then return v end                                   -- already an HVehicle handle
    if v.Object and HVehicle and HVehicle.wrap then return HVehicle.wrap(v.Object) end
    return v
end
function lib.getVehiclePlate(v)  v = asVehicle(v); local p; pcall(function() p = v:GetPlate() end); return p end
function lib.getVehicleFuel(v)   v = asVehicle(v); local f; pcall(function() f = v:GetFuelRatio() end); return f end
function lib.getVehicleEngineHealth(v) v = asVehicle(v); local h; pcall(function() h = v:GetEngineHealth() end); return h end
function lib.setVehicleFuel(v, f) v = asVehicle(v); return pcall(function() v:SetFuel(f) end) end
function lib.setVehiclePlate(v, p) v = asVehicle(v); return pcall(function() v:SetPlate(tostring(p)) end) end

-- ── attach / detach (props on peds/vehicles, etc.) ────────────────────────────────────────────────────────────────
-- rule: "snap" | "keepWorld" | "keepRelative" (default "snap"). Attaches `child` actor to `parent` actor.
function lib.attachEntity(child, parent, rule)
    if not child or not parent then return { ok = false, error = "child and parent required" } end
    if AttachActorToActor == nil then return { ok = false, error = "AttachActorToActor unavailable" } end
    local rules = { snap = UE and UE.EAttachmentRule and UE.EAttachmentRule.SnapToTarget,
                    keepworld = UE and UE.EAttachmentRule and UE.EAttachmentRule.KeepWorld,
                    keeprelative = UE and UE.EAttachmentRule and UE.EAttachmentRule.KeepRelative }
    local r = rules[tostring(rule or "snap"):lower()]
    local ok = pcall(function() AttachActorToActor(child, parent, r) end)
    return ok and { ok = true } or { ok = false, error = "AttachActorToActor failed" }
end
function lib.detachEntity(child)
    if not child then return { ok = false, error = "child required" } end
    if DetachActor == nil then return { ok = false, error = "DetachActor unavailable" } end
    local ok = pcall(function() DetachActor(child) end)
    return ok and { ok = true } or { ok = false, error = "DetachActor failed" }
end

-- Destroy a spawned actor (vehicle or object). Returns boolean (or true=scheduled when ejectFirst delays the destroy).
-- ⚠️ STRANDING (live-verified 2026-06-27): destroying a VEHICLE while a player is seated STRANDS them in the seated pose, and
-- there is NO programmatic recovery once it's deleted (exitVehicle/anim-override/movement-reset all fail — only a RELOG fixes it).
-- So this must be PREVENTED, not recovered. `ejectFirst=true` ejects occupants WHILE the vehicle still exists, then DELAYS the
-- destroy (the exit event is async — hl-garages waits ~3s) so occupants fully leave before the actor is gone. With a delay
-- available it returns true immediately and destroys later; without a Timer it falls back to eject+immediate (best-effort).
local EJECT_DESTROY_DELAY = 3000
function lib.deleteEntity(entity, ejectFirst)
    if not entity then return false end
    if ejectFirst and entity.SeatOccupancy then
        lib.ejectAll(entity)
        if type(Timer) == "table" and type(Timer.SetTimeout) == "function" then
            Timer.SetTimeout(function() pcall(function() entity:K2_DestroyActor() end) end, EJECT_DESTROY_DELAY)
            return true   -- scheduled: occupants ejected now, actor destroyed after the delay
        end
    end
    return pcall(function() entity:K2_DestroyActor() end)
end

-- ── entity / ped CONTROL + state (probe-VERIFIED actor/character methods, in-engine 2026-06-30) ─────────────────────
-- Resolve a raw UE actor from an HVehicle handle / wrapper / actor.
local function asActor(e) if type(e) == "table" then return e.Object or e end return e end

local function healthComponent(entity)
    local a = asActor(entity); if not a then return nil end
    local hc; pcall(function() hc = UE.UHActorHealthComponent.FindHealthComponent(a) end)
    return hc
end

-- FreezeEntityPosition (PED): frozen=true stops movement; false restores walking.
function lib.freezeEntity(ped, frozen)
    local a = asActor(ped); if not a then return false end
    return pcall(function()
        if frozen ~= false then a.CharacterMovement:DisableMovement()
        else a.CharacterMovement:SetMovementMode(1, 0) end   -- 1 = MOVE_Walking
    end)
end

-- Freeze a gameplay VEHICLE dead in place. The Chaos vehicle keeps sliding otherwise; SetSimulatePhysics alone does NOT
-- hold, so disable every component tick + physics. frozen=false re-enables. (proven in the vehicle-paint test.)
function lib.freezeVehicle(vehicle, frozen)
    local a = asActor(vehicle); if not a then return false end
    return pcall(function()
        a:SetActorTickEnabled(frozen == false)
        local comps = a:K2_GetComponentsByClass(UE.UActorComponent)
        local n = 0; pcall(function() n = comps:Length() end)
        for i = 0, n - 1 do
            local c; pcall(function() c = comps:Get(i) end)
            if c then
                pcall(function() c:SetComponentTickEnabled(frozen == false) end)
                pcall(function() c:SetSimulatePhysics(frozen == false) end)
            end
        end
    end)
end

-- SetEntityCollision / SetEntityVisible / GetEntityModel.
function lib.setEntityCollision(entity, enabled) local a = asActor(entity); return a and pcall(function() a:SetActorEnableCollision(enabled ~= false) end) end
function lib.setEntityVisible(entity, visible)  local a = asActor(entity); return a and pcall(function() a:SetActorHiddenInGame(visible == false) end) end
function lib.getEntityModel(entity) local a = asActor(entity); local n; pcall(function() n = tostring(a:GetClass():GetName()) end); return n end

-- Entity health. PEDS read real values via the actor health component; VEHICLES read 0 here -> use lib.getVehicleEngineHealth.
function lib.getEntityHealth(entity)    local hc = healthComponent(entity); local h; if hc then pcall(function() h = hc:GetHealth() end) end; return h end
function lib.getEntityMaxHealth(entity) local hc = healthComponent(entity); local h; if hc then pcall(function() h = hc:GetMaxHealth() end) end; return h end
function lib.isEntityDead(entity)       local hc = healthComponent(entity); local d; if hc then pcall(function() d = hc:IsDeadOrDying() end) end; return d end

-- GetPedBoneCoords: world location of a ped's bone/socket. NOTE: GetMesh() is nil in UnLua -> read the .Mesh PROPERTY.
function lib.getBoneCoords(ped, bone)
    local a = asActor(ped); if not a then return nil end
    local loc; pcall(function() loc = a.Mesh:GetSocketLocation(bone) end); return loc
end

-- TaskGoToCoord: send an NPC (HPawn-spawned) to a destination via its AI controller. Returns boolean.
function lib.taskGoTo(ped, coords)
    local a = asActor(ped); if not a then return false end
    return pcall(function()
        local ctrl = a:GetController()
        UE.UAIBlueprintHelperLibrary.SimpleMoveToLocation(ctrl, toVector(coords))
    end)
end
