-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- offline tests: lap tracker on the real BeamJoy races, server sessions and
-- grid order, race results with cuts.
-- luajit tests/test_session.lua   (from the repo root)
-- tests/fixtures/races.lua: steps + start positions captured from the live
-- server's BeamJoyData/db/scenarii/*_races.json.
package.path = "client/lua/?.lua;" .. package.path
local L = require("ge/extensions/raceprep/lapTracker")
local Sessions = dofile("server/RacePrep/Sessions.lua")
local races = dofile("tests/fixtures/races.lua")
local ok = true
local function check(name, cond) print(string.format("%-70s %s", name, cond and "ok" or "FAIL")) ok = ok and cond end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

-- drive a polyline through the checkpoints at constant speed, 20 Hz
local function drive(tracker, points, speed, t0, onSample)
    local t = t0
    local laps = {}
    tracker:update(t, points[1])
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local d = dist(a, b)
        local n = math.max(1, math.ceil(d / speed * 20))
        for k = 1, n do
            local f = k / n
            local p = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = a.z + (b.z - a.z) * f }
            t = t + d / speed / n * 1000
            if onSample then onSample(i, k, n, tracker) end
            local lap = tracker:update(t, p)
            if lap then table.insert(laps, lap) end
        end
    end
    return laps, t
end

-- Route between gate approaches without crossing any other gate. Gate centres
-- are not a circuit, particularly on two-gate races with adjacent lines.
local function clear(a, b, gates)
    for _, alts in ipairs(gates) do for _, g in ipairs(alts) do
        local rx, ry = b.x-a.x, b.y-a.y
        local sx, sy = g.b.x-g.a.x, g.b.y-g.a.y
        local den = rx*sy-ry*sx
        if math.abs(den) > 1e-9 then
            local qx, qy = g.a.x-a.x, g.a.y-a.y
            local t, u = (qx*sy-qy*sx)/den, (qx*ry-qy*rx)/den
            if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return false end
        end
    end end
    return true
end
local function connect(a, b, gates)
    local nodes = {a, b}
    for _, alts in ipairs(gates) do for _, g in ipairs(alts) do
        local dx, dy = g.b.x-g.a.x, g.b.y-g.a.y
        local len = math.sqrt(dx*dx+dy*dy)
        dx, dy = dx/len, dy/len
        for _, endpoint in ipairs({g.a, g.b}) do
            local sign = endpoint == g.a and -1 or 1
            for _, side in ipairs({-1, 1}) do
                nodes[#nodes+1] = {x=endpoint.x+sign*dx*12-dy*side*12,
                    y=endpoint.y+sign*dy*12+dx*side*12, z=(a.z+b.z)/2}
            end
        end
    end end
    local cost, prev, done = {[1]=0}, {}, {}
    while true do
        local best
        for i in ipairs(nodes) do
            if not done[i] and cost[i] and (not best or cost[i]<cost[best]) then best=i end
        end
        assert(best, "no gate-free connector")
        if best == 2 then break end
        done[best]=true
        for i in ipairs(nodes) do
            if not done[i] and clear(nodes[best], nodes[i], gates) then
                local c=cost[best]+dist(nodes[best], nodes[i])
                if not cost[i] or c<cost[i] then cost[i],prev[i]=c,best end
            end
        end
    end
    local route, i = {}, 2
    while i ~= 1 do table.insert(route, 1, nodes[i]); i=prev[i] end
    return route
end
local function loopPoints(race, laps, skip)
    local gates, approaches = L.buildGates(race.steps), {}
    for i, step in ipairs(race.steps) do
        local wp, incoming = step[1], race.steps[(i-2)%#race.steps+1][1].pos
        local f=L.forward(wp.rot)
        if (wp.pos.x-incoming.x)*f.x+(wp.pos.y-incoming.y)*f.y < 0 then
            f={x=-f.x,y=-f.y,z=-f.z}
        end
        approaches[i]={
            {x=wp.pos.x-8*f.x,y=wp.pos.y-8*f.y,z=wp.pos.z-8*f.z},
            {x=wp.pos.x+8*f.x,y=wp.pos.y+8*f.y,z=wp.pos.z+8*f.z}}
    end
    local sharedLine = #race.steps > 2 and dist(race.steps[1][1].pos, race.steps[#race.steps][1].pos) < 3
    local pts={approaches[sharedLine and #race.steps or 1][1]}
    local function to(p)
        for _, node in ipairs(connect(pts[#pts],p,gates)) do pts[#pts+1]=node end
    end
    for cycle=1,laps do
        if cycle>1 and #race.steps==2 then
            local p=race.steps[1][1].pos
            to({x=p.x+1000,y=p.y+1000,z=p.z}) -- circuit detour outside both gates
        end
        for i in ipairs(race.steps) do
            if not (sharedLine and i == 1) then
            to(approaches[i][1])
            if i~=skip then pts[#pts+1]=approaches[i][2]
            else
                -- Go around the missed gate, rather than crossing its centre.
                to(approaches[i][2])
            end
            end
        end
    end
    return pts
end
local function length(points)
    local n=0
    for i=2,#points do n=n+dist(points[i-1],points[i]) end
    return n
end
local function loopLength(race)
    return length(loopPoints(race,2))-length(loopPoints(race,1))
end

-- 1. every real race: gates are across the track (the path through the
-- checkpoint centres crosses each gate), 3 laps timed after the out-lap
for _, race in ipairs(races) do
    if race.loopable and #race.steps >= 2 then
        local tr = L.new(race.steps)
        local speed = 40
        local laps = drive(tr, loopPoints(race, 3), speed, 0)
        local expect = loopLength(race) / speed * 1000
        local good = #laps == 2 -- out-lap ends at the line; laps 1 and 2 complete before lap 3's line
        for _, l in ipairs(laps) do
            local sectors = tr:sectorTimes(l)
            if tr.sectorBounds then
                good = good and sectors and sectors[1] > 0 and sectors[2] > 0 and sectors[3] > 0 and
                    sectors[1] + sectors[2] + sectors[3] == l.time
            else good = good and sectors == nil end
            good = good and l.valid and math.abs(l.time - expect) < 120
        end
        check(string.format("%s / %s: %d laps timed, %.1f s each", race.level, race.name, #laps, expect / 1000), good)
    end
end

-- single-step race (lemans 1): lap = line to line
for _, race in ipairs(races) do
    if #race.steps == 1 then
        local p = race.steps[1][1].pos
        local f = L.forward(race.steps[1][1].rot)
        local far = { x = p.x + f.x * 2000, y = p.y + f.y * 2000, z = p.z }
        local back = { x = p.x - f.x * 50, y = p.y - f.y * 50, z = p.z }
        local tr = L.new(race.steps)
        local laps = drive(tr, { back, far, { x = far.x + 30, y = far.y, z = far.z }, back, far, far }, 50, 0)
        check("single-checkpoint race: line-to-line lap counted", #laps >= 1 and laps[1].valid)
    end
end

local mosport
for _, race in ipairs(races) do if race.level == "mosport" then mosport = race end end

-- 2. a cut makes the lap invalid; the next lap is valid again
do
    local tr = L.new(mosport.steps)
    local laps = drive(tr, loopPoints(mosport, 3), 40, 0, function(i, k, n, t)
        if t.lapNo == 1 and t.cuts == 0 and k == 1 then t:cut() end
    end)
    check("cut: lap invalid with 1 cut, next lap valid", #laps == 2 and not laps[1].valid and laps[1].cuts == 1 and laps[2].valid)
end

-- 3. a missed checkpoint: the lap is not counted
do
    local tr = L.new(mosport.steps)
    local pts = loopPoints(mosport, 2, 3)
    local laps = drive(tr, pts, 40, 0)
    check("missed checkpoint: lap incomplete", #laps == 1 and laps[1].incomplete == true)
end

-- 3b. a forced miss (gate removed from the path entirely) is incomplete
do
    local steps = mosport.steps
    local tr = L.new(steps)
    tr.state, tr.next, tr.lapStart, tr.lapNo = "lap", 1, 0, 1
    tr.prev, tr.prevT = nil, nil
    -- approach the finish line from 100 m before it, without any other gate
    local fin = steps[#steps][1]
    local f = L.forward(fin.rot)
    local before = { x = fin.pos.x - f.x * 8, y = fin.pos.y - f.y * 8, z = fin.pos.z }
    local after = { x = fin.pos.x + f.x * 10, y = fin.pos.y + f.y * 10, z = fin.pos.z }
    tr:update(60000, before)
    local lap = tr:update(61000, after)
    check("finish reached with checkpoints missing: incomplete", lap and lap.incomplete == true)
end

-- 4. teleport during a lap voids it
do
    local tr = L.new(mosport.steps)
    local jumped = false
    local laps = drive(tr, loopPoints(mosport, 3), 40, 0, function(i, k, n, t)
        if t.lapNo == 1 and k == 2 and not jumped then
            jumped = true
            t:update(t.prevT + 10, { x = t.prev.x + 500, y = t.prev.y, z = t.prev.z })
            t:update(t.prevT + 10, { x = t.prev.x - 500, y = t.prev.y, z = t.prev.z })
        end
    end)
    check("reset/teleport: lap void, not valid", #laps >= 1 and laps[1].void == "reset" and not laps[1].valid)
end

-- 5. lap-time interpolation: the same path sampled at 20 Hz and 7 Hz agrees
do
    local tr1, tr2 = L.new(mosport.steps), L.new(mosport.steps)
    local a = drive(tr1, loopPoints(mosport, 2), 40, 0)
    local function coarse(tracker, pts, speed)
        local t, laps = 0, {}
        tracker:update(t, pts[1])
        for i = 2, #pts do
            local d = dist(pts[i - 1], pts[i])
            local n = math.max(1, math.ceil(d / speed * 7))
            for k = 1, n do
                local f = k / n
                t = t + d / speed / n * 1000
                local lap = tracker:update(t, { x = pts[i - 1].x + (pts[i].x - pts[i - 1].x) * f,
                    y = pts[i - 1].y + (pts[i].y - pts[i - 1].y) * f, z = pts[i - 1].z + (pts[i].z - pts[i - 1].z) * f })
                if lap then table.insert(laps, lap) end
            end
        end
        return laps
    end
    local b = coarse(tr2, loopPoints(mosport, 2), 40)
    check("crossing time interpolated (20 Hz vs 7 Hz within 5 ms)", a[1] and b[1] and math.abs(a[1].time - b[1].time) <= 5)
end

-- 6. server sessions
do
    local s = Sessions.new("s1", 1, "MOSPORT", "qualifying", 10, 1000)
    Sessions.addLap(s, 1, "Alice", { time = 75000, valid = true, pi = 600, class = "R" }, 1100)
    Sessions.addLap(s, 2, "Bob", { time = 74000, valid = false, cuts = 1 }, 1110)
    Sessions.addLap(s, 3, "Cid", { time = 76000, valid = true }, 1120)
    Sessions.addLap(s, 2, "Bob", { time = 74500, valid = true }, 1190)
    Sessions.addLap(s, 1, "Alice", { time = 73000, valid = true }, 1200)
    local v = Sessions.view(s, 1200)
    check("standings by best valid lap", v.rows[1].name == "Alice" and v.rows[2].name == "Bob" and v.rows[3].name == "Cid")
    check("invalid lap not a best lap", v.rows[2].best == 74500)
    check("gap to leader", v.rows[2].gap == 1500)
    check("lap after zero refused unless started before it", Sessions.addLap(s, 3, "Cid", { time = 70000, valid = true }, 1700) == nil)
    check("tick: overtime at zero", Sessions.tick(s, 1600) == "overtime" and s.state == "overtime")
    check("overtime grace = 1.5 x best lap", math.abs(s.overtimeEnd - (1600 + 73 * 1.5)) < 0.01)
    check("lap started before zero accepted in overtime", Sessions.addLap(s, 3, "Cid", { time = 73500, valid = true, beforeEnd = true }, 1650) ~= nil)
    check("overtime claim cannot admit a lap started after zero", Sessions.addLap(s, 3, "Cid",
        {time=10000,valid=true,beforeEnd=true},1651)==nil)
    check("NaN lap rejected", Sessions.addLap(s, 3, "Cid", {time=0/0,valid=true},1500)==nil)
    check("signed deadline remains negative in overtime", Sessions.view(s,1650).deadlineRemaining == -50000)
    check("tick: ended after grace", Sessions.tick(s, 1720) == "ended")
    check("no laps after the end", Sessions.addLap(s, 1, "Alice", { time = 60000, valid = true, beforeEnd = true }, 1721) == nil)
    local final = Sessions.view(s, 1720)
    check("late valid lap counted (Cid P2)", final.rows[2].name == "Cid" and final.rows[1].name == "Alice")
    local quali = final
    local o = Sessions.gridOrder("qualifying", quali, {}, 6)
    check("grid: qualifying order", o[1].name == "Alice" and o[2].name == "Cid" and o[3].name == "Bob")
    o = Sessions.gridOrder("reverse", quali, {}, 2)
    check("grid: reverse top 2", o[1].name == "Cid" and o[2].name == "Alice" and o[3].name == "Bob")
    local s2 = Sessions.new("s2", 1, "X", "qualifying", 5, 0)
    Sessions.addLap(s2, 1, "A", { time = 70000, valid = true }, 10)
    Sessions.addLap(s2, 2, "B", { time = 71000, valid = true }, 10)
    Sessions.addLap(s2, 3, "C", { time = 72000, valid = false }, 10)
    o = Sessions.gridOrder("reverse", Sessions.view(s2, 20), {}, 6)
    check("grid: reverse only drivers with a valid lap", o[1].name == "B" and o[2].name == "A" and o[3].name == "C")
    o = Sessions.gridOrder("handicap", nil, { ["1"] = 700, ["2"] = 450, ["3"] = 600 }, 6)
    check("grid: handicap slowest first", o[1].playerID == 2 and o[2].playerID == 3 and o[3].playerID == 1)
    o=Sessions.gridOrder("handicap",nil,{["1"]=0,["2"]=500,["3"]=0/0},6)
    check("grid: unknown or invalid PI does not get pole",#o==1 and o[1].playerID==2)
    check("grid: join -> no order", Sessions.gridOrder("join", quali, {}, 6) == nil)
    check("grid: qualifying without a session -> no order", Sessions.gridOrder("qualifying", nil, {}, 6) == nil)
end

-- Best-lap sectors must stay tied to that exact valid lap.
do
    local s=Sessions.new("sectors",1,"T","qualifying",10,0)
    Sessions.addLap(s,1,"A",{time=60000,valid=true,sectors={20000,19000,21000}},70)
    Sessions.addLap(s,1,"A",{time=59000,valid=false,sectors={19000,19000,21000}},130)
    Sessions.addLap(s,1,"A",{time=62000,valid=true,sectors={21000,20000,21000}},200)
    local row=Sessions.view(s,200).rows[1]
    check("sectors remain those of best valid lap",row.best==60000 and row.bestSectors[1]==20000 and row.bestSectors[2]==19000)
    Sessions.addLap(s,1,"A",{time=58000,valid=true,sectors={18000,19000,21000}},260)
    row=Sessions.view(s,260).rows[1]
    check("new best lap replaces all sectors together",row.best==58000 and row.bestSectors[1]==18000 and row.bestLap==4)
    Sessions.addLap(s,2,"B",{time=60000,valid=true,sectors={20000,20000,0/0}},70)
    Sessions.addLap(s,3,"C",{time=60000,valid=true,sectors={20000,20000,19000}},70)
    check("malformed sector data discarded",not s.drivers['2'].bestSectors and not s.drivers['3'].bestSectors)
    Sessions.addLap(s,1,"A",{time=57000,valid=true},330)
    check("best without splits does not retain stale sectors",s.drivers['1'].bestSectors==nil)
    local tr=L.new({{{pos={x=0,y=0,z=0},radius=5}}})
    check("one gate does not invent sectors",tr.sectorBounds==nil)
end

-- 9. race results with track-limit cuts
do
    local R = require("ge/extensions/raceprep/results")
    bjiRacePrep = { getRules = function() return { trackLimits = "penalty", cutPenaltyAfter = 1, cutPenaltySeconds = 5 } end }
    BJI_Context = { Players = {} }
    TriggerServerEvent = nil
    local c1, c2 = {}, {}
    -- 2 laps x 3 checkpoints; A: 60 s laps, B: 61 s laps
    for step = 1, 6 do c1[step] = step * 20000; c2[step] = step * 20333 end
    local run = { key = "k", raceID = 1, raceName = "T", laps = 2, wpPerLap = 3, crossings = { [1] = c1, [2] = c2 },
        names = { [1] = "A", [2] = "B" }, cars = {}, order = { 1, 2 }, finished = { [1] = true, [2] = true }, eliminated = {},
        cuts = { [1] = { [2] = 3 } } }
    R.finalizeForTest(run)
    local res = R.last
    local a, b
    for _, row in ipairs(res.rows) do if row.playerID == 1 then a = row else b = row end end
    check("results: cut lap marked invalid", a.lapList[2].invalid == true and a.lapList[1].invalid == nil)
    check("results: best lap excludes the invalid lap", a.best.lap == 1)
    check("results: penalty (3 cuts, 1 free) = 10 s", a.penalty == 10000 and a.cuts == 3)
    check("results: penalty changes the order (B wins)", res.rows[1].playerID == 2 and res.rows[2].playerID == 1)
    bjiRacePrep = nil
end

print(ok and "ALL OK" or "FAILURES")
os.exit(ok and 0 or 1)
