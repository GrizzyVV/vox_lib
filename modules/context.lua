--[[ lib.registerContext / showContext / hideContext / getOpenContextMenu — navigable context menu (clean-room from the
     ox_lib context contract). STATEFUL + CALLBACK-based (not a single-await dialog): each option carries an onSelect
     callback and/or a submenu link; the page renders display data and reports the picked INDEX via the hEvent reverse
     channel, and Lua dispatches to the kept callbacks (functions never leave Lua → they survive the WebUI boundary).
       lib.registerContext({ id, title, menu?(=back-target id), options = { {title, description?, icon?, iconColor?,
            disabled?, readOnly?, arrow?, metadata?, menu?(=submenu id), onSelect?(fn), args?}, ... } })
       lib.showContext(id) · lib.hideContext() · lib.getOpenContextMenu() -> id|nil   ·   registerContext also accepts an array of menus. ]]

local PAGE = "vox_lib/web/context/index.html"
local _ui, _menus, _open = nil, {}, nil

local function toDisplay(data)
    local opts = {}
    for i, o in ipairs(data.options or {}) do
        opts[i] = {
            index = i, title = o.title, description = o.description, icon = o.icon, iconColor = o.iconColor,
            disabled = o.disabled and true or false, readOnly = o.readOnly and true or false,
            arrow = (o.menu ~= nil) or (o.arrow and true or false),
            metadata = o.metadata, progress = o.progress, colorScheme = o.colorScheme,
        }
    end
    return { id = data.id, title = data.title, canBack = (data.menu ~= nil), options = opts }
end

local function onSelect(d)
    local data = _menus[_open]; if not data then return end
    local o = data.options and data.options[tonumber(d and d.index) or -1]
    if not o or o.disabled or o.readOnly then return end
    if o.menu then
        lib.showContext(o.menu)                       -- descend into the submenu
    else
        if type(o.onSelect) == "function" then pcall(o.onSelect, o.args) end
        lib.hideContext()                             -- leaf select closes (ox_lib parity)
    end
end

local function onBack()
    local data = _menus[_open]
    if data and data.menu then lib.showContext(data.menu) else lib.hideContext() end
end

local function ensureUI()
    if _ui or not WebUI then return _ui end
    _ui = WebUI("vox_lib_context", PAGE, 0)
    pcall(function() _ui:RegisterEventHandler("context:select", onSelect) end)
    pcall(function() _ui:RegisterEventHandler("context:back", onBack) end)
    pcall(function() _ui:RegisterEventHandler("context:close", function() lib.hideContext() end) end)
    return _ui
end

function lib.registerContext(data)
    if type(data) ~= "table" then return end
    if data.id then _menus[data.id] = data            -- single menu
    else for _, m in ipairs(data) do if type(m) == "table" and m.id then _menus[m.id] = m end end end  -- array of menus
end

function lib.showContext(id)
    local data = _menus[id]; if not data then return end
    local ui = ensureUI(); if not ui then return end
    _open = id
    pcall(function() ui:SetInputMode(1) end)          -- menu captures the cursor
    ui:SendEvent("context:show", toDisplay(data))
end

function lib.hideContext()
    _open = nil
    if _ui then
        pcall(function() _ui:SetInputMode(0) end)
        pcall(function() _ui:SendEvent("context:hide", {}) end)
    end
end

function lib.getOpenContextMenu() return _open end

return lib.registerContext
