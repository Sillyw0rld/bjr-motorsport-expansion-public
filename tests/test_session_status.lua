-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local map,freeroam,car='here',true,{}
getCurrentLevelIdentifier=function() return map end
package.loaded['ge/extensions/raceprep/platform']={isBJR=function() return true end,get=function(name)
 if name=='BJI_Veh' then return {getCurrentVehicleOwn=function() return car end} end
 if name=='BJI_Scenario' then return {TYPES={},isFreeroam=function() return freeroam end,get=function() end} end
end}
local S=dofile('client/lua/ge/extensions/raceprep/session.lua')
assert(S.status().code=='none')
S.data={id='q',state='running',track={level='other'}};assert(S.status().code=='map')
S.data.track.level='here';freeroam=false;assert(S.status().code=='freeroam')
freeroam=true;car=nil;assert(S.status().code=='vehicle')
car={};assert(S.status().code=='checkpoints')
S.data.track.nativeRace={gates={{},{}}};assert(S.status().timing)
S.data.track.nativeRace.branchingEnabled=true;assert(S.status().sectorMessage:find('sector'))
S.data.state='ended';assert(S.status().code=='ended')
print('PASS: session reasons for no session, wrong map, active race, car, checkpoints, branching sectors and end')
