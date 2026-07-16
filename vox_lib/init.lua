--[[ vox_lib — clean-room HELIX-native equivalent of ox_lib's lib.* contract.
     PROVISIONAL NAME (vox_lib) — provisional. Clean-room from the ox_lib API docs ONLY; no ox source was read.
     LOAD MODEL: source-bundled into a consumer's HELIX package OR used as an exports resource (`modules/zexports.lua` registers
     every `lib.*` as `exports.vox_lib:*`; yield survives the boundary, and per the 2026-07-07 object-RPC finding even metatable
     objects proxy across it — each proxied method is one RPC hop, so hot paths still prefer source-bundling). Load order
     matters: this file first (creates `lib`), then class, then the rest (array needs class).
     Standard Lua 5.4 (probe-verified HELIX runtime). ]]

lib = lib or {}
lib._VERSION = "vox_lib 1.7.3"   -- 1.7.3: + VEHICLE-DEFINITION catalog (modules/assets.lua: enumerateVehicleDefinitions/
                                 --   writeVehicleDefTable — the DA_* HVehicleDefinition layer: 8 defs {id,name,vehicleType,path},
                                 --   live-validated via exports; proves the "DA_* native-definition layer" reader generalizes
                                 --   past cosmetics — enumerate a DataAsset CLASS + read its config fields. `vox_dumpassets
                                 --   vehicledef`. ⚠ def catalog (8) ≠ spawn-BP pool (3, the `vehicle` family) — reconcile per vehicle.
                                 -- 1.7.2: + COSMETICS/CLOTHING enumeration (modules/assets.lua: enumerateCosmetics/
                                 --   serializeCosmeticTable/writeCosmeticTable — the Mutable cosmetic catalog
                                 --   DA_CharacterCustomizationData.SlotMap → 30 slots / 433 items {id,slot,name,gender};
                                 --   live-validated via exports 2026-07-15) + PED asset family (DA_PawnData_*_NPC_*) +
                                 --   vox_dumpassets now covers ped|cosmetics. (Objects/props = no native pool → Vault-driven.)
                                 -- 1.7.1: + WEAPON give/remove (modules/weapon.lua: giveWeapon/removeWeapon/removeAllWeapons
                                 --   — HELIX-id inventory mutation, server-authoritative; live-validated 2026-07-15 net-zero
                                 --   give+remove via exports) + vox_dumpassets command (modules/assetdump.lua, server-only:
                                 --   dumps the live pool to a curatable .lua) + FIX: weapon.lua now loads SERVER-side
                                 --   (package.json) — was client-only, so server give/remove/ammo exports didn't exist.
                                 --   ⚠ HELIXisms found+fixed live: (a) exports MUST return plain data — returning a UObject
                                 --   crashes the editor (giveWeapon returns {ok,id,quickbar}); (b) weapon-id match must keep
                                 --   HYPHENS (Ronin-777/CS-446 — %w drops them).
                                 -- 1.7.0: + asset enumeration (modules/assets.lua: enumerateAssets/serializeAssetTable/
                                 --   writeAssetTable/registerAssetFamily — runtime UE AssetRegistry pool → the "run a command,
                                 --   asset tables ready" engine; weapon/item/vehicle) + weapon AMMO (modules/weapon.lua:
                                 --   getWeaponAmmo/getWeaponAmmoTotal/setWeaponAmmo/setWeaponSpare/addWeaponSpare — item-instance
                                 --   ammo stat-tags, live-validated) + progressActive/getLocales (ox_lib-parity getters)
                                 -- 1.6.9: + resource-state (getResourceState/hasResource/getResources via _G.__PackageLoader:
                                 --   HasPackage/GetPackageMap — HELIX package-loaded query; FiveM GetResourceState equivalent)
                                 -- 1.6.8: + convar store (getConvar/getConvarInt/getConvarBool/setConvar — FiveM server-config
                                 --   equivalent, seeded from a VoxConvars table or setConvar; converter maps GetConvar* onto it)
                                 -- foundation (class/table/array/string/math/cache/print/locale/waitFor/timer/callback/hook)
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
