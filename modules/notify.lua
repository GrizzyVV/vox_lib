--[[ lib.notify(data) — on-screen toast notifications (clean-room from the ox_lib notify contract).
     Drives a HELIX WebUI page (web/notify/index.html) via the WebUI seam: a single page is instantiated once and each
     lib.notify ships its data to it as a 'notify' event. Client-side (renders on the local player's screen).
     data: { id?, title?, description? (markdown), duration?=3000, showDuration?=true, position?='top-right',
             type?='inform'|'error'|'success'|'warning', icon?, iconColor?, iconAnimation?, alignIcon?, style?, sound? }
     Title OR description required. Server can notify a client via TriggerClientEvent('ox_lib:notify', source, data). ]]

local PAGE = "vox_lib/web/notify/index.html"
local _ui

local function ensureUI()
    if not _ui and WebUI then
        -- mode 0 = game layer (renders an overlay WITHOUT capturing input — a toast must not steal focus)
        _ui = WebUI("vox_lib_notify", PAGE, 0)
    end
    return _ui
end

function lib.notify(data)
    if type(data) ~= "table" then return end
    local ui = ensureUI()
    if not ui then return end           -- no WebUI (e.g. server state) — surfaced no-op
    ui:SendEvent("notify", data)
end

-- server -> client: another resource (or the server) triggers a notification on this client
if RegisterClientEvent then
    RegisterClientEvent("ox_lib:notify", function(data) lib.notify(data) end)
end

return lib.notify
