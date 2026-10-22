-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- v7 (2026-10-16): Automation cars are exactly v6; native cars with the
-- probed aero (nativeAero) get true drag/downforce and their own factors
local R=dofile('client/lua/ge/extensions/raceprep/rating.lua')
local fixture=dofile('tests/fixtures/rating-golden-v6.lua')
local function deep(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=deep(v) end return o end
local c6=fixture.constants
local c7=deep(c6);c7.v7=deep(c6.v6);c7.v7.native={lat=0.83,brake=1.13,q=0.01,r0=2.4}
for _,f in ipairs(fixture.fixtures) do
  local a,b=assert(R.compute(f.static,c6,f.drive)),assert(R.compute(f.static,c7,f.drive))
  assert(a.pi==b.pi and a.pi_speed==b.pi_speed and a.pi_technical==b.pi_technical,'Automation car changed under v7: '..f.model)
end
assert(R.compute(fixture.fixtures[1].static,c7,fixture.fixtures[1].drive).method=='formula-v7')
-- a native car: probed aero replaces the default area; native factors apply
local st=deep(fixture.fixtures[1].static)
local plain=assert(R.compute(st,c7,fixture.fixtures[1].drive))
st.nativeAero={cdA=0.9,dfF200=-200,dfR200=0}
local native=assert(R.compute(st,c7,fixture.fixtures[1].drive))
assert(native.pi<plain.pi,'more drag, lift and lower native grip rate lower')
local slick=deep(st);slick.nativeAero={cdA=1.4,dfF200=2400,dfR200=3800}
assert(R.compute(slick,c7,fixture.fixtures[1].drive).pi_technical>native.pi_technical,'downforce raises the technical rating')
local bad=deep(st);bad.nativeAero={cdA=-1,dfF200=0,dfR200=0}
assert(R.compute(bad,c7,fixture.fixtures[1].drive).pi==plain.pi,'invalid probe data is ignored')
print('PASS: v7 leaves Automation cars on v6; native probed aero and factors apply only to native cars')
-- v7: a native axle without ABS brakes at the native no-ABS factor
do
  local c=deep(c7);c.v7.native.noAbs=0.7
  local st=deep(fixture.fixtures[1].static);st.nativeAero={cdA=0.9,dfF200=0,dfR200=0}
  local withAbs=assert(R.compute(st,c,fixture.fixtures[1].drive))
  for _,w in ipairs(st.wheels) do w.abs=false end
  local noAbs=assert(R.compute(st,c,fixture.fixtures[1].drive))
  assert(noAbs.pi<withAbs.pi,'locking brakes cost PI')
  local auto=deep(fixture.fixtures[1].static);for _,w in ipairs(auto.wheels) do w.abs=false end
  assert(R.compute(auto,c,fixture.fixtures[1].drive).pi==R.compute(fixture.fixtures[1].static,c,fixture.fixtures[1].drive).pi,'Automation cars: no ABS factor')
  print('PASS: native no-ABS braking factor')
end
-- v7: native electric drive uses its measured efficiency (0.95, AWD included)
do
  local c=deep(c7);c.v7.native.evEff=0.95
  local st=deep(fixture.fixtures[1].static);st.nativeAero={cdA=0.9,dfF200=0,dfR200=0}
  local ice=assert(R.compute(st,c,fixture.fixtures[1].drive))
  st.engineKind={kind='electric'}
  local ev=assert(R.compute(st,c,fixture.fixtures[1].drive))
  assert(ev.pi_speed>ice.pi_speed,'single-reduction electric drive keeps more power')
  local auto=deep(fixture.fixtures[1].static);auto.engineKind={kind='electric'}
  assert(R.compute(auto,c,fixture.fixtures[1].drive).pi==R.compute(fixture.fixtures[1].static,c,fixture.fixtures[1].drive).pi,'Automation cars: unchanged')
  print('PASS: native EV drivetrain efficiency')
end
