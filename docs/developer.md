# vox_lib — Developer Reference

Every public function on the global `lib` table. All UI is **client-side**. Functions that return a value (alertDialog,
inputDialog, progressBar/Circle, skillCheck) **yield** — call them from inside a thread (`CreateThread(function() ... end)`).

- [UI](#ui)
- [Cinematic — weather / sky / time / freecam](#cinematic)
- [Character Creator — appearance](#character-creator)
- [Entities — spawning](#entities)
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

### Weather — `lib.SetWeather(type, transitionSec)` / `lib.InterpolateWeather(type, durationSec)` / `lib.ClearWeather()` / `lib.WeatherTypes`
`type` is one of the 13 native weather names (also in `lib.WeatherTypes`): `ClearSkies, Cloudy, Foggy, Overcast,
PartlyCloudy, Rain, RainLight, RainThunderstorm, SandDustCalm, SandDustStorm, Snow, SnowBlizzard, SnowLight`. GTA-style
aliases (`EXTRASUNNY`, `THUNDER`, `BLIZZARD`, …) also resolve, so converted FiveM resources keep working.
```lua
lib.SetWeather("RainThunderstorm", 10)      -- preset transition eased over 10s by the engine (0/omitted = instant snap)
lib.InterpolateWeather("Foggy", 8)          -- same, with the IsWeatherInterpolating() contract
```
The preset **transition** is the engine's native blend (UltraDynamicSky). `lib.IsWeatherInterpolating()` reports whether a
timed transition is still in flight; a newer `SetWeather`/`InterpolateWeather` supersedes the previous one.

### Sky parameters — `lib.SetSky(params)` / `lib.InterpolateSky(params, durationSec, easing)` / `lib.IsSkyInterpolating()`
Per-parameter control of the scalar sky look (`lib.SkyParams`): `fog, cloudCoverage, contrast, overallIntensity,
nightBrightness, sunLightIntensity, sunRadius`. These have **no native blend** — `InterpolateSky` tweens them frame-by-frame
(same eased machinery as `InterpolateTime`). Each param is a number (tween from the last value we set / a neutral baseline) or
`{ from =, to = }` for an explicit ramp. `easing` ∈ `linear | easeIn | easeOut | easeInOut` (default `easeInOut`).
```lua
lib.SetSky({ fog = 0.1, cloudCoverage = 0.4 })                      -- snap
lib.InterpolateSky({ fog = 0.85, cloudCoverage = 0.9,              -- roll a storm in over 12s
                     overallIntensity = 0.6 }, 12, "easeInOut")
lib.InterpolateSky({ fog = { from = 0, to = 0.5 } }, 6)            -- explicit from→to ramp
```

### Time — `lib.SetTime(t, transitionSec)` / `lib.InterpolateTime(target, durationSec, easing)` / `lib.ClearTime()`
`t` / `target` is `HHMM` (e.g. `1830`). `InterpolateTime` eases the clock; `easing` is optional.
`lib.IsTimeInterpolating()` reports tween state.
```lua
lib.SetTime(1200)              -- jump to noon
lib.InterpolateTime(2200, 6)  -- ease to 22:00 over 6s
```

### Cinematic sky — `lib.SetCinematicSky(opts)` / `lib.ClearCinematicSky()` / `lib.GetSky()`
Compose a whole look atomically. `opts = { time =, weather =, sky = {…}, transition =, easing = }`. When `transition > 0`,
time + the scalar `sky` params **ease** over that many seconds (and the weather preset uses the engine blend); otherwise it all
snaps. `lib.GetSky()` reads back the current time/weather/forcing state.
```lua
lib.SetCinematicSky({ time = 2100, weather = "Foggy",
                      sky = { fog = 0.7, overallIntensity = 0.5 }, transition = 10 })
```

### Freecam — `lib.StartFreeCam(opts)` / `lib.StopFreeCam()` / `lib.ToggleFreeCam(opts)` / `lib.IsFreeCamActive()`
Detached cinematic camera (your character is parked on a hidden host pawn, so movement/ability inputs don't leak). WASD +
mouse-look, Shift to boost; **Backspace** exits.
```lua
lib.ToggleFreeCam({ speed = 1.0, invertY = true })   -- invertY default true (spectator-host pitch)
```

---

## Character Creator

Surfaces HELIX's **native** character-customization system (the `BPC_CharacterCreator` / cosmetics component on the local
pawn). HELIX renders the customization UI itself — vox_lib gives you the verbs to open it and, crucially, to **capture, persist,
and re-apply the appearance** so a created look survives a respawn. **Client-side.**

### The appearance contract
`lib.getAppearance()` returns a **JSON string** (~7 KB) — the engine's `BP_JsonObjectWrapper` serialized:
```json
{ "Gender": "Male", "Slots": { "<slot-guid>": { "MaterialParameters": [ ... ] }, ... } }
```
Treat it as an opaque blob: store the whole string, hand the whole string back. (Probe-verified round-trip on HELIX.)

### Verbs
| Function | Does |
|---|---|
| `lib.openCharacterCreator(opts?)` | Opens the native customization UI. `opts.slotFilter` = `{ SlotName = true }` to **hide** slots (e.g. `{ Hats = true, Masks = true }`). |
| `lib.getAppearance()` → `string\|nil` | Capture the current appearance as a JSON string (persist this). |
| `lib.applyAppearance(json)` → `boolean` | Reconstruct + apply a saved appearance string. |
| `lib.resetAppearance(gender?, bodyType?)` → `boolean` | Reset to engine defaults (defaults to the character's current gender/bodyType). |
| `lib.equipCosmetic(id)` / `lib.unequipCosmetic(id)` / `lib.equipCosmetics(ids)` | Wearable items by `equipmentId`. |
| `lib.isCosmeticEquipped(id)` → `boolean` | — |
| `lib.getCosmeticGender()` / `lib.getCosmeticBodyType()` | Current enum values. |
| `lib.getCosmeticsSystem()` | The raw component, for anything not wrapped here. |

### Persistence pattern (the important part)
The native flow captures the preset only to read gender, then **throws it away** — so customization is lost on respawn. Close
that gap by persisting the JSON and re-applying on possession. vox_lib is client-side; persistence is your server's job (e.g.
[vox_sqlite](https://github.com/GrizzyVV)):

```lua
-- CLIENT: when the player confirms creation (or closes the creator)
local json = lib.getAppearance()
if json then TriggerServerEvent("myresource:saveAppearance", json) end

-- SERVER: persist keyed by character id
RegisterServerEvent("myresource:saveAppearance", function(src, json)
    local cid = getCitizenId(src)
    exports["vox_sqlite"]:Execute("UPDATE players SET appearance = ? WHERE citizenid = ?", { json, cid })
end)

-- CLIENT: re-apply on spawn
RegisterClientEvent("HEvent:PlayerPossessed", function()
    TriggerServerEvent("myresource:requestAppearance")
end)
RegisterClientEvent("myresource:loadAppearance", function(json)
    if json then lib.applyAppearance(json) end
end)
```

> **Notes.** `applyAppearance` re-applies the *full* preset (face/body/material params), distinct from equipment-driven clothing
> (which qb-style inventories re-equip via `equipCosmetics` on possession). `resetAppearance`'s `gender` arg flips the enum but
> does not by itself swap the base body mesh in the default state. The native UI's "finished" signal (for auto-capture) is an
> `OnCosmeticsUpdated`-style event — not yet wrapped here; capture on your own confirm/close for now.

---

## Entities

Clean one-call spawning that packages the HELIX natives (`HVehicle`, `HWorld:SpawnActor`, `K2_DestroyActor`). **Server-side** —
spawned actors replicate to clients automatically (a bare `HVehicle()` is visible with no extra registration; probe-verified).
Coords accept a UE `Vector` or a plain table (`{x=,y=,z=}` / `{X=,Y=,Z=}` / `{n,n,n}`); rotation accepts a `Rotator`, a bare
yaw number, or `{pitch=,yaw=,roll=}`.

| Function | Does |
|---|---|
| `lib.spawnVehicle(asset, coords, heading?, opts?)` → vehicle\|nil | Spawn a vehicle. `asset` = vehicle Blueprint path. `opts = { plate=, tags={} }`. |
| `lib.spawnObject(class, coords, rotation?, opts?)` → actor\|nil | Spawn any actor. `class` = a UClass or a class-path string. `opts = { tags={} }`. |
| `lib.deleteEntity(entity)` → boolean | Destroy a spawned actor. |

```lua
-- vehicle (asset path comes from your vehicle catalog, e.g. qb-core Shared.Vehicles[model].asset_name)
local car = lib.spawnVehicle("/HelixVehicles/Blueprints/Cars/H1/BP_H1.BP_H1_C",
    { x = 569462, y = 562978, z = 4574 }, 90, { plate = "VOX 001" })

-- generic actor
local cam = lib.spawnObject("/Script/Engine.CameraActor", coords, { yaw = 180 })

lib.deleteEntity(car)
```

> **⚠️ Don't delete an occupied vehicle.** Destroying a vehicle while a player is seated leaves them stuck in the seated pose
> (the seat link dangles — there's no character-level `ExitVehicle` to recover cleanly; a relog resets it). Empty/eject the
> vehicle before `deleteEntity`.

> **Exposing as a cross-package export** is a one-liner in your resource:
> `exports("myresource", "SpawnVehicle", lib.spawnVehicle)` — then `exports["myresource"]:SpawnVehicle(...)` from anywhere.
> (vox_lib itself is source-bundled, so it doesn't register exports for you — you choose what to expose.)

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
- **Load order** — `init.lua` → `class.lua` → rest. Use the shipped [`package.json`](../vox_lib/package.json) order.
