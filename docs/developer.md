# vox_lib — Developer Reference

Every public function on the global `lib` table. All UI is **client-side**. Functions that return a value (alertDialog,
inputDialog, progressBar/Circle, skillCheck) **yield** — call them from inside a thread (`CreateThread(function() ... end)`).

- [UI](#ui)
- [Cinematic — weather / time / freecam](#cinematic)
- [Foundation](#foundation)

---

## UI

### lib.notify(data)
Transient toast. Non-blocking.
```lua
lib.notify({
  title = "Saved", description = "Vehicle stored.",  -- description supports **bold**
  type = "success",         -- success | error | warning | inform (default inform)
  icon = "circle-check",    -- Font Awesome name (optional)
  duration = 5000,          -- ms (optional)
  position = "top-right",   -- top-right | top | top-left | bottom-* | center-* (optional)
})
```

### lib.showTextUI(text, options) / lib.hideTextUI() / lib.isTextUIOpen()
Persistent on-screen prompt. `text` supports `**bold**`, `[KEY]` badges, and `$price` accents.
```lua
lib.showTextUI("[E] Refuel — $1.20/L", {
  icon = "gas-pump", iconColor = "#F0454E", iconAnimation = "beat",   -- all optional
  position = "right-center",        -- right-center (default) | left-center | top-center
})
lib.hideTextUI()
local open = lib.isTextUIOpen()
```

### lib.alertDialog(opts) → `"confirm" | "cancel" | nil`
Modal confirm box. **Returns** the choice (yields).
```lua
local r = lib.alertDialog({
  header = "Delete", content = "Are you **sure**?",   -- content supports markdown
  cancel = true,            -- show a Cancel button (default false)
  labels = { confirm = "Yes", cancel = "No" },        -- optional
  size = "md",              -- sm | md | lg (optional)
})
```

### lib.inputDialog(heading, rows, options) → `table | nil`
Multi-field form. **Returns** an array of values in row order, or `nil` if cancelled (yields).
```lua
local r = lib.inputDialog("Register Vehicle", {
  { type = "input",    label = "Plate", required = true, icon = "id-card", placeholder = "ABC 123" },
  { type = "number",   label = "Price", default = 5000, min = 0 },
  { type = "checkbox", label = "Insured", checkboxLabel = "Has insurance" },
  { type = "select",   label = "Color", options = { { value="r", label="Red" }, { value="b", label="Black" } } },
  { type = "slider",   label = "Mileage", min = 0, max = 200, default = 40 },
  { type = "textarea", label = "Notes" },
  -- also: date, color
})
if r then print(r[1], r[2], r[3], r[4], r[5]) end
```

### lib.progressBar(opts) / lib.progressCircle(opts) → `boolean`
Timed progress. **Returns** `true` if it completed, `false` if cancelled (yields). `lib.cancelProgress()` cancels early.
```lua
local ok = lib.progressBar({
  duration = 4000, label = "Searching…",
  canCancel = true, cancelKey = "X",   -- optional
  position = "bottom",                  -- bottom (default) | middle
})
```

### Context menu
Nested, mouse-driven menu with metadata/progress rows.
```lua
lib.registerContext({
  id = "garage", title = "Garage",
  options = {
    { title = "Take out", icon = "car", onSelect = function() takeOut() end },
    { title = "Storage", icon = "warehouse", menu = "garage_storage" },   -- submenu by id
    { title = "Status", metadata = { { label = "Fuel", value = "62%" } }, progress = 62 },
    { title = "Locked", icon = "lock", disabled = true },
  },
})
lib.showContext("garage")        -- lib.hideContext() ; lib.getOpenContextMenu()
```

### List menu
Keyboard-driven menu with side-scroll values, checkboxes, progress.
```lua
lib.registerMenu({
  id = "settings", title = "Settings",
  options = {
    { label = "Brightness", values = { { label="Low" }, { label="Med" }, { label="High" } } },
    { label = "HUD", checked = true },
    { label = "Fuel", progress = 40 },
  },
  onSelected   = function(i) end,
  onSideScroll = function(i, scrollIndex) end,
  onCheck      = function(i, checked) end,
}, function(selectedIndex, scrollIndex) end)   -- final select cb
lib.showMenu("settings")   -- lib.hideMenu() ; lib.getOpenMenu() ; lib.setMenuOptions(id, options, index)
```

### lib.skillCheck(difficulty, keys) → `boolean`
Timing minigame. `difficulty` is a string or array of rounds (`"easy"|"medium"|"hard"` or `{ areaSize=.., speedMultiplier=.. }`).
**Returns** `true` on success (yields). `lib.skillCheckActive()` / `lib.cancelSkillCheck()`.
```lua
local passed = lib.skillCheck({ "easy", "medium", "hard" }, { "e" })
```

### Radial menu
```lua
lib.addRadialItem({
  { id = "wave", label = "Wave", icon = "hand", onSelect = function() end },
  { label = "More", icon = "ellipsis", menu = "more_radial" },   -- submenu
})
lib.registerRadial({ id = "more_radial", items = { { label = "Dance", icon = "music", onSelect = function() end } } })
lib.showRadial()    -- or lib.showRadial("more_radial")
-- lib.hideRadial() ; lib.removeRadialItem(id) ; lib.disableRadial(true) ; lib.getCurrentRadialId()
```

---

## Cinematic

### Weather — `lib.SetWeather(type, transitionSec)` / `lib.ClearWeather()` / `lib.WeatherTypes`
`type` is one of the 13 native weather names (also in `lib.WeatherTypes`): `ClearSkies, Cloudy, Foggy, Overcast,
PartlyCloudy, Rain, RainLight, RainThunderstorm, SandDustCalm, SandDustStorm, Snow, SnowBlizzard, SnowLight`.
```lua
lib.SetWeather("RainThunderstorm", 10)   -- ease over 10s (0/omitted = instant)
```

### Time — `lib.SetTime(t, transitionSec)` / `lib.InterpolateTime(target, durationSec, easing)` / `lib.ClearTime()`
`t` / `target` is `HHMM` (e.g. `1830`). `InterpolateTime` eases the clock; `easing` is optional.
`lib.IsTimeInterpolating()` reports tween state.
```lua
lib.SetTime(1200)              -- jump to noon
lib.InterpolateTime(2200, 6)  -- ease to 22:00 over 6s
```

### Cinematic sky — `lib.SetCinematicSky(opts)` / `lib.ClearCinematicSky()` / `lib.GetSky()`
Direct access to the HELIX `Sky()` surface for combined weather/time/animation control.

### Freecam — `lib.StartFreeCam(opts)` / `lib.StopFreeCam()` / `lib.ToggleFreeCam(opts)` / `lib.IsFreeCamActive()`
Detached cinematic camera (your character is parked on a hidden host pawn, so movement/ability inputs don't leak). WASD +
mouse-look, Shift to boost; **Backspace** exits.
```lua
lib.ToggleFreeCam({ speed = 1.0, invertY = true })   -- invertY default true (spectator-host pitch)
```

---

## Foundation

Clean-room equivalents of the ox_lib utility contract. `lib.table` / `lib.string` index through to Lua's standard libs, so
e.g. `lib.string.upper` and the extras below both work.

| Surface | Highlights |
|---|---|
| `lib.class(name)` | OOP base — `Class:new(...)` calls `:constructor(...)`; used by array/timer. |
| `lib.table` | `contains, matches, deepclone, merge, freeze, isFrozen` (+ stdlib). |
| `lib.array` | JS-style: `from, isArray, at, push, pop, shift, unshift, slice, map, filter, forEach, every, find, findIndex, indexOf, reduce, join, fill, reverse, toReversed, merge`. `lib.isArray(v)`. |
| `lib.string` | `random(pattern, length)` (+ stdlib). |
| `lib.math` | `clamp, round, groupdigits, hextorgb, tohex, toscalars`. |
| `cache(key, fn, timeout)` | Global callable — memoize `fn()` under `key`, optional ms expiry. `cache.resource` / `cache.game`. |
| `lib.print` | `lib.print.{error,warn,info,verbose,debug}(...)` — level-filtered (convar `ox:printlevel`), pretty-prints tables. |
| `lib.locale(dict)` / `locale(key, ...)` | i18n — load a phrase table, then `locale("key", ...)` resolves `${refs}` + `string.format`s. |
| `lib.timer(ms, onEnd, async)` | Returns an `OxTimer` — `pause/play/isPaused/forceEnd(trigger)/getTimeLeft(fmt)/restart`. |
| `lib.waitFor(cb, errMessage, timeout)` | Poll `cb` each tick until non-nil (returned) or timeout (ms, default 1000; `false` = forever). Call from a thread. |
| `lib.callback` | `register(name, fn)`, `lib.callback(name, ...)` / `lib.callback.await(name, ...)` — request/response over the verified net-event transport. |
| `lib.hook` / `lib.registerHook(event, handler, opts)` | Pipelines that run hooks in order; a hook returning `false` rejects the action. Local-state pipelines fully supported. |

> **Deviations from ox_lib** (deliberate, for HELIX): `lib.waitFor` returns `nil` on timeout instead of throwing (a throw can
> halt the HELIX package); `lib.locale` is fed a table rather than auto-loading `locales/*.json` (pending verified file IO);
> cross-resource hook dispatch is not yet wired (local pipelines are). See [`tech.md`](tech.md).

## Gotchas

- **Return-value calls yield** — always wrap `alertDialog`/`inputDialog`/`progressBar`/`skillCheck` in a thread.
- **Source-bundled, not exports** — `lib` lives in your package's state; you can't call it across the package boundary.
- **Load order** — `init.lua` → `class.lua` → rest. Use the shipped [`package.json`](../package.json) order.
