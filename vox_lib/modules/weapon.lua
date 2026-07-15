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

-- ── WEAPON AMMO (item-instance stat-tags) ────────────────────────────────────────────────────────────────────────────
-- PIE-validated 2026-07-13 + re-validated 2026-07-14 (Patriot: clip 14/30, spare 690 — read IDENTICALLY client & server).
-- HELIX weapon ammo is INTEGER stat-tag STACKS on the weapon's OWNING ITEM INSTANCE (Lyra pattern) — plain COUNTS, NOT
-- GTA's enumerated ammo types. Reached via the player's ACTIVE quickbar slot item (the equipment component is on the pawn;
-- `GetEquippedItems(controller)` returns 0). Ammo READS work either side (replicated); WRITES are server-authoritative
-- (they mutate the saved inventory) — call the setters SERVER-side. Tag reads MUST use `RequestGameplayTag` (never build a
-- GameplayTag via MUSE Python — that crashes the editor). Write mechanism (Add/RemoveStatTagStack) = PROBE #1 validated.

local AMMO_CLIP  = "Inventory.Stat.Weapon.Ammo.ClipCurrent"   -- rounds in the magazine
local AMMO_CAP   = "Inventory.Stat.Weapon.Ammo.ClipCapacity"  -- magazine size
local AMMO_SPARE = "Inventory.Stat.Weapon.Ammo.Spare"         -- reserve ammo

local function _ammoTag(name) local t; pcall(function() t = UE.UHelixResourceUtility.RequestGameplayTag(name) end); return t end

-- Resolve a quickbar component from a caller-supplied handle. Accepts a controller (quickbar owner), a pawn (→ its
-- controller), or nil (→ the local player). The FiveM ped/player handle a converted resource passes (PlayerPedId()/
-- GetPlayerPed()) can be a pawn — normalise it. Returns the quickbar or nil.
local function _resolveQuickbar(entity)
    local function qbOf(e) local qb; pcall(function() qb = e and HInventory.GetQuickbar(e) end); return qb end
    if type(HInventory) ~= "table" then return nil end
    local qb = qbOf(entity)
    if qb then return qb end
    if entity then                                              -- given a pawn? try its controller
        local ctrl; pcall(function() ctrl = entity.GetController and entity:GetController() end)
        qb = qbOf(ctrl); if qb then return qb end
    end
    return qbOf(GetLocalPlayer and GetLocalPlayer())            -- fall back to the local player
end

-- The player's ACTIVE weapon item instance (carries the ammo stat-tags), or nil if unarmed/holstered.
function lib.getActiveWeaponItem(entity)
    local qb = _resolveQuickbar(entity)
    local it; if qb then pcall(function() it = qb:GetActiveSlotItem() end) end
    return it
end

local function _statGet(it, tagName)
    if not it then return nil end
    local tag = _ammoTag(tagName); if not tag then return nil end
    local v; pcall(function() v = it:GetStatTagStackCount(tag) end); return v
end

-- Set a stat-tag on an item instance to an ABSOLUTE value by adding/removing the delta. Server-authoritative.
local function _statSet(it, tagName, value)
    if not it or type(value) ~= "number" then return false end
    local tag = _ammoTag(tagName); if not tag then return false end
    local cur = 0; pcall(function() cur = it:GetStatTagStackCount(tag) or 0 end)
    local delta = math.floor(value + 0.5) - cur
    if delta > 0 then pcall(function() it:AddStatTagStack(tag, delta) end)
    elseif delta < 0 then pcall(function() it:RemoveStatTagStack(tag, -delta) end) end
    return true
end

-- Read the active weapon's ammo → { clip, capacity, spare } (nil if unarmed). Works client OR server.
function lib.getWeaponAmmo(entity)
    local it = lib.getActiveWeaponItem(entity)
    if not it then return nil end
    return { clip = _statGet(it, AMMO_CLIP), capacity = _statGet(it, AMMO_CAP), spare = _statGet(it, AMMO_SPARE) }
end

-- Total ammo (clip + spare) — the GTA `GetAmmoInPedWeapon` analogue (GTA counts total rounds, not clip/reserve split). 0 if unarmed.
function lib.getWeaponAmmoTotal(entity)
    local a = lib.getWeaponAmmo(entity)
    return a and ((a.clip or 0) + (a.spare or 0)) or 0
end

-- Set the active weapon's clip and/or spare to ABSOLUTE counts (nil = leave unchanged). Server-side (persists).
function lib.setWeaponAmmo(entity, clip, spare)
    local it = lib.getActiveWeaponItem(entity)
    if not it then return { ok = false, error = "no active weapon" } end
    if clip  ~= nil then _statSet(it, AMMO_CLIP, clip) end
    if spare ~= nil then _statSet(it, AMMO_SPARE, spare) end
    return { ok = true }
end

-- Set just the reserve — the GTA `SetPedAmmo(ped, weapon, n)` analogue (GTA's SetPedAmmo sets total-carried; we map it to
-- the RESERVE, the closest single-count meaning — the clip is refilled by the reload path). Server-side.
function lib.setWeaponSpare(entity, n) return lib.setWeaponAmmo(entity, nil, n) end

-- Add to the reserve — the GTA `AddAmmoToPed(ped, weapon, n)` analogue. Server-side.
function lib.addWeaponSpare(entity, n)
    local it = lib.getActiveWeaponItem(entity)
    if not it then return { ok = false, error = "no active weapon" } end
    local cur = _statGet(it, AMMO_SPARE) or 0
    _statSet(it, AMMO_SPARE, cur + (tonumber(n) or 0))
    return { ok = true }
end

-- ── WEAPON GIVE / REMOVE (server-authoritative inventory mutation) ────────────────────────────────────────────────────
-- Codifies the give/remove recipe LIVE-VALIDATED 2026-07-13 (gave + removed a weapon net-zero; the surgical by-name remove
-- left the player's OTHER weapons untouched — Matt's eyes). This previously lived ONLY as prose in the converter's
-- feature-ledger and got re-derived every session; this is its durable, callable home.
--
-- MODEL: a HELIX weapon is an `HInventoryItemDefinition` DATA ASSET (`ID_Weapon_*` under /HelixWeapons/Weapons). You GIVE
-- one by loading its def, adding it to the player's inventory manager, then to the quickbar (so it's drawable). This is the
-- HELIX-NATIVE replacement for GTA `GiveWeaponToPed(ped, hash, …)` — you pass a HELIX weapon id resolved from the live pool
-- (`lib.enumerateAssets('weapon')`), NEVER a GTA hash (the hash table IS the FiveMism). Server-authoritative + PERSISTS to
-- the character save → CALL SERVER-SIDE (a client-side call cannot mutate the saved inventory).
--   • defs are DATA ASSETS → `UE.UObject.Load(path)` — NOT `UClass.Load` (returns nil; that's the blessed GiveItemByKey trap).
--   • inventory-manager access is via the pawn's COMPONENT (the `HInventory`/`UHInventorySystemGlobals` globals are
--     half-wired on this build) → resolve with `GetComponentByClass`, fall back to the globals path.

-- Resolve a weapon reference to a loadable def PATH. Accepts a full def path (contains '/'), or a HELIX weapon id
-- ("ID_Weapon_Rifle_Patriot") resolved against the live enumerated pool. Returns path or nil.
local function _weaponDefPath(weapon)
    if type(weapon) ~= "string" then return nil end
    if weapon:find("/", 1, true) then return weapon end             -- already a def path
    if lib.enumerateAssets then
        local pool = lib.enumerateAssets("weapon")
        if pool then for _, a in ipairs(pool) do if a.id == weapon then return a.path end end end
    end
    return nil
end

-- Resolve the SERVER-side inventory manager component for an entity (pawn or controller; default local player).
local function _resolveInventory(entity)
    local pawn, ctrl
    if entity then
        pcall(function() if entity.GetController then ctrl = entity:GetController() end end)
        if ctrl then pawn = entity else ctrl = entity end           -- had a controller → entity was the pawn
    end
    ctrl = ctrl or (GetLocalPlayer and GetLocalPlayer())
    if not pawn then pcall(function() pawn = ctrl and ctrl.K2_GetPawn and ctrl:K2_GetPawn() end) end
    local im
    if pawn then pcall(function() im = pawn:GetComponentByClass(UE.UHInventoryManagerComponent) end) end
    if not im then pcall(function() im = UE.UHInventorySystemGlobals.GetInventory(ctrl) end) end   -- fallback
    local qb
    if type(HInventory) == "table" then pcall(function() qb = HInventory.GetQuickbar(ctrl) end) end
    return im, qb
end

-- Collect-then-remove weapon instances (mutating the live TArray while iterating is unsafe). `matchId` nil = ALL weapons.
-- `max` nil = no cap. Returns the count removed.
local function _removeWeapons(im, matchId, max)
    local removed = 0
    pcall(function()
        local items = im:GetAllItems()
        local hits = {}
        for i = 1, items:Length() do
            local it = items:Get(i)
            local nm; pcall(function() nm = tostring(it:GetItemDef():GetName()) end)
            if nm and (matchId and nm == matchId or (not matchId and nm:sub(1, 10) == "ID_Weapon_")) then
                hits[#hits + 1] = it
            end
        end
        for _, it in ipairs(hits) do
            if max and removed >= max then break end
            pcall(function() im:RemoveItemInstance(it, 1) end)
            removed = removed + 1
        end
    end)
    return removed
end

-- GIVE a weapon (by HELIX id or def path) to a player. `count` defaults 1. `opts.quickbar ~= false` adds it to the quickbar
-- (drawable). SERVER-side + persists. Returns { ok = true, instance } or { ok = false, error }.
function lib.giveWeapon(entity, weapon, count, opts)
    opts = opts or {}
    local path = _weaponDefPath(weapon)
    if not path then return { ok = false, error = "unknown weapon (not in pool / not a def path): " .. tostring(weapon) } end
    local im, qb = _resolveInventory(entity)
    if not im then return { ok = false, error = "no inventory manager (call server-side)" } end
    local def; pcall(function() def = UE.UObject.Load(path) end)     -- DATA ASSET → UObject.Load, not UClass.Load
    if not def then return { ok = false, error = "weapon def failed to load: " .. path } end
    local inst; pcall(function() inst = im:AddItemDefinition(def, count or 1) end)
    if not inst then return { ok = false, error = "AddItemDefinition returned nil" } end
    local quickbarred = false
    if opts.quickbar ~= false and qb then pcall(function() qb:AddItemToFirstEmptySlot(inst); quickbarred = true end) end
    -- ⚠ RETURN PLAIN DATA ONLY — NEVER a live UObject across the export boundary. Returning the item `instance`
    -- (a UHInventoryItemInstance) HARD-CRASHED the editor (EXCEPTION_ACCESS_VIOLATION in recursive UnLua marshalling,
    -- 2026-07-15, confirmed via crash log): the object-RPC layer walks the UObject reference graph and derefs bad memory.
    -- The 2026-07-07 object-RPC proxying is for LUA metatable objects, NOT raw UE UObjects. A caller that needs the live
    -- instance must call giveWeapon SOURCE-BUNDLED (same Lua state), never via exports.vox_lib.
    return { ok = true, id = tostring(weapon), quickbar = quickbarred }
end

-- REMOVE weapon(s) by HELIX id from a player — surgical, matches ONLY the named weapon (other items untouched). `count`
-- nil = remove ALL instances of that weapon. SERVER-side + persists. Returns { ok = true, removed = n }.
function lib.removeWeapon(entity, weapon, count)
    -- Accept a bare id ("ID_Weapon_Sniper_Ronin-777") or a full def path (".../ID_Weapon_….ID_Weapon_…") → take the trailing
    -- name segment. ⚠ do NOT use `%w+` — HELIX weapon ids contain HYPHENS (Ronin-777, CS-446, LWS-32, DMC-68…) which `%w`
    -- drops, truncating the id so the exact-name match silently fails. Validation caught this 2026-07-15 (remove reported
    -- ok but removed 0). `[^%./]+$` keeps hyphens/digits and strips any path/package prefix.
    local wantId
    if type(weapon) == "string" then
        local base = weapon:match("([^%./]+)$") or weapon
        if base:sub(1, 10) == "ID_Weapon_" then wantId = base end
    end
    if not wantId then return { ok = false, error = "expected a HELIX weapon id: " .. tostring(weapon) } end
    local im = _resolveInventory(entity)
    if not im then return { ok = false, error = "no inventory manager (call server-side)" } end
    return { ok = true, removed = _removeWeapons(im, wantId, count) }
end

-- REMOVE ALL weapons from a player — the GTA `RemoveAllPedWeapons` analogue. Strips every `ID_Weapon_*` instance (their
-- quickbar slots auto-clear → the player can't re-draw). Non-weapon items untouched. SERVER-side + persists.
function lib.removeAllWeapons(entity)
    local im = _resolveInventory(entity)
    if not im then return { ok = false, error = "no inventory manager (call server-side)" } end
    return { ok = true, removed = _removeWeapons(im, nil, nil) }
end
