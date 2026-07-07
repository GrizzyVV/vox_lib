--[[ vox_lib export decomposition — register every lib.* function as an INDIVIDUAL export (dotted keys for nested tables),
     so a converted resource calls `exports.vox_lib:notify(...)` / `exports.vox_lib:spawnVehicle(...)` etc. This is the
     HELIX-preferred cross-package model (Matt): a table-held function does NOT marshal across the package boundary, but an
     export does. Same pattern es_extended uses (_exportAll). Loads LAST so every module has attached to `lib` first.

     ADDITIVE — does not disturb the source-bundled path. THREE facts, all now settled:
       • CALLBACKS don't cross: a function passed INTO an export arrives nil in vox_lib. Consumers keep the callback in their
         own state — sync fns return their value (data crosses); register-and-trigger fns (lib.callback) ride the net-event
         transport (handler stays local, trigger+result cross as data). The converter decomposes lib.callback locally.
       • YIELD across an export SURVIVES (probe-verified 2026-07-01, r=42): a yielding fn called via an export blocks the
         caller and returns its value. So the yielding UI fns (progress/input/menu/alert/…) export cleanly — no round-trip.
       • OOP was HISTORICALLY excluded: a returned method-bearing object (lib.class/array) used to lose its methods crossing
         the boundary, so those stayed SOURCE-BUNDLED (used inline to build objects in the consumer's state). ⭐ UPDATED
         2026-07-07 (in-engine, UE 5.7.4 CL 47537391): the export boundary now PROXIES metatable objects — a returned table
         with a metatable crosses with data fields copied and methods callable as synchronous remote-dispatch stubs (stateful;
         yielding methods survive). So returning lib.class/array instances across the boundary is now VIABLE. Code behavior is
         UNCHANGED here (this helper still exports functions only, not instances) — documented as now-possible; each proxied
         method is one RPC hop, so hot per-frame paths still prefer source-bundled instances. Everything else exports. ]]

local function _exportAll(tbl, prefix, seen)
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if type(k) == "string" then
            local path = (prefix ~= "") and (prefix .. "." .. k) or k
            if type(v) == "function" then
                pcall(exports, "vox_lib", path, v)
            elseif type(v) == "table" and v ~= tbl then
                _exportAll(v, path, seen)
            end
        end
    end
end

if lib and exports then
    _exportAll(lib, "", {})
    pcall(print, "[vox_lib] exports registered (lib.* -> exports.vox_lib:*)")
end
