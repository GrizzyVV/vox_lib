# ShowOff post — vox_lib

## Screenshots to grab (in priority order)

1. **A montage of the UI components** *(the money shot)* — notify toast + a context/list menu + the skill-check + radial,
   ideally a few stacked or a quick collage. This is the "whoa, all of this?" thumbnail. The skill-check or radial mid-animation
   reads best.
2. **The native character creator open** *(the "it hooks real systems" shot)* — `lib.openCharacterCreator()` popping HELIX's
   customization UI. Sells that it's wired into engine systems, not just hello-world panels.
3. **A code snippet** *(the "oh that's clean" shot)* — carbon/dark-editor grab of:
   ```lua
   lib.notify({ title = "Saved", type = "success" })
   if lib.alertDialog({ header = "Sell?", content = "Sell for **$12,000**?", cancel = true }) == "confirm" then
       local fields = lib.inputDialog("Sale", { { type = "input", label = "Buyer", required = true } })
   end
   ```

Lead with #1 as the thumbnail; the breadth is the hook.

---

## Blurb (your voice)

> **vox_lib — a free HELIX UI + utility library** 🧩
>
> if you've ported anything from FiveM you know that `lib.*` contract everything leans on — notify, menus, dialogs, progress,
> skill checks. none of it exists natively on HELIX. so i rebuilt it, clean-room, HELIX-native:
>
> - **UI:** notify · textUI · alert · progress bar/circle · input forms · context menu · list menu · skill check · radial
> - **character creator:** open HELIX's native customization UI + actually **save & re-apply** the appearance (the stock flow
>   throws the preset away, so your look dies on respawn — this fixes that)
> - **cinematic:** weather + time-of-day control (with smooth interpolation) + a detached freecam
> - **entities:** one-call `spawnVehicle` / `spawnObject` / `deleteEntity`
> - **+ the foundation:** class, table, array, string, math, cache, timer, callbacks, hooks, locale
>
> every UI piece was verified in-engine, styled in the HELIX-Life look, and it's all driven by one global `lib` table:
>
> ```lua
> lib.notify({ title = "Saved", type = "success" })
> ```
>
> free, MIT, fully documented (full API reference + a "how it works" writeup) 👉 [repo link]
>
> built it while reverse-engineering the runtime, so it comes with a pile of verified-on-build notes too. lmk if you break it 🖤

---

## Shorter alt (if the channel likes it brief)

Made a thing: **[vox_lib](https://github.com/GrizzyVV/vox_lib-HELIX-)** — free HELIX-native UI + utility library, clean-room of the `lib.*` contract FiveM resources expect. notify/menus/dialogs/progress/skillcheck/radial, a character creator with save+reapply appearance, weather/freecam, one-call entity spawning, MIT, fully documented.
```lua
lib.notify({ title = "Saved", type = "success" })
```
👉 https://github.com/GrizzyVV/vox_lib-HELIX-

---

## Posting tips
- Swap `[repo link]` for the GitHub URL.
- Pairs naturally with the vox_sqlite post — "the UI half of the same toolkit."
- If the Discord down-ranks link-leading posts, drop the repo link as a reply.
- The character-creator save/reapply gap is a genuinely useful hook — lead replies with that if people ask "why not just use X."
