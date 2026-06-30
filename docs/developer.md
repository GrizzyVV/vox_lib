# vox_lib — Developer Reference

Every public function on the global `lib` table. All UI is **client-side**. Functions that return a value (alertDialog,
inputDialog, progressBar/Circle, skillCheck) **yield** — call them from inside a thread (`CreateThread(function() ... end)`).

- [UI](#ui)
- [Cinematic — weather / sky / time / freecam](#cinematic)
- [Character Creator — appearance](#character-creator)
- [Entities — spawning / vehicles / peds / attach](#entities)
- [Animations](#animations)
- [Raycast](#raycast)
- [World — worldToScreen / markers](#world)
- [Zones & points](#zones--points)
- [Screen fade](#screen-fade)
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

### Scripted camera — `lib.createCam` / `lib.setCamCoord` / `lib.setCamRot` / `lib.pointCamAt` / `lib.renderScriptCams` / `lib.destroyCam`
The FiveM scripted-camera family for cutscenes/menus. Create a camera actor, position + aim it, make the player view it, then blend
back. One active scripted cam at a time. ⚠️ *Visual smoke-test still owed — built on the freecam-verified view-target primitives.*
```lua
local cam = lib.createCam({ x = 100, y = 200, z = 90 })
lib.pointCamAt(targetActorOrCoords)        -- or lib.setCamRot({ pitch = -10, yaw = 90 })
lib.renderScriptCams(true, 1.0)            -- blend TO the cam over 1s
-- ...cutscene...
lib.renderScriptCams(false, 1.0)           -- blend back to the pawn
lib.destroyCam()
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
| `lib.setSlotColor(slot, color)` / `lib.clearSlotColor(slot)` | Per-slot material tint. `color` = `UE.FLinearColor(r,g,b,a)`. |
| `lib.setCosmeticGender(gender)` / `lib.clearCosmetics()` | Set gender / clear all worn cosmetic slots. |
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
| `lib.spawnPed(coords, rotation?, opts?, cb?)` | Spawn an NPC via `HPawn` (**async** — `cb(pawn)`). `opts = { name=, nameplate=, invincible=, frozen=, tags={} }`. |
| `lib.exitVehicle(pawn, opts?)` → result | Eject a pawn from its vehicle (`opts = { skipAnimations=true }`). |
| `lib.ejectAll(vehicle, opts?)` → result | Eject every occupant (iterates `SeatOccupancy`). |
| `lib.warpIntoVehicle(...)` → result | ⛔ **disabled no-op** — the enter native crashes the client without a valid target (see note); returns an error. |
| `lib.attachEntity(child, parent, rule?)` / `lib.detachEntity(child)` | Attach/detach actors. `rule = "snap"\|"keepWorld"\|"keepRelative"`. |
| `lib.getVehiclePlate/Fuel/EngineHealth(v)` · `lib.setVehicleFuel/Plate(v, x)` | Read/write vehicle state (accepts an HVehicle or a raw actor — auto-wraps). |
| `lib.deleteEntity(entity, ejectFirst?)` → boolean | Destroy a spawned actor; `ejectFirst=true` ejects occupants first. |
| `lib.freezeEntity(ped, frozen)` | Freeze/unfreeze a ped in place (movement mode). |
| `lib.freezeVehicle(vehicle, frozen)` | Hard-freeze a vehicle (disables every component tick + physics — `SetSimulatePhysics` alone won't hold the Chaos vehicle). |
| `lib.setEntityCollision(entity, enabled)` / `lib.setEntityVisible(entity, visible)` | Toggle actor collision / visibility. |
| `lib.getEntityModel(entity)` → `string` | The actor's class name. |
| `lib.getEntityHealth/getEntityMaxHealth/isEntityDead(entity)` | Ped health via the health component (vehicles read 0 → use `getVehicleEngineHealth`). |
| `lib.getBoneCoords(ped, bone)` → `Vector` | World location of a ped bone/socket (e.g. `"head"`, `"spine_03"`). |
| `lib.taskGoTo(ped, coords)` → boolean | Walk an NPC (spawned via `lib.spawnPed`) to a destination via its AI controller. |

```lua
-- vehicle (asset path comes from your vehicle catalog, e.g. qb-core Shared.Vehicles[model].asset_name)
local car = lib.spawnVehicle("/HelixVehicles/Blueprints/Cars/H1/BP_H1.BP_H1_C",
    { x = 569462, y = 562978, z = 4574 }, 90, { plate = "VOX 001" })

lib.spawnPed(coords, 0, { name = "Clerk", nameplate = true }, function(npc) print("spawned", npc) end)

lib.exitVehicle(GetPlayerPawn())          -- clean eject (no more stranded seated pose)
lib.deleteEntity(car, true)               -- eject occupants, then destroy
```

> **Stranded-vehicle — PREVENT, don't try to recover.** `lib.exitVehicle`/`ejectAll` cleanly eject occupants **while the vehicle
> still exists** (live-verified — ejects to a normal standing pose). But if you delete a vehicle with someone still seated, they
> are **stranded in the seated pose with NO programmatic recovery** (live-tested: exitVehicle, anim-override, and movement-reset
> all fail once the vehicle is gone — only a relog fixes it). So always use **`lib.deleteEntity(vehicle, true)`**, which ejects
> occupants and then **delays the destroy ~3s** (the exit is async) so they fully leave before the actor is removed. Never delete
> an occupied vehicle without `ejectFirst`.
>
> **⛔ `warpIntoVehicle` is a disabled no-op.** On the current build, `SendEnterVehicleEventToActor` with an empty
> `FHEnterVehicleParams` (which has no vehicle/seat field) dereferences null and **hard-crashes the client** (verified live —
> a C++ access violation that `pcall` cannot catch). Until the correct way to pass the target vehicle is found, the function
> returns an error instead of calling the native. **Do not re-enable without a verified-safe invocation.**

> **Exposing as a cross-package export** is a one-liner in your resource:
> `exports("myresource", "SpawnVehicle", lib.spawnVehicle)` — then `exports["myresource"]:SpawnVehicle(...)` from anywhere.
> (vox_lib itself is source-bundled, so it doesn't register exports for you — you choose what to expose.)

---

## Vehicle Paint

Per-vehicle colouring on HELIX's **instanced** vehicle render. **Client-side** (material/render is client-side — call these on
the client, e.g. inside a `RegisterClientEvent` handler driven by your server).

> **How it works:** gameplay vehicles are drawn by an `HVehicleInstancesContainerActor` (one instanced mesh per body part), so a
> flat material colour would tint *every* car of that model. These functions instead write **per-instance custom data** (RGB) at
> the target vehicle's instance, so you can paint **one car without touching the others**.

> ### ⚠️ TWO CURRENT LIMITATIONS — read before using (mirrored in the README and the CLAUDE changelog)
>
> **1. The vehicle's material must read per-instance custom data** (`PerInstanceCustomData3Vector` driving base colour). This is a
> **HELIX-side material change** (proposed to HELIX, not something vox_lib can ship). Until a given vehicle's material supports it,
> the calls set the data but it renders as a **harmless no-op** — no visible change. `lib.setFleetColor(..., "flat")` works on any
> paint material today. **➜ Remove this limitation once HELIX ships per-instance-reading vehicle materials.**
>
> **2. The vehicle must be STATIONARY — a vehicle loses its paint the moment it MOVES.** This is a **HELIX engine behaviour**, not a
> vox_lib bug: when a vehicle moves, the instance container **reassigns instance indices AND does not carry the per-instance custom
> data with it**, so the moving car's colour is dropped (verified in-engine — a car teleported away ended up at a new index, black).
> Stationary cars keep their colour. Paint parked/stopped vehicles. **➜ Remove this limitation once HELIX keeps per-instance custom
> data bound to the vehicle across movement** (proposed to HELIX — it can't be fixed from Lua).

Colours accept three numbers (`0..1`, or `0..255` if any value > 1), a table `{r,g,b}`, or a hex string `"#RRGGBB"`.
The `vehicle` argument accepts an `HVehicle` handle, a raw vehicle actor, or anything with `.Object`.

| function | does |
|---|---|
| `lib.setVehicleColor(vehicle, r, g, b)` | paint the **whole body** of one vehicle. Returns # of components painted. |
| `lib.setVehicleComponentColor(vehicle, component, r, g, b)` | paint **one component** — `component` is a mesh-name substring, e.g. `"Body"`, `"Door"`, `"Hood"`, `"Trunk"` (case-insensitive). |
| `lib.setFleetColor(r, g, b, mode)` | paint the **entire fleet** (all vehicles). `mode` = `"instance"` (default) or `"flat"` (works on any paint material today, but uniform per model). |
| `lib.getVehicleColor(vehicle)` → `r, g, b` | read a vehicle's current colour (or nil). |
| `lib.resetVehicleColor(vehicle [, r, g, b])` | stop any effect + reset to white (or a given colour). |
| `lib.interpVehicleColor(vehicle, r, g, b, duration [, opts])` → handle | **smoothly interpolate** to a target colour over `duration` ms. `opts`: `{ component, from, steps_ms, onDone }`. |
| `lib.vehicleParty(vehicle [, opts])` → handle | **party mode** — continuously cycle the colour wheel. `opts`: `{ component, speed (hue/sec, default 0.25), saturation, value, steps_ms }`. |
| `lib.stopVehicleEffect(vehicle)` | stop an active interp/party effect (or call `handle.stop()`). |
| `lib.hsvToRgb(h, s, v)` → `r, g, b` | helper for custom colour effects. |

```lua
-- on the client (e.g. after the server tells you to paint a vehicle)
lib.setVehicleColor(veh, "#1E90FF")            -- whole car blue
lib.setVehicleComponentColor(veh, "Hood", 255, 0, 0)   -- just the hood red
lib.interpVehicleColor(veh, 0, 1, 0, 2000)     -- fade to green over 2s
local party = lib.vehicleParty(veh, { speed = 0.5 })   -- rainbow loop
-- party.stop()  -- or lib.stopVehicleEffect(veh)
```

> One effect runs per vehicle (starting a new one cancels the previous). For networked paint, store the colour server-side and
> broadcast to clients, which apply it on spawn + on change (paint itself is client-local).

---

## Animations

> ✅ **VERIFIED RENDERING (in-engine).** The long-standing non-render was a **wrong slot**: the default was `"FullBody"`, which
> isn't a real montage slot on the player ABP — so montages played into nothing. The correct slot is **`"DefaultSlot"`** (now the
> default), confirmed visibly animating the player pawn in-editor. If you pass a custom `slot`, it must be a real slot on the
> character's anim blueprint (`"DefaultSlot"` or `"UpperBody"`).

`lib.playAnim(pawn, animPath, opts?)` / `lib.stopAnim(pawn)` over the HELIX `Animation` global (montages). **Client-side.**
`animPath` is the animation **asset path** (e.g. `/HelixAnimation/Unified/Animations/Actions/A_Action_Wave.A_Action_Wave`).
`opts = { loop=bool, slot="DefaultSlot"|"UpperBody" (default "DefaultSlot"), blendIn=sec, blendOut=sec, playRate=number,
lockMovement=bool (freeze the player during the anim — for emotes), cancellable=bool, onComplete=fn }`.

`FHPlayAnimParams` exposes `BlendInTime`/`BlendOutTime`/`PlayRate` (read live off the struct), so playing a new montage on the same
slot crossfades from the current pose — smooth A→B transitions. (Parametric blend-spaces — walk↔run by speed — are a separate
anim-BP mechanism, not exposed here.)

```lua
CreateThread(function()
    lib.playAnim(pawn, "/HelixAnimation/Unified/Animations/Actions/A_Action_Wave.A_Action_Wave", { blendIn = 0.3 })
    Wait(2000)
    lib.playAnim(pawn, dancePath, { loop = true, blendIn = 0.5 })   -- crossfades wave → dance
    Wait(5000)
    lib.stopAnim(pawn)                                              -- blends back to base pose
end)
```

## Raycast

`lib.raycast(startCoords, endCoords, opts?)` and `lib.raycastFromCamera(opts?)` (default = screen centre). **Client-side.**
Returns `{ ok, hit=bool, result={ location, normal, actor, distance } }`. `opts = { ignore={actors}, complex=bool, x=, y=, distance= }`.
```lua
local hit = lib.raycastFromCamera({ distance = 50000 })
if hit.hit then print("looking at", hit.result.actor, hit.result.location) end
```

## World

`lib.worldToScreen(coords)` → `{ ok, onScreen, x, y }` (x,y as 0-1 screen fractions) — the primitive for in-world labels.
`lib.spawnMarker(coords, opts?)` → mesh — a marker is a real `StaticMesh` (remove with `lib.deleteEntity`). `opts = { asset=, scale=, rotation=, collision= }`.

## Zones & points

Spatial triggers (the ox_lib points/zones contract), pure-Lua over one shared tick loop. **Client-side.**
- `lib.points.new{ coords=, distance=, onEnter=, onExit=, inside=, nearby=, nearDistance= }`
- `lib.zones.sphere{ coords=, radius=, onEnter=, onExit=, inside= }`
- `lib.zones.box{ coords=, size={x,y,z}, rotation=yawDeg, onEnter=, onExit=, inside= }`

Each returns a handle with `:remove()`. `onEnter`/`onExit` fire on transition; `inside` fires every tick while inside. `lib.removeAllZones()` clears all.
```lua
local z = lib.zones.sphere{ coords = shopCoords, radius = 250,
    onEnter = function() lib.showTextUI("[E] Shop") end,
    onExit  = function() lib.hideTextUI() end }
-- z.remove()
```

## Screen fade

`lib.fadeOut(durationMs?)` / `lib.fadeIn(durationMs?)` / `lib.isScreenFaded()`. **Client-side.** A WebUI black overlay
(the engine's `DoScreenFade*` globals were removed on the current build, so vox_lib owns this).
```lua
CreateThread(function() lib.fadeOut(800); Wait(800); doTeleport(); lib.fadeIn(800) end)
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
- **Load order** — `init.lua` → `class.lua` → rest. Use the shipped [`package.json`](../vox_lib/package.json) order.
