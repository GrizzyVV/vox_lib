# vox_lib (HELIX)

A HELIX-native Lua library for [HELIX](https://helixgame.com) resources — built ground-up for HELIX's runtime.

Two layers:

- **ox_lib-compatible surface** — a clean-room implementation of the common `lib.*` contract (notify, textUI,
  alertDialog, progressBar/Circle, inputDialog, context menu, skillCheck, callbacks, hooks, and the class/table/
  array/string/math/cache/locale/timer utilities), so HELIX resources written against that contract work. Built
  from the public API contract only.
- **World / camera capability verbs** — HELIX-native cinematic tooling: weather + time-of-day control (`Sky()`),
  a detached free-camera, entity/asset helpers.

UI is styled in HELIX's "HELIX-Life" visual language.

## Layout
- `init.lua` — creates the global `lib` table (load first)
- `modules/` — the Lua modules (each attaches to `lib`)
- `web/` — the WebUI pages for the UI components (`web/_shared/helix-life.css` = shared style)
- `dev/` — dev sandboxes (`/weather`, `/freecam`)
- `design/`, `design-divergent/` — UI design references

## Status
In active development. The non-UI foundation + several UI components are probe-verified on HELIX; the remaining
components are built and pending an in-engine verification pass.

## License
TODO — to be set by the maintainer.
