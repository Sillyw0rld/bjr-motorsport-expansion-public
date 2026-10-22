-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Lap timing for practice and qualifying sessions (free roam, outside a
-- BeamJoy race), from a BeamJoy race's checkpoints.
--
-- Gates work like BeamJoy's own (RaceWaypointManager): a checkpoint is a
-- segment of half-width `radius` across the track, perpendicular to the
-- checkpoint's forward vector (rot * (0,-1,0)), from 1 m below to 2 x radius
-- above its position. A gate is passed when the car's movement since the last
-- update crosses that segment (either direction); the crossing time is
-- interpolated along the movement.
--
-- A lap is BeamJoy's lap: it ends at the race's last step. The first crossing
-- of the last step starts timing (out-lap before it). A lap counts when every
-- step was passed in order; reaching the line with a step missed discards the
-- lap and starts a new one. A reset/teleport (jump of more than JUMP_M in
-- one update) voids the lap in progress. Track-limit cuts mark the lap
-- invalid (it is still timed and shown, but does not count as a best lap).
--
-- Plain Lua (tables for vectors), so it runs in the game and in tests.

local L = {}

L.JUMP_M = 60
L.MIN_LAP_MS = 10000

local function v(p)
    if type(p) ~= "table" then return nil end
    local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

-- forward vector of a quaternion: rot * (0,-1,0)
L.forward = function(q)
    local x, y, z, w = tonumber(q.x) or 0, tonumber(q.y) or 0, tonumber(q.z) or 0, tonumber(q.w) or 1
    -- rotate (0,-1,0): column 2 of the rotation matrix, negated
    local fx = -(2 * (x * y - w * z))
    local fy = -(1 - 2 * (x * x + z * z))
    local fz = -(2 * (y * z + w * x))
    local len = math.sqrt(fx * fx + fy * fy + fz * fz)
    if len < 1e-9 then return { x = 0, y = -1, z = 0 } end
    return { x = fx / len, y = fy / len, z = fz / len }
end

local function gate(wp)
    local pos = v(wp.pos)
    local radius = tonumber(wp.radius) or 1
    if not pos then return nil end
    local f = v(wp.dir) or (wp.rot and L.forward(wp.rot)) or { x = 0, y = -1, z = 0 }
    -- right = forward x up(0,0,1) = (fy, -fx, 0)
    local rx, ry = f.y, -f.x
    local len = math.sqrt(rx * rx + ry * ry)
    if len < 1e-9 then rx, ry, len = 1, 0, 1 end
    rx, ry = rx / len, ry / len
    return {
        a = { x = pos.x - rx * radius, y = pos.y - ry * radius },
        b = { x = pos.x + rx * radius, y = pos.y + ry * radius },
        zMin = pos.z - (tonumber(wp.zOffset) or 1) - 2.5, -- car height margin
        zMax = pos.z + (tonumber(wp.height) or radius * 2),
        name = wp.name,
    }
end

--- steps: BeamJoy race steps (array of steps, each an array of alternative
--- waypoints {pos, rot, radius, ...})
L.buildGates = function(steps)
    local out = {}
    for _, step in ipairs(type(steps) == "table" and steps or {}) do
        local alts = {}
        for _, wp in ipairs(type(step) == "table" and step or {}) do
            local g = type(wp) == "table" and gate(wp)
            if g then table.insert(alts, g) end
        end
        if #alts > 0 then table.insert(out, alts) end
    end
    return out
end

-- fraction t in [0,1] along p0->p1 where it crosses segment a-b (2D), or nil
local function crossFraction(p0, p1, a, b)
    local rx, ry = p1.x - p0.x, p1.y - p0.y
    local sx, sy = b.x - a.x, b.y - a.y
    local denom = rx * sy - ry * sx
    if math.abs(denom) < 1e-12 then return nil end
    local qx, qy = a.x - p0.x, a.y - p0.y
    local t = (qx * sy - qy * sx) / denom
    local u = (qx * ry - qy * rx) / denom
    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return t end
    return nil
end

local function crossesStep(alts, p0, p1)
    for _, g in ipairs(alts) do
        local t = crossFraction(p0, p1, g.a, g.b)
        if t then
            local z = p0.z + (p1.z - p0.z) * t
            if z >= g.zMin and z <= g.zMax then return t end
        end
    end
    return nil
end

local Tracker = {}
Tracker.__index = Tracker

--- new tracker for one car
L.new = function(steps)
    local self = setmetatable({}, Tracker)
    self.gates = L.buildGates(steps)
    local first, last = self.gates[1] and self.gates[1][1], self.gates[#self.gates] and self.gates[#self.gates][1]
    if #self.gates > 1 and first and last then
        local dx = (first.a.x + first.b.x - last.a.x - last.b.x) / 2
        local dy = (first.a.y + first.b.y - last.a.y - last.b.y) / 2
        self.sharedLine = dx*dx + dy*dy <= 9
    end
    local offset = self.sharedLine and 1 or 0
    local count = #self.gates - offset
    if count >= 3 then
        self.sectorBounds = {offset + math.max(1, math.floor(count / 3 + 0.5)),
            offset + math.max(2, math.floor(2 * count / 3 + 0.5))}
    end
    self.state = "out" -- "out" (before the first line crossing) | "lap"
    self.next = 1      -- next step expected during a lap
    self.lapStart = nil
    self.lapNo = 0
    self.cuts = 0      -- cuts in the lap in progress
    self.void = nil    -- reason the lap in progress cannot count ("reset")
    self.splits = {}   -- ms at each step of the lap in progress
    self.prev = nil
    self.prevT = nil
    return self
end

function Tracker:valid()
    return #self.gates > 0
end

--- the lap in progress gets a track-limits cut
function Tracker:cut()
    if self.state == "lap" then
        self.cuts = self.cuts + 1
    end
end

function Tracker:startLap(t)
    self.lapDist = 0
    self.state = "lap"
    self.next = 1
    self.lapStart = t
    self.cuts = 0
    self.void = nil
    self.splits = {}
    self.lapNo = self.lapNo + 1
end

--- feed the car position at time t (ms). Returns a completed lap or nil:
--- { lap, time, valid, cuts, void, splits }, or { lap, incomplete = true }
function Tracker:update(t, pos)
    pos = v(pos)
    if not pos or #self.gates == 0 then return nil end
    local p0, t0 = self.prev, self.prevT
    self.prev, self.prevT = pos, t
    if not p0 then return nil end
    local dx, dy, dz = pos.x - p0.x, pos.y - p0.y, pos.z - p0.z
    if dx * dx + dy * dy + dz * dz > L.JUMP_M * L.JUMP_M then
        if self.state == "lap" then self.void = "reset" end
        return nil
    end
    self.lapDist = (self.lapDist or 0) + math.sqrt(dx * dx + dy * dy + dz * dz)
    local n = #self.gates
    local result
    -- the finish line (last step)
    local ft = crossesStep(self.gates[n], p0, pos)
    if self.state == "lap" and n > 1 then
        local st = self.next < n and crossesStep(self.gates[self.next], p0, pos)
        if st then
            self.splits[self.next] = t0 + (t - t0) * st - self.lapStart
            self.next = self.next + 1
        end
    end
    if ft then
        local at = t0 + (t - t0) * ft
        if self.state == "lap" then
            local time = at - self.lapStart
            if time < L.MIN_LAP_MS then
                return nil -- wiggling on the line
            end
            if self.next >= n or n == 1 then
                result = { lap = self.lapNo, time = math.floor(time + 0.5), cuts = self.cuts, void = self.void,
                    splits = self.splits, distance = math.floor(self.lapDist or 0) }
                result.valid = self.cuts == 0 and not self.void
            else
                result = { lap = self.lapNo, incomplete = true, missed = self.next }
            end
        end
        self:startLap(at)
        -- Some BeamJoy circuits put step 1 on the finish line. The same
        -- crossing starts the new lap and satisfies that first checkpoint.
        local first = n > 1 and crossesStep(self.gates[1], p0, pos)
        if self.sharedLine or (first and math.abs(first - ft) * math.sqrt(dx*dx + dy*dy + dz*dz) <= 3) then
            self.next, self.splits[1] = 2, 0
        end
    end
    return result
end

--- Three sectors at checkpoint boundaries, all belonging to this lap.
--- A checkpoint overlapping the start/finish is not an intermediate split.
function Tracker:sectorTimes(lap)
    if not self.sectorBounds or not lap or not lap.splits then return nil end
    local a = tonumber(lap.splits[self.sectorBounds[1]])
    local b = tonumber(lap.splits[self.sectorBounds[2]])
    local total = tonumber(lap.time)
    if not a or not b or not total or a ~= a or b ~= b then return nil end
    a, b = math.floor(a + 0.5), math.floor(b + 0.5)
    if a <= 0 or b <= a or total <= b then return nil end
    return {a, b - a, total - b}
end

--- ms into the lap in progress, or nil on the out-lap
function Tracker:current(t)
    if self.state == "lap" and self.lapStart then
        return t - self.lapStart
    end
end

return L
