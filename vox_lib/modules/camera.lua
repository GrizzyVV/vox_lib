--[[ lib.camera — scripted / cutscene camera over HELIX's camera-actor + view-target pattern (the freecam-verified path).
     CLIENT-SIDE. A scripted cam = an `ACameraActor` you position + aim, then make the player controller VIEW it via
     `SetViewTargetWithBlend`; `renderScriptCams(false)` blends back to the pawn. One active scripted cam at a time (FiveM-style).
     Covers the FiveM scripted-camera family: CreateCam / SetCamCoord / SetCamRot / PointCamAt(Coord|Entity) / RenderScriptCams /
     DestroyCam. Follows the in-engine-VERIFIED freecam primitives (SetViewTargetWithBlend 5-arg, ACameraActor, K2_TeleportTo);
     visually smoke-test before relying on it in a cutscene. ]]

local _cam   -- the active scripted ACameraActor
local function controller() return HPlayer end
-- args-constructor form — see entity.lua toVector note (Vector()+`.X=` does NOT persist on table input → NaN/zero).
local function toV(c)
    if type(c) == "userdata" then return c end
    if not c then return Vector(0, 0, 0) end
    return Vector(c.x or c.X or c[1] or 0, c.y or c.Y or c[2] or 0, c.z or c.Z or c[3] or 0)
end
local function toR(r)
    if type(r) == "userdata" then return r end
    if type(r) == "number" then return Rotator(0, r, 0) end
    if not r then return Rotator(0, 0, 0) end
    return Rotator(r.pitch or r.Pitch or 0, r.yaw or r.Yaw or 0, r.roll or r.Roll or 0)
end

-- CreateCam / CreateCamWithParams: spawn a scripted camera actor. Returns it (also stored as the active cam).
-- Uses the freecam-VERIFIED form: HWorld:SpawnActor(ACameraActor, Transform, AlwaysSpawn), spawned with an IDENTITY
-- (normalized) rotation. The (cls, vector, rotator) overload is AVOIDED: in-engine 2026-06-30 it reached SpawnActor with
-- a non-normalized rotation quaternion and HARD-CRASHED the client (Assertion IsRotationNormalized — a C++ crash pcall
-- can't catch). Orient the cam AFTER spawn via setCamRot / pointCamAt (those go through valid-rotation paths).
function lib.createCam(coords, rot)
    if not (HWorld and UE and UE.ACameraActor) then return nil end
    local cam
    pcall(function()
        local t = Transform()
        t.Translation = toV(coords)                 -- userdata assignment (safe); rotation left identity = normalized
        cam = HWorld:SpawnActor(UE.ACameraActor, t, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn)
    end)
    _cam = cam or _cam
    if cam and rot ~= nil then lib.setCamRot(rot, cam) end
    return cam
end

-- SetCamCoord / SetCamRot (default to the active cam).
function lib.setCamCoord(coords, cam) cam = cam or _cam; return cam and pcall(function() cam:K2_TeleportTo(toV(coords), cam:K2_GetActorRotation()) end) end
function lib.setCamRot(rot, cam)       cam = cam or _cam; return cam and pcall(function() cam:K2_SetActorRotation(toR(rot), false) end) end

-- PointCamAtCoord / PointCamAtEntity: aim the cam at a world point or an actor's location.
function lib.pointCamAt(target, cam)
    cam = cam or _cam; if not cam then return false end
    return pcall(function()
        local tloc = (type(target) == "userdata" and target.K2_GetActorLocation) and target:K2_GetActorLocation() or toV(target)
        cam:K2_SetActorRotation(UE.UKismetMathLibrary.FindLookAtRotation(cam:K2_GetActorLocation(), tloc), false)
    end)
end

-- RenderScriptCams(true): view the scripted cam. (false): blend back to the pawn. blendTime in seconds (0 = instant).
function lib.renderScriptCams(on, blendTime, cam)
    local pc = controller(); if not pc then return false end
    blendTime = blendTime or 0
    if on == false then
        local pawn = GetPlayerPawn and GetPlayerPawn(pc)
        return pcall(function() pc:SetViewTargetWithBlend(pawn, blendTime, 0, 0, false) end)   -- 5 args required
    end
    cam = cam or _cam; if not cam then return false end
    return pcall(function() pc:SetViewTargetWithBlend(cam, blendTime, 0, 0, false) end)
end

-- DestroyCam: blend back to the pawn (if this was the active cam) and destroy the actor.
function lib.destroyCam(cam)
    cam = cam or _cam
    if cam == _cam then pcall(function() lib.renderScriptCams(false, 0) end); _cam = nil end
    return cam and pcall(function() cam:K2_DestroyActor() end)
end
