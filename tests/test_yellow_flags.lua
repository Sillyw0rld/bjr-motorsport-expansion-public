-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- yellow flags (2026-10-17): local hazard yellows only for drivers in the race;
-- full-course yellow for everyone, spectators included
local part,own=true,nil
local raceObj={STATES={RACE='RACE'},state='RACE',isParticipant=function() return part end}
BJI_Scenario={TYPES={RACE_MULTI='race'},get=function() return raceObj end}
BJI_Veh={getCurrentVehicleOwn=function() return own end}
local D=require('ge/extensions/raceprep/director')
D.hazards={['7']={position={x=100,y=0,z=0}}}
local near={getPosition=function() return {x=0,y=0,z=0} end}
own=near
assert(D.yellow():find('stopped car ahead'),'driver near a stopped car: local yellow')
part=false
assert(D.yellow()==nil,'spectator with a car of their own: no race hazard yellows')
own=nil
assert(D.yellow()==nil,'spectator without a car: no "hazards reported" banner')
D.data={fullCourseYellow=true}
assert(D.yellow():find('FULL COURSE YELLOW'),'full-course yellow shows for spectators too')
print('PASS: hazard yellows for drivers in the race; full-course yellow for everyone')
