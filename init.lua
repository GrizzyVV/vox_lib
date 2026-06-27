--[[ vox_lib — clean-room HELIX-native equivalent of ox_lib's lib.* contract.
     PROVISIONAL NAME (vox_lib) — provisional. Clean-room from the ox_lib API docs ONLY; no ox source was read.
     LOAD MODEL: source-bundled into a consumer's HELIX package (functions don't cross the package boundary, so this is NOT
     an exports resource). Load order matters: this file first (creates `lib`), then class, then the rest (array needs class).
     Standard Lua 5.4 (probe-verified HELIX runtime). ]]

lib = lib or {}
lib._VERSION = "vox_lib 0.3.0 (s1 class/table/array/string/math; s2 cache/print/locale/waitFor/timer; s3 callback/hook)"

-- Modules attach themselves to the global `lib` table when their file is loaded after this one.
-- (A standalone deployable build can drive load order via package.json; a host/consumer build bundles in dependency order.)
return lib
