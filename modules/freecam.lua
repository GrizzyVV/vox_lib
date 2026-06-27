--[[ vox_lib freecam — detached cinematic free-fly camera (HELIX port of a FiveM cinematic free-cam).
     HELIX's Lua input API is bare (Input.BindKey only — NO mouse-delta/axis), so we can't run a manual mouse-look loop
     the FiveM way. Instead we DRIVE A CAMERA ACTOR ourselves: view-target it, freeze the ped, read the mouse-driven
     control rotation for look (correct pitch — owning the rotation means invert is just a setting), and translate it
     per-tick from tracked movement keys. The player's body stays put = truly detached (vs the native Debug Camera / noclip).

     Verified primitives (probe 2026-06-26): HWorld:SpawnActor(UE.ACameraActor, Transform, AlwaysSpawn);
     HPlayer:SetViewTargetWithBlend / SetIgnoreMoveInput / GetControlledCharacter / GetControlRotation;
     cam:K2_Get/SetActorLocation/Rotation; UE.UKismetMathLibrary.GetForwardVector/GetRightVector; UE.FVector;
     Timer.SetInterval; Input.BindKey(key, fn, 'Pressed'|'Released'). API quirks (key names, blend args) get tuned in-world.

     Controls: WASD move · E/SpaceBar up · Q/LeftControl/C down · LeftShift fast · mouse look.
     API: lib.StartFreeCam(opts?) / lib.StopFreeCam() / lib.ToggleFreeCam(opts?) / lib.IsFreeCamActive()
          opts: { speed?=600, invertY?=false } ]]

local STATE = { active = false, cam = nil, char = nil, host = nil, iv = nil, speed = 600, invertY = false, fast = false }
local held = {}        -- movement keys currently down
local _bound = false

-- movement key → (axis, sign): f=forward, r=right, u=up(world)
local MOVE_KEYS = {
    W = { "f", 1 }, S = { "f", -1 }, D = { "r", 1 }, A = { "r", -1 },
    E = { "u", 1 }, SpaceBar = { "u", 1 }, Q = { "u", -1 }, LeftControl = { "u", -1 }, C = { "u", -1 },
}

local function bindKeys()
    if _bound or not (Input and Input.BindKey) then return end
    _bound = true
    for key in pairs(MOVE_KEYS) do
        pcall(function() Input.BindKey(key, function() if STATE.active then held[key] = true end end, "Pressed") end)
        pcall(function() Input.BindKey(key, function() held[key] = nil end, "Released") end)
    end
    pcall(function() Input.BindKey("LeftShift", function() STATE.fast = true end, "Pressed") end)
    pcall(function() Input.BindKey("LeftShift", function() STATE.fast = false end, "Released") end)
    -- mouse-wheel speed (key names tentative — tune in-world if they don't fire)
    pcall(function() Input.BindKey("MouseScrollUp", function() if STATE.active then STATE.speed = math.min(6000, STATE.speed + 150) end end, "Pressed") end)
    pcall(function() Input.BindKey("MouseScrollDown", function() if STATE.active then STATE.speed = math.max(60, STATE.speed - 150) end end, "Pressed") end)
    -- Backspace exits the freecam (alongside the /freecam command). Only acts while the cam is active.
    pcall(function() Input.BindKey("BackSpace", function() if STATE.active and lib.StopFreeCam then lib.StopFreeCam() end end, "Pressed") end)
end

local function tick()
    if not STATE.active or not STATE.cam then return end
    -- LOOK: control rotation is mouse-driven (correct pitch). invertY flips it (spectator-host inverts pitch).
    local rot
    pcall(function() rot = HPlayer:GetControlRotation() end)
    if not rot then return end
    if STATE.invertY then pcall(function() rot.Pitch = -rot.Pitch end) end
    local loc
    pcall(function() loc = STATE.cam:K2_GetActorLocation() end)
    if not loc then return end
    -- MOVE: sum held movement keys into forward/right/up, in the look direction so forward = where you see
    local mf, mr, mu = 0, 0, 0
    for key in pairs(held) do
        local m = MOVE_KEYS[key]
        if m then
            if m[1] == "f" then mf = mf + m[2] elseif m[1] == "r" then mr = mr + m[2] else mu = mu + m[2] end
        end
    end
    if mf ~= 0 or mr ~= 0 or mu ~= 0 then
        local fwd, rgt
        pcall(function() fwd = UE.UKismetMathLibrary.GetForwardVector(rot) end)
        pcall(function() rgt = UE.UKismetMathLibrary.GetRightVector(rot) end)
        if fwd and rgt then
            local sp = STATE.speed * (STATE.fast and 3 or 1) * 0.016   -- units per tick (~16ms)
            loc = UE.FVector(loc.X + (fwd.X * mf + rgt.X * mr) * sp,
                             loc.Y + (fwd.Y * mf + rgt.Y * mr) * sp,
                             loc.Z + (fwd.Z * mf + rgt.Z * mr) * sp + (mu * sp))   -- vertical = world up
        end
    end
    -- K2_TeleportTo sets BOTH position and rotation in one call — no sweep/FHitResult args (probe-verified clean).
    pcall(function() STATE.cam:K2_TeleportTo(loc, rot) end)
end

function lib.StartFreeCam(opts)
    if STATE.active then return { ok = true, already = true } end
    if not (HPlayer and HWorld and UE and Timer) then return { ok = false, error = "camera API unavailable" } end
    opts = type(opts) == "table" and opts or {}
    STATE.char = HPlayer:GetControlledCharacter()
    STATE.speed = tonumber(opts.speed) or 600
    -- default invertY=TRUE: possessing the spectator host flips the control-rotation pitch, so we negate it to make
    -- up=up. (probe-confirmed 2026-06-26: char-possess = correct, spectator-host-possess = inverted.) opts.invertY overrides.
    STATE.invertY = (opts.invertY == nil) and true or (opts.invertY and true or false)
    -- spawn the camera at the player, facing the current look direction
    local t = Transform()
    pcall(function() t.Translation = STATE.char:K2_GetActorLocation() end)
    local r; pcall(function() r = HPlayer:GetControlRotation() end)
    if r then pcall(function() t.Rotation = r:ToQuat() end) end
    -- Possess a do-nothing HOST pawn so the CHARACTER stops receiving gameplay input (otherwise Space=jump, C=crouch,
    -- Q=grenade still fire — SetIgnoreMoveInput only blocks movement axes, not ability inputs). The character is left
    -- standing where it was = truly detached. We never VIEW the host; we view our own camera actor and drive it from the
    -- (correct-pitch) control rotation. Host frozen so it doesn't drift.
    local host
    pcall(function() host = HWorld:SpawnActor(UE.ASpectatorPawn, t, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn) end)
    if host then
        STATE.host = host
        pcall(function() HPlayer:Possess(host) end)
    end
    pcall(function() HPlayer:SetIgnoreMoveInput(true) end)
    local cam
    local ok = pcall(function() cam = HWorld:SpawnActor(UE.ACameraActor, t, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn) end)
    if not ok or not cam then return { ok = false, error = "camera spawn failed" } end
    STATE.cam = cam
    -- full 5-arg form (target, BlendTime, BlendFunc, BlendExp, bLockOutgoing) — verified from real HELIX code (hl-vehicleshop)
    pcall(function() HPlayer:SetViewTargetWithBlend(cam, 0.4, 0, 0.0, false) end)
    bindKeys()
    held, STATE.fast = {}, false
    STATE.active = true
    STATE.iv = Timer.SetInterval(tick, 16)
    if lib.ShowFreeCamHelp then pcall(lib.ShowFreeCamHelp) end
    return { ok = true }
end

function lib.StopFreeCam()
    if not STATE.active then return { ok = true } end
    STATE.active = false
    if STATE.iv then
        pcall(function() if Timer.ClearInterval then Timer.ClearInterval(STATE.iv) end end)
        STATE.iv = nil
    end
    pcall(function() HPlayer:SetIgnoreMoveInput(false) end)
    if STATE.char then pcall(function() HPlayer:Possess(STATE.char) end) end          -- give control back to the character
    if STATE.char then pcall(function() HPlayer:SetViewTargetWithBlend(STATE.char, 0.4, 0, 0.0, false) end) end
    if STATE.cam then pcall(function() STATE.cam:K2_DestroyActor() end) end
    if STATE.host then pcall(function() STATE.host:K2_DestroyActor() end) end
    STATE.cam, STATE.host, held, STATE.fast = nil, nil, {}, false
    if lib.HideFreeCamHelp then pcall(lib.HideFreeCamHelp) end
    return { ok = true }
end

function lib.ToggleFreeCam(opts)
    if STATE.active then return lib.StopFreeCam() else return lib.StartFreeCam(opts) end
end

function lib.IsFreeCamActive() return STATE.active end

return lib.StartFreeCam
