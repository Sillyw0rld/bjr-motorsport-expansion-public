-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local W=dofile('server/RacePrep/WeeklyRivals.lua')
local P=dofile('server/RacePrep/Persistence.lua')
local now=1793000000;local disk;local writes=0;local blocked=false
local row={driver='driver',model='car',time=12000,runID='run',verified=false}
local api={now=function() return now end,copy=P.copy,read=function() return disk end,exists=function() return disk~=nil end,
 write=function(v) disk=P.copy(v);writes=writes+1;return true end,
 groups=function() return {g={id='g',raceID=1,class='B',raceName='Fixture',layout='l',rulesKey='r',rules={},bests={row}}} end,
 available=function() return true end,carAvailable=function() return true end,blocked=function() return blocked end}
local w=W.new(api);assert(w.get('fixture')==nil and writes==0,'legacy baselines cannot seed weekly targets')
row.verified=true;local pick=assert(w.get('fixture'));assert(writes==1 and pick.target.verified)
blocked=true;local old,why=w.get('fixture');assert(old.id==pick.id and why and writes==1,'moderated weekly target preserved and disabled')
blocked=false;disk.picks[pick.id].target.verified=nil
local reload=W.new(api);old,why=reload.get('fixture');assert(old.id==pick.id and why and writes==1,'old frozen weekly target retained, not silently replaced')
print('PASS: only verified weekly baselines; unverified and moderated frozen targets retained but unavailable')
