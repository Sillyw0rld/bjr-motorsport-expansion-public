-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- offline test for server/RacePrep/Skill.lua and the plugin's skill hook
-- luajit tests/test_skill.lua   (from the repo root)
local Skill = dofile("server/RacePrep/Skill.lua")
local ok = true
local function check(name, cond) print(string.format("%-62s %s", name, cond and "ok" or "FAIL")) ok = ok and cond end

-- identity
local store = Skill.newStore()
local h1, h2 = Skill.hash("salt-a", "203.0.113.7"), Skill.hash("salt-b", "203.0.113.7")
check("hash is 16 hex chars and stable", #h1 == 16 and h1:match("^%x+$") and h1 == Skill.hash("salt-a", "203.0.113.7"))
check("hash depends on the salt", h1 ~= h2)
check("different IPs give different hashes", h1 ~= Skill.hash("salt-a", "203.0.113.8"))
local kIP = Skill.key(store, { ip = "203.0.113.7" })
check("guest key uses the hashed IP, not the IP", kIP:sub(1, 3) == "ip:" and not kIP:find("203", 1, true))
check("account id preferred over IP", Skill.key(store, { ip = "203.0.113.7", beammp = "4242" }) == "bmp:4242")
store.aliases[kIP] = "bmp:4242"
check("alias merges profiles", Skill.key(store, { ip = "203.0.113.7" }) == "bmp:4242")
store.aliases = {}

-- Elo, equal cars
store = Skill.newStore()
local d = Skill.update(store, { { key = "a", name = "A" }, { key = "b", name = "B" }, { key = "c", name = "C" } }, 1)
check("winner gains, last loses", d.a > 0 and d.c < 0 and math.abs(d.b) < 1e-9)
check("total change balanced (same K)", math.abs(d.a + d.b + d.c) < 0.2)
check("stats: races and wins counted", store.players.a.races == 1 and store.players.a.wins == 1 and store.players.c.podiums == 1)

-- car factor: same result, but the winner's car is 100 PI faster
local s1, s2 = Skill.newStore(), Skill.newStore()
local even = Skill.update(s1, { { key = "a", pi = 500 }, { key = "b", pi = 500 } }, 1)
local fast = Skill.update(s2, { { key = "a", pi = 600 }, { key = "b", pi = 500 } }, 1)
check("winning in a much faster car earns less", fast.a < even.a and fast.a > 0)
local slow = Skill.update(Skill.newStore(), { { key = "a", pi = 400 }, { key = "b", pi = 500 } }, 1)
check("winning in a slower car earns more", slow.a > even.a)

-- provisional: K halves after 5 races
local s = Skill.newStore()
for i = 1, 5 do Skill.update(s, { { key = "x" }, { key = "y" } }, i) end
local before = s.players.x.rating
local later = Skill.update(s, { { key = "x" }, { key = "y" } }, 6)
check("K halves after the provisional races", later.x < 16 and later.x > 0)

-- names kept to the 5 most recent
local sn = Skill.newStore()
for i = 1, 8 do Skill.update(sn, { { key = "g", name = "guest" .. i }, { key = "h", name = "h" } }, i) end
local count = 0 for _ in pairs(sn.players.g.names) do count = count + 1 end
check("only the 5 most recent names kept", count == 5 and sn.players.g.names.guest8 and not sn.players.g.names.guest1)

-- plugin integration with a stubbed BeamMP API
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. tmp .. "/RacePrep/history && cp server/RacePrep/*.lua server/RacePrep/*.json " .. tmp .. "/RacePrep/ 2>/dev/null")
local function fixture(path, text)
    local f=assert(io.open(tmp .. path,'w'));f:write(text);f:close()
end
os.execute("mkdir -p " .. tmp .. "/BeamJoyData/db/players " .. tmp .. "/BeamJoyData/db/scenarii")
fixture('/BeamJoyData/db/players/x.json','admin-fixture')
fixture('/BeamJoyData/db/groups.json','groups-fixture')
fixture('/BeamJoyData/db/permissions.json','permissions-fixture')
fixture('/BeamJoyData/db/scenarii/test_races.json','races-fixture')
local sessionRace = dofile('tests/fixtures/races.lua')[1]
local decodedFixtures = {['admin-fixture']={group='admin'},['groups-fixture']={admin={level=10}},
    ['permissions-fixture']={SetConfig=5},['races-fixture']={sessionRace}}
local encoded, serial = {}, 0
local fakeNow=1000
os.time=function() return fakeNow end
local written = {}
FS = { Exists = function(p) local f = io.open(p, "r") if f then f:close() return true end return false end, CreateDirectory = function(p) os.execute("mkdir -p " .. p) end }
local lastEncoded
Util = { JsonDecode = function(x) if decodedFixtures[x] then return decodedFixtures[x] end; if encoded[x] then return encoded[x] end; if type(x) == "string" and x:find('"entries"', 1, true) then return { entries = {}, constants = {} } end return x end,
    JsonEncode = function(t) if type(t) == "table" and t.players then lastEncoded = t end serial=serial+1;local key="encoded-"..serial;encoded[key]=t;return key end, JsonPrettify = function(s) return s end }
local sent = {}
local ids = { [1] = { ip = "198.51.100.1" }, [2] = { ip = "198.51.100.2" }, [3] = { beammp = "777", ip = "198.51.100.3" } }
MP = { CreateEventTimer = function() end, TriggerGlobalEvent = function() end, RegisterEvent = function() end, TriggerClientEvent = function(pid, ev, data) table.insert(sent, { pid = pid, ev = ev, data = data }) end,
    GetPlayerName = function() return "x" end, GetPlayerIdentifiers = function(pid) return ids[pid] end,
    GetPlayers = function() return { [1] = "A", [2] = "B", [3] = "C" } end }
local src = io.open("server/RacePrep/RacePrep.lua"):read("*a"):gsub("debug%.getinfo%(1%)%.source", '("' .. tmp .. '/RacePrep/RacePrep.lua")')
local realprint = print
print = function() end
assert(loadstring(src))()
local result = { key = "7:1000", raceID = 7, raceName = "Test", laps = 1, date = "now", rows = {
    { playerID = 3, position = 1, name = "C", status = "FIN", model = "hawk_fm5" },
    { playerID = 1, position = 2, name = "A", status = "FIN", model = "neonna_gt" },
    { playerID = 2, position = 3, name = "B", status = "DNF", model = "neonna_gt" } } }
RacePrepRaceResult(1, result)
result.key = "7:1003" -- another client has a different clock offset
RacePrepRaceResult(2, result) -- same raceID must still deduplicate
print = realprint
local f = io.open(tmp .. "/RacePrep/skills.json")
local text = f and f:read("*a") or ""
if f then f:close() end
local skillsTable = lastEncoded
check("skills.json written", text ~= "")
local hasIP = false
for k, p in pairs(skillsTable.players or {}) do if k:find("198.51", 1, true) then hasIP = true end end
check("no IP address stored", not hasIP and not text:find("198.51", 1, true))
check("account player keyed by account", skillsTable.players and skillsTable.players["bmp:777"] ~= nil)
local races = 0 for _, p in pairs(skillsTable.players or {}) do races = races + p.races end
check("duplicate result not counted twice (3 drivers x 1 race)", races == 3)
local broadcast = false for _, m in ipairs(sent) do if m.ev == "RacePrepSkills" and m.pid == -1 then broadcast = true end end
check("skills broadcast to everyone", broadcast)
-- Fast successive runs of the same layout must score separately despite the legacy 90s window.
RacePrepControlSnapshot({raceID=7,runID='run-a',phase='race',participants={1,2,3}})
result.runID='run-a';result.key='7:2000';RacePrepRaceResult(1,result)
result.key='7:2003';RacePrepRaceResult(2,result)
local counted=0;for _,p in pairs(lastEncoded.players) do counted=counted+p.races end
check('authoritative run ID deduplicates different client clocks',counted==6)
RacePrepControlSnapshot({raceID=7,runID='run-b',phase='race',participants={1,2,3}})
result.runID='run-b';result.key='7:2010';RacePrepRaceResult(1,result)
counted=0;for _,p in pairs(lastEncoded.players) do counted=counted+p.races end
check('next same-layout run inside 90s counts separately',counted==9)
-- Real server handlers with actual readJson fixture files, isolated from live data.
local function latestSession()
    for i=#sent,1,-1 do if sent[i].ev=='RacePrepSession' then return encoded[sent[i].data] end end
end
local quiet=print;print=function() end
RacePrepWeekendStart(1,{raceID=sessionRace.id,level='test',practiceMinutes=1,qualifyingMinutes=1})
print=quiet
check('weekend reads the race file and starts practice', latestSession().type=='practice' and latestSession().state=='running' and latestSession().weekend.stage=='practice')
fakeNow=1060;RacePrepSessionTick()
check('server enters overtime',latestSession().state=='overtime')
fakeNow=1240;RacePrepSessionTick()
check('practice ends',latestSession().state=='ended')
fakeNow=1241;RacePrepSessionTick()
check('qualifying starts at once after practice (owner 2026-10-21)',latestSession().type=='qualifying' and latestSession().remaining==60000 and latestSession().weekend.stage=='qualifying')
RacePrepLap(1,{sessionID='wrong',time=60000,valid=true})
check('wrong session ID refused',#latestSession().rows==0)
RacePrepLap(1,{sessionID=latestSession().id,time=20000,valid=true,sectors={6000,7000,7000}})
check('valid qualifying lap broadcast',latestSession().rows[1].best==20000)
check('server handler broadcasts best-lap sectors',latestSession().rows[1].bestSectors[2]==7000)
fakeNow=1301;RacePrepSessionTick()
check('qualifying overtime: laps in progress may finish',latestSession().state=='overtime')
fakeNow=1331;RacePrepSessionTick()
check('qualifying over: the weekend shows the grid',latestSession().state=='ended' and latestSession().weekend.stage=='grid' and latestSession().weekend.grid[1].playerID==1)
local f=io.popen('find '..tmp..'/RacePrep/history -name "*_qualifying.json"')
local saved=f:read('*a');f:close()
check('qualifying history saved',saved~='')
RacePrepWeekendEnd(1)
check('staff end the weekend',latestSession().weekend==nil)
fixture('/BeamJoyData/db/players/x.json','no-admin')
local before=#sent
RacePrepWeekendStart(1,{raceID=sessionRace.id,level='test',qualifyingMinutes=1})
check('weekend start denied without permission', latestSession().weekend==nil)
os.execute("rm -rf " .. tmp)
print(ok and "ALL OK" or "FAILURES")
os.exit(ok and 0 or 1)
