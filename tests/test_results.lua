-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- offline test for raceprep/results + server history: luajit tests/test_results.lua (repo root)
package.path = "client/lua/?.lua;" .. package.path
local wpPerLap, laps = 6, 3
local cars = { { pid = 1, lapMs = 60000 }, { pid = 2, lapMs = 58000 }, { pid = 3, lapMs = 61000, retireAt = 8 } }
-- each car: uneven checkpoint spacing (fractions of a lap), lap times vary a bit per lap
local frac = { 0.10, 0.25, 0.40, 0.62, 0.80, 1.00 }
local function crossTime(c, step)
    local lap = math.floor((step - 1) / wpPerLap) + 1
    local k = (step - 1) % wpPerLap + 1
    local t = 0
    for l = 1, lap - 1 do t = t + c.lapMs + (l == 2 and 700 or 0) end
    return t + math.floor((c.lapMs + (lap == 2 and 700 or 0)) * frac[k])
end
local race = {
    state = 2, STATES = { GRID = 1, RACE = 2, FINISHED = 3 }, raceID = 5, raceName = "Test Ring",
    settings = { laps = laps },
    race = { startTime = 1000, raceData = { wpPerLap = wpPerLap, steps = {} }, leaderboard = {}, finished = {}, eliminated = {} },
}
BJI_Scenario = { TYPES = { RACE_MULTI = "race" }, get = function() return race end }
BJI_Context = { Players = { [1] = { playerName = "Alice" }, [2] = { playerName = "Bob" }, [3] = { playerName = "Cid" } } }
MPVehicleGE = { getVehicles = function() return {
    { ownerID = 1, jbeam = "hawk_fm5", isLocal = true, gameVehicleID = 1 },
    { ownerID = 2, jbeam = "giselle__flying_400", gameVehicleID = 2, remoteVehID = 2 },
    { ownerID = 3, jbeam = "neonna_gt", gameVehicleID = 3, remoteVehID = 3 } } end }
local sent
TriggerServerEvent = function(name, payload) sent = payload end
package.loaded['ge/extensions/raceprep/net']={send=function(...) return TriggerServerEvent(...) end} -- chunking: test_net_chunks.lua
jsonEncode = function(t) return t end
local R = require("ge/extensions/raceprep/results")
local clock = 0
local now = 0
while now <= 3 * 62000 do
    local lb = {}
    for _, c in ipairs(cars) do
        local step = 0
        while step < laps * wpPerLap and crossTime(c, step + 1) <= now and not (c.retireAt and step >= c.retireAt) do step = step + 1 end
        local lap, wp = math.floor(step / wpPerLap) + 1, step % wpPerLap
        if step == laps * wpPerLap then lap, wp = laps, wpPerLap end
        table.insert(lb, { playerID = c.pid, lap = lap, wp = wp, time = step > 0 and crossTime(c, step) or 0, step = step })
        if step == laps * wpPerLap and not c.done then c.done = true; table.insert(race.race.finished, c.pid) end
        if c.retireAt and step >= c.retireAt and not c.dnf and now > crossTime(c, c.retireAt) + 5000 then c.dnf = true; table.insert(race.race.eliminated, c.pid) end
    end
    table.sort(lb, function(a, b) if a.step ~= b.step then return a.step > b.step end return a.time < b.time end)
    race.race.leaderboard = lb
    clock = clock + 0.1
    R.update(clock)
    if now == 30000 then R.onCut(2, 5, 1) end -- Bob cuts on lap 1
    now = now + 100
end
race.state = 3
clock = clock + 0.1
R.update(clock)
local res = R.last
local ok = true
local function check(name, cond) print(string.format("%-58s %s", name, cond and "ok" or "FAIL")) ok = ok and cond end
check("results built when the race finished", res ~= nil and R.visible)
check("order Bob, Alice, Cid", res.rows[1].name == "Bob" and res.rows[2].name == "Alice" and res.rows[3].name == "Cid")
check("Bob total = true total", res.rows[1].total == crossTime(cars[2], laps * wpPerLap))
check("Alice gap = difference of totals", res.rows[2].gap == crossTime(cars[1], 18) - crossTime(cars[2], 18))
check("Cid DNF with 1 lap done", res.rows[3].status == "DNF" and res.rows[3].laps == 1)
local alice = res.rows[2]
check("Alice lap 2 time = 60.700 s", alice.lapList[2].time == 60700)
check("Alice best lap = lap 1 or 3 (60.000 s)", alice.best.time == 60000)
local s = alice.lapList[2].sectors
check("sectors add up to the lap time", s and s[1] + s[2] + s[3] == alice.lapList[2].time)
check("sector bounds at checkpoints 2 and 4", res.sectorBounds[1] == 2 and res.sectorBounds[2] == 4)
check("fastest lap flagged on Bob", res.rows[1].fastestLap == true)
local bob = res.rows[1]
check("Bob's cut lap 1 is his fastest lap shown (red)", bob.bestAny == bob.lapList[1] and bob.bestAny.invalid == true)
check("Bob's best valid lap is lap 3", bob.best == bob.lapList[3] and not bob.best.invalid)
check("Alice's fastest shown lap is valid (green)", alice.bestAny and not alice.bestAny.invalid)
check("car label from model", res.rows[1].car == "giselle__flying_400")
check("sent to server", sent == res)
-- server side: run the plugin handler with stubbed BeamMP API into a temp folder
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. tmp .. "/RacePrep/history && cp server/RacePrep/*.lua server/RacePrep/*.json " .. tmp .. "/RacePrep/ 2>/dev/null")
FS = { Exists = function(p) local f = io.open(p, "r") if f then f:close() return true end return false end, CreateDirectory = function(p) os.execute("mkdir -p " .. p) end }
Util = { JsonDecode = function(x) if type(x) == "string" and x:find('"entries"', 1, true) then return { entries = {}, constants = {} } end return x end, JsonEncode = function() return "{}" end, JsonPrettify = function(s) return s end }
MP = { CreateEventTimer = function() end, TriggerGlobalEvent = function() end, RegisterEvent = function() end, TriggerClientEvent = function() end, GetPlayerName = function() return "x" end }
local src = io.open("server/RacePrep/RacePrep.lua"):read("*a")
src = src:gsub("debug%.getinfo%(1%)%.source", '("' .. tmp .. '/RacePrep/RacePrep.lua")')
local realprint = print
print = function() end
assert(loadstring(src))()
local hok, herr = pcall(RacePrepRaceResult, 1, sent) if not hok then io.stderr:write("handler error: " .. tostring(herr) .. "\n") end
RacePrepRaceResult(2, sent) -- duplicate from another driver: ignored
print = realprint
local csv = io.open(tmp .. "/RacePrep/history/results.csv"):read("*a")
local lines = 0 for _ in csv:gmatch("[^\n]+") do lines = lines + 1 end
check("CSV has header + 3 rows (duplicate ignored)", lines == 4)
check("CSV row for Bob has total 174.700 s", csv:find("Bob,giselle__flying_400,FIN,3,174.700", 1, true) ~= nil)
print(ok and "ALL OK" or "FAILURES")
os.execute("rm -rf " .. tmp)
os.exit(ok and 0 or 1)
