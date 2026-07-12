--[[ lib.weapon* — WEAPON ATTACHMENT control for HELIX weapon actors. PIE-verified 2026-07-11/12.

     MODEL (verified against a fully-configured Patriot): HELIX weapons are per-instance actors (`B_WeaponActor_*`)
     whose `SkeletalMesh` holds attachment CHILDREN as `StaticMeshComponent`s. Each child is parented to a SOCKET
     (`Charge`=top rail, `Muzzle`, `Grip`, `Stock`, `Clip`, …). Multiple children can share a socket, and exactly
     ONE is visible per socket = "the active attachment". So swapping an attachment = hide the active child on that
     socket + show the chosen one — done via the TWO render flags: `SetVisibility` + `SetHiddenInGame` (pass BOTH
     args to each, the 2nd = propagate-to-children, or UnLua logs a spurious "bool needed" warning).

     Attachments are normally PRE-PLACED in the weapon Blueprint (every option authored as a hidden child); this module
     reads + toggles them, and can runtime-ADD new ones (⚠ experimental — see `addWeaponAttachment`). CLIENT-side (the
     weapon actor + its render are client-local). Resolve the weapon actor from a pawn via `lib.getEquippedWeapon`.

     GOTCHAS (probe-verified): a component's mesh reads via the `.StaticMesh` PROPERTY, not `GetStaticMesh()` (nil in UnLua);
     `RegisterComponent`/`IsRegistered` are NOT Lua-exposed (affects runtime-add rendering — build-dependent). ]]

-- ── resolution helpers ───────────────────────────────────────────────────────────────────────────────────────────
-- The equipped weapon ACTOR for a pawn (default: local player). Returns the `B_WeaponActor_*` actor, or nil if unarmed/holstered.
function lib.getEquippedWeapon(pawn)
    pawn = pawn or (GetLocalPlayer and GetLocalPlayer() and GetLocalPlayer():GetControlledCharacter())
    if not pawn or type(HInventory) ~= "table" then return nil end
    local actor
    pcall(function()
        local eq = HInventory.GetEquippedItems(pawn)
        if not eq or eq:Length() == 0 then return end
        local inst = eq:Get(1)
        local sa = inst and inst.GetSpawnedActors and inst:GetSpawnedActors()
        if sa and sa:Length() > 0 then actor = sa:Get(1) end
    end)
    return actor
end

local function skeletalMesh(actor)
    local skm
    pcall(function()
        local comps = actor:GetComponentsByClass(UE.UActorComponent)
        for i = 1, comps:Length() do
            local c = comps:Get(i)
            if tostring(c:GetClass():GetName()):find("SkeletalMesh") then skm = c; break end
        end
    end)
    return skm
end

-- Iterate a weapon's attachment children (its StaticMeshComponents). `fn(component)`.
local function eachAttachment(actor, fn)
    if not actor or not actor.GetComponentsByClass then return end
    local ok, comps = pcall(function() return actor:GetComponentsByClass(UE.UStaticMeshComponent) end)
    if not ok or not comps then return end
    for i = 1, comps:Length() do local c = comps:Get(i); if c then fn(c) end end
end

local function socketOf(c) local s = "None"; pcall(function() s = tostring(c:GetAttachSocketName()) end); return s end
local function isVisible(c) local v = true; pcall(function() v = c:IsVisible() end); return v end
local function isHidden(c) local h = false; pcall(function() h = c.bHiddenInGame end); return h end
local function meshName(c) local m; pcall(function() local sm = c.StaticMesh; if sm then m = tostring(sm:GetName()) end end); return m end

local function findChild(actor, name)
    local found
    eachAttachment(actor, function(c) if tostring(c:GetName()) == name then found = c end end)
    return found
end

local function attachInfo(c)
    return { name = tostring(c:GetName()), socket = socketOf(c), mesh = meshName(c),
             visible = isVisible(c), hidden = isHidden(c) }
end

-- ── READ ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- All attachment children of a weapon actor → { {name, socket, mesh, visible, hidden}, ... }.
function lib.getWeaponAttachments(actor)
    local out = {}
    eachAttachment(actor, function(c) out[#out + 1] = attachInfo(c) end)
    return out
end

-- One attachment's render state → { visible, hidden } (or nil if not found).
function lib.getAttachmentState(actor, name)
    local c = actor and findChild(actor, name)
    if not c then return nil end
    return { visible = isVisible(c), hidden = isHidden(c) }
end

-- Distinct sockets in use on this weapon → { "Charge", "Stock", ... }.
function lib.getWeaponSockets(actor)
    local seen, out = {}, {}
    eachAttachment(actor, function(c)
        local s = socketOf(c)
        if s ~= "None" and not seen[s] then seen[s] = true; out[#out + 1] = s end
    end)
    return out
end

function lib.hasWeaponSocket(actor, socket)
    for _, s in ipairs(lib.getWeaponSockets(actor)) do if s == socket then return true end end
    return false
end

-- The currently-active (visible) attachment name at a socket, or nil.
function lib.getActiveAttachment(actor, socket)
    local active
    eachAttachment(actor, function(c)
        if socketOf(c) == socket and isVisible(c) then active = tostring(c:GetName()) end
    end)
    return active
end

-- ── WRITE ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Show/hide ONE attachment (sets BOTH render flags). `visible` true = show, false = hide.
function lib.toggleAttachment(actor, name, visible)
    local c = actor and findChild(actor, name)
    if not c then return { ok = false, error = "attachment not found: " .. tostring(name) } end
    pcall(function() c:SetVisibility(visible and true or false, true) end)
    pcall(function() c:SetHiddenInGame(not visible and true or false, true) end)
    return { ok = true }
end

-- Equip an attachment at a socket: hide EVERY child on that socket, show `name`. The main menu/equip primitive.
function lib.setActiveAttachment(actor, socket, name)
    if not actor then return { ok = false, error = "weapon actor required" } end
    local shown = false
    eachAttachment(actor, function(c)
        if socketOf(c) == socket then
            local target = (tostring(c:GetName()) == name)
            pcall(function() c:SetVisibility(target, true) end)
            pcall(function() c:SetHiddenInGame(not target, true) end)
            if target then shown = true end
        end
    end)
    if not shown then return { ok = false, error = "no attachment '" .. tostring(name) .. "' at socket '" .. tostring(socket) .. "'" } end
    return { ok = true }
end

-- Set a child's relative transform. `t` = { loc={x,y,z}, rot={pitch,yaw,roll}, scale={x,y,z} } (any subset).
-- `nameOrComp` may be a child name (string) or the component itself (userdata).
function lib.setAttachmentTransform(actor, nameOrComp, t)
    local c = (type(nameOrComp) == "userdata") and nameOrComp or (actor and findChild(actor, nameOrComp))
    if not c or type(t) ~= "table" then return { ok = false, error = "attachment + transform required" } end
    -- pass the full arg set (NewValue, bSweep, SweepHitResult, bTeleport) — a 1-arg call logs a spurious UnLua
    -- "bool needed but got no value" marshal warning (same class as SetHiddenInGame); the value applies either way.
    if t.loc then pcall(function() c:SetRelativeLocation(Vector(t.loc.x or t.loc[1] or 0, t.loc.y or t.loc[2] or 0, t.loc.z or t.loc[3] or 0), false, nil, false) end) end
    if t.rot then pcall(function() c:SetRelativeRotation(Rotator(t.rot.pitch or t.rot[1] or 0, t.rot.yaw or t.rot[2] or 0, t.rot.roll or t.rot[3] or 0), false, nil, false) end) end
    if t.scale then pcall(function() c:SetRelativeScale3D(Vector(t.scale.x or t.scale[1] or 1, t.scale.y or t.scale[2] or 1, t.scale.z or t.scale[3] or 1)) end) end
    return { ok = true }
end

-- Runtime-ADD a new attachment mesh to a weapon at a socket (for attachments NOT pre-placed in the BP).
-- `meshPath` = a StaticMesh asset path (e.g. "/HelixWeapons/Attachments/Optic/Optic_1/SM_Optic1.SM_Optic1").
-- `transform` (optional) = { loc/rot/scale } relative offset.
-- ⚠ DOES NOT RENDER on the current build (verified 2026-07-12): NewObject + mesh-load + K2_AttachToComponent all succeed
--    and the component IS parented at the socket, but `RegisterComponent`/`IsRegistered` are NOT Lua-exposed, so the
--    runtime-created component stays INVISIBLE (Matt confirmed: no mesh shown). ⇒ use PRE-PLACED attachments in the weapon
--    BP + `setActiveAttachment` (the reliable path). If a truly-runtime add is ever needed, spawn a StaticMeshActor and
--    attach the ACTOR (spawned actors auto-register/render) — heavier, not implemented here. Kept for future builds/reference.
function lib.addWeaponAttachment(actor, meshPath, socket, transform)
    if not actor or type(meshPath) ~= "string" then return { ok = false, error = "actor + meshPath required" } end
    local skm = skeletalMesh(actor)
    if not skm then return { ok = false, error = "no weapon skeletal mesh" } end
    local mesh; pcall(function() mesh = UE.UStaticMesh.Load(meshPath) end)
    if not mesh then return { ok = false, error = "mesh not found: " .. meshPath } end
    local c = NewObject(UE.UStaticMeshComponent, actor)
    if not c then return { ok = false, error = "NewObject failed" } end
    pcall(function() c:SetStaticMesh(mesh) end)
    local rule = UE.EAttachmentRule.SnapToTarget
    pcall(function() c:K2_AttachToComponent(skm, socket or "None", rule, rule, rule, false) end)
    if transform then lib.setAttachmentTransform(actor, c, transform) end
    return { ok = true, component = c, name = tostring(c:GetName()) }
end

-- ── DEV / EXPORT ─────────────────────────────────────────────────────────────────────────────────────────────────
-- Export a weapon's full attachment tree grouped by socket. Returns a JSON STRING if a JSON encoder is present, else a table.
-- Devs turn this into a `.lua` config: which weapons/sockets/attachments exist + which is active. (Nobody knows the catalog
-- without digging — this dumps it.)
function lib.exportWeaponAttachments(actor)
    if not actor then return nil end
    local tree = { weapon = tostring(actor:GetClass():GetName()), sockets = {} }
    eachAttachment(actor, function(c)
        local i = attachInfo(c)
        tree.sockets[i.socket] = tree.sockets[i.socket] or {}
        table.insert(tree.sockets[i.socket], { name = i.name, mesh = i.mesh, active = i.visible })
    end)
    -- prefer HELIX-native JSON, then any lib.json, else return the raw table for the caller to encode.
    if type(JSON) == "table" and type(JSON.stringify) == "function" then local ok, s = pcall(function() return JSON.stringify(tree) end); if ok then return s end end
    if lib.json and lib.json.encode then local ok, s = pcall(function() return lib.json.encode(tree) end); if ok then return s end end
    return tree
end

-- Open a navigable DEV menu to browse + swap a weapon's attachments (socket -> attachments -> equip). For TESTING:
-- nobody knows the attachment catalog without digging, so this surfaces it live. Requires the context module.
-- `actor` = a weapon actor (default: the local player's equipped weapon). Selecting an attachment equips it (setActiveAttachment)
-- and the menu re-opens on the same socket page (via a 1ms Timer, since a leaf-select closes the context menu by contract).
local ATTACH_MENU_ROOT = "vox_weapon_attachments"
local function socketMenuId(socket) return "vox_weap_sock_" .. tostring(socket) end
function lib.openAttachmentMenu(actor)
    actor = actor or lib.getEquippedWeapon()
    if not actor then return { ok = false, error = "no weapon actor / equipped weapon" } end
    if type(lib.registerContext) ~= "function" or type(lib.showContext) ~= "function" then
        return { ok = false, error = "context menu module not loaded" }
    end

    -- group attachments by socket
    local bySocket = {}
    for _, at in ipairs(lib.getWeaponAttachments(actor)) do
        if at.socket and at.socket ~= "None" then
            bySocket[at.socket] = bySocket[at.socket] or {}
            table.insert(bySocket[at.socket], at)
        end
    end

    local weaponName = tostring(actor:GetClass():GetName())
    local menus = {}

    -- ROOT: one entry per socket (→ its submenu)
    local rootOptions = {}
    for socket, list in pairs(bySocket) do
        local active = lib.getActiveAttachment(actor, socket)
        rootOptions[#rootOptions + 1] = {
            title = socket, arrow = true, menu = socketMenuId(socket),
            description = (active and ("active: " .. active) or "empty") .. "  (" .. #list .. " option" .. (#list == 1 and "" or "s") .. ")",
        }
    end
    menus[#menus + 1] = { id = ATTACH_MENU_ROOT, title = weaponName .. " — attachments", options = rootOptions }

    -- SUBMENU per socket: one entry per attachment (onSelect equips it)
    for socket, list in pairs(bySocket) do
        local subOptions = {}
        for _, at in ipairs(list) do
            local name = at.name
            subOptions[#subOptions + 1] = {
                title = name,
                description = at.mesh and ("mesh: " .. at.mesh) or nil,
                icon = at.visible and "check" or nil,
                onSelect = function()
                    lib.setActiveAttachment(actor, socket, name)
                    if type(Timer) == "table" and type(Timer.SetTimeout) == "function" then
                        Timer.SetTimeout(function()
                            lib.openAttachmentMenu(actor)             -- rebuild (refresh active markers)
                            pcall(function() lib.showContext(socketMenuId(socket)) end)   -- stay on this socket
                        end, 1)
                    end
                end,
            }
        end
        menus[#menus + 1] = { id = socketMenuId(socket), title = tostring(socket), menu = ATTACH_MENU_ROOT, options = subOptions }
    end

    lib.registerContext(menus)
    lib.showContext(ATTACH_MENU_ROOT)
    return { ok = true }
end
