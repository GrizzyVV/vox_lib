--[[ lib.inputDialog(heading, rows, options?) -> { values } | nil   (clean-room from the ox_lib inputDialog contract).
     A multi-field modal form. RETURN-VALUE: yields until submit (-> array of field values, by row order) or cancel
     (-> nil). MUST be called from a thread. Reuses modules/_dialog.lua (hEvent reverse channel).
       rows: array of field specs. type ∈ input|number|checkbox|select|multi-select|slider|textarea|date|color.
       common keys: label, description, default, required, placeholder, min, max, step, options ({value,label} list),
                    icon. Returns values in row order: input/number/textarea -> string/number, checkbox -> bool,
                    select -> value, slider -> number. ]]

local Dialog = lib._Dialog
local inputUI = Dialog and Dialog.new("vox_lib_input", "vox_lib/web/input/index.html", "input:response")

function lib.inputDialog(heading, rows, options)
    if type(rows) ~= "table" or not inputUI then return nil end
    local resp = inputUI:request("input:show", { heading = tostring(heading or "Input"), rows = rows,
                                                 options = type(options) == "table" and options or {} })
    -- page replies { result = { ...values } } on submit, or { result = nil } on cancel
    if resp and type(resp.result) == "table" then return resp.result end
    return nil
end

return lib.inputDialog
