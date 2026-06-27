--[[ lib.addRadialItem / registerRadial / removeRadialItem / showRadial / hideRadial / disableRadial / getCurrentRadialId —
     circular radial menu (clean-room from the ox_lib radial contract). Global items (addRadialItem) populate the main ring;
     registerRadial defines submenu rings (an item with `menu=<id>` opens that submenu). Items report the picked INDEX via
     the hEvent reverse channel; Lua dispatches to the kept `onSelect` callbacks.
       addRadialItem({ id, label, icon, onSelect?(fn), menu?(submenu id) })  (or an array)
       registerRadial({ id, items = { {label, icon, onSelect?, menu?}, ... } })
       showRadial(id?) · hideRadial() · removeRadialItem(id) · disableRadial(bool) · getCurrentRadialId() -> id|nil ]]

local PAGE = "vox_lib/web/radial/index.html"
local _ui, _global, _radials, _open, _disabled = nil, {}, {}, nil, false

local function itemsFor(id)
    if id and _radials[id] then return _radials[id].items end
    return _global
end

local function toDisplay(items, isSub)
    local out = {}
    for i, it in ipairs(items or {}) do out[i] = { index = i, label = it.label, icon = it.icon, sub = (it.menu ~= nil) } end
    return { items = out, isSub = isSub and true or false }
end

local function ensureUI()
    if _ui or not WebUI then return _ui end
    _ui = WebUI("vox_lib_radial", PAGE, 0)
    pcall(function() _ui:RegisterEventHandler("radial:select", function(d)
        local it = itemsFor(_open)[tonumber(d and d.index) or -1]
        if not it then return end
        if it.menu then lib.showRadial(it.menu)
        else if type(it.onSelect) == "function" then pcall(it.onSelect) end; lib.hideRadial() end
    end) end)
    pcall(function() _ui:RegisterEventHandler("radial:back", function() if _open then lib.showRadial() else lib.hideRadial() end end) end)
    pcall(function() _ui:RegisterEventHandler("radial:close", function() lib.hideRadial() end) end)
    return _ui
end

function lib.addRadialItem(items)
    if type(items) ~= "table" then return end
    if items.id or items.label or items.icon then _global[#_global + 1] = items       -- single item
    else for _, it in ipairs(items) do _global[#_global + 1] = it end end             -- array
end

function lib.registerRadial(data) if type(data) == "table" and data.id then _radials[data.id] = data end end

function lib.removeRadialItem(id)
    for i, it in ipairs(_global) do if it.id == id then table.remove(_global, i); break end end
end

function lib.showRadial(id)
    if _disabled then return end
    local ui = ensureUI(); if not ui then return end
    _open = id
    pcall(function() ui:SetInputMode(1) end)
    ui:SendEvent("radial:show", toDisplay(itemsFor(id), id ~= nil))
end

function lib.hideRadial()
    _open = nil
    if _ui then pcall(function() _ui:SetInputMode(0) end); pcall(function() _ui:SendEvent("radial:hide", {}) end) end
end

function lib.disableRadial(state) _disabled = state and true or false end
function lib.getCurrentRadialId() return _open end

return lib.addRadialItem
