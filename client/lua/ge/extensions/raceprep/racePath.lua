-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race path for the timing: the line cars actually drive between checkpoints.
--
-- BeamJoy races only store checkpoint positions, and a straight line between
-- two checkpoints is much shorter than the road on a curvy section, so gaps in
-- metres were wrong there. Each driver's game records its own car's line
-- between consecutive checkpoints during the race (a point every few metres)
-- and keeps it per race layout (BeamJoy's race hash). Later races on that
-- layout measure every car's progress along the recorded line. Segments not
-- recorded yet fall back to the straight line.
--
-- Segment keys: "start" = grid to checkpoint 1 (first lap), "1".."n" =
-- checkpoint k-1 to checkpoint k on later laps ("1" starts at the finish
-- line). Points are plain {x, y, z} tables.

local P = {}

local SAMPLE_M = 4          -- record a point every 4 m
local JUMP_M = 40           -- a bigger jump between samples is a reset/teleport
local SAVE_DIR = "settings/raceprep/paths/"

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
P.dist = dist

local function pt(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function polyLength(points)
    local len = 0
    for i = 2, #points do
        len = len + dist(points[i - 1], points[i])
    end
    return len
end

--- new path state for a race layout
---@param raceHash string?
---@param checkpoints table<integer, {x,y,z}> checkpoint positions, index 1..wpPerLap
---@param start {x,y,z}? first grid slot
---@param wpPerLap integer
P.new = function(raceHash, checkpoints, start, wpPerLap)
    local self = {
        hash = raceHash,
        wpPerLap = wpPerLap,
        cps = checkpoints,
        start = start,
        segments = {}, -- key -> {points = {...}, cum = {...}, length}
        recording = nil,
        dirty = false,
    }
    if raceHash and type(jsonReadFile) == "function" then
        local saved = jsonReadFile(SAVE_DIR .. tostring(raceHash) .. ".json")
        if type(saved) == "table" and type(saved.segments) == "table" then
            for key, points in pairs(saved.segments) do
                P.setSegment(self, key, points)
            end
        end
    end
    return self
end

P.setSegment = function(self, key, points)
    if type(points) ~= "table" or #points < 2 then
        return
    end
    local cum = { 0 }
    for i = 2, #points do
        cum[i] = cum[i - 1] + dist(points[i - 1], points[i])
    end
    self.segments[tostring(key)] = { points = points, cum = cum, length = cum[#cum] }
end

--- endpoints of a segment: from checkpoint k-1 (finish line for k = 1,
--- grid for "start") to checkpoint k
local function segmentEnds(self, key)
    if key == "start" then
        return self.start or self.cps[1], self.cps[1]
    end
    local k = tonumber(key)
    local from = k == 1 and self.cps[self.wpPerLap] or self.cps[k - 1]
    return from or self.start, self.cps[k]
end

--- (lap, wp) with "passed the last checkpoint of lap L" as "lap L+1, wp 0"
local function normalise(self, lap, wp)
    lap, wp = math.max(1, lap or 1), math.max(0, wp or 0)
    while wp >= self.wpPerLap do
        lap, wp = lap + 1, wp - self.wpPerLap
    end
    return lap, wp
end

--- segment key the car is on after passing checkpoint `wp` (0..wpPerLap) on `lap`
P.keyAfter = function(self, lap, wp)
    lap, wp = normalise(self, lap, wp)
    if lap <= 1 and wp == 0 then
        return "start"
    end
    return tostring(wp + 1)
end

--- distance along a segment for position p (recorded line, or the straight
--- line), and the distance from the line
local function along(self, key, p)
    local seg = self.segments[key]
    if seg then
        local best, bestD, bestAlong = nil, math.huge, 0
        local pts, cum = seg.points, seg.cum
        for i = 2, #pts do
            local a, b = pts[i - 1], pts[i]
            local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
            local len2 = abx * abx + aby * aby + abz * abz
            local t = 0
            if len2 > 1e-6 then
                t = ((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / len2
                t = math.max(0, math.min(1, t))
            end
            local q = { x = a.x + abx * t, y = a.y + aby * t, z = a.z + abz * t }
            local d = dist(p, q)
            if d < bestD then
                bestD, best = d, i
                bestAlong = cum[i - 1] + t * math.sqrt(len2)
            end
        end
        return bestAlong, bestD, seg.length
    end
    local a, b = segmentEnds(self, key)
    if not a or not b then
        return 0, math.huge, 0
    end
    local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
    local len2 = abx * abx + aby * aby + abz * abz
    if len2 < 1e-6 then
        return 0, dist(p, a), 0
    end
    local t = math.max(0, math.min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / len2))
    local q = { x = a.x + abx * t, y = a.y + aby * t, z = a.z + abz * t }
    return t * math.sqrt(len2), dist(p, q), math.sqrt(len2)
end

local function segLength(self, key)
    local seg = self.segments[key]
    if seg then
        return seg.length
    end
    local a, b = segmentEnds(self, key)
    return (a and b) and dist(a, b) or 0
end

--- distance from the race start to the start of each lap segment, and the lap length
local function lapTable(self)
    if self.lapCache and self.lapCacheVersion == self.version then
        return self.lapCache
    end
    local startOf = {}
    local cum = 0
    for k = 1, self.wpPerLap do
        startOf[k] = cum
        cum = cum + segLength(self, tostring(k))
    end
    local firstLapExtra = segLength(self, "start") - segLength(self, "1")
    self.lapCache = { startOf = startOf, lapLength = cum, firstLapExtra = firstLapExtra }
    self.lapCacheVersion = self.version
    return self.lapCache
end

--- distance from the start of lap `lap` to position d along segment `key`
local function inLap(self, key, d)
    if key == "start" then
        -- the grid can sit before the finish line: measure from checkpoint 1 back
        return d - (segLength(self, "start") - segLength(self, "1"))
    end
    return lapTable(self).startOf[tonumber(key)] + d
end

--- total distance driven since the start, for a car at position p that last
--- passed checkpoint `wp` of lap `lap`. Near the end of its segment the next
--- segment is tried too (the leaderboard can lag a checkpoint behind).
P.progress = function(self, lap, wp, p)
    lap, wp = normalise(self, lap, wp)
    local lapLen = lapTable(self).lapLength
    local key = P.keyAfter(self, lap, wp)
    local d, off, len = along(self, key, p)
    local best = (lap - 1) * lapLen + inLap(self, key, d)
    if len > 0 and d >= len - 1 then
        local lap2, wp2 = normalise(self, lap, wp + 1)
        local key2 = P.keyAfter(self, lap2, wp2)
        local d2, off2 = along(self, key2, p)
        if off2 < off then
            best = (lap2 - 1) * lapLen + inLap(self, key2, d2)
        end
    end
    return best
end

P.lapLength = function(self)
    return lapTable(self).lapLength
end

---------------------------------------------------------------- recording

--- feed the driver's own car: position and the checkpoint just passed
P.record = function(self, lap, wp, pos)
    local key = P.keyAfter(self, lap, wp)
    local rec = self.recording
    if not rec or rec.key ~= key then
        -- passed a checkpoint: close the previous segment
        if rec and rec.valid and #rec.points >= 2 then
            local a, b = segmentEnds(self, rec.key)
            local pts = rec.points
            if b then table.insert(pts, pt(b)) end
            local len = polyLength(pts)
            local old = self.segments[rec.key]
            local straight = (a and b) and dist(a, b) or 0
            -- keep the shortest clean line (the racing line, not a spin);
            -- a line shorter than the straight line is a cut and is ignored
            if len >= straight * 0.98 and (not old or len < old.length) then
                P.setSegment(self, rec.key, pts)
                self.version = (self.version or 0) + 1
                self.dirty = true
            end
        end
        local a = segmentEnds(self, key)
        rec = { key = key, points = { a and pt(a) or pt(pos) }, valid = true, last = pt(pos) }
        self.recording = rec
    end
    local d = dist(rec.last, pos)
    if d > JUMP_M then
        rec.valid = false -- reset or teleport: this segment is not a clean line
    elseif d >= SAMPLE_M then
        table.insert(rec.points, pt(pos))
        rec.last = pt(pos)
    end
end

--- write recorded segments to disk (call after a lap or at race end)
P.save = function(self)
    if not self.dirty or not self.hash or type(jsonWriteFile) ~= "function" then
        return false
    end
    local out = {}
    for key, seg in pairs(self.segments) do
        out[key] = seg.points
    end
    jsonWriteFile(SAVE_DIR .. tostring(self.hash) .. ".json", { version = 1, segments = out }, false)
    self.dirty = false
    return true
end

P.recordedCount = function(self)
    local n = 0
    for _ in pairs(self.segments) do n = n + 1 end
    return n
end

return P
