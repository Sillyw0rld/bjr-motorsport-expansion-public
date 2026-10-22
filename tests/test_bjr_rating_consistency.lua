-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Entire expansion server VM, isolated filesystem and fake BJR API. No server
-- process or live data is used. Exercises reports -> grid -> frozen results.
local tmp=os.tmpname();os.remove(tmp)
os.execute('mkdir -p '..tmp..'/RacePrep/history && cp server/RacePrep/*.lua '..tmp..'/RacePrep/')
local function write(name,s) local f=assert(io.open(tmp..'/RacePrep/'..name,'w'));f:write(s);f:close() end
write('host.json','host-fixture');write('ratings-seed.json','seed-fixture')
local wires,serial={},0
local function encode(p) serial=serial+1;local k='wire-'..serial;wires[k]=p;return k end
local seed={entries={},constants={}}
Util={JsonEncode=encode,JsonPrettify=function(s) return s end,JsonDecode=function(s)
 if s=='host-fixture' then return {host='beamjoy-revived',version='test'} end
 if s=='seed-fixture' then return seed end
 return wires[s]
end}
FS={Exists=function(path) local f=io.open(path);if f then f:close();return true end;return false end,
 CreateDirectory=function() end,ListFiles=function() return {} end}
local sent={}
MP={RegisterEvent=function() end,CreateEventTimer=function() end,TriggerGlobalEvent=function() end,
 GetPlayers=function() return {[0]='Driver'} end,GetPlayerName=function() return 'Driver' end,
 GetPlayerIdentifiers=function(id) assert(type(id)=='number');return {beammp='test'} end,
 TriggerClientEvent=function(pid,event,wire) sent[#sent+1]={event=event,data=wires[wire] or wire} end}
-- Private fake host plugin API, solely in the temporary test folder.
write('BJRApi.lua',[[return {start=function(o)
 testAPI={result=o.result,cars=o.cars,refreshes=0,fields={}}
 -- BJR state comes from the API (2.14.2: no bridge file): the map, race sessions
 testAPI.call=function(method,params,cb) if method=='races.sessions' then cb(true,{sessions=testSessions}) end end
 o.ready({map={name='imola'}})
 testAPI.refreshCars=function() testAPI.refreshes=testAPI.refreshes+1 end
 testAPI.setCarFields=function(run,pid,e) testAPI.fields[#testAPI.fields+1]={run=run,pid=pid,pi=e.pi} end
 return testAPI
end}]])
local src=assert(io.open('server/RacePrep/RacePrep.lua')):read('*a'):gsub('debug%.getinfo%(1%)%.source','("'..tmp..'/RacePrep/RacePrep.lua")')
local printBefore=print;print=function() end;assert(loadstring(src))();print=printBefore
local run={sessionId='r1',raceId=1,map='imola',state='GRID',racers={{id=0,lap=1}}}
testSessions={run}
local function metadata() RacePrepHostPoll() end
metadata()
local p={model='car',config='Race setup',parts={a='part1'},serverVehicleID='0-3',pi=586,pi_speed=600,pi_technical=570,
 presentation={tuningShare=.015,weightShare=0,carName='Hawk Vipere S'}}
RacePrepComputedRating(0,encode(p))
assert(testAPI.cars(0)[1].pi==595 and testAPI.refreshes==1,'rail uses full parts PI and refreshes on report')
RacePrepGridCar(0,encode{raceID=1,serverVehicleID='0-3',pi=595})
assert(testAPI.fields[#testAPI.fields].pi==595,'public native-results labels use the same PI')
-- New setup on that exact grid vehicle updates the frozen rating promptly.
p.parts={a='part2'};p.pi=600;RacePrepComputedRating(0,encode(p))
assert(testAPI.cars(0)[1].pi==609 and testAPI.fields[#testAPI.fields].pi==609)
run.state='RACE';metadata()
p.parts={a='part3'};p.pi=720;RacePrepComputedRating(0,encode(p))
assert(testAPI.cars(0)[1].pi==731,'current car reflects a later setup')
testAPI.result{key='bjr:r1',runID='r1',raceID=1,raceName='Imola',level='imola',laps=1,
 rows={{playerID=0,name='Driver',status='FIN',position=1,laps=1,total=60000,lapList={{lap=1,time=60000,sectors={30000,30000}}}}}}
local result
for _,s in ipairs(sent) do if s.event=='RacePrepBJRResults' then result=s.data end end
assert(result and result.rows[1].pi==609 and result.rows[1].car=='Hawk Vipere S','race results keep the start setup, never current PI')
-- short report: a rating the server holds is named by key, without parts
local key2
for _,m in ipairs(sent) do if m.event=='RacePrepRatings' and type(m.data)=='table' then for k,e in pairs(m.data.entries or {}) do if e.parts and e.parts.a=='part2' then key2=k end end end end
assert(key2,'stored setup has a key')
local before=#sent
RacePrepComputedRating(0,encode{model='car',key=key2,serverVehicleID='0-3',presentation=p.presentation})
assert(testAPI.cars(0)[1].pi==609,'short report maps the car back to the stored setup')
for i=before+1,#sent do assert(sent[i].event~='RacePrepRatingMissing','known key is accepted') end
RacePrepComputedRating(0,encode{model='car',key='car/Race setup/unknown',serverVehicleID='0-3'})
assert(sent[#sent].event=='RacePrepRatingMissing' and sent[#sent].data=='0-3','unknown key asks the client for the full report')
RacePrepComputedRating(0,encode{model='car',key='other/x/1',serverVehicleID='0-3'})
assert(sent[#sent].event=='RacePrepRatingMissing','a key for another model is refused')
os.execute('rm -rf '..tmp)
print('PASS: report -> rail -> grid -> native labels agree, setup refresh, short key reports, historic PI freezes at race start')
