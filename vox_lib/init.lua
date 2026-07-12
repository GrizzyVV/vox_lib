--[[ vox_lib — clean-room HELIX-native equivalent of ox_lib's lib.* contract.
     PROVISIONAL NAME (vox_lib) — provisional. Clean-room from the ox_lib API docs ONLY; no ox source was read.
     LOAD MODEL: source-bundled into a consumer's HELIX package OR used as an exports resource (`modules/zexports.lua` registers
     every `lib.*` as `exports.vox_lib:*`; yield survives the boundary, and per the 2026-07-07 object-RPC finding even metatable
     objects proxy across it — each proxied method is one RPC hop, so hot paths still prefer source-bundling). Load order
     matters: this file first (creates `lib`), then class, then the rest (array needs class).
     Standard Lua 5.4 (probe-verified HELIX runtime). ]]

lib = lib or {}
lib._VERSION = "vox_lib 1.6.7"   -- foundation (class/table/array/string/math/cache/print/locale/waitFor/timer/callback/hook)
                                 -- + UI tier (notify/textUI/alert/progress/input/context/menu/skillCheck/radial)
                                 -- + cinematic (weather/freecam/camera) + character creator (appearance + per-slot tint)
                                 -- + entities (spawn/delete + freeze/collision/visible/model/health + bone idx/coords + AI goto
                                 --   + offset/actors-of-class/closest + speed/forward + ped motion-state + repair + place-on-ground
                                 --   + world->screen) + anim (play/stop/isPlaying)
                                 -- + vehicle paint (per-instance colour: component/body/fleet/individual + interp + party)
                                 -- 1.6.7: + vehicle PERFORMANCE tuning (per-instance Chaos movement comp: engine/drive/brake
                                 --   torque + drag/downforce/differential; PIE per-instance-verified; ⚠ replication untested in
                                 --   live MP — see README; persistence = caller-owned, DB-keyed by plate/VIN)
                                 --   + WEAPON attachments (getWeaponAttachments/Sockets/State + toggle/setActiveAttachment
                                 --   [one-active-per-socket] + exportWeaponAttachments JSON + openAttachmentMenu dev swap-menu;
                                 --   runtime addWeaponAttachment ⚠ non-rendering on this build — pre-place in BP instead)

-- Modules attach themselves to the global `lib` table when their file is loaded after this one.
-- (A standalone deployable build can drive load order via package.json; a host/consumer build bundles in dependency order.)
return lib
