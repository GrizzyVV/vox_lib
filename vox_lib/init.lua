--[[ vox_lib — clean-room HELIX-native equivalent of ox_lib's lib.* contract.
     PROVISIONAL NAME (vox_lib) — provisional. Clean-room from the ox_lib API docs ONLY; no ox source was read.
     LOAD MODEL: source-bundled into a consumer's HELIX package (functions don't cross the package boundary, so this is NOT
     an exports resource). Load order matters: this file first (creates `lib`), then class, then the rest (array needs class).
     Standard Lua 5.4 (probe-verified HELIX runtime). ]]

lib = lib or {}
lib._VERSION = "vox_lib 1.6.5"   -- foundation (class/table/array/string/math/cache/print/locale/waitFor/timer/callback/hook)
                                 -- + UI tier (notify/textUI/alert/progress/input/context/menu/skillCheck/radial)
                                 -- + cinematic (weather/freecam/camera) + character creator (appearance + per-slot tint)
                                 -- + entities (spawn/delete + freeze/collision/visible/model/health + bone idx/coords + AI goto
                                 --   + offset/actors-of-class/closest + speed/forward + ped motion-state + repair + place-on-ground
                                 --   + world->screen) + anim (play/stop/isPlaying)
                                 -- + vehicle paint (per-instance colour: component/body/fleet/individual + interp + party)

-- Modules attach themselves to the global `lib` table when their file is loaded after this one.
-- (A standalone deployable build can drive load order via package.json; a host/consumer build bundles in dependency order.)
return lib
