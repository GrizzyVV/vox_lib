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

Weather/time/sky drive HELIX's `Sky()` surface (`SetTimeOfDay`, `ChangeWeather`, `SetAnimateTimeOfDay`); `InterpolateTime`
eases the clock over a duration. The freecam spawns a hidden `ASpectatorPawn` to **possess** (detaching the character so
movement/ability inputs don't leak), views a camera actor blended in with `SetViewTargetWithBlend`, and drives it from
`GetControlRotation` + key-tracked movement applied via `K2_TeleportTo`. Input is `Input.BindKey` (HELIX exposes key
press/release only — no mouse-delta/axis), with mouse-look read from control rotation.

## Known deviations / limits

- `lib.waitFor` returns `nil` on timeout (no throw — see halt-on-first-throw).
- `lib.locale` is fed a phrase table; auto-loading `locales/<lang>.json` is deferred pending verified HELIX file IO.
- `lib.hook` cross-resource dispatch isn't wired (local same-state pipelines are fully supported).
- Native `RegisterCallback`/`TriggerCallback` are unreliable on HELIX, so `lib.callback` rides the verified net-event transport.

## Styling

All component pages share `web/_shared/helix-life.css` (the "HELIX-Life" kit). Each page reads a `{ name, args }` envelope on
`message` and emits results via `hEvent`; a `#preview` hash renders a static sample for design work.
