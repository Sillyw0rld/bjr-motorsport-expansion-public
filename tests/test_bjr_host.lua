-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR state without a bridge file (2.14.2): BJRHost from BJR's API and race files
Util={JsonDecode=function() end};MP={GetPlayers=function() return {[1]='Ana',[2]='Ben',[3]='Cy'} end}
local H=dofile('server/RacePrep/BJRHost.lua')
H.enabled=true
-- races.sessions -> runs (BJR 2.0 session shape)
local now=1000000
local runs=H.fromSessions({
 {sessionId=7,raceId=3,raceName='Imola',map='imola',state='COUNTDOWN',phaseIndex=3,phaseCount=3,phase={name='Race'},greenAt={unixMs=now+4000},racers={{id=1,racerKey='a',lap=1},{id=2,racerKey='b',lap=1}}},
 {sessionId=8,raceId=4,raceName='Ring',map='imola',state='RACE',greenAt={unixMs=now-30000},racers={{id=3,lap=2}}},
 {sessionId=9,raceId=5,state='GRID',racers={}},
},now)
assert(runs['7'].phase=='race' and runs['7'].remaining==4000 and runs['7'].participants[2]==2 and runs['7'].laps['1']==1,'countdown: remaining to green')
assert(runs['7'].racerKeyByPlayer['1']=='a' and runs['7'].phaseIndex==3,'stable racer identity and phase metadata')
assert(runs['8'].phase=='race' and runs['8'].elapsed==30 and runs['8'].laps['3']==2,'race: time since green')
assert(runs['9'].phase=='grid' and #runs['9'].participants==0)
assert(next(H.fromSessions(nil,now))==nil)
assert(not H.fresh(),'stale until a poll answers');H.setRuns(runs);assert(H.fresh())
assert(H.runFor(3)=='8' and H.runFor(9)==nil)
local t=H.targets('7');table.sort(t);assert(#t==2 and t[1]==1 and t[2]==2)
-- players.online -> staff and names
H.setPlayers({{id=1,name='ana',displayName='Ana',staff=true,group='admin'},{id=2,name='ben',staff=false}})
assert(H.canEdit(1) and not H.canEdit(2) and H.names['1']=='Ana' and H.names['2']=='ben')
-- race layouts from BJR's saved race file, read once per map
local reads=0
H.loadRaces=function(level) reads=reads+1;assert(level=='imola');return {{id=3,name='Imola',loopable=true,sectorCount=3,
 gates={{pos={x=0,y=0,z=0},dir={x=1,y=0,z=0},width=20,step=1},{pos={x=100,y=0,z=0},dir={x=1,y=0,z=0},width=16,step=2},{pos={x=200,y=0,z=0},dir={x=1,y=0,z=0},step=3}},
 startPositions={{pos={x=-5,y=0,z=0},dir={x=1,y=0,z=0}}}}} end
H.setLevel('imola')
local r=H.race('imola',3)
assert(r and r.name=='Imola' and #r.steps==3 and r.steps[3][1].radius==10,'loopable: start/finish gate last')
assert(r.steps[1][1].radius==8 and r.startPositions[1].rot and r.nativeRace.sectorCount==3)
assert(H.race('imola',3) and reads==1,'read once per map')
assert(H.race('other',3)==nil,'another map: nothing')
H.setLevel('imola');assert(H.race('imola',99)==nil and reads==1)
H.racesLevel=nil;H.race('imola',3);assert(reads==2,'RacesChanged: read again')
H.setLevel('mosport');assert(#H.races==0,'map change drops layouts')
-- start report: every API feature BJR:ME uses, available or missing
local A=dofile('server/RacePrep/BJRApi.lua')
local rep=A.report({methods={'races.sessions','players.online','environment.set','results.setFields','pages.register','hooks.register','formats.register','race.open','race.endPhase','race.close','race.penalize'},
 events={'RacePositionsChanged','RacerReset','RaceControl','RaceFinished','RacePhaseFinished','RaceGridOpened','RaceGreenLight','RaceCountdown','RaceClosed','MapChanged','RacesChanged','PlayerLeft','EnvironmentChanged'}})
assert(#rep.ok==#A.USES and #rep.missing==0,'all present on BJR 2.0')
rep=A.report({methods={'races.sessions'},events={}})
assert(#rep.ok==1 and #rep.missing==#A.USES-1 and rep.missing[1]:find('gridOrder',1,true),'missing ones named')
-- track limits per phase: a qualifying cut is recorded without a penalty and kept
-- when the race phase starts (it decides which qualifying laps set the grid)
local qrules={trackLimits='penalty',cutPenaltyAfter=0,cutPenaltySeconds=5}
H.setRuns(H.fromSessions({{sessionId=20,raceId=6,state='RACE',phaseIndex=2,phaseCount=3,phase={name='Qualifying'},greenAt={unixMs=now-1000},racers={{id=1,racerKey='q1',lap=2}}}},now))
local qcut=H.cut(1,{raceID=6,lap=2},qrules)
assert(qcut and qcut.penaltyMs==0 and qcut.racerKey=='q1','qualifying cut recorded, no time penalty')
assert(H.phaseCuts(20,2).q1['2']==1,'running phase cuts readable')
H.setRuns(H.fromSessions({{sessionId=20,raceId=6,state='RACE',phaseIndex=3,phaseCount=3,phase={name='Race'},greenAt={unixMs=now-1000},racers={{id=1,racerKey='q1',lap=1}}}},now))
assert(H.phaseCuts(20,2).q1['2']==1 and H.phaseCuts(20,3)==nil,'qualifying cuts kept, race starts clean')
local rcut=H.cut(1,{raceID=6,lap=1},qrules)
assert(rcut and rcut.penaltyMs==5000,'race cut is penalised')
H.setRuns({})
assert(H.phaseCuts(20,2)==nil,'cleared when the event ends')
print('PASS: BJR state from its API and race files (sessions, players, layouts), no bridge; start report of every API feature used')
