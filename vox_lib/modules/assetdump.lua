--[[ vox_lib asset-dump COMMAND — the dev-facing trigger for "drop the converted resource in, run one command, the asset
     tables materialise" (Matt's install flow). Wraps modules/assets.lua (lib.enumerateAssets / lib.writeAssetTable) as a
     server command. SERVER-ONLY (registered from package.json's server list only) — it writes a `.lua` file to disk.

     DIRECTIONALITY (the governing frame — see DOCTRINE.md): HELIX is the immutable platform; the converted resource consumes
     the world's REAL HELIX asset pool (native weapon/item/vehicle defs + whatever Vault packages the world has installed) —
     enumerated LIVE, never a translated FiveM hash table (the hash table IS the FiveMism). This command dumps that live pool
     to a curatable `.lua` so the server owner can attach economy metadata (weight/price/label) to the HELIX assets that
     actually exist in THEIR world. Runtime give/remove already resolve ids live via lib.enumerateAssets, so this dump is a
     CURATION convenience, not a runtime dependency. ⚠ a file write takes effect on the NEXT world load (the in-memory cache
     is the primary, no-restart path).

     HELIX RegisterCommand (atlas 02 §G, source-read Commands.lua:1-34): `RegisterCommand(name, help, fn)`; the handler is
     `fn(args, cmd)` with `args` a 1-indexed token table — NO source arg like FiveM. ⚠ Because no source is passed,
     in-handler player-permission gating isn't available on this signature → treat this as a SERVER-OWNER / console setup
     command. The exact signature + whether any source is reachable for gating are a BOOT-VALIDATION checkpoint — confirm live
     before relying on it; if source becomes reachable, wrap the body in `lib.hasPermission(src, 'admin')`.

     USAGE (server console / admin):  vox_dumpassets <weapon|item|vehicle|vehicledef|ped|cosmetics|all> [filepath] ]]

if type(RegisterCommand) ~= "function" then return end

local DUMP_FAMILIES = { "weapon", "item", "vehicle", "vehicledef", "ped", "cosmetics" }   -- 'all' dumps each of these

local function _dump(family, filepath)
    -- cosmetics is a slot-catalog reader (not AssetRegistry path+prefix) → its own serialize/write path.
    if family == "cosmetics" then
        filepath = filepath or "vox_cosmetics.lua"
        local ok, err = lib.writeCosmeticTable(filepath)
        if not ok then return ("[vox_lib] vox_dumpassets cosmetics: FAILED — %s"):format(tostring(err)) end
        local list = lib.enumerateCosmetics()
        return ("[vox_lib] vox_dumpassets cosmetics: wrote %d entries -> %s"):format(list and #list or 0, filepath)
    end
    if family == "vehicledef" then
        filepath = filepath or "vox_vehicledefs.lua"
        local ok, err = lib.writeVehicleDefTable(filepath)
        if not ok then return ("[vox_lib] vox_dumpassets vehicledef: FAILED — %s"):format(tostring(err)) end
        local list = lib.enumerateVehicleDefinitions()
        return ("[vox_lib] vox_dumpassets vehicledef: wrote %d entries -> %s"):format(list and #list or 0, filepath)
    end
    filepath = filepath or ("vox_assets_" .. family .. ".lua")
    local ok, err = lib.writeAssetTable(family, filepath)
    if not ok then return ("[vox_lib] vox_dumpassets %s: FAILED — %s"):format(family, tostring(err)) end
    local list = lib.enumerateAssets(family)
    return ("[vox_lib] vox_dumpassets %s: wrote %d entries -> %s"):format(family, list and #list or 0, filepath)
end

RegisterCommand("vox_dumpassets",
    "Dump the live HELIX asset pool (weapon|item|vehicle|vehicledef|ped|cosmetics|all) to a curatable .lua  [server/admin]",
    function(a, b)
        -- HELIX passes fn(argsTable, consoleCmdObject). ⚠ the token table is OFFSET on this build — user args start at
        -- index [2] ([1] is nil); validated live 2026-07-15 via an arg-capture probe (NOT [1] as one would assume).
        -- Collect the non-nil string tokens positionally — robust to the offset AND to the command name landing at [1]
        -- in a console-typed invocation.
        local at = (type(a) == "table" and a) or (type(b) == "table" and b) or {}
        local toks = {}
        for i = 1, 8 do local v = at[i]; if type(v) == "string" and v ~= "" then toks[#toks + 1] = v end end
        if toks[1] == "vox_dumpassets" then table.remove(toks, 1) end
        local family, filepath = toks[1], toks[2]
        -- ⚠ a filesystem PATH typed through the HELIX console gets MANGLED (the tokenizer drops `:`/`/` segments →
        -- validated 2026-07-15), so the optional [filepath] is unreliable from console. Prefer `vox_dumpassets <family>`
        -- and let it write the default relative filename (lands in the server process cwd). A computed sensible output
        -- dir (resource dir / a known exports folder) is a follow-up refinement.
        if not family then
            pcall(print, "[vox_lib] usage: vox_dumpassets <weapon|item|vehicle|vehicledef|ped|cosmetics|all>   (writes vox_assets_<family>.lua)")
            return
        end
        local fams = (family == "all") and DUMP_FAMILIES or { family }
        for _, fam in ipairs(fams) do
            pcall(print, _dump(fam, (#fams == 1) and filepath or nil))
        end
    end)
