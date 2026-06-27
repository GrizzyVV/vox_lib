--[[ lib.fadeOut / lib.fadeIn — full-screen fade to/from black. CLIENT-side.
     The old build had DoScreenFadeIn/Out globals; the CURRENT build dropped them (probe-verified 2026-06-27), so vox_lib OWNS
     the fade as a WebUI black-overlay (opacity transition). Mode 0 = game-layer overlay that does NOT capture input. ]]

local PAGE = "vox_lib/web/screenfade/index.html"
local _ui, _faded = nil, false

local function ensureUI()
    if not _ui and WebUI then
        _ui = WebUI("vox_lib_screenfade", PAGE, 0)
        pcall(function() _ui:SetLayer(50) end)   -- ride above other UI when SetLayer exists
    end
    return _ui
end

-- Fade the screen TO black over durationMs (default 500). Returns { ok }.
function lib.fadeOut(durationMs)
    local ui = ensureUI(); if not ui then return { ok = false, error = "WebUI unavailable" } end
    _faded = true
    ui:SendEvent("fade", { state = "out", duration = durationMs or 500 })
    return { ok = true }
end

-- Fade the screen back FROM black over durationMs (default 500). Returns { ok }.
function lib.fadeIn(durationMs)
    local ui = ensureUI(); if not ui then return { ok = false, error = "WebUI unavailable" } end
    _faded = false
    ui:SendEvent("fade", { state = "in", duration = durationMs or 500 })
    return { ok = true }
end

function lib.isScreenFaded() return _faded end

return lib.fadeOut
