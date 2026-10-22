-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local G=dofile('client/lua/ge/extensions/raceprep/bjr/grid.lua')
local function entry(id)
 if id==3 then error('not collected') end
 return {class='B',pi=550,pi_speed=600,pi_technical=510,source='computed',anchored=true,
  method='formula-v6',performancePI=530,tuningPotentialPI=20,parts={private='large parts tree'}}
end
local session={state='GRID',settings={placementMode='manual'},participants={
 {playerID=2,playerName='Second',displayName='Nickname',ready=true,joinIndex=2,gridSlot=1,vehicleModel='car2'},
 {playerID=1,playerName='Self',ready=false,joinIndex=1,gridSlot=3,vehicleModel='car1'},
 {playerID=3,playerName='Pending',ready=false,joinIndex=3,gridSlot=2}}}
local out=G.snapshot(session,1,{getPlayer=entry})
assert(out.active and out.total==3 and out.readyCount==1)
assert(out.rows[1].name=='Nickname' and out.rows[1].position==1 and out.rows[1].ready)
assert(out.rows[2].playerID==3 and not out.rows[2].rating,'pending peer does not break grid')
assert(out.rows[3].isSelf and out.rows[3].position==3)
assert(out.rows[1].rating.pi_speed==600 and out.rows[1].rating.pi_technical==510 and out.rows[1].rating.method=='formula-v6')
assert(out.rows[1].rating.tuningPotentialPI==20 and out.rows[1].rating.performancePI==530)
assert(not out.rows[1].rating.parts,'compact tooltip entry excludes parts data')
session.settings.placementMode='deterministic';out=G.snapshot(session,1,{getPlayer=entry})
assert(out.rows[1].playerID==1 and out.rows[1].position==1)
session.settings.placementMode='random';out=G.snapshot(session,1,{getPlayer=entry})
assert(out.rows[1].playerID==1 and not out.rows[1].position and out.note:find('random'),'never invent random slots')
session.participants={};out=G.snapshot(session,1);assert(out.total==0 and out.readyCount==0)
assert(not G.snapshot(nil).active)
session.state='RACE';assert(not G.snapshot(session).active)
print('PASS: native BJR grid ready count, self/nickname, compact rating details, manual/join/random order and missing peers')
