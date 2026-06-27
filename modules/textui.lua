--[[ lib.showTextUI / lib.hideTextUI / lib.isTextUIOpen — persistent on-screen interaction hint (clean-room from the
     ox_lib TextUI contract). Drives web/textui/index.html via the WebUI seam. Client-side, one-way (no return value).
       lib.showTextUI(text, options?)  text: string (supports **bold**, [KEY] badges, $price). options: {
           position?='right-center'|'left-center'|'top-center', icon?, iconColor?, iconAnimation?, alignIcon?, style? }
       lib.hideTextUI()
       lib.isTextUIOpen()  -> isOpen(bool), text(string|nil)
     Re-calling showTextUI while open UPDATES the panel (ox_lib parity). ]]

local PAGE = "vox_lib/web/textui/index.html"
local _ui, _open, _text = nil, false, nil

local function ensureUI()
    -- mode 0 = game layer: a hint overlay must render WITHOUT capturing input/focus.
    if not _ui and WebUI then _ui = WebUI("vox_lib_textui", PAGE, 0) end
    return _ui
end

function lib.showTextUI(text, options)
    if type(text) ~= "string" then return end
    local ui = ensureUI()
    if not ui then return end          -- no WebUI (e.g. server state) — surfaced no-op
    _open, _text = true, text
    ui:SendEvent("textui:show", { text = text, options = type(options) == "table" and options or {} })
end

function lib.hideTextUI()
    _open, _text = false, nil
    if _ui then _ui:SendEvent("textui:hide", {}) end
end

function lib.isTextUIOpen()
    return _open, _text
end

return lib.showTextUI
