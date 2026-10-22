-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Exercise the actual canonical collector with a different live Race slider.
package.path='client/lua/?.lua;'..package.path
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
tableMergeRecursive=function(a,b) for k,x in pairs(b) do a[k]=x end return a end
tableFromHeaderTable=function(rows)
 local out={}
 for i=2,#rows do local row={} for j,key in ipairs(rows[1]) do row[key]=rows[i][j] end out[#out+1]=row end
 return out
end
createCurve=function(points)
 local out={}
 for i=1,#points-1 do
  local a,b=points[i],points[i+1]
  for rpm=a[1],b[1] do out[rpm]=a[2]+(b[2]-a[2])*(rpm-a[1])/math.max(1,b[1]-a[1]) end
 end
 return out
end
local actual={name='mainEngine',type='camsoEngine',idleRPM=800,maxRPM=2000}
actual.getTorqueData=function(self)
 local curve={}
 for rpm,t in pairs(self.torqueThrottleMap[99]) do curve[rpm]=t-(self.frictionTorqueTable[rpm] or 0) end
 return {maxRPM=2000,maxPowerRPM=2000,curves={{torque=curve}},finalCurveName=1}
end
powertrain={getDevicesByCategory=function() return {actual} end}
wheels={wheels={}}
local captured,serializeValue
serialize=function(t) serializeValue=t;return '{}' end
obj={getID=function() return 1 end,queueGameEngineLua=function() captured=serializeValue end}
local C=dofile('client/lua/vehicle/extensions/raceprepRating.lua')
local data={nodes={[1]={nodeWeight=100,pos={y=-1}},[2]={nodeWeight=100,pos={y=1}}},
 wheels={{name='FR',node1=1,node2=1,radius=.3,tireWidth=.245,noLoadCoef=1.5,compound='sport'}},
 powertrain={},mainEngine={torque={{'throttle','rpm','torque','Pressure'},{99,1000,200,1},{99,2000,180,1}},
 frictionTorque={{'rpm','torque'},{1000,20},{2000,10}},maxRPM=2000},
 engineSpec={stockRevLimit=2000,ecu='race',ecuGain=.5},
 downforceModel={downforceTargetFront=100,downforceTargetRear=200,targetSpeedKMH=200},
 dragModel={vehicleArea=.5},raceprepAero={ratedFrontN=1000,ratedRearN=2000,ratedCdA=.8,baseCdA=.5}}
C.collect(clone(data),'one')
assert(not captured.error,tostring(captured.error))
local first=clone(captured)
assert(first.engineKind.kind=='automation' and first.engineKind.supported,'canonical engine classification')
data.engineSpec.ecuGain=1
C.collect(clone(data),'two')
assert(not captured.error,tostring(captured.error))
local function at(res,rpm) for _,p in ipairs(res.engines[1].torque) do if p[1]==rpm then return p[2] end end end
assert(math.abs(at(first,1000)-at(captured,1000))<1e-6,'race ECU slider does not change the rated curve')
assert(math.abs(at(first,1000)-180*1.05)<0.2,'race ECU rated at its full +5%: '..tostring(at(first,1000)))
-- turbo: PI curve discounts the gain for lag (small turbo 10 %)
data.engineSpec={stockRevLimit=2000,induction='turbo_small',turboLayout='single'}
C.collect(clone(data),'three')
assert(not captured.error,tostring(captured.error))
assert(math.abs(at(captured,1000)-180*(1+.40*.90))<0.2,'small turbo +40 % less 10 % lag discount: '..tostring(at(captured,1000)))
assert(first.aero.downforceTargetFront==1000 and first.aero.downforceTargetRear==2000 and first.aero.vehicleArea==.8)
assert(first.aero.kitBaseCdA==.5,'v6 collector retains stock CdA to scale only added kit drag')
assert(first.wheels[1].compound=='sport' and first.wheels[1].tireWidth==.245)
-- formula v6 inputs. Node positions are vec3 cdata in the game, not plain
-- tables (a type()=='table' check silently dropped all geometry, 2026-10-15)
local ffi=require('ffi')
pcall(ffi.cdef,'typedef struct { double x, y, z; } rp_test_v3;')
local function v3(x,y,z) return ffi.new('rp_test_v3',x,y,z) end
local car=clone(data)
car.nodes={[1]={nodeWeight=500,pos=v3(0,-1.2,0.5)},[2]={nodeWeight=500,pos=v3(0,1.3,0.5)},
 [3]={nodeWeight=0,pos=v3(-0.8,-1.2,0.3)},[4]={nodeWeight=0,pos=v3(-0.7,-1.2,0.3)},
 [5]={nodeWeight=0,pos=v3(0.7,-1.2,0.3)},[6]={nodeWeight=0,pos=v3(0.8,-1.2,0.3)},
 [7]={nodeWeight=0,pos=v3(-0.8,1.3,0.3)},[8]={nodeWeight=0,pos=v3(-0.7,1.3,0.3)},
 [9]={nodeWeight=0,pos=v3(0.7,1.3,0.3)},[10]={nodeWeight=0,pos=v3(0.8,1.3,0.3)}}
car.wheels={{name='FL',node1=3,node2=4,radius=.3,tireWidth=.245,noLoadCoef=1.5},{name='FR',node1=5,node2=6,radius=.3,tireWidth=.245,noLoadCoef=1.5},
 {name='RL',node1=7,node2=8,radius=.3,tireWidth=.245,noLoadCoef=1.5},{name='RR',node1=9,node2=10,radius=.3,tireWidth=.245,noLoadCoef=1.5}}
car.suspension={springs={spring_FL=34000,spring_FR=34000,spring_RL=40000,spring_RR=40000},bars={torsionBarFront=1960,torsionBarRear=1101}}
C.collect(car,'geo')
assert(not captured.error,tostring(captured.error))
local g,sp=captured.geometry,captured.suspension
assert(g,'geometry collected from vec3 node positions')
assert(math.abs(g.cogHeight-0.5)<1e-6,'CoG 0.5 m above ground (contact 0.3-0.3=0): '..tostring(g.cogHeight))
assert(math.abs(g.wheelbase-2.5)<1e-6 and math.abs(g.trackF-1.5)<1e-6,'wheelbase 2.5, track 1.5')
assert(sp and sp.springF==34000 and sp.springR==40000 and sp.barF==1960 and sp.barR==1101,'stock springs and sway bars')
print('actual collector: race ECU rated at maximum, turbo lag PI discount, max aero and tyre fields, v6 geometry from vec3 nodes and stock suspension passed')
-- A direct-drive EV must retain its torque above the power peak. There is
-- no transmission shift at peak power; this used to cap eSBR at 150 km/h.
actual.type='electricMotor'
actual.getTorqueData=function(self)
 local curve={}
 for rpm,t in pairs(self.torqueCurve) do curve[rpm]=t end
 return {maxRPM=2000,maxPowerRPM=1000,curves={{torque=curve}},finalCurveName=1}
end
local ev=clone(car)
ev.mainEngine={torque={{'rpm','torque'},{0,100},{1000,100},{2000,50}},maxRPM=2000}
ev.engineSpec=nil
ev.vehicleController={highShiftUpRPM=1100}
ev.powertrain={}
C.collect(ev,'ev')
assert(not captured.error,tostring(captured.error))
assert(captured.engineKind.kind=='electric' and captured.shift.highShiftUpRPM==2000,'fixed electric drive uses motor limit')
assert(ev.vehicleController.highShiftUpRPM==1100,'canonical input not mutated')
ev.powertrain={{type='automaticGearbox',name='gearbox',gearRatios={-2,0,2,1}}}
C.collect(ev,'ev-gearbox')
assert(not captured.error,tostring(captured.error))
assert(captured.shift.highShiftUpRPM==1100,'an actual EV gearbox retains its canonical shift rule')
print('fixed-drive EV redline and explicit-gearbox behavior passed')
