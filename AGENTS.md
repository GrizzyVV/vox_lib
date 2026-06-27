# AGENTS.md — vox_lib

Guidance for AI agents reading, navigating, or extending this codebase. (For the human overview, see [README.md](README.md).)

## What this is
vox_lib is a **HELIX-native UI + utility library** for HELIX (the UE5-based game) — a clean-room equivalent of the `lib.*`
contract that FiveM/ox_lib resources expect, rebuilt for HELIX's runtime (standard Lua 5.4). Every capability attaches to a
single global table: **`lib`**.

## Critical: the load model (read this before reasoning about the code)
HELIX packages are **sandboxed Lua states, and functions do not cross the package boundary.** So vox_lib is **not** an `exports`
resource — you cannot call `exports['vox_lib']:fn()` from another package. Instead, its modules load **into the consumer's own
state** and attach to the global `lib`. Two supported ways to use it, both ending with `lib.*` living in the consumer's state:
- **Standalone package** — drop the `vox_lib/` folder into `scripts/` and list `"vox_lib"` in `config.json`. Self-contained
  (ships its own optional scheduler).
- **Source-bundled** — copy the module files into your own package and list them in your `package.json` in dependency order.

`init.lua` runs first (creates `lib`), then `modules/class.lua`, then the rest. The canonical order is in `vox_lib/package.json`.

## Repo layout
- **`vox_lib/`** — THE deployable resource (this is what actually runs):
  - `init.lua` — creates global `lib`, sets `lib._VERSION`
  - `package.json` — the load manifest (canonical module order)
  - `modules/*.lua` — one file per capability; each attaches itself to `lib`
  - `web/<component>/index.html` — the WebUI page for each visual component; `web/_shared/helix-life.css` is the shared theme
- `docs/developer.md` — the full `lib.*` API reference (every function, options, examples)
- `docs/tech.md` — how it works (runtime constraints, the WebUI reverse channel, the scheduler, the cinematic/entity layers)

## Module map (where to look for what)
**Foundation**
- `class.lua` → `lib.class` (OOP base; `array` + `timer` depend on it)
- `table.lua` `array.lua` `string.lua` `math.lua` → `lib.table` / `lib.array` / `lib.string` / `lib.math`
- `cache.lua` → global callable `cache`; `print.lua` → `lib.print`; `locale.lua` → `lib.locale` + global `locale()`
- `timer.lua` → `lib.timer`; `waitfor.lua` → `lib.waitFor`
- `callback.lua` → `lib.callback`; `hooks.lua` → `lib.hook` / `lib.registerHook`
- `scheduler.lua` → optional global `Wait` / `CreateThread` (guarded — no-ops if the host already provides them)

**UI** (each is a module + a matching `web/<name>/` page)
- `notify.lua` · `textui.lua` · `alert.lua` · `progress.lua` · `input.lua` · `context.lua` · `menu.lua` · `skillcheck.lua` · `radial.lua`
- `_dialog.lua` → shared return-value plumbing: create WebUI → register a one-shot `hEvent` response handler → `SendEvent` → `Wait`-yield until the user responds

**Cinematic / world**
- `weather.lua` → `lib.SetWeather` / `lib.SetTime` / `lib.InterpolateTime` (drives the HELIX `Sky()` API)
- `freecam.lua` → detached cinematic camera
- `charcreator.lua` → `lib.openCharacterCreator` / `getAppearance` / `applyAppearance` (wraps HELIX's native cosmetics)
- `entity.lua` → `lib.spawnVehicle` / `spawnObject` / `deleteEntity`

## Conventions
- **WebUI events**: Lua→page via `SendEvent` (envelope `{ name, args:[payload] }`); page→Lua via `hEvent(name, data)` →
  handlers registered on the page object. Per-component event names are `"<component>:show"` / `"<component>:response"`, etc.
- **Return-value calls yield**: `alertDialog` / `inputDialog` / `progressBar` / `skillCheck` suspend until the user responds —
  call them from inside a thread (`CreateThread(function() ... end)`).
- **Styling**: every page links `web/_shared/helix-life.css`; a `#preview` URL hash renders a static sample for design work.

## Gotchas
- Load order matters: `init.lua` → `class.lua` → rest (use `vox_lib/package.json`).
- `Timer.SetTimeout` rejects `0` ms (the scheduler clamps to ≥1).
- Avoid throwing in normal control flow — HELIX halts a package on an uncaught error during load (e.g. `lib.waitFor` returns
  `nil` on timeout rather than erroring).

## Extending — adding a UI component
1. Add `vox_lib/modules/<name>.lua` that attaches `lib.<fn>` and lazily creates its WebUI on first use.
2. Add `vox_lib/web/<name>/index.html` using `web/_shared/helix-life.css`; read the `{name,args}` envelope on `message` and
   emit results via `hEvent`.
3. Register the module in `vox_lib/package.json` (dependency order).
4. Document it in `docs/developer.md`.

## License
MIT — see [LICENSE](LICENSE). Made by Grizzy / MetaVoxel.
