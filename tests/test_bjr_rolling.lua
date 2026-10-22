-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local R=dofile('client/lua/ge/extensions/raceprep/bjr/rollingStart.lua')
local race={startPositions={{pos={x=0,y=0,z=0}},{pos={x=0,y=-10,z=0}}}}
local a={playerID=9,playerName='Leader',startPosition=race.startPositions[1],currentGate=0}
local b={playerID=3,playerName='Self',startPosition=race.startPositions[2],currentGate=0}
local session={settings={placementMode='random'},participants={b,a}}
assert(R.order(session,race)[1].player==a,'actual randomized placements, not join order')
local p={[9]={pos={x=0,y=10,z=0},dir={x=0,y=1}},[3]={pos={x=3,y=15,z=0},dir={x=0,y=1}}}
local pass=R.check(session,race,3,p);assert(pass and pass.metres==5,'same gate wheel-to-wheel pass caught in metres')
p[3].pos.y=5;assert(not R.check(session,race,3,p),'back behind clears warning')
p[3].pos.y=15;p[3].pos.z=8;assert(not R.check(session,race,3,p),'overpass excluded')
p[3].pos.z=0;p[3].dir.y=-1;assert(not R.check(session,race,3,p),'opposing road excluded')
p[3].dir.y=1;p[3].pos.x=30;assert(not R.check(session,race,3,p),'distant lateral section excluded')
p[3].pos={x=7,y=17,z=0};p[9].dir={x=1,y=1};p[3].dir={x=1,y=1}
assert(R.check(session,race,3,p),'curved heading uses spatial projection')
a.currentGate=1;assert(R.released(session),'native gate 1 releases formation');a.currentGate=0
assert(not R.released(session));a.startPosition=nil;b.startPosition=nil;assert(not R.order(session,race),'unassigned random grid is never guessed')
session.settings.placementMode='deterministic';a.joinIndex=1;b.joinIndex=2;assert(R.order(session,race)[1].player==a)
print('PASS: native gate-1 release, actual random grid, metre-based same-section pass and ambiguity guards')
