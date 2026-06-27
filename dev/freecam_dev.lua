--[[ vox_lib dev — /freecam toggle command + the on-screen instructions panel for the freecam capability (modules/freecam.lua).
     The help panel is a mode-0 WebUI overlay (no input capture, so it never eats the flight controls). lib.StartFreeCam /
     StopFreeCam call ShowFreeCamHelp / HideFreeCamHelp if present. ]]

local HELP_PAGE = "vox_lib/web/freecam/index.html"
local helpUI

function lib.ShowFreeCamHelp()
    if not helpUI and WebUI then helpUI = WebUI("vox_lib_freecam_help", HELP_PAGE, 0) end
    if helpUI then pcall(function() helpUI:SendEvent("help:show", {}) end) end
end

function lib.HideFreeCamHelp()
    if helpUI then pcall(function() helpUI:SendEvent("help:hide", {}) end) end
end

-- /freecam — toggle the cinematic free-cam (client chat command via HConsole; verified pattern from hl-admin)
pcall(function()
    local HConsole = GetActorByTag and GetActorByTag("HConsole")
    if HConsole and HConsole.RegisterCommand then
        HConsole:RegisterCommand("freecam", "Toggle the vox_lib cinematic free-cam", nil, { HWorld, function()
            if lib.ToggleFreeCam then lib.ToggleFreeCam() end
        end })
    end
end)
