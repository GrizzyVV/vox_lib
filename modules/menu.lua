--[[ lib.registerMenu / showMenu / hideMenu / getOpenMenu / setMenuOptions — keyboard-navigable list menu (clean-room from
     the ox_lib registerMenu contract). STATEFUL + CALLBACK-based: ArrowUp/Down navigate, ArrowLeft/Right side-scroll an
     option's `values`, Enter selects, Backspace/Esc closes. The page reports nav/select/scroll/check via the hEvent reverse
     channel; Lua dispatches to the kept callbacks (functions stay Lua-side).
       registerMenu({ id, title, position?='top-left', canClose?=true, options={ {label, icon?, description?, values?(side-
            scroll list), checked?, close?, args?, progress?, colorScheme? }, ... },
            onSelected?(sel,args), onSideScroll?(sel,scrollIndex,args), onCheck?(sel,checked,args), onClose?(keyPressed) }, cb)
       showMenu(id) · hideMenu() · getOpenMenu() -> id|nil · setMenuOptions(id, options, index?) ]]

local PAGE = "vox_lib/web/menu/index.html"
local _ui, _menus, _open = nil, {}, nil

local function toDisplay(data)
    local opts = {}
    for i, o in ipairs(data.options or {}) do
        opts[i] = { index = i, label = o.label, icon = o.icon, description = o.description, values = o.values,
                    checked = o.checked and true or false, isCheck = (o.checked ~= nil),
                    progress = o.progress, colorScheme = o.colorScheme }
    end
    return { id = data.id, title = data.title, position = data.position or "top-left", canClose = data.canClose ~= false, options = opts }
end

local function ensureUI()
    if _ui or not WebUI then return _ui end
    _ui = WebUI("vox_lib_menu", PAGE, 0)
    pcall(function() _ui:RegisterEventHandler("menu:select", function(d)
        local data = _menus[_open]; if not data then return end
        local i = tonumber(d and d.index) or 1
        if type(data.onSelected) == "function" then pcall(data.onSelected, i, data.options[i] and data.options[i].args) end
        if type(data.cb) == "function" then pcall(data.cb, i, tonumber(d and d.scrollIndex)) end
        if not (data.options[i] and data.options[i].close == false) then lib.hideMenu() end
    end) end)
    pcall(function() _ui:RegisterEventHandler("menu:scroll", function(d)
        local data = _menus[_open]; if not data then return end
        local i = tonumber(d and d.index) or 1
        if type(data.onSideScroll) == "function" then pcall(data.onSideScroll, i, tonumber(d and d.scrollIndex), data.options[i] and data.options[i].args) end
    end) end)
    pcall(function() _ui:RegisterEventHandler("menu:check", function(d)
        local data = _menus[_open]; if not data then return end
        local i = tonumber(d and d.index) or 1
        if data.options[i] then data.options[i].checked = d and d.checked and true or false end
        if type(data.onCheck) == "function" then pcall(data.onCheck, i, d and d.checked, data.options[i] and data.options[i].args) end
    end) end)
    pcall(function() _ui:RegisterEventHandler("menu:close", function(d)
        local data = _menus[_open]
        if data and type(data.onClose) == "function" then pcall(data.onClose, d and d.key) end
        lib.hideMenu()
    end) end)
    return _ui
end

function lib.registerMenu(data, cb)
    if type(data) ~= "table" or not data.id then return end
    data.cb = cb
    _menus[data.id] = data
end

function lib.showMenu(id)
    local data = _menus[id]; if not data then return end
    local ui = ensureUI(); if not ui then return end
    _open = id
    pcall(function() ui:SetInputMode(1) end)
    ui:SendEvent("menu:show", toDisplay(data))
end

function lib.hideMenu()
    _open = nil
    if _ui then pcall(function() _ui:SetInputMode(0) end); pcall(function() _ui:SendEvent("menu:hide", {}) end) end
end

function lib.getOpenMenu() return _open end

function lib.setMenuOptions(id, options, index)
    local data = _menus[id]; if not data then return end
    if index and type(options) == "table" then data.options[index] = options else data.options = options end
    if _open == id and _ui then _ui:SendEvent("menu:show", toDisplay(data)) end
end

return lib.registerMenu
