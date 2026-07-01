--[[ lib.characterCreator — HELIX-native Character Creator / appearance surface. Wraps the engine cosmetics component
     (`BPC_CharacterCreator_C`, a.k.a. UHCharacterCosmetics) hanging off the LOCAL player pawn. CLIENT-SIDE.

     THE DATA CONTRACT (probe-verified on HELIX): the full appearance is a `BP_JsonObjectWrapper_C` you serialize with
     `:SaveToString()` -> a JSON string (~7KB) shaped:
         { "Gender": "Male", "Slots": { "<slot-guid>": { "MaterialParameters": [ ... ] }, ... } }
     Save that string; reconstruct + reapply it later with the wrapper's `:LoadFromString(json)` +
     `ApplyCharacterCustomizationPreset(wrapper)`. This is the round-trip that lets a created character's look survive a respawn.

     WHY THIS EXISTS: the stock flow captures the preset only to read `.Gender`, then discards it — so face/body customization is
     lost on spawn. These verbs make the appearance first-class: capture -> persist (your DB, keyed by citizenid) -> reapply on
     `HEvent:PlayerPossessed`. See docs/developer.md (Character Creator) for the full persistence pattern. ]]

local _wrapperClass   -- cached BP_JsonObjectWrapper_C UClass

local function getSystem()
    local pawn = GetPlayerPawn and GetPlayerPawn(HPlayer)
    if not pawn or not pawn.GetCosmeticsSystem then return nil end
    return pawn:GetCosmeticsSystem()
end
lib.getCosmeticsSystem = getSystem

-- Open the native character-customization UI. opts.slotFilter (optional): a map of { SlotName = true } to HIDE those slots
-- (e.g. { Hats = true, Masks = true }) — mirrors the engine's BP_HelixFilterDataSource pattern.
function lib.openCharacterCreator(opts)
    local cs = getSystem()
    if not cs then return false end
    opts = opts or {}
    if opts.slotFilter and cs.GetWearablesDataSource and cs.SetWearablesDataSource and NewObject and LoadClass then
        local ok = pcall(function()
            local filter = NewObject(LoadClass("/HelixRemoteResourceModel/Persistence/BP_HelixFilterDataSource.BP_HelixFilterDataSource_C"))
            filter.Source = cs:GetWearablesDataSource()
            filter.OnSubqueryComplete:Add(filter, function(_, query)
                local items = UE.TArray(UE.FJsonObjectWrapper)
                for _, item in pairs(query.Items) do
                    if not opts.slotFilter[UE.UHelixResourceUtility.GetStringField(item, "Slot")] then items:Add(item) end
                end
                query.Items = items
            end)
            cs:SetWearablesDataSource(filter)
        end)
        if not ok then return false end
    end
    return pcall(function() cs:ShowCharacterCustomizationUI() end)
end

-- Capture the current appearance as a JSON string (persist this). Returns string | nil.
function lib.getAppearance()
    local cs = getSystem()
    if not cs then return nil end
    local preset = cs:RetainCharacterCustomizationPreset()
    if not preset then return nil end
    if not _wrapperClass and preset.GetClass then _wrapperClass = preset:GetClass() end
    local ok, json = pcall(function() return preset:SaveToString() end)
    return ok and json or nil
end

-- Reapply a saved appearance JSON string. Returns boolean.
function lib.applyAppearance(json)
    local cs = getSystem()
    if not cs or type(json) ~= "string" or json == "" then return false end
    local cls = _wrapperClass
    if not cls then
        local preset = cs:RetainCharacterCustomizationPreset()
        cls = preset and preset.GetClass and preset:GetClass()
        _wrapperClass = cls
    end
    if not cls or not NewObject then return false end
    return pcall(function()
        local w = NewObject(cls)
        w:LoadFromString(json)
        cs:ApplyCharacterCustomizationPreset(w)
    end)
end

-- Reset cosmetics to engine defaults. gender/bodyType default to the character's current values.
function lib.resetAppearance(gender, bodyType)
    local cs = getSystem()
    if not cs then return false end
    if gender == nil and cs.GetCosmeticGender then gender = cs:GetCosmeticGender() end
    if bodyType == nil and cs.GetCosmeticBodyType then bodyType = cs:GetCosmeticBodyType() end
    return pcall(function() cs:ResetCosmeticsToDefaults(gender, bodyType) end)
end

-- Wearable item verbs (equipmentId strings).
function lib.equipCosmetic(equipmentId)   local cs = getSystem(); if not cs then return false end; return pcall(function() cs:EquipCosmeticItem(equipmentId) end) end
function lib.unequipCosmetic(equipmentId) local cs = getSystem(); if not cs then return false end; return pcall(function() cs:UnequipCosmeticItem(equipmentId) end) end
function lib.equipCosmetics(equipmentIds) local cs = getSystem(); if not cs then return false end; return pcall(function() cs:EquipCosmeticItems(equipmentIds) end) end
function lib.isCosmeticEquipped(equipmentId) local cs = getSystem(); if not cs then return false end; local ok, v = pcall(function() return cs:IsCosmeticItemEquipped(equipmentId) end); return ok and v or false end

-- Slot/gender control. lib.setCosmeticGender — ✅ VERIFIED 2026-06-30 by readback (1 -> 0 -> restore 1).
function lib.setCosmeticGender(gender)   local cs = getSystem(); if not cs then return false end; return pcall(function() cs:SetCosmeticGender(gender) end) end
function lib.clearCosmetics()            local cs = getSystem(); if not cs then return false end; return pcall(function() cs:ClearAllCosmeticSlots() end) end

-- ⛔ lib.setSlotColor / clearSlotColor — DISABLED guarded no-ops (2026-07-01). The string-slot signature is WRONG: the engine
-- method `SetMaterialColorOverrideForSlot` wants params (userdata, string, string, userdata) — param 0 is a cosmetic-SLOT
-- DATA-ASSET HANDLE (userdata), NOT a slot NAME string. Calling it with a string silently ABORTS on UnLua param validation
-- (returns no Lua error, so the old `pcall→true` was a FALSE POSITIVE) AND spams `Invalid parameter` log errors. There is NO
-- HELIX Lua source that calls it (nothing to copy, unlike Trace). Re-enable only once the slot-handle enumeration API is
-- understood (get the slot data-asset from the cosmetics system, then pass it + the param name(s) + the FLinearColor).
function lib.setSlotColor(_slot, _color) return false end
function lib.clearSlotColor(_slot)       return false end

-- Getters.
function lib.getCosmeticGender()   local cs = getSystem(); if not cs then return nil end; local ok, v = pcall(function() return cs:GetCosmeticGender() end); return ok and v or nil end
function lib.getCosmeticBodyType() local cs = getSystem(); if not cs then return nil end; local ok, v = pcall(function() return cs:GetCosmeticBodyType() end); return ok and v or nil end
