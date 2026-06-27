--[[ lib.points / lib.zones — spatial triggers (the ox_lib points/zones contract), pure-Lua over a single tick loop.
     A point = a coords + a trigger radius; a zone = a sphere or an (optionally yaw-rotated) box. One shared interval reads the
     local player's position and fires onEnter / onExit (and per-tick inside/nearby) on transitions. CLIENT-side.

     Pure math (distance / point-in-box) — no UE physics components needed, so it's portable and cheap. For physics-overlap
     zones use UBoxComponent/USphereComponent directly. ]]

local _entries = {}      -- id -> entry
local _next = 0
local _timer = nil
local TICK = 200         -- ms

local function playerCoords()
    if GetPlayerPawn == nil then return nil end
    local c
    pcall(function() c = GetEntityCoords(GetPlayerPawn()) end)
    return c
end

local function dist2(a, b)
    local dx, dy, dz = (a.X or 0) - (b.X or 0), (a.Y or 0) - (b.Y or 0), (a.Z or 0) - (b.Z or 0)
    return dx * dx + dy * dy + dz * dz
end

local function insideSphere(e, p) return dist2(e.coords, p) <= (e.radius * e.radius) end

local function insideBox(e, p)
    -- translate into box space, undo yaw, compare half-extents
    local dx, dy, dz = p.X - e.coords.X, p.Y - e.coords.Y, p.Z - e.coords.Z
    if e.yaw and e.yaw ~= 0 then
        local r = -math.rad(e.yaw)
        local cosr, sinr = math.cos(r), math.sin(r)
        dx, dy = dx * cosr - dy * sinr, dx * sinr + dy * cosr
    end
    return math.abs(dx) <= e.half.x and math.abs(dy) <= e.half.y and math.abs(dz) <= e.half.z
end

local function tick()
    local p = playerCoords()
    if not p then return end
    for _, e in pairs(_entries) do
        local now = e.test(e, p)
        if now and not e.was then if e.onEnter then pcall(e.onEnter, e) end end
        if (not now) and e.was then if e.onExit then pcall(e.onExit, e) end end
        if now and e.inside then pcall(e.inside, e) end
        if e.nearby and dist2(e.coords, p) <= (e.nearDist * e.nearDist) then pcall(e.nearby, e, p) end
        e.was = now
    end
end

local function ensureTimer()
    if _timer or type(Timer) ~= "table" or type(Timer.SetInterval) ~= "function" then return end
    _timer = Timer.SetInterval(tick, TICK)
end

local function toCoords(c)
    return { X = c.x or c.X or c[1] or 0, Y = c.y or c.Y or c[2] or 0, Z = c.z or c.Z or c[3] or 0 }
end

local function register(e)
    _next = _next + 1; e.id = _next; e.was = false
    _entries[e.id] = e
    ensureTimer()
    e.remove = function() _entries[e.id] = nil end
    return e
end

lib.points = {}
-- lib.points.new{ coords=, distance= (trigger radius), onEnter=, onExit=, inside=, nearby=, nearDistance= }
function lib.points.new(o)
    o = o or {}
    return register({
        coords = toCoords(o.coords or {}), radius = o.distance or 100, test = insideSphere,
        onEnter = o.onEnter, onExit = o.onExit, inside = o.inside,
        nearby = o.nearby, nearDist = o.nearDistance or (o.distance or 100) * 2,
    })
end

lib.zones = {}
-- lib.zones.sphere{ coords=, radius=, onEnter=, onExit=, inside= }
function lib.zones.sphere(o)
    o = o or {}
    return register({ coords = toCoords(o.coords or {}), radius = o.radius or 100, test = insideSphere,
                      onEnter = o.onEnter, onExit = o.onExit, inside = o.inside, nearDist = 0 })
end
-- lib.zones.box{ coords=, size={x,y,z} (FULL extents), rotation= (yaw deg), onEnter=, onExit=, inside= }
function lib.zones.box(o)
    o = o or {}
    local s = o.size or { x = 100, y = 100, z = 100 }
    return register({ coords = toCoords(o.coords or {}),
                      half = { x = (s.x or s[1] or 100) / 2, y = (s.y or s[2] or 100) / 2, z = (s.z or s[3] or 100) / 2 },
                      yaw = type(o.rotation) == "number" and o.rotation or (o.rotation and (o.rotation.yaw or o.rotation.Yaw)) or 0,
                      test = insideBox, onEnter = o.onEnter, onExit = o.onExit, inside = o.inside, nearDist = 0 })
end

-- remove all zones/points (e.g. in onShutdown)
function lib.removeAllZones()
    _entries = {}
    if _timer then pcall(function() Timer.ClearInterval(_timer) end); _timer = nil end
end

return lib.points
