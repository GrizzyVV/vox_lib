--[[ lib.spawnVehicle / lib.spawnObject / lib.deleteEntity — clean one-call entity spawning that packages the HELIX natives.
     SERVER-side (HVehicle / HWorld:SpawnActor are server-authoritative; spawned actors replicate to clients automatically —
     probe-verified: a bare HVehicle() is visible to clients with no extra registration).

     Coords accept a UE `Vector` OR a plain table `{x=,y=,z=}` / `{X=,Y=,Z=}` / `{n,n,n}`. Heading is a yaw number; rotation
     accepts a `Rotator`, a yaw number, or `{pitch=,yaw=,roll=}`. ]]

local function toVector(c)
    if c == nil then return Vector() end
    if type(c) == "userdata" then return c end          -- already a UE Vector
    local v = Vector()
    v.X = c.x or c.X or c[1] or 0
    v.Y = c.y or c.Y or c[2] or 0
    v.Z = c.z or c.Z or c[3] or 0
    return v
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
function lib.spawnObject(class, coords, rotation, opts)
    local cls = class
    if type(class) == "string" then cls = LoadClass(class) end
    if not cls then return nil end
    local ok, a = pcall(function() return HWorld:SpawnActor(cls, toVector(coords), toRotator(rotation)) end)
    if not ok or not a then return nil end
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
-- ⚠️ PARTIAL (probe-verified 2026-06-27): SendEnterVehicleEventToActor + FHEnterVehicleParams EXIST, but the params struct
-- carries ONLY `bSkipAnimations` — it does NOT take a target vehicle/seat. So this fires the enter intent (likely the nearest
-- vehicle, FiveM-"press F"-style); warping into a SPECIFIC vehicle/seat isn't expressible via these params on the current build.
-- The 3rd/4th args are accepted for forward-compat but currently unused. Needs a deeper probe to target a specific seat.
function lib.warpIntoVehicle(pawn, _vehicle, _seat, opts)
    if not pawn then return { ok = false, error = "pawn required" } end
    if type(UE) ~= "table" or not UE.UHGameplaySystemGlobals then return { ok = false, error = "vehicle-event globals unavailable" } end
    opts = opts or {}
    local ok = pcall(function()
        local p = UE.FHEnterVehicleParams()
        p.bSkipAnimations = opts.skipAnimations and true or false
        UE.UHGameplaySystemGlobals.SendEnterVehicleEventToActor(pawn, p)
    end)
    return ok and { ok = true, note = "enter intent sent; specific-vehicle targeting unverified" }
        or { ok = false, error = "SendEnterVehicleEventToActor failed" }
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

-- Destroy a spawned actor (vehicle or object). Returns boolean.
-- NOTE: destroying a VEHICLE while a player is seated strands that player in the seated pose. Pass `ejectFirst = true`
-- (or call lib.ejectAll) to cleanly eject occupants first — now that lib.exitVehicle exists, this is the proper fix.
function lib.deleteEntity(entity, ejectFirst)
    if not entity then return false end
    if ejectFirst and entity.SeatOccupancy then lib.ejectAll(entity) end
    return pcall(function() entity:K2_DestroyActor() end)
end
