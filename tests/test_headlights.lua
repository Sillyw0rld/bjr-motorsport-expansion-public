-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- raceprep/headlights: aim measurement and the aim solver (the in-game loop
-- was proven live on 2026-10-14; these check the maths offline)
package.path='client/lua/?.lua;'..package.path
local V={};V.__index=V
function vec3(x,y,z) if type(x)=="table" then return setmetatable({x=x.x,y=x.y,z=x.z},V) end return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function V.dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
function V.cross(a,b) return vec3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
V.__add=function(a,b) return vec3(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__mul=function(a,s) return vec3(a.x*s,a.y*s,a.z*s) end
function V.normalized(a) local l=math.sqrt(a:dot(a));return vec3(a.x/l,a.y/l,a.z/l) end
local H=dofile('client/lua/ge/extensions/raceprep/headlights.lua')
local fwd,up=vec3(0,-1,0),vec3(0,0,1) -- BeamNG cars face -Y
local function dirOf(pitch,yaw)
 local p,y=math.rad(pitch),math.rad(yaw)
 local right=fwd:cross(up)
 return vec3(fwd.x*math.cos(p)*math.cos(y)+right.x*math.cos(p)*math.sin(y)+up.x*math.sin(p),
  fwd.y*math.cos(p)*math.cos(y)+right.y*math.cos(p)*math.sin(y)+up.y*math.sin(p),
  fwd.z*math.cos(p)*math.cos(y)+right.z*math.cos(p)*math.sin(y)+up.z*math.sin(p))
end
local a=H.angles(dirOf(-2.5,1.5),vec3(0.5,-1.8,0.9),fwd,up)
assert(math.abs(a.pitch+2.5)<1e-6 and math.abs(a.yaw-1.5)<1e-6 and a.front,'front light pitch/yaw')
local r=H.angles(vec3(0,1,0),vec3(0.5,2.0,0.9),fwd,up)
assert(not r.front and math.abs(math.abs(r.yaw)-180)<1e-6,'tail-light headlight points backwards')
-- a light whose rotation axes are skewed against the car (as Automation's
-- helper nodes make them): the solver still reaches the target in a few steps
local J={{0.8,0.3},{0.1,-0.2},{-0.4,0.9}}
local pitch,yaw,rot=-4,2,{0,0,0}
local function response() return -4+J[1][1]*rot[1]+J[2][1]*rot[2]+J[3][1]*rot[3], 2+J[1][2]*rot[1]+J[2][2]*rot[2]+J[3][2]*rot[3] end
for _=1,3 do
 pitch,yaw=response()
 local d=H.solve(J,{H.LOW.pitch-pitch,-yaw})
 for i=1,3 do rot[i]=rot[i]+d[i] end
end
pitch,yaw=response()
assert(math.abs(pitch-H.LOW.pitch)<1e-6 and math.abs(yaw)<1e-6,'aimed: '..pitch..' / '..yaw)
assert(H.solve({{0,0},{0,0},{0,0}},{1,1})==nil,'no response: no change')
assert(H.LOW.pitch==-0.6 and H.HIGH.pitch==-0.3 and H.HIGH.range==300 and H.LOW.range==120,'live-tuned values')
assert(H.LOW.brightness==3.0 and H.HIGH.brightness==7.2,'brightness +20 % (owner)')
print('PASS: headlight angles (front / tail fixture), skewed-axis aim solver, live-tuned beam values')

-- a car rebuilt (reset / respawn) while its lights are being aimed: the job
-- must never touch the old, freed light objects (1.8.8 crashed the game)
do
 local H=dofile('client/lua/ge/extensions/raceprep/headlights.lua')
 local function Q() return {} end
 quat=function() return setmetatable({}, {__mul=function() return vec3(0,-1,0) end}) end
 tableSizeC=function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
 ColorF=function() return {} end
 local freed=false
 local function newCar()
  local props={[0]={mesh='SPOTLIGHT',func='lowbeam',pid=0,lightColor={r=255,g=255,b=255,a=255}}}
  local live={freed=false}
  local obj={getLiveTransformWorld=function(self) assert(not live.freed,'used a freed light object')
     return {toQuatF=function() return {} end,getColumn=function() return vec3(0,-2,0.8) end} end,
   setBaseRotation=function(self) assert(not live.freed,'used a freed light object') end,
   getLight=function(self) assert(not live.freed,'used a freed light object') return {setLightArgs=function() end} end}
  local veh={getID=function() return 7 end,getProp=function(_,pid) return props[pid] and obj end,
   getDirectionVector=function() return vec3(0,-1,0) end,getDirectionVectorUp=function() return vec3(0,0,1) end}
  return {vdata={props=props,activeParts={a='Camso_Engine_1'}},veh=veh,live=live}
 end
 local car=newCar()
 be={getObjectCount=function() return 1 end,getObject=function() return car.veh end,getObjectByID=function() return car.veh end}
 core_vehicle_manager={getVehicleData=function() return {vdata=car.vdata} end}
 H.LOW.pitch=-0.6
 local clock=0
 for _=1,3 do H.update(clock);clock=clock+0.6 end -- settle, then the aiming job starts
 for _=1,4 do H.update(clock);clock=clock+0.02 end -- job running
 car.live.freed=true;car=newCar() -- rebuilt mid-job: old objects freed
 for _=1,60 do H.update(clock);clock=clock+0.02 end
 print('PASS: car rebuilt while its headlights are aimed: no freed light object touched')
end
