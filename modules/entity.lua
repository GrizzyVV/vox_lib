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

-- Destroy a spawned actor (vehicle or object). Returns boolean.
-- WARNING: destroying a VEHICLE while a player is seated in it leaves that player stuck in the seated pose (the seat link
-- dangles). Make sure the vehicle is empty before deleting it — eject/clear occupants first. (A relog clears a stuck player.)
function lib.deleteEntity(entity)
    if not entity then return false end
    return pcall(function() entity:K2_DestroyActor() end)
end
