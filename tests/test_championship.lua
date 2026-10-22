-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local C=dofile('server/RacePrep/Championship.lua');local store=C.new()
local s=C.create(store,'Test',100,true)
s.rounds={{raceID=1,level='a',name='A'},{raceID=1,level='b',name='B'}};s.status='running'
local function identity(pid) return tostring(pid) end
local r={runID='one',raceID=1,level='a',rows={{playerID=1,name='A',position=1,status='FIN',fastestLap=true},
 {playerID=2,name='B',position=2,status='FIN'}}}
assert(not C.record(store,r,identity,false));assert(C.record(store,r,identity,true))
assert(s.drivers['1'].points==26 and s.drivers['2'].points==18)
assert(not C.record(store,r,identity,true))
r.runID='two';assert(not C.record(store,r,identity,true),'same ID on different level must not score')
r.level='b';r.rows[1].position=2;r.rows[1].fastestLap=nil;r.rows[2].position=1
assert(C.record(store,r,identity,true));assert(s.status=='completed')
assert(C.view(store).rows[1].name=='A')
local older=s;C.create(store,'New',200,true);assert(#store.series==2 and store.series[1]==older)
local store2=C.new();local s2=C.create(store2,'Any order',300)
assert(s2.linkTournament==false,'not tied to BeamJoy tournaments by default')
s2.rounds={{raceID=1,level='a',name='A'},{raceID=2,level='Mosport',name='M'},{raceID=1,level='a',name='A again'}};s2.status='running'
local m={runID='m1',raceID=2,level='mosport',rows={{playerID=1,name='A',position=1,status='FIN'}}}
assert(C.record(store2,m,identity,false),'round 2 scores first; no tournament; map name case-insensitive')
assert(not C.record(store2,{runID='m2',raceID=2,level='mosport',rows=m.rows},identity,false),'round raced once')
assert(C.record(store2,{runID='a1',raceID=1,level='a',rows=m.rows},identity,false))
assert(s2.status=='running' and s2.round==3)
assert(C.record(store2,{runID='a2',raceID=1,level='a',rows=m.rows},identity,false))
assert(s2.status=='completed' and s2.drivers['1'].points==75)
print('PASS: rounds in any order, repeated race fills the next matching round, no tournament needed')
print('PASS: championship points, fastest lap, tournament linkage, map matching, dedup, completion and archives')
