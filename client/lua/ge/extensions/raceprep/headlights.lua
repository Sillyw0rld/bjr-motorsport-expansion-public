-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Headlights for Automation cars (RacePrep add-on, 1.8.8). Automation exports
-- aim their headlights low, use a 120 degree floodlight cone with no hot spot,
-- a short range (50 / 80 m) and sometimes put "headlights" in the tail-light
-- fixtures, shining backwards. Every Automation car in this game (own and
-- other players') is fixed when it appears: low beam 0.6 deg down, high beam
-- 0.3 deg down, straight ahead, brighter and longer (tuned live at night on
-- the Nordschleife, 2026-10-14); rear-fixture headlights are switched off.
-- Visual only, nothing is synced; the car files are not changed.
local H = {}

-- brightness +20 % over the live-tuned 2.5 / 6 (owner, 2026-10-16: "slightly brighter")
-- cone a bit wider (owner, 2026-10-18): inner 25 -> 32, outer 80 -> 95 degrees
H.LOW = { pitch = -0.6, brightness = 3.0, range = 120, inner = 32, outer = 95 }
H.HIGH = { pitch = -0.3, brightness = 7.2, range = 300, inner = 32, outer = 95 }
H.CHECK_S = 5      -- re-check each car this often (a reset can rebuild the lights)
H.TOLERANCE = 0.3  -- degrees; re-aim when a light drifts further than this
H.SETTLE_S = 1     -- wait this long after a car appears or is rebuilt

local STEP = math.rad(2) -- trial nudge to learn how the rotation moves the beam
local WAIT = 3           -- frames for a new rotation to show in the transform

local cars = {}  -- vehicle id -> {vdata, nextCheck}
local job = nil  -- one car at a time: {id, lights, phase, wait, axis, iter}

local function isAutomation(vdata)
    for _, part in pairs(vdata and vdata.activeParts or {}) do
        if type(part) == "string" and part:find("Camso_", 1, true) then return true end
    end
    return false
end

local function headlightProps(vdata)
    local out = {}
    local props = vdata and vdata.props
    if not props then return out end
    for i = 0, tableSizeC(props) - 1 do
        local p = props[i]
        if p and p.mesh == "SPOTLIGHT" and (p.func == "lowbeam" or p.func == "highbeam") and p.pid then
            out[#out + 1] = p
        end
    end
    return out
end

--- where a light points relative to its car: pitch / yaw in degrees, and
--- whether it sits in the front half (a pure function of the vectors, tested offline)
H.angles = function(dir, pos, fwd, up)
    fwd, up = fwd:normalized(), up:normalized()
    local right = fwd:cross(up):normalized()
    dir = dir:normalized()
    return {
        pitch = math.deg(math.asin(math.max(-1, math.min(1, dir:dot(up))))),
        yaw = math.deg(math.atan2(dir:dot(right), dir:dot(fwd))),
        front = pos:dot(fwd) > 0,
    }
end

local function measure(veh, prop)
    local obj = veh:getProp(prop.pid)
    if not obj then return nil end
    local m = obj:getLiveTransformWorld()
    return H.angles(quat(m:toQuatF()) * vec3(0, 1, 0), vec3(m:getColumn(3)), veh:getDirectionVector(), veh:getDirectionVectorUp())
end

local function colorOf(c)
    if type(c) == "table" then return ColorF((c.r or 255) / 255, (c.g or 255) / 255, (c.b or 255) / 255, (c.a or 255) / 255) end
    return ColorF(1, 1, 1, 1)
end

local function setBeam(obj, prop, spec, brightness)
    local light = obj:getLight()
    if not light then return end
    light:setLightArgs(spec.inner, spec.outer, brightness or spec.brightness, spec.range, colorOf(prop.lightColor),
        prop.lightAttenuation and vec3(prop.lightAttenuation) or vec3(0, 1, 1), prop.lightCastShadows or false)
end

--- minimum-norm rotation change (degrees, 3 axes) that moves (pitch, yaw) by
--- err, from the measured 2x3 response J[axis] = {dPitch, dYaw} per degree
H.solve = function(J, err)
    local a11, a12, a22 = 0, 0, 0
    for i = 1, 3 do
        a11 = a11 + J[i][1] * J[i][1]; a12 = a12 + J[i][1] * J[i][2]; a22 = a22 + J[i][2] * J[i][2]
    end
    local det = a11 * a22 - a12 * a12
    if math.abs(det) < 1e-9 then return nil end
    local y1 = (a22 * err[1] - a12 * err[2]) / det
    local y2 = (a11 * err[2] - a12 * err[1]) / det
    return { J[1][1] * y1 + J[1][2] * y2, J[2][1] * y1 + J[2][2] * y2, J[3][1] * y1 + J[3][2] * y2 }
end

local function axisVec(i, s) return vec3(i == 1 and s or 0, i == 2 and s or 0, i == 3 and s or 0) end

local function startJob(id, veh, vdata)
    local lights = {}
    for _, p in ipairs(headlightProps(vdata)) do
        local obj = veh:getProp(p.pid)
        local a = obj and measure(veh, p)
        if a then
            local spec = p.func == "lowbeam" and H.LOW or H.HIGH
            if a.front then
                setBeam(obj, p, spec)
                local rot = p.baseRotation and vec3(p.baseRotation) or vec3(0, 0, 0)
                obj:setBaseRotation(rot)
                lights[#lights + 1] = { prop = p, rot = rot, target = spec.pitch }
            else
                setBeam(obj, p, spec, 0) -- headlight in a tail-light fixture: off
            end
        end
    end
    if #lights > 0 then job = { id = id, vdata = vdata, lights = lights, phase = "base", wait = WAIT, axis = 0, iter = 0 } end
end

-- Never keep prop objects across frames: a reset, respawn or parts change
-- rebuilds the car and frees them (1.8.8 kept them and could crash the game).
-- Each frame: same car, same build (vdata), props fetched again by id.
local function jobCar()
    local veh = be:getObjectByID(job.id)
    local d = veh and core_vehicle_manager.getVehicleData(job.id)
    if not d or d.vdata ~= job.vdata then return nil end
    return veh
end
local function setRot(veh, l, rot)
    local obj = veh:getProp(l.prop.pid)
    if not obj then return false end
    obj:setBaseRotation(rot)
    return true
end

local function stepJob()
    job.wait = job.wait - 1
    if job.wait > 0 then return end
    job.wait = WAIT
    local veh = jobCar()
    if not veh then job = nil; return end -- car rebuilt or gone: its check will start again
    if job.phase == "base" then
        for _, l in ipairs(job.lights) do l.base = measure(veh, l.prop) end
        job.phase, job.axis = "probe", 1
        for _, l in ipairs(job.lights) do setRot(veh, l, l.rot + axisVec(1, STEP)) end
    elseif job.phase == "probe" then
        for _, l in ipairs(job.lights) do
            local m = measure(veh, l.prop)
            l.J = l.J or {}
            if m and l.base then l.J[job.axis] = { (m.pitch - l.base.pitch) / math.deg(STEP), (m.yaw - l.base.yaw) / math.deg(STEP) } end
        end
        if job.axis < 3 then
            job.axis = job.axis + 1
            for _, l in ipairs(job.lights) do setRot(veh, l, l.rot + axisVec(job.axis, STEP)) end
        else
            job.phase = "step"
            for _, l in ipairs(job.lights) do setRot(veh, l, l.rot) end
        end
    else
        local worst = 0
        for _, l in ipairs(job.lights) do
            local m = measure(veh, l.prop)
            if m and l.J and #l.J == 3 then
                local err = { l.target - m.pitch, -m.yaw }
                worst = math.max(worst, math.abs(err[1]), math.abs(err[2]))
                local d = H.solve(l.J, err)
                if d then
                    l.rot = l.rot + vec3(d[1], d[2], d[3]) * (math.pi / 180)
                    setRot(veh, l, l.rot)
                end
            end
        end
        job.iter = job.iter + 1
        if worst < 0.05 or job.iter >= 6 then job = nil end
    end
end

--- does any front headlight of this car need (re)aiming?
local function needsAim(veh, vdata)
    for _, p in ipairs(headlightProps(vdata)) do
        local a = measure(veh, p)
        if a and a.front then
            local spec = p.func == "lowbeam" and H.LOW or H.HIGH
            if math.abs(a.pitch - spec.pitch) > H.TOLERANCE or math.abs(a.yaw) > H.TOLERANCE then return true end
        end
    end
    return false
end

H.update = function(clock)
    if job then stepJob(); return end
    if not (be and core_vehicle_manager) then return end
    for i = 0, be:getObjectCount() - 1 do
        local veh = be:getObject(i)
        local id = veh and veh:getID()
        local d = id and core_vehicle_manager.getVehicleData(id)
        if d and d.vdata then
            local known = cars[id]
            if not known or known.vdata ~= d.vdata then
                -- new car or rebuilt (reset, parts, config): fix it once it has settled
                cars[id] = { vdata = d.vdata, automation = isAutomation(d.vdata), nextCheck = clock + H.SETTLE_S }
            elseif known.automation and clock >= known.nextCheck then
                known.nextCheck = clock + H.CHECK_S
                if needsAim(veh, d.vdata) then startJob(id, veh, d.vdata); return end
            end
        end
    end
end

return H
