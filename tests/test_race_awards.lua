-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Awards=dofile('server/RacePrep/RaceAwards.lua')
local function key(k) return {racerKey=k} end
local function award(res,id) for _,a in ipairs(res.awards) do if a.id==id then return a end end end
local function winners(a) local out={};for _,w in ipairs(a and a.winners or {}) do out[#out+1]=w.racerKey end;return table.concat(out,',') end
local GREEN=1000000000 -- ms
local function rows()
 local clean={firstAt=GREEN/1000,lastAt=GREEN/1000+300,samples=100,maxGap=1,contacts=0}
 return {
  {racerKey='b',name='B',status='FIN',position=1,total=300000,best={time=61000}},
  {racerKey='d',name='D',status='FIN',position=2,total=301000,best={time=62000}},
  {racerKey='a',name='A',status='FIN',position=3,total=302000,best={time=60000}},
  {racerKey='c',name='C',status='FIN',position=4,total=303000,best={time=63000},incidents=clean},
 }
end
local function phase(A,i,grid)
 local g={};for n,k in ipairs(grid) do g[n]={racerKey=k,gridPosition=n} end
 A.event('RaceCountdown',{sessionId='w',phaseIndex=i,grid=g})
 A.event('RaceGreenLight',{sessionId='w',phaseIndex=i,greenAt={unixMs=GREEN}})
end

-- Weekend: practice and qualifying events must not reach the race's awards.
local A=Awards.new();A.capabilities({events={'RacePositionsChanged','RacerReset','RaceControl'}})
phase(A,1,{'a','b','c','d'})
A.event('RacerReset',{sessionId='w',phaseIndex=1,racer=key('c')})
A.event('RacePositionsChanged',{sessionId='w',phaseIndex=1,changes={{racer=key('a'),to=4}}})
phase(A,2,{'a','b','c','d'})
A.event('RaceControl',{sessionId='w',phaseIndex=2,racer=key('c'),penaltyMs=5000})
A.event('RacePositionsChanged',{sessionId='w',phaseIndex=2,changes={{racer=key('a'),to=4}}})
phase(A,3,{'a','b','c','d'})
A.event('RacePositionsChanged',{sessionId='w',phaseIndex=3,changes={{racer=key('b'),to=4}}})
A.event('RacerReset',{sessionId='w',phaseIndex=2,racer=key('c')}) -- late qualifying event: ignored
local res={runID='w',phaseCount=3,rows=rows(),recordContext={rules={trackLimits='invalid'}}}
A.result(res)
assert(winners(award(res,'fastest'))=='a','fastest valid race lap')
assert(winners(award(res,'gained'))=='d','places gained from the race grid')
assert(winners(award(res,'comeback'))=='b','comeback from the race phase only; a lost places only in practice/qualifying')
assert(winners(award(res,'clean'))=='c','practice reset and qualifying penalty do not cost the race cleanest award')
assert(res.awardsNote:find('race only',1,true),'weekend note')

-- Ordinary single-phase race: unchanged.
A=Awards.new();A.capabilities({events={'RacePositionsChanged','RacerReset','RaceControl'}})
phase(A,1,{'a','b','c','d'})
A.event('RacerReset',{sessionId='w',phaseIndex=1,racer=key('c')})
res={runID='w',rows=rows(),recordContext={rules={trackLimits='invalid'}}}
A.result(res)
assert(winners(award(res,'fastest'))=='a' and winners(award(res,'gained'))=='d')
assert(award(res,'clean')==nil,'a reset in the race itself costs cleanest')
assert(not res.awardsNote:find('race only',1,true))
print('PASS: weekend awards come from the race phase only; ordinary races unchanged')
