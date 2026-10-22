-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- offline race simulation for raceprep/timing: luajit tests/test_timing.lua (repo root)
package.path = "client/lua/?.lua;" .. package.path
local R, wpPerLap = 200, 4
local function at(a) return { x = R * math.cos(a), y = R * math.sin(a), z = 0 } end
local steps = {}
for i = 1, wpPerLap do steps[i] = { { pos = at(i * math.pi / 2) } } end
local start = -0.05
local cars = {
    { pid = 1, w = 0.250, veh = 101 },             -- me
    { pid = 2, w = 0.262, veh = 202, parked = 203 }, -- ahead, also owns a parked car
    { pid = 3, w = 0.240, veh = 303 },             -- behind
}
local now = 0
local function angle(c) return start + c.w * now / 1000 end
local function passed(c) return math.max(0, math.floor((angle(c) + 1e-9) / (math.pi / 2))) end
local crossT = {} -- pid -> step -> ms (true)
local race = {
    state = 2, STATES = { RACE = 2 }, raceID = 7, raceHash = nil, settings = { laps = 10 },
    grid = { startPositions = { { pos = at(start) } } },
    race = { startTime = 0, raceData = { steps = steps, wpPerLap = wpPerLap }, leaderboard = {}, lap = 1, waypoint = 0,
        timers = { lap = { get = function() return 0 end } } },
    isFinished = function() return false end, isEliminated = function() return false end,
    isParticipant = function() return true end, lapData = {},
}
BJI_Scenario = { TYPES = { RACE_MULTI = "race" }, get = function() return race end }
BJI_Context = { User = { playerID = 1 } }
BJI = { Utils = { UI = { RaceDelay = function(ms) return tostring(ms) end } } }
local objs = {}
local function mkobj(c, parked)
    return {
        getPosition = function() return parked and { x = 500, y = 500, z = 0 } or at(angle(c)) end,
        getVelocity = function() return { length = function() return parked and 0 or c.w * R end } end,
    }
end
local list = {}
for _, c in ipairs(cars) do
    if c.parked then objs[c.parked] = mkobj(c, true); table.insert(list, { ownerID = c.pid, gameVehicleID = c.parked, remoteVehID = c.parked, isSpawned = true, isLocal = c.pid == 1 }) end
    objs[c.veh] = mkobj(c, false); table.insert(list, { ownerID = c.pid, gameVehicleID = c.veh, remoteVehID = c.veh, isSpawned = true, isLocal = c.pid == 1 })
end
MPVehicleGE = { getVehicles = function() return list end }
getObjectByID = function(id) return objs[id] end
local players = {}
for _, c in ipairs(cars) do players[c.pid] = { playerName = "P" .. c.pid, currentVehicle = c.veh } end

local timing = require("ge/extensions/raceprep/timing")
local function updateLeaderboard()
    local lb = {}
    for _, c in ipairs(cars) do
        local n = passed(c)
        crossT[c.pid] = crossT[c.pid] or {}
        for k = 1, n do
            if not crossT[c.pid][k] then crossT[c.pid][k] = math.floor((k * math.pi / 2 - start) / c.w * 1000) end
        end
        local lap, wp = math.floor(n / wpPerLap) + 1, n % wpPerLap
        table.insert(lb, { playerID = c.pid, lap = lap, wp = wp, time = n > 0 and crossT[c.pid][n] or 0, diff = 0, n = n })
    end
    table.sort(lb, function(a, b) return angle(cars[a.playerID]) > angle(cars[b.playerID]) end)
    race.race.leaderboard = lb
    local me = cars[1]
    local n = passed(me)
    race.race.lap = math.floor(n / wpPerLap) + 1
    race.race.waypoint = n
end
local snap
while now <= 100000 do
    updateLeaderboard()
    snap = timing.get({ now = now, players = players })
    now = now + 50
end
now = now - 50
local me, ahead, behind = cars[1], cars[2], cars[3]
local function check(name, got, want, tol)
    local ok = got ~= nil and math.abs(got - want) <= tol
    print(string.format("%-52s %10s  want %10.1f  %s", name, got and string.format("%.1f", got) or "nil", want, ok and "ok" or "FAIL"))
    return ok
end
local all = true
print("order:", snap.entries[1].name, snap.entries[2].name, snap.entries[3].name, " path segments recorded:", snap.pathRecorded)
local k = passed(me)
all = check("interval to car ahead at my checkpoint (ms)", snap.gapAhead.interval, crossT[1][k] - crossT[2][k], 1) and all
all = check("distance to car ahead (m, arc)", snap.gapAhead.distance, (angle(ahead) - angle(me)) * R, 3) and all
all = check("live gap to car ahead (ms)", snap.gapAhead.live, (angle(ahead) - angle(me)) / ahead.w * 1000, 120) and all
local kb = passed(behind)
all = check("interval of car behind at its checkpoint (ms)", snap.gapBehind.interval, crossT[3][kb] - crossT[1][kb], 1) and all
all = check("distance to car behind (m)", snap.gapBehind.distance, (angle(me) - angle(behind)) * R, 3) and all
all = check("live gap of car behind (ms)", snap.gapBehind.live, (angle(me) - angle(behind)) / me.w * 1000, 120) and all
print(all and "ALL OK" or "FAILURES")
os.exit(all and 0 or 1)
