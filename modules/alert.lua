--[[ lib.alertDialog(opts) -> 'confirm' | 'cancel'  (clean-room from the ox_lib alertDialog contract).
     A modal confirm/notice dialog. RETURN-VALUE: yields until the user answers (page -> Lua via hEvent). MUST be
     called from a thread (CreateThread). opts: {
        header (string), content (string, **markdown**), centered?=true, cancel?=false (show a cancel button),
        size?='md' (xs|sm|md|lg|xl), labels?={ confirm?, cancel? } }
     Returns 'confirm' when the user confirms, 'cancel' on cancel/escape. ]]

local Dialog = lib._Dialog
local alertUI = Dialog and Dialog.new("vox_lib_alert", "vox_lib/web/alert/index.html", "alert:response")

function lib.alertDialog(opts)
    if type(opts) ~= "table" or not alertUI then return nil end
    local resp = alertUI:request("alert:show", opts)
    -- page replies { result = 'confirm' | 'cancel' }; default to cancel (safe) if it closed without a clear answer
    if resp and resp.result == "confirm" then return "confirm" end
    return "cancel"
end

return lib.alertDialog
