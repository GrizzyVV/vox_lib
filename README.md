# vox_lib

A free, **HELIX-native UI + utility library** for HELIX servers — a clean-room equivalent of the `lib.*` contract that
FiveM resources expect. Notifications, text UI, dialogs, menus, progress, skill checks, a radial, plus weather/time control
and a cinematic freecam — all styled for HELIX and driven by a single global `lib` table.

> Verified on HELIX (UE 5.7.4 / Lua 5.4). Clean-room from the public ox_lib API docs only — **no ox_lib source was read.**

## What's in it

| Group | Surface |
|---|---|
| **UI** | `notify` · `showTextUI/hideTextUI` · `alertDialog` · `progressBar/progressCircle` · `inputDialog` · context menu · list menu · `skillCheck` · radial menu |
| **Cinematic** | weather (`SetWeather`/`SetCinematicSky`) · time (`SetTime`/`InterpolateTime`) · freecam (`StartFreeCam`/`ToggleFreeCam`) |
| **Character** | character creator (`openCharacterCreator`) + appearance capture/persist/reapply (`getAppearance`/`applyAppearance`) over HELIX's native cosmetics |
| **Entities** | one-call spawning — `spawnVehicle` · `spawnObject` · `deleteEntity` (packages `HVehicle`/`SpawnActor`/`K2_DestroyActor`) |
| **Foundation** | `lib.class` · `lib.table` · `lib.array` · `lib.string` · `lib.math` · `lib.cache` · `lib.print` · `lib.locale` · `lib.timer` · `lib.waitFor` · `lib.callback` · `lib.hook` |

## How it loads (read this first)

HELIX packages are **sandboxed Lua states — functions don't cross the package boundary.** So vox_lib is **not** an `exports`
resource like a database service; you can't `exports['vox_lib']:notify()` from another package. There are two supported ways to
use it, and both end with `lib.*` living **inside your own package's state**:

**A) Standalone package** — drop `vox_lib/` into `scripts/` and list it in `config.json`. It loads as a complete, self-contained
library (including its own optional scheduler). Best for a single-package project or a demo world.

```json
{ "packages": ["vox_lib", "your_resource"] }
```

**B) Source-bundled** — copy the `modules/` (and `web/`) files into **your** package and list them in **your** `package.json`
in dependency order (handy when a build pipeline emits a single package). The host then provides the scheduler, so you can omit
`modules/scheduler.lua`.

Either way, `init.lua` must load first (it creates `lib`), then `modules/class.lua`, then the rest — see
[`package.json`](package.json) for the canonical order.

## Quick start

```lua
-- notifications
lib.notify({ title = "Saved", description = "Your vehicle was stored.", type = "success" })

-- a persistent prompt
lib.showTextUI("[E] Open trunk", { icon = "box" })
lib.hideTextUI()

-- return-value dialogs (call from inside a thread — they yield)
CreateThread(function()
    if lib.alertDialog({ header = "Sell?", content = "Sell this car for **$12,000**?", cancel = true }) == "confirm" then
        local fields = lib.inputDialog("Sale", {
            { type = "input",  label = "Buyer",  required = true },
            { type = "number", label = "Price",  default = 12000 },
        })
        if fields then print(fields[1], fields[2]) end
    end
end)

-- progress (returns true if it completed, false if cancelled)
CreateThread(function()
    if lib.progressBar({ duration = 4000, label = "Searching…", canCancel = true }) then
        lib.notify({ title = "Done", type = "success" })
    end
end)

-- weather + time
lib.SetWeather("Rain", 8)        -- ease into Rain over 8s
lib.InterpolateTime(2200, 6)     -- ease the clock to 22:00 over 6s
```

See **[`docs/developer.md`](docs/developer.md)** for the complete API (every function, every option).

## Styling

The WebUI components ship a single shared theme — `web/_shared/helix-life.css` (the "HELIX-Life" kit: red `#F0454E`,
Tomorrow/Anton type, dark translucent panels). Restyle once there and every component follows.

## Layout

- `init.lua` — creates the global `lib` table (**load first**)
- `modules/` — the Lua modules (each attaches itself to `lib`)
- `web/` — the WebUI pages for the visual components (`web/_shared/helix-life.css` = shared style)
- `dev/` — **dev-only** sandboxes & the in-engine test harness (not part of a production build)
- `design/`, `design-divergent/` — static UI design references

## Docs

- **[`docs/developer.md`](docs/developer.md)** — full `lib.*` API reference, options, and examples.
- **[`docs/tech.md`](docs/tech.md)** — how it works: the source-bundle model, the WebUI reverse channel, the scheduler, and the
  HELIX constraints it solves.

## License

MIT — see [LICENSE](LICENSE). Free to use, modify, and ship. Made by Grizzy / MetaVoxel. 🖤
