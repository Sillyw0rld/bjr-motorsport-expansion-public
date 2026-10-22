-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S=dofile('server/RacePrep/DriverStats.lua')
local store=S.new()
local r={key='one',raceID=1,rows={{playerID=1,name='A',position=1,status='FIN',laps=4,cuts=0,
 incidents={contacts=0,distance=5000},best={time=60000},lapList={{},{},{},{}}},
 {playerID=2,name='B',position=2,status='FIN',laps=4,cuts=2,incidents={contacts=1},lapList={{},{},{},{invalid=true}}}}}
local function id(pid) return 'account:'..pid end
assert(S.record(store,r,id,true));assert(not S.record(store,r,id,true))
assert(store.drivers['account:1'].wins==1 and store.drivers['account:1'].safety>3)
assert(store.drivers['account:2'].safety<3)
local view=S.view(store,id,{[1]='Renamed',[2]='B'})
assert(view[1].name=='Renamed' and view[1].kilometres==5 and view[1].provisional)
r.key='two';local before=store.drivers['account:2'].safety;S.record(store,r,id,false)
assert(store.drivers['account:2'].safety==before)
-- BJR metadata is JSON: its player-name map has string keys. BeamMP's
-- account lookup needs numeric player IDs, just like result rows provide.
local function numericIdentity(pid)
 if type(pid)=='number' then return 'account:'..pid end
end
local bjrView=S.view(store,numericIdentity,{['1']='Renamed',['2']='B',['0']='New guest'})
local byID={};for _,row in ipairs(bjrView) do byID[row.playerID]=row end
assert(byID[1].races==2 and byID[1].wins==2 and byID[1].laps==8,'BJR reads existing account statistics')
assert(byID[1].kilometres==10 and byID[1].safety==store.drivers['account:1'].safety,'BJR shows saved distance and safety')
assert(byID[2].contacts==2 and byID[2].safety==before,'guest identity lookup also uses numeric IDs')
assert(byID[0].races==0 and byID[0].safety==3,'player zero is valid and an unknown driver stays provisional')
print('PASS: driver identity, statistics, no-fault incidents, optional safety updates, dedup and display')
