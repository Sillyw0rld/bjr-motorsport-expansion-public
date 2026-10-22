-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- Public BJR client interfaces; never constructs legacy BJI globals.
local P=require('ge/extensions/raceprep/platform')
BJI={CLIENT_READY=true};assert(P.get('BJI')==BJI)
raceprepBJR={};beamjoy_main={client_ready=true};beamjoy_cache={loaded=true}
MPCoreNetwork={isMPSession=function() return true end};MPGameNetwork={launcherConnected=function() return true end}
MPConfig={getPlayerServerID=function() return 2 end}
beamjoy_permissions={hasAllPermissions=function() return true end};BJ_PERMISSIONS={SetConfig='SetConfig'}
local veh={getID=function() return 7 end};be={getPlayerVehicle=function() return veh end}
MPVehicleGE={isOwn=function() return true end}
beamjoy_players={players={A={playerID=2,playerName='A'}}}
local r={id=1,name='Circuit',loopable=true,gates={{pos={x=0,y=0,z=0},dir={x=0,y=1,z=0},width=20,step=1},{pos={x=0,y=100,z=20},dir={x=0,y=1,z=0},width=10,step=2}}}
beamjoy_races={data={r}}
beamjoy_raceRunner={countdownStartMs=1000,countdownTotal=10,session={id='a',raceId=1,state='COUNTDOWN',settings={laps=3},participants={{playerID=2,gridSlot=2},{playerID=1,gridSlot=1}}}}
GetCurrentTimeMillis=function() return 2000 end
local h=require('ge/extensions/raceprep/bjr/host')
assert(h.ready() and h.canEdit() and h.editable()==false)
assert(h.vehicle()==veh and P.get('BJI_Context').Players[2].playerName=='A')
local s=P.get('BJI_Scenario').get();assert(s.race.startTime==11000 and s.grid.participants[1]==1)
GetCurrentTimeMillis=function() return 3000 end
assert(P.get('BJI_Scenario').get().race.startTime==11000,'countdown anchor stable')
local t=P.track(r);assert(t.steps[1][1].pos.y==100 and t.steps[2][1].pos.y==0,'BJR finish is first gate')
assert(t.steps[1][1].radius==5)
beamjoy_raceRunner.session.state='GRID';assert(h.editable())
beamjoy_raceRunner.session.participants[1].ready=true;assert(not h.editable())
MPVehicleGE.isOwn=function() return false end;assert(not h.vehicle())
print('PASS: BJR readiness, ownership, permissions, countdown, grid and race translation')
