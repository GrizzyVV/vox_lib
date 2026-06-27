# vox_lib — How It Works

The HELIX constraints vox_lib is built around, and the patterns that solve them. Verified on HELIX (UE 5.7.4 / Lua 5.4).

## The runtime it targets

HELIX runs **standard Lua 5.4** (not CfxLua). A few behaviours shape the whole design:

1. **Packages are sandboxed states.** Each package runs in its own Lua state; globals don't leak between packages, and **Lua
   functions can't cross the package boundary** — only data passes through `exports`/events. A function sent across is stripped.
2. **No native `Wait` / `CreateThread`.** HELIX schedules via `Timer.SetTimeout(fn, ms)` (rejects `0`). There's no FiveM-style
   game loop or millisecond game timer.
3. **Halt-on-first-throw.** An uncaught error during package load aborts the rest of that package's load. So vox_lib avoids
   throwing in normal control flow (e.g. `waitFor` returns `nil` on timeout instead of erroring).
4. **WebUI is a one-way send by default.** `SendEvent`/page messaging pushes Lua→page cleanly; getting data **back** from a
   page needs the reverse channel below.

## Why source-bundled, not exports

Because functions don't cross the package boundary, a library of *functions* can't be consumed via `exports['vox_lib']:fn()`
the way a data service (like a database) can. So vox_lib's modules are designed to **load into the consumer's own state** — each
module attaches itself to the global `lib` table when its file runs. Two delivery shapes, same end state:

- **Standalone package** — vox_lib loads as its own package; `lib` is complete within it. It includes `modules/scheduler.lua`
  so it's self-sufficient.
- **Source-bundled** — a build pipeline copies the module files into the target package and lists them in that package's
  `package.json`. The host already provides `Wait`/`CreateThread`, so `scheduler.lua` is omitted (its guard would no-op anyway).

`init.lua` creates `lib` and must load first; `class.lua` underpins `array`/`timer`, so it's next; the rest follow. The shipped
`package.json` encodes the canonical order.

## The scheduler

`modules/scheduler.lua` supplies `Wait` + `CreateThread` **only if the host hasn't already** (`type(Wait) ~= "function"`).
`CreateThread(fn)` runs `fn` on a coroutine; each `Wait(ms)` yields the delay and the resume is rescheduled via
`Timer.SetTimeout` (clamped to ≥1ms — Timer rejects 0). This is what lets the blocking pieces — `lib.timer` and the
return-value UI (`alertDialog`/`progressBar`/`inputDialog`/`skillCheck`) — *yield* and resume.

## The WebUI reverse channel (page → Lua)

The return-value components need the page to send the user's choice back to Lua. The pattern (in `modules/_dialog.lua`):

1. Lua creates the WebUI page and registers a **one-shot** response handler via the page's `RegisterEventHandler`.
2. Lua `SendEvent`s the request payload to the page (HELIX wraps it as `{ name, args:[payload] }`).
3. The page renders, the user acts, and the page calls `hEvent(name, data)` — HELIX's page→Lua callback — with the result.
4. The handler resolves; the calling thread (which was `Wait`-yielding) wakes with the value.

For **NUI-style pages** that emit via `fetch`/`$.post` to `https://<resource>/<cb>` instead of `hEvent`, a host build can install
a small shim that intercepts those and rewrites them to `hEvent` — so existing pages work unchanged. (That shim is a host
concern; vox_lib's own pages call `hEvent` directly.)

## Cinematic layer

Weather/time/sky drive HELIX's `Sky()` surface. There are **two kinds of transition**, because the engine blends some things
and not others:

- **Presets** (`ChangeWeather(type, sec)`) and **time** are different beasts. `ChangeWeather` has a *native* blend — pass it a
  duration and UltraDynamicSky tweens the preset for you (this is canonical; HELIX's own qb-weathersync uses a 5s delay).
  `SetTimeOfDay`, by contrast, is an **instant snap** with no native blend.
- **Scalar sky params** (`SetFog`, `SetCloudCoverage`, `SetContrast`, `SetOverallIntensity`, `SetNightBrightness`,
  `SetSunLightIntensity`, `SetSunRadius`) also have **no native blend** — and crucially **no getters** (probe-verified: the
  `Get*` for scalars are `nil`).

So vox_lib supplies the missing eased tweens itself. `InterpolateTime` and `InterpolateSky` share one `runTween` helper that
steps ~25 fps over the native `Timer`, applying an eased fraction each frame (`easeIn/Out/InOut/linear`) and landing exactly on
the final step; a monotonic id supersedes a stale tween, and `Is*Interpolating()` reports state. Because the scalar params have
no getters, vox_lib **tracks the last value it set** (`_skyState`) to know where a tween starts (or you pass `{from, to}`).
`InterpolateWeather` wraps the native preset blend with the same state/supersede contract for symmetry; `SetCinematicSky`
composes time + weather + scalar sky in one call (eased when given a `transition`). **Probe + screenshot-verified end-to-end**
on the ESX testbed (all 7 setters present/float-accepting; a 12s eased ramp captured frame-by-frame). These are client-render,
so they run client-side.

The freecam spawns a hidden `ASpectatorPawn` to **possess** (detaching the character so movement/ability inputs don't leak),
views a camera actor blended in with `SetViewTargetWithBlend`, and drives it from `GetControlRotation` + key-tracked movement
applied via `K2_TeleportTo`. Input is `Input.BindKey` (HELIX exposes key press/release only — no mouse-delta/axis), with
mouse-look read from control rotation.

## Character Creator (native cosmetics)

Unlike GTA/FiveM ped drawables, HELIX has a native cosmetics component (`BPC_CharacterCreator` / `UHCharacterCosmetics`) on the
player pawn. vox_lib wraps it rather than reimplementing a creator UI — HELIX renders the customization UI via
`ShowCharacterCustomizationUI()`. The appearance round-trips as a `BP_JsonObjectWrapper`: `RetainCharacterCustomizationPreset()`
→ `:SaveToString()` gives a JSON string `{ Gender, Slots: { <guid>: { MaterialParameters } } }`; reconstructing a wrapper with
`NewObject(class)` + `:LoadFromString(json)` and calling `ApplyCharacterCustomizationPreset(wrapper)` restores it exactly
(probe-verified end-to-end). The stock flow reads only `.Gender` and discards the preset, so appearance is otherwise lost on
respawn — `lib.applyAppearance` on `HEvent:PlayerPossessed` closes that gap. See `developer.md`.

## Entity spawning

`HVehicle(pos, rot, assetPath)` is a global constructor (like `Sky`/`HWorld`) that spawns a vehicle actor server-side; it
replicates to clients with no extra step (probe-verified — a bare spawn is immediately visible). Generic actors use
`HWorld:SpawnActor(class, location, rotation)`; both clean up via `actor:K2_DestroyActor()`. `lib.spawnVehicle/spawnObject/
deleteEntity` wrap these with flexible coord/rotation inputs. A host framework may additionally set a plate + fire its own
entity-registration event for a metadata/ownership layer — that's app bookkeeping, *not* required for the entity to exist or
render, so vox_lib leaves it to the consumer.

NPCs use the global `HPawn(pos, rot, callback, { CharacterName, bShowNameplate })` (async — the pawn arrives in the callback);
vehicle occupancy is driven by `UE.UHGameplaySystemGlobals.Send{Exit,Enter}VehicleEventToActor(pawn, params)` — `lib.exitVehicle`
/`ejectAll` use the exit event (which finally closes the "stranded seated pawn" problem deleteEntity used to warn about). Attach
uses the `AttachActorToActor`/`DetachActor` globals + `UE.EAttachmentRule`.

## Animation & spatial layer

Animations ride the `Animation` global: `Animation.Play(pawn, animAssetPath, UE.FHPlayAnimParams, onDone)` / `Animation.Stop(pawn)`.
`FHPlayAnimParams` (probe-verified fields) carries `LoopCount`, `AnimSlotName`, and the blend knobs `BlendInTime`/`BlendOutTime`
plus `PlayRate` — so `lib.playAnim` crossfades between animations. Raycasting is `UE.UKismetSystemLibrary.LineTraceSingle` (+
`UE.UGameplayStatics.DeprojectScreenToWorld` for the camera ray); `lib.worldToScreen` is `HPlayer:ProjectWorldLocationToScreen`.
`lib.points`/`lib.zones` are deliberately **pure-Lua** (distance / point-in-box math on one `Timer.SetInterval` loop) rather than
UE physics components — cheaper and portable. `lib.fadeOut/fadeIn` is a WebUI black overlay.

**Build note (important):** the HELIX scripting API has TWO generations. An older build exposed FiveM-style global natives
(`CreateThread`, `DoScreenFadeIn`, `FreezeEntityPosition`, …) that the **current** build dropped for cleaner idioms (`Timer.*`,
`Animation.*`, WebUI overlay fade). vox_lib targets the **current** build — every API above is probe-verified on it (2026-06-27).
That's why, e.g., screen fade is a WebUI overlay (the old `DoScreenFade*` globals no longer exist).

## Known deviations / limits

- `lib.waitFor` returns `nil` on timeout (no throw — see halt-on-first-throw).
- `lib.locale` is fed a phrase table; auto-loading `locales/<lang>.json` is deferred pending verified HELIX file IO.
- `lib.hook` cross-resource dispatch isn't wired (local same-state pipelines are fully supported).
- Native `RegisterCallback`/`TriggerCallback` are unreliable on HELIX, so `lib.callback` rides the verified net-event transport.

## Styling

All component pages share `web/_shared/helix-life.css` (the "HELIX-Life" kit). Each page reads a `{ name, args }` envelope on
`message` and emits results via `hEvent`; a `#preview` hash renders a static sample for design work.
