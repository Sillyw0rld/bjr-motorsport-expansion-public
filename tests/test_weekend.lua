-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race weekend + Motorsport settings (2026-10-21, owner design):
-- practice -> qualifying at once -> grid -> race -> ended; permissions by BJR group
local W=dofile('server/RacePrep/Weekend.lua')
local w=W.new({raceID=3,level='imola',raceName='Imola',practiceMinutes=15,qualifyingMinutes=10,by='Sillyw0rld'},100)
assert(w.raceID=='3')
local k,m=W.first(w);assert(k=='practice' and m==15)
k,m=W.after(w,'practice');assert(k=='qualifying' and m==10,'practice ends: qualifying at once')
assert(W.after(w,'qualifying')=='grid')
local noQ=W.new({raceID=1,practiceMinutes=5,qualifyingMinutes=0},0)
assert(W.after(noQ,'practice')=='grid','no qualifying: straight to the grid')
assert(W.first(W.new({raceID=1,practiceMinutes=0,qualifyingMinutes=8},0))=='qualifying')
assert(W.first(W.new({raceID=1},0))=='grid','nothing set: grid only')
w.stage='grid'
assert(not W.raceStarted(w,'4') and W.raceStarted(w,3) and w.stage=='race','only this race starts the race stage')
assert(W.raceFinished(w,'3') and w.stage=='ended')
assert(W.new({raceID=1,practiceMinutes=999},0).practiceMinutes==120,'minutes clamped')
local v=W.view(w);assert(v.label=='Ended' and v.raceName=='Imola' and v.by=='Sillyw0rld')
local g=W.gridList({{playerID=7,name='A'},{playerID=2,name='B'}});assert(g[2].pos==2 and g[2].playerID==2)

local S=dofile('server/RacePrep/MotorsportSettings.lua')
local groups={{name='default'},{name='player'},{name='vip'},{name='mod'},{name='admin'},{name='owner'}}
local s=S.sanitize(nil,groups)
assert(s.permissions.weekend=='mod' and s.permissions.rules=='admin' and s.permissions.raceControl=='mod','owner-approved defaults')
assert(s.weekend.practiceMinutes==10 and s.weekend.gridOrder=='qualifying' and s.weekend.gridSource=='rules')
assert(S.allowed(s,'weekend','mod',groups) and S.allowed(s,'weekend','admin',groups) and not S.allowed(s,'weekend','vip',groups))
assert(not S.allowed(s,'rules','mod',groups) and S.allowed(s,'rules','admin',groups))
assert(not S.allowed(s,'rules',nil,groups) and not S.allowed(s,'rules','stranger',groups),'unknown group: no')
local open=S.sanitize({permissions={weekend='everyone',rules='owner',raceControl='nonsense'},weekend={practiceMinutes=-5,qualifyingMinutes='12',gridOrder='reverse',gridSource='weekend'}},groups)
assert(open.permissions.weekend=='everyone' and S.allowed(open,'weekend','default',groups))
assert(open.permissions.rules=='owner' and not S.allowed(open,'rules','admin',groups) and S.allowed(open,'rules','owner',groups),'owner always')
assert(open.permissions.raceControl=='mod','unknown group name falls back to the default')
assert(open.weekend.practiceMinutes==0 and open.weekend.qualifyingMinutes==12 and open.weekend.gridOrder=='reverse' and open.weekend.gridSource=='weekend')
assert(S.rank(groups,'vip')==3 and S.rank(nil,'owner')==6,'no groups.json: BeamJoy default order')
print('PASS: race weekend stages (practice -> qualifying at once -> grid -> race -> ended) and Motorsport settings permissions by BJR group')
