-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Formula v6: the game's rating.lua must reproduce the Python reference
-- (calib/fit3/v6_reference.py) on every measured car's rig data + geometry.
local fixture=dofile('tests/fixtures/rating-golden-v6.lua')
local rating=dofile('client/lua/ge/extensions/raceprep/rating.lua')
local count,maxError=0,0
for _,f in ipairs(fixture.fixtures) do
 local r,err=rating.compute(f.static,fixture.constants,f.drive);assert(r,f.model..": "..tostring(err))
 assert(r.method=="formula-v6",f.model.." did not use formula v6")
 for _,field in ipairs({"pi","pi_speed","pi_technical"}) do
  local delta=math.abs(r[field]-f.expected[field]);maxError=math.max(maxError,delta)
  assert(delta<=3,string.format("%s %s expected %d got %d",f.model,field,f.expected[field],r[field]))
 end
 count=count+1
end
-- aero kit: the kit's extra drag counts x kitDrag; same result as giving the
-- car that drag area directly (how the Python analysis rated kits)
do
 local f=fixture.fixtures[1]
 local consts={};for k,v in pairs(fixture.constants) do consts[k]=v end
 local v6={};for k,v in pairs(fixture.constants.v6) do v6[k]=v end;v6.kitDrag=1.303;consts.v6=v6
 local function withAero(aero) local s={};for k,v in pairs(f.static) do s[k]=v end;s.aero=aero;return s end
 local base,rated=f.static.aero.vehicleArea or .7,2.0
 local kit=rating.compute(withAero({downforceTargetFront=3000,downforceTargetRear=3000,targetSpeedKMH=200,vehicleArea=rated,kitBaseCdA=base}),consts,f.drive)
 local direct=rating.compute(withAero({downforceTargetFront=3000,downforceTargetRear=3000,targetSpeedKMH=200,vehicleArea=base+1.303*(rated-base)}),consts,f.drive)
 local plain=rating.compute(withAero({downforceTargetFront=3000,downforceTargetRear=3000,targetSpeedKMH=200,vehicleArea=rated}),consts,f.drive)
 assert(kit.pi==direct.pi and kit.pi_speed==direct.pi_speed and kit.pi_technical==direct.pi_technical,'kit extra drag x1.303')
 assert(kit.pi<plain.pi,'the measured kit drag costs PI against the rated drag')
end
-- old car data without geometry/suspension: v6 still rates it (no weight
-- transfer, no softness penalty) instead of failing
local plain={};for k,v in pairs(fixture.fixtures[1].static) do plain[k]=v end
plain.geometry,plain.suspension=nil,nil
local r=rating.compute(plain,fixture.constants,fixture.fixtures[1].drive);assert(r and r.pi and r.rollPerG==nil)
print(string.format("PASS: formula v6 matches the Python reference on %d cars (%d ratings), maximum error %d PI; kit drag factor; missing geometry falls back",count,count*3,maxError))
