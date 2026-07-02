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

-- The world handle: bare `HWorld` can be nil in some package states (smoke-test 2026-06-30 caught getActorsOfClass
-- returning 0 because of this) -> fall back to GetWorld().
local function world() return HWorld or (GetWorld and GetWorld()) or nil end

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
    local w = world()
    if not cls or not w then return nil end
    local a
    pcall(function()
        local t = Transform()
        t.Translation = toVector(coords)
        a = w:SpawnActor(cls, t, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn)
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
-- setEntityVisible / isEntityVisible — ✅ VERIFIED 2026-06-30 via the `.bHidden` PROPERTY (the `IsHidden()` getter reads nil):
-- setVisible(true) -> bHidden=false, setVisible(false) -> bHidden=true.
function lib.setEntityVisible(entity, visible)  local a = asActor(entity); return a and pcall(function() a:SetActorHiddenInGame(visible == false) end) end
function lib.isEntityVisible(entity) local a = asActor(entity); local h; if a then pcall(function() h = a.bHidden end) end; return h == false end
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

-- TaskGoToCoord: send an NPC (HPawn-spawned) to a destination via its AI controller.
-- ⚠️ UNPROVEN — NAVMESH-BLOCKED in the test world (diagnosed 2026-06-30): the wiring is CORRECT — a grounded ped (MovementMode=1
-- Walking) with its B_AI_Controller_C; SimpleMoveToLocation/MoveToLocation are callable. BUT the ped moves 0 units because the
-- sandbox world has NO navmesh (RecastNavMesh actors = 0; ProjectPointToNavigation = false), and AI pathing REQUIRES a built
-- navmesh. So this is environment-blocked, not code-broken — it should work on a real HELIX map with navigation built, but that
-- is UNPROVEN (no navmeshed world to test on here). Returns pcall success of the call only. For nav-free movement, a manual
-- AddMovementInput steering loop is the fallback to explore.
function lib.taskGoTo(ped, coords)
    local a = asActor(ped); if not a then return false end
    return pcall(function()
        local ctrl = a:GetController()
        UE.UAIBlueprintHelperLibrary.SimpleMoveToLocation(ctrl, toVector(coords))
    end)
end

-- lib.walkTo(ped, coords, opts) — NAV-FREE straight-line steering: AddMovementInput toward the target each tick until within
-- `radius` or timeout. ✅ VERIFIED in-engine 2026-06-30 (measured: a ped walked 351->768->1169 units toward the target, + eyes).
-- Works WITHOUT a navmesh (unlike taskGoTo's AI pathing), but is straight-line = NO obstacle avoidance. Non-blocking (drives
-- itself on a Timer). opts: { radius=100, maxMs=15000, speed=1.0, onArrive=fn(reached_bool) }. Returns true if the loop started.
function lib.walkTo(ped, coords, opts)
    local a = asActor(ped); if not a then return false end
    opts = opts or {}
    local dest = toVector(coords)
    local radius = opts.radius or 100
    local maxTicks = math.floor((opts.maxMs or 15000) / 33)
    local speed = opts.speed or 1.0
    local ticks = 0
    local function tick()
        ticks = ticks + 1
        local cur; pcall(function() cur = a:K2_GetActorLocation() end)
        if not cur then if opts.onArrive then pcall(opts.onArrive, false) end return end
        local dx, dy = dest.X - cur.X, dest.Y - cur.Y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= radius or ticks >= maxTicks then
            if opts.onArrive then pcall(opts.onArrive, dist <= radius) end
            return
        end
        pcall(function() a:AddMovementInput(UE.FVector(dx, dy, 0.0), speed, false) end)
        Timer.SetTimeout(tick, 33)
    end
    tick()
    return true
end

-- ── spatial + enumeration + vehicle repair (b2probe-VERIFIED 2026-06-30) ────────────────────────────────────────────
-- GTA bone-id/hash -> UE skeleton bone NAME (PARTIAL, best-effort — the common set; unknown ids fall through to nil, no
-- regression). FiveM GetPedBoneIndex passes a GTA bone id; HELIX GetBoneIndex wants a UE bone-name string. ⚠️ UE names are
-- best-guess (standard UE5 humanoid); verify against SK_Unified in-engine and extend. A string `bone` is used as-is.
local GTA_BONE = {
    [0]     = "root",     [31086] = "head",      [39317] = "neck_01",   [24816] = "spine_03",
    [24817] = "spine_02", [23553] = "spine_01",  [57597] = "pelvis",    [18905] = "hand_l",
    [57005] = "hand_r",   [45509] = "upperarm_l",[40269] = "upperarm_r",[61163] = "lowerarm_l",
    [28252] = "lowerarm_r",[65245]= "thigh_l",   [51826] = "thigh_r",   [14201] = "calf_l",
    [52301] = "calf_r",   [2108]  = "foot_l",    [14606] = "foot_r",
}
-- GetPedBoneIndex: a ped's bone index. Accepts a UE bone-NAME string, or a GTA bone id (translated via GTA_BONE, partial).
function lib.getBoneIndex(ped, bone)
    local a = asActor(ped); if not a then return nil end
    if type(bone) == "number" then bone = GTA_BONE[bone] end
    if type(bone) ~= "string" then return nil end
    local i; pcall(function() i = a.Mesh:GetBoneIndex(bone) end); return i
end

-- GetOffsetFromEntityInWorldCoords: world point at a local offset from an actor. NOTE GetActorTransform() is nil ->
-- use GetTransform(); TransformPosition returned ped_loc + offset EXACTLY in-engine.
function lib.getEntityOffsetCoords(entity, dx, dy, dz)
    local a = asActor(entity); if not a then return nil end
    local p; pcall(function() p = a:GetTransform():TransformPosition(toVector({ dx or 0, dy or 0, dz or 0 })) end)
    return p
end

-- GetGamePool / GetGamePoolForEntityType: all actors of a class as a Lua array. `class` = a UClass (e.g. UE.AHVehiclePawn,
-- UE.AHCharacter) or a class-path string. Verified via UGameplayStatics.GetAllActorsOfClass.
-- FAILED-CLASS CACHE (log/CPU guard 2026-07-02): converted GTA code passes GTA MODEL NAMES ('prop_roadcone02a') in per-tick
-- loops -> LoadClass warns EVERY call (209x/name in one session). Unresolvable strings are cached and skipped silently.
local _badClass = {}
function lib.getActorsOfClass(class)
    local out = {}
    if type(class) == "string" and _badClass[class] then return out end
    local cls = type(class) == "string" and LoadClass(class) or class
    if not cls then
        if type(class) == "string" then
            _badClass[class] = true
            print("[vox_lib] getActorsOfClass: unresolvable class '" .. class .. "' (GTA model name? needs a HELIX asset path) -> cached, further calls silent")
        end
        return out
    end
    local w = world()
    if not w then return out end
    pcall(function()
        local arr = UE.TArray(UE.AActor)
        UE.UGameplayStatics.GetAllActorsOfClass(w, cls, arr)
        for i = 1, arr:Length() do out[#out + 1] = arr:Get(i) end   -- UnLua TArray is 1-INDEXED (Get(0)=nil)
    end)
    return out
end

-- SetVehicleFixed / engine-health write. ⚠️ NO OBSERVABLE EFFECT — even DRIVEN. Exhaustively checked 2026-06-30: on a bare
-- spawn AND with the PLAYER SEATED IN THE CAR (occupancy=1), all three readers stayed flat (GetEngineHealth=nil,
-- GetVehicleHealthComponent():GetHealth()=0.0, actor HealthComponent=0.0), and SetEngineHealth(250)/(1000) changed none of them.
-- ⇒ this engine-health API is effectively DEAD on this build (no read, no write). Do NOT claim it works; surface vehicle
-- damage/repair as a gap or via a different mechanism if HELIX exposes one.
function lib.setVehicleEngineHealth(v, h) v = asVehicle(v); return pcall(function() v:SetEngineHealth(h) end) end
function lib.repairVehicle(v, full)       v = asVehicle(v); return pcall(function() v:SetEngineHealth(full or 1000) end) end

-- PlaceObjectOnGroundProperly: raycast straight down from the actor and teleport it to the ground hit (keeps rotation).
-- ✅ VERIFIED 2026-06-30 (measured: an actor spawned at Z=892 dropped to Z≈0 = ground). The earlier smoke "false" was a too-short
-- `down` distance for that spawn -> pass a `down` that reaches the ground (default 1000; use more for high spawns).
function lib.placeOnGround(entity, opts)
    local a = asActor(entity); if not a then return false end
    opts = opts or {}
    local loc; pcall(function() loc = a:K2_GetActorLocation() end)
    if not loc then return false end
    local up, down = opts.up or 100, opts.down or 1000
    local res = lib.raycast and lib.raycast({ loc.X, loc.Y, loc.Z + up }, { loc.X, loc.Y, loc.Z - down }, { ignore = { a } })
    if not (res and res.hit and res.result and res.result.location) then return false end
    return pcall(function() a:K2_TeleportTo(res.result.location, a:K2_GetActorRotation()) end)
end

-- ── motion / state reads (b2probe-VERIFIED 2026-06-30) ──────────────────────────────────────────────────────────────
-- GetEntitySpeed — velocity magnitude (cm/s). GetEntityForwardVector — facing unit vector.
function lib.getEntitySpeed(entity)  local a = asActor(entity); local s; if a then pcall(function() s = a:GetVelocity():Size() end) end; return s end
function lib.getForwardVector(entity) local a = asActor(entity); local v; if a then pcall(function() v = a:GetActorForwardVector() end) end; return v end

-- Ped movement state via the UHCharacterMovementComponent (verified: IsSwimming/IsFalling/IsMovingOnGround callable).
local function charMove(ped) local a = asActor(ped); local c; if a then pcall(function() c = a.CharacterMovement end) end; return c end
function lib.isPedSwimming(ped) local c = charMove(ped); local r; if c then pcall(function() r = c:IsSwimming() end) end; return r and true or false end
function lib.isPedFalling(ped)  local c = charMove(ped); local r; if c then pcall(function() r = c:IsFalling() end) end; return r and true or false end
function lib.isPedOnFoot(ped)   local c = charMove(ped); local r; if c then pcall(function() r = c:IsMovingOnGround() end) end; return r and true or false end

-- GetClosestObjectOfType / GetClosestPed|Vehicle — nearest actor of `class` to `coords` (GetGamePool + nearest filter).
-- Returns actor, distance. `class` = a UClass (UE.AHCharacter, UE.AHVehiclePawn, …) or a class-path string.
function lib.getClosestActor(coords, class, maxDist)
    local c = toVector(coords); local best, bestD
    for _, a in ipairs(lib.getActorsOfClass(class)) do
        local d; pcall(function() local l = a:K2_GetActorLocation(); d = math.sqrt((l.X - c.X) ^ 2 + (l.Y - c.Y) ^ 2 + (l.Z - c.Z) ^ 2) end)
        if d and (not bestD or d < bestD) and (not maxDist or d <= maxDist) then best, bestD = a, d end
    end
    return best, bestD
end

-- World3dToScreen2d — project a world point to a screen position {x,y}. CLIENT-side. VERIFIED 2026-06-30 (client smoke:
-- returned real screen coords for the player's own position). ProjectWorldToScreen returns (bool, FVector2D).
function lib.worldToScreen(coords)
    if not (HPlayer and UE.UGameplayStatics and UE.UGameplayStatics.ProjectWorldToScreen) then return nil end
    local out
    pcall(function()
        local ok, v2 = UE.UGameplayStatics.ProjectWorldToScreen(HPlayer, toVector(coords))
        local v = (type(v2) == "userdata") and v2 or (type(ok) == "userdata" and ok or nil)
        if v then out = { x = v.X, y = v.Y } end
    end)
    return out
end

-- ── converter B2->A wrappers (2026-07-02): back the FiveM-native re-compose map. Grounded in the 8-family sensor sweep +
-- catalog; several call catalog methods whose BEHAVIOR is unverified (pcall-guarded) -> in-engine test owed. ────────────
-- teleport (SetEntityCoordsNoOffset / SetPedCoordsKeepVehicle): move actor to coords, keep current rotation.
function lib.setEntityCoords(entity, x, y, z)
    local a = asActor(entity); if not a then return false end
    local loc = (type(x) == "userdata" or type(x) == "table") and toVector(x) or toVector({ x = x, y = y, z = z })
    return pcall(function() a:K2_TeleportTo(loc, a:K2_GetActorRotation()) end)
end
-- alpha (SetEntityAlpha): HELIX has no per-actor opacity -> binary visible (0 hidden / >0 shown).
function lib.setEntityAlpha(entity, alpha) return lib.setEntityVisible(entity, (tonumber(alpha) or 255) > 0) end
-- dynamic (SetEntityDynamic): dynamic=false => frozen=true (bool inverted).
function lib.setEntityDynamic(entity, dynamic) return lib.freezeEntity(entity, dynamic == false) end
-- proofs (SetEntityProofs): HELIX has only blanket invincibility, not granular per-proof flags.
function lib.setEntityProofs(entity, on) local a = asActor(entity); return a and pcall(function() SetEntityInvincible(a, on ~= false) end) end
-- clear tasks (ClearPedTasksImmediately / ClearPedSecondaryTask): no GTA task queue -> stop anim + restore movement.
function lib.clearPedTasks(ped) if lib.stopAnim then pcall(function() lib.stopAnim(ped) end) end return lib.freezeEntity(ped, false) end
-- stand still (TaskStandStill): freeze, auto-unfreeze after ms.
function lib.taskStandStill(ped, ms)
    lib.freezeEntity(ped, true)
    if ms and ms > 0 and Timer then pcall(function() Timer.SetTimeout(function() lib.freezeEntity(ped, false) end, ms) end) end
    return true
end
-- is-a-vehicle (IsEntityAVehicle): class check.
function lib.isEntityAVehicle(entity) local a = asActor(entity); local r; if a then pcall(function() r = a:IsA(UE.AHVehiclePawn) end) end return r and true or false end
-- is-a-player (IsPedAPlayer): controlled by a player.
function lib.isPedAPlayer(ped) local a = asActor(ped); local r; if a then pcall(function() r = a:IsPlayerControlled() end) end return r and true or false end
-- is-walking (IsPedWalking): on-foot + moving in a rough walking speed band (cm/s). NOT swimming/in-vehicle aware.
function lib.isPedWalking(ped)
    if lib.isPedOnFoot and not lib.isPedOnFoot(ped) then return false end
    local s = lib.getEntitySpeed(ped) or 0
    return s > 20 and s < 350
end
-- speed vector (GetEntitySpeedVector): world-space velocity vector.
function lib.getEntitySpeedVector(entity) local a = asActor(entity); local v; if a then pcall(function() v = a:GetVelocity() end) end return v end
-- player control (SetPlayerControl): enable/disable the local player's input over their character.
function lib.setPlayerControl(ped, hasControl)
    local frozen = hasControl == false
    lib.freezeEntity(ped, frozen)
    pcall(function() if HPlayer and HPlayer.SetIgnoreMoveInput then HPlayer:SetIgnoreMoveInput(frozen) end end)
    return true
end
-- vehicle seats (GetVehicleNumberOfPassengers / Max / IsPedSittingIn[Any]Vehicle) via SeatOccupancy.
function lib.getVehiclePassengerCount(v)
    v = asVehicle(v); local n = 0
    if v and v.SeatOccupancy then pcall(function() for _, occ in pairs(v.SeatOccupancy:ToTable()) do if occ then n = n + 1 end end end) end
    return n
end
function lib.getVehicleMaxSeats(v)
    v = asVehicle(v); local n = 0
    if v and v.SeatOccupancy then pcall(function() n = #v.SeatOccupancy:ToTable() end) end
    return n
end
function lib.isPedSittingInVehicle(ped, v)
    v = asVehicle(v); local a = asActor(ped); local r = false
    if v and v.SeatOccupancy and a then pcall(function() for _, occ in pairs(v.SeatOccupancy:ToTable()) do if occ == a then r = true break end end end) end
    return r
end
function lib.isPedSittingInAnyVehicle(ped)
    local a = asActor(ped); local r = false
    if a then pcall(function() local idx = a:GetSeatIndex(); r = idx ~= nil and idx >= 0 end) end
    return r
end
-- vehicle doors (SetVehicleDoorOpen / SetVehicleDoorsShut) via SetDoorRotation.
function lib.setVehicleDoorOpen(v, doorIndex) v = asVehicle(v); return v and pcall(function() v:SetDoorRotation(doorIndex or 0, 1.0) end) end
function lib.setVehicleDoorsShut(v) v = asVehicle(v); return v and pcall(function() for i = 0, 5 do v:SetDoorRotation(i, 0.0) end end) end
-- ped in vehicle (CreatePedInsideVehicle): spawn a ped then seat it.
function lib.createPedInsideVehicle(vehicle, seatIndex, coords, rotation)
    local ok, ped = pcall(function() return lib.spawnPed(coords, rotation) end)
    if ok and ped then local v = asVehicle(vehicle); pcall(function() v:TakeSeat(ped, seatIndex or 0) end) end
    return ped
end
-- all objects (GetAllObjects): enumerate world static-mesh actors (best-effort object class).
function lib.getAllObjects() return lib.getActorsOfClass(UE.AStaticMeshActor) end
-- gameplay cam rotation (GetGameplayCamRot): the local player's control rotation.
function lib.getGameplayCamRot() local r; pcall(function() r = HPlayer:GetControlRotation() end) return r end
-- occupant of a seat (GetPedInVehicleSeat): GTA seat -1 = driver -> first SeatOccupancy entry; else seat index (0-based GTA
-- -> ToTable() is 1-indexed, so seat s -> entry s+1). Returns the pawn or nil.
function lib.getPedInVehicleSeat(v, seat)
    v = asVehicle(v); if not (v and v.SeatOccupancy) then return nil end
    local occ; pcall(function() occ = v.SeatOccupancy:ToTable() end)
    if not occ then return nil end
    if seat == nil or seat == -1 then return occ[1] end
    return occ[(tonumber(seat) or 0) + 1]
end
