-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local W=dofile('server/RacePrep/Weekend.lua')
local phases=W.phases{practiceMinutes=15,qualifyingMinutes=10,raceLaps=8}
assert(#phases==3 and phases[1].name=='Practice' and phases[1].timeLimitMin==15 and phases[1].ranking=='best')
assert(phases[1].countsToEvent==false and phases[1].leaderboard==false and phases[1].afterTime=='own')
assert(phases[2].name=='Qualifying' and phases[2].countsToEvent==false)
assert(phases[3].name=='Race' and phases[3].laps==8 and phases[3].countsToEvent==true and phases[3].ranking=='position')
local noPractice=W.phases{practiceMinutes=0,qualifyingMinutes=9,raceLaps=5}
assert(#noPractice==2 and noPractice[1].name=='Qualifying' and noPractice[2].name=='Race','practice toggle')
local raceOnly=W.phases{practiceMinutes=0,qualifyingMinutes=0,raceLaps=3}
assert(#raceOnly==1 and raceOnly[1].name=='Race','plain single phase')
local format=W.format{practiceMinutes=5,qualifyingMinutes=4,raceLaps=7}
assert(format.id=='weekend' and format.result=='last' and format.locked[1]=='phases')
local payload=W.openPayload{raceID='3',name='Imola weekend',practiceMinutes=5,qualifyingMinutes=4,raceLaps=7}
assert(payload.raceId==3 and payload.options.format==nil and payload.options.result=='last' and #payload.options.phases==3)
assert(not W.isRacePhase{session={phaseCount=3},phase={name='Qualifying',ranking='best',countsToEvent=false}})
assert(W.isRacePhase{session={phaseCount=3},phase={name='Race',ranking='position',countsToEvent=true}})
assert(W.isRacePhase{session={phaseCount=1}},'plain one-phase race')
local w=W.new{raceID=3,level='imola',raceName='Imola',practiceMinutes=5,qualifyingMinutes=4,raceLaps=7,by='Sillyw0rld'}
assert(W.update(w,{raceId=3,sessionId='s1',phaseIndex=1,phaseCount=3,phase={name='Practice'}},'race') and w.stage=='practice')
assert(W.update(w,{raceId=3,sessionId='s1',phaseIndex=2,phase={name='Qualifying'}},'break') and w.stage=='break_')
assert(not W.update(w,{raceId=4},'race'),'another event cannot move this weekend')
local v=W.view(w);assert(v.sessionId=='s1' and v.raceLaps==7 and v.phaseCount==3)
assert(not W.update(w,{raceId=3,sessionId='other',phase={name='Race'}},'race'),'same track, different event cannot move this weekend')
local fromMenu=W.fromSession({format=W.FORMAT_REF,sessionId='menu',raceId=3,map='imola',phases=phases,phaseIndex=1,phase=phases[1]},0)
assert(fromMenu and fromMenu.practiceMinutes==15 and fromMenu.raceLaps==8 and fromMenu.stage=='grid','menu format follows the same weekend')
local phaseView=W.phaseView({sessionId='menu',raceId=3,phaseIndex=2,phase=phases[2],map='imola',endsAt={unixMs=200000},racers={{id=5,racerKey=1,name='Rejoined',lap=3,bestLapMs=61000},{id=2,racerKey=2,name='Faster',lap=2,bestLapMs=60000}}},100000)
assert(phaseView.native and phaseView.remaining==100000 and phaseView.rows[1].name=='Faster' and phaseView.rows[2].gap==1000)
local finished=W.phaseView({sessionId='menu',raceId=3,phaseIndex=2,phase=phases[2],results={{racerKey=1,name='Away',bestLapMs=60000,laps={{lap=1,timeMs=60000,sectorsMs={20000,20000,20000}}}}}})
assert(finished.state=='ended' and finished.rows[1].racerKey==1 and finished.rows[1].bestSectors[2]==20000 and #finished.rows[1].lapList==1)

local S=dofile('server/RacePrep/MotorsportSettings.lua')
local groups={{name='default'},{name='player'},{name='vip'},{name='mod'},{name='admin'},{name='owner'}}
local s=S.sanitize(nil,groups)
assert(s.permissions.weekend=='mod' and s.permissions.rules=='admin' and s.permissions.raceControl=='mod')
assert(s.weekend.practiceMinutes==10 and s.weekend.qualifyingMinutes==10 and s.weekend.raceLaps==5)
local open=S.sanitize({permissions={weekend='everyone'},weekend={practiceMinutes=-5,qualifyingMinutes='12',raceLaps=2000,gridOrder='reverse',gridSource='weekend'}},groups)
assert(open.weekend.practiceMinutes==0 and open.weekend.qualifyingMinutes==12 and open.weekend.raceLaps==1000)
assert(open.weekend.gridOrder=='reverse' and open.weekend.gridSource=='weekend' and S.allowed(open,'weekend','default',groups))
print('PASS: BJR three-phase weekend, optional timed phases, race-only result payload and Motorsport settings')
