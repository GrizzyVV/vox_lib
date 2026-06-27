--[[ dev-only UI test harness. Triggers each vox_lib UI component in-engine for verification. PRIMARY path = a NET-EVENT
     listener (`vox:ui`) the probe drives via BroadcastEvent — robust, doesn't depend on chat/console timing. Also registers
     /v* chat commands as a convenience IF HConsole is ready at load (it often isn't — chat inits after package load).
     Results print to the log ([uitest] ...). Remove from package.json for a production build. ]]

local function pr(s) pcall(print, "[uitest] " .. s) end

local TESTS = {
    notify = function() lib.notify({ title = "Notify", description = "Hello from **vox_lib**", type = "success", icon = "circle-check" }) end,
    textui = function() lib.showTextUI("[E] vox_lib text UI — $1.20/L", { icon = "gas-pump" }); if Timer then Timer.SetTimeout(function() lib.hideTextUI() end, 4000) end end,
    alert = function() CreateThread(function() pr("alert -> " .. tostring(lib.alertDialog({ header = "Alert Test", content = "Does this **return**?", cancel = true }))) end) end,
    progress = function() CreateThread(function() pr("progress -> " .. tostring(lib.progressBar({ duration = 4000, label = "Testing progress…", canCancel = true }))) end) end,
    input = function() CreateThread(function()
        local r = lib.inputDialog("Input Test", {
            { type = "input", label = "Name", required = true, icon = "user" },
            { type = "number", label = "Age" },
            { type = "checkbox", label = "Agree", checkboxLabel = "I agree" },
            { type = "select", label = "Color", options = { { value = "r", label = "Red" }, { value = "b", label = "Black" } } },
            { type = "slider", label = "Level", min = 0, max = 100, default = 50 },
        })
        pr("input -> " .. (type(r) == "table" and ("ok, " .. #r .. " fields; [1]=" .. tostring(r[1])) or "cancelled"))
    end) end,
    context = function()
        lib.registerContext({ id = "vtest_ctx", title = "Context Test", options = {
            { title = "Plain option", icon = "star", onSelect = function() pr("ctx -> Plain") end },
            { title = "With submenu", icon = "folder", menu = "vtest_ctx2" },
            { title = "With metadata", icon = "gauge", metadata = { { label = "Fuel", value = "62%" } }, progress = 62, onSelect = function() pr("ctx -> Metadata") end },
            { title = "Disabled", icon = "lock", disabled = true },
        } })
        lib.registerContext({ id = "vtest_ctx2", title = "Submenu", menu = "vtest_ctx", options = { { title = "Back works?", icon = "check", onSelect = function() pr("ctx -> Sub leaf") end } } })
        lib.showContext("vtest_ctx")
    end,
    menu = function()
        lib.registerMenu({ id = "vtest_menu", title = "List Menu Test", options = {
            { label = "Plain" }, { label = "Side-scroll", values = { { label = "Low" }, { label = "Med" }, { label = "High" } } },
            { label = "Checkbox", checked = false }, { label = "With progress", progress = 40 },
        },
            onSelected = function(i) pr("menu onSelected " .. i) end,
            onSideScroll = function(i, s) pr("menu scroll " .. i .. " -> " .. tostring(s)) end,
            onCheck = function(i, c) pr("menu check " .. i .. " -> " .. tostring(c)) end,
        }, function(i, s) pr("menu SELECT " .. i .. " scroll=" .. tostring(s)) end)
        lib.showMenu("vtest_menu")
    end,
    skill = function() CreateThread(function() pr("skillCheck -> " .. tostring(lib.skillCheck({ "easy", "medium", "hard" }, { "e" }))) end) end,
    radial = function()
        lib.addRadialItem({
            { label = "Action 1", icon = "star", onSelect = function() pr("radial -> 1") end },
            { label = "Submenu", icon = "folder", menu = "vtest_radial2" },
            { label = "Action 3", icon = "gear", onSelect = function() pr("radial -> 3") end },
        })
        lib.registerRadial({ id = "vtest_radial2", items = { { label = "Sub A", icon = "check", onSelect = function() pr("radial -> Sub A") end } } })
        lib.showRadial()
    end,
}

-- PRIMARY: net-event trigger (probe: BroadcastEvent('vox:ui', '<name>')). Robust — no chat/console dependency.
if RegisterClientEvent then
    RegisterClientEvent("vox:ui", function(name)
        local fn = TESTS[name]
        if fn then pr("running " .. tostring(name)); pcall(fn) else pr("unknown test: " .. tostring(name)) end
    end)
    pr("net-event listener 'vox:ui' ready")
end

-- BONUS: /v* chat commands if the console happens to be ready at load.
local HConsole = GetActorByTag and GetActorByTag("HConsole")
if HConsole and HConsole.RegisterCommand then
    for name, fn in pairs(TESTS) do pcall(function() HConsole:RegisterCommand("v" .. name, "vox_lib UI test", nil, { HWorld, fn }) end) end
end
