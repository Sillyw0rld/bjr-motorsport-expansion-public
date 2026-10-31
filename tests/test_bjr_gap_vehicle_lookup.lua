package.path='client/lua/?.lua;'..package.path
local host={vehicle=function() return nil end,playerID=function() return 1 end,ready=function() return true end,canEdit=function() return false end}
package.loaded['ge/extensions/raceprep/frontend']={host=function() return host end}
package.loaded['ge/extensions/raceprep/bjr/raceGaps']={}
local remote={getPosition=function() return {x=12,y=34,z=0} end,getDirectionVector=function() return {x=1,y=0,z=0} end}
be={getObjectByID=function(_,id) return id==42 and remote or nil end}
beamjoy_players={players={{playerID=2,playerName='Ben',currentVehicle='200'}}}
beamjoy_vehicles={vehicles={}}
MPVehicleGE={getVehicles=function() return {{ownerID='2',gameVehicleID=42,remoteVID=200}} end}
local d=dofile('client/lua/ge/extensions/raceprep/bjr/driving.lua')
local cars=d.positions()
assert(cars[2] and cars[2].id==42,'string/numeric remote IDs match through MPVehicleGE')

-- BJR's own normalized remoteVID route is also used when MPVehicleGE has no row.
MPVehicleGE.getVehicles=function() return {} end
beamjoy_players.players={Ben={playerID=2,playerName='Ben',currentVehicle='300'}}
beamjoy_vehicles.vehicles={{ownerID='2',ownerName='Ben',remoteVID=300,vid=42,isVehicle=true,veh=remote}}
cars=d.positions()
assert(cars[2] and cars[2].id==42,'string/numeric currentVehicle matches BJR remoteVID')
print('PASS: remote position lookup by BJR playerID through MPVehicleGE and remoteVID')
