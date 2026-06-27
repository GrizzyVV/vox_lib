--[[ vox_lib dev — weather/time SANDBOX menu (client). A dev playground (dev tool) to mess around with the world:
     run /weather to toggle a WebUI panel that drives lib.SetTime / lib.SetWeather / lib.ClearTime live. Loaded client-side in
     the same package state as init.lua + modules/weather.lua, so it calls lib.* directly. Pattern from the real HELIX
     qb-weathersync (Input.BindKey + WebUI SetInputMode/BringToFront/SendEvent + RegisterEventHandler reverse channel). ]]

local PAGE = "vox_lib/web/weather_menu/index.html"
local ui, ui_open = nil, false
local showMenu, hideMenu, toggle   -- forward declarations

local function currentState()
    local st = { time = 1200, weather = "ClearSkies", animate = false }
    if lib and lib.GetSky then
        local r = lib.GetSky()
        if r and r.ok and r.value then
            st.time = r.value.time or st.time
            st.weather = r.value.weather or st.weather
            st.animate = not r.value.forcingTime
        end
    end
    return st
end

local function ensureUI()
    if ui or not WebUI then return ui end
    ui = WebUI("vox_lib_weather_menu", PAGE, 0)
    pcall(function() ui:RegisterEventHandler("setTime",   function(d) if lib.SetTime    then lib.SetTime(tonumber(d and d.time) or 1200, 1.2) end end) end)
    pcall(function() ui:RegisterEventHandler("setWeather", function(d) if lib.SetWeather then lib.SetWeather(d and d.weather) end end) end)
    pcall(function() ui:RegisterEventHandler("setAnimate", function(d)
        if d and d.on then
            if lib.ClearTime then lib.ClearTime() end                      -- resume the day/night cycle
        else
            local s = currentState(); if lib.SetTime then lib.SetTime(s.time) end  -- freeze at current time
        end
    end) end)
    pcall(function() ui:RegisterEventHandler("close", function() hideMenu() end) end)
    return ui
end

showMenu = function()
    local u = ensureUI(); if not u then return end
    ui_open = true
    pcall(function() u:BringToFront() end)
    pcall(function() u:SetInputMode(1) end)            -- capture cursor for the menu
    u:SendEvent("menu:show", currentState())
end

hideMenu = function()
    if not ui then return end
    ui_open = false
    pcall(function() ui:SetInputMode(0) end)           -- release control back to the game
    ui:SendEvent("menu:hide", {})
end

toggle = function() if ui_open then hideMenu() else showMenu() end end

-- toggle via a CHAT COMMAND (/weather) — F-keys collide with native modes (F6 = photo mode). Client chat commands
-- register on the HConsole actor: HConsole:RegisterCommand(name, desc, nil, {HWorld, fn}) (verified from real HELIX
-- scripts — hl-admin). GetActorByTag('HConsole') is the client console; HWorld is the world context.
pcall(function()
    local HConsole = GetActorByTag and GetActorByTag("HConsole")
    if HConsole and HConsole.RegisterCommand then
        HConsole:RegisterCommand("weather", "Toggle the vox_lib weather/time sandbox", nil, { HWorld, function() toggle() end })
    end
end)
