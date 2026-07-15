--[[ lib.map / blips — GTA-style map blips over HELIX's HMap marker API. CLIENT-SIDE.

     ✅ RENDER-VALIDATED (2026-07-11, PIE, Matt-confirmed): the engine call this module rides — `HMap.AddMarkerAt(FVector,
     opts)` (line ~44) — RENDERS on the minimap (`MarkerType=0` = a white square at the location; `SizeMultiplier` scales it);
     `RemoveMarkerAt(handle)` removes it. So `lib.addBlip`/`addBlipForEntity` render for real. (This was validated at the
     primitive layer but not previously noted here — banked 2026-07-13. Converter maps AddBlipForCoord/CreateBlip/
     AddBlipForEntity/SetBlipSprite -> exports.vox_lib:addBlip/... so a converted resource's blips ride this same path.)

     WHY IT'S SHAPED THIS WAY:
     - HMap has NO mutation methods (a marker is create-with-OPTIONS + remove only — AddMarker/AddMarkerAt/RemoveMarker/
       RemoveMarkerAt). FiveM's flow is AddBlipForCoord() -> then SetBlipSprite/Colour/Scale/name mutate that blip. So a blip
       here is a BUFFERED record: Set* store props and RE-CREATE the HMap marker (remove + AddMarkerAt with merged options).
     - Handles are INTEGER IDs, not tables. A blip is consumed via exports.vox_lib:* (blip handles must survive the package
       boundary); a table would be msgpack-COPIED (mutations wouldn't persist), so vox_lib owns the registry keyed by an id
       that crosses as plain data. (An entity marker holds the actor userdata, which DOES cross — probe-verified 2026-07-02.)
     - GRACEFUL NO-OP on map-less worlds: HMap is nil / the world has no minimap (e.g. HELIX_Craft) -> every call is a safe
       no-op (the blip is still tracked so DoesBlipExist/RemoveBlip stay consistent; it just never renders).

     ⚠️ IN-ENGINE TEST OWED on a map-HAVING world (HELIX_Craft has none). GTA numeric SPRITE ids have no HELIX icon map, so
        sprite is best-effort (stored as MarkerType tag); GTA COLOUR ids map via a small palette -> FLinearColor. The blip-name
        text-command cluster (BeginTextCommandSetBlipName/End) is handled at the converter layer, not here. ]]

local _blips = {}      -- id -> { x,y,z | actor, title, desc, sprite, color={r,g,b}, scale, h (HMap handle), _actorAdded }
local _seq = 0

-- GTA blip colour id -> {r,g,b} 0..1 (the common set; unknown ids fall back to white)
local COLOR = {
    [0]  = {1.00, 1.00, 1.00}, [1]  = {0.90, 0.12, 0.12}, [2]  = {0.20, 0.80, 0.25},
    [3]  = {0.30, 0.55, 0.95}, [4]  = {1.00, 1.00, 1.00}, [5]  = {0.90, 0.85, 0.20},
    [8]  = {0.95, 0.45, 0.80}, [17] = {0.95, 0.60, 0.25}, [21] = {0.95, 0.40, 0.10},
    [38] = {0.20, 0.45, 0.95}, [46] = {0.10, 0.10, 0.10}, [47] = {0.70, 0.20, 0.20},
}

local function hasMap() return HMap ~= nil end

-- (re)create the HMap marker for a blip record from its current buffered props
local function commit(b)
    if not hasMap() then return end
    if b.h then pcall(function() HMap.RemoveMarkerAt(b.h) end); b.h = nil end
    if b._actorAdded and b.actor then pcall(function() HMap.RemoveMarker(b.actor) end); b._actorAdded = false end
    local opts = { Title = b.title or "", Description = b.desc or "", SizeMultiplier = b.scale or 1.0 }
    if b.sprite then opts.MarkerType = tostring(b.sprite) end
    if b.color then
        local ok, col = pcall(function() return UE.FLinearColor(b.color[1], b.color[2], b.color[3], 1.0) end)
        if ok then opts.OverrideColor = col end
    end
    if b.actor then
        pcall(function() HMap.AddMarker(b.actor, opts) end); b._actorAdded = true
    else
        local ok, h = pcall(function() return HMap.AddMarkerAt(UE.FVector(b.x, b.y, b.z), opts) end)
        b.h = (ok and h ~= 0) and h or nil
    end
end

local function newId() _seq = _seq + 1; return _seq end

--- addBlip(x,y,z) or addBlip(vector) -> id. World-anchored map blip.
function lib.addBlip(x, y, z)
    local b
    if type(x) == "userdata" or type(x) == "table" then
        local v = x
        b = { x = v.X or v.x or v[1] or 0, y = v.Y or v.y or v[2] or 0, z = v.Z or v.z or v[3] or 0, scale = 1.0 }
    else
        b = { x = x or 0, y = y or 0, z = z or 0, scale = 1.0 }
    end
    local id = newId(); _blips[id] = b; commit(b)
    return id
end

--- addBlipForEntity(actor) -> id. Marker that follows an actor (auto-removed by HMap when the actor dies).
function lib.addBlipForEntity(actor)
    local b = { actor = actor, scale = 1.0 }
    local id = newId(); _blips[id] = b; commit(b)
    return id
end

local function set(id, k, v) local b = _blips[id]; if b then b[k] = v; commit(b) end end
function lib.setBlipSprite(id, spriteId) set(id, "sprite", spriteId) end
function lib.setBlipColour(id, colourId) set(id, "color", COLOR[colourId] or COLOR[0]) end
lib.setBlipColor = lib.setBlipColour
function lib.setBlipScale(id, s) set(id, "scale", tonumber(s) or 1.0) end
function lib.setBlipName(id, name) set(id, "title", tostring(name or "")) end
function lib.setBlipDescription(id, d) set(id, "desc", tostring(d or "")) end

--- doesBlipExist(id) -> boolean
function lib.doesBlipExist(id) return _blips[id] ~= nil end

--- removeBlip(id)
function lib.removeBlip(id)
    local b = _blips[id]; if not b then return end
    if b.h then pcall(function() HMap.RemoveMarkerAt(b.h) end) end
    if b._actorAdded and b.actor then pcall(function() HMap.RemoveMarker(b.actor) end) end
    _blips[id] = nil
end

--- setBlipNoop(...) — GTA blip props with NO HELIX analog (short-range / display / category / flashes / high-detail /
--- route / friendly / number-on-blip). Accepts + ignores its args so the call site is a safe no-op.
function lib.setBlipNoop() end
