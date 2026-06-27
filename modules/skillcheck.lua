--[[ lib.skillCheck(difficulty, keys?) -> bool  ·  lib.skillCheckActive()  ·  lib.cancelSkillCheck()
     Timing minigame (clean-room from the ox_lib skillCheck contract). RETURN-VALUE + BLOCKING: yields until the player
     passes all rounds (-> true) or misses/cancels (-> false). MUST be called from a thread. The PAGE owns the game loop +
     key timing (it needs keyboard focus); Lua just shows it and awaits the result via the hEvent reverse channel (_dialog).
       difficulty: 'easy'|'medium'|'hard', OR { areaSize=, speedMultiplier= }, OR an ARRAY of those (one round each).
       keys: array of valid keys (default {'e'}). Kit B = LINEAR check (blessed). ]]

local Dialog = lib._Dialog
local scUI = Dialog and Dialog.new("vox_lib_skillcheck", "vox_lib/web/skillcheck/index.html", "skillcheck:done")
local _active = false

function lib.skillCheck(difficulty, keys)
    if not scUI then return false end
    -- normalize to an array of rounds
    local rounds = difficulty
    if type(difficulty) == "string" or (type(difficulty) == "table" and difficulty.areaSize) then rounds = { difficulty } end
    _active = true
    local resp = scUI:request("skillcheck:show", { rounds = rounds or { "medium" }, keys = keys or { "e" } })
    _active = false
    return resp and resp.success == true
end

function lib.skillCheckActive() return _active end
function lib.cancelSkillCheck() if scUI then scUI:send("skillcheck:cancel", {}) end end

return lib.skillCheck
