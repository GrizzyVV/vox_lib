--[[ lib.playAnim / lib.stopAnim — play a montage animation on a pawn, with optional eased BLEND between animations.

     ⚠️ EXPERIMENTAL — NOT VISUALLY VERIFIED (2026-06-27). Animation.Play returns success but no visible animation was observed
     on a pawn when a human watched. The wrapper mirrors hl-emotes' usage and the FHPlayAnimParams blend fields are
     probe-confirmed to exist, but actual on-pawn playback is unresolved (likely a slot / anim-BP / player-pawn detail). Don't
     rely on this rendering until confirmed in-world.

     Built on the probe-verified HELIX `Animation` global: Animation.Play(pawn, animAssetPath, UE.FHPlayAnimParams, onDone) ->
     success ; Animation.Stop(pawn). CLIENT-side (animation is local render).

     ANIM INTERPOLATION / BLENDING (PROBE-CONFIRMED 2026-06-27): UE montages crossfade from the current pose to the new
     animation over a blend duration, and playing a new montage on the SAME slot blends out the previous one. So transitioning
     anim A -> anim B is smooth when blendIn/blendOut are set. `FHPlayAnimParams` fields confirmed on the current build:
     LoopCount, AnimSlotName, BlendInTime, BlendOutTime, PlayRate (all numbers/strings). Parametric blend-spaces (walk<->run by
     speed) are a separate anim-BP mechanism, not exposed here. ]]

local _playing = {}   -- pawn -> last anim path (best-effort tracking; HELIX has no GetPlayingAnim readback)

-- pawn: the character/pawn to animate. animPath: the animation asset path.
-- opts: { loop = bool, slot = "FullBody"|"UpperBody" (default "FullBody"), blendIn = sec, blendOut = sec, playRate = number,
--         onComplete = function }  -> returns { ok, value=success } (the result of Animation.Play).
--   blendIn/blendOut crossfade the transition (smooth A->B); playRate scales speed (1 = normal).
function lib.playAnim(pawn, animPath, opts)
    if not pawn then return { ok = false, error = "pawn required" } end
    if type(animPath) ~= "string" or animPath == "" then return { ok = false, error = "animPath (asset path) required" } end
    if type(Animation) ~= "table" or type(Animation.Play) ~= "function" then
        return { ok = false, error = "Animation API unavailable on this side/build" }
    end
    opts = opts or {}
    local params
    local okp = pcall(function() params = UE.FHPlayAnimParams() end)
    if not okp or not params then return { ok = false, error = "FHPlayAnimParams unavailable" } end
    pcall(function() params.LoopCount = opts.loop and -1 or 1 end)
    pcall(function() params.AnimSlotName = opts.slot or "FullBody" end)
    -- BLEND fields PROBE-CONFIRMED 2026-06-27: FHPlayAnimParams has BlendInTime / BlendOutTime / PlayRate (all numbers, seconds).
    -- Setting blendIn/blendOut crossfades the transition FROM the current pose/anim TO this one (smooth A->B).
    if opts.blendIn ~= nil then pcall(function() params.BlendInTime = opts.blendIn end) end
    if opts.blendOut ~= nil then pcall(function() params.BlendOutTime = opts.blendOut end) end
    if opts.playRate ~= nil then pcall(function() params.PlayRate = opts.playRate end) end
    local success
    local ok = pcall(function()
        success = Animation.Play(pawn, animPath, params, function()
            _playing[pawn] = nil
            if opts.onComplete then pcall(opts.onComplete) end
        end)
    end)
    if not ok then return { ok = false, error = "Animation.Play failed" } end
    _playing[pawn] = animPath
    return { ok = true, value = success }
end

-- Stop the current animation on a pawn (blends back to the base pose). opts reserved for future blend-out control.
function lib.stopAnim(pawn, _opts)
    if not pawn then return { ok = false, error = "pawn required" } end
    if type(Animation) ~= "table" or type(Animation.Stop) ~= "function" then
        return { ok = false, error = "Animation API unavailable" }
    end
    local ok = pcall(function() Animation.Stop(pawn) end)
    _playing[pawn] = nil
    return ok and { ok = true } or { ok = false, error = "Animation.Stop failed" }
end

-- best-effort: the last anim path we started on this pawn (nil once it completes / is stopped). Not an engine readback.
function lib.getPlayingAnim(pawn) return _playing[pawn] end

return lib.playAnim
