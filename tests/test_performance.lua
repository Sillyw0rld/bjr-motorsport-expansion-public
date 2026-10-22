-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- Setup performance panel: model figures from the PI curves, anchored to rig runs
local fixture=dofile('tests/fixtures/rating-golden-v6.lua')
local rating=dofile('client/lua/ge/extensions/raceprep/rating.lua')
local fm5
for _,f in ipairs(fixture.fixtures) do if f.model=='hawk_fm5' then fm5=f end end
local base=assert(rating.performance(fm5.static,fixture.constants,fm5.drive))
for _,k in ipairs({'zeroTo60','sixtyTo100','brake60','brake120','lat60','lat120','topSpeed'}) do assert(base[k] and base[k]>0,k) end
assert(base.brake120>base.brake60*3,'120-0 much longer than 60-0')
local light={};for k,v in pairs(fm5.static) do light[k]=v end;light.mass=fm5.static.mass*0.85
local fast=assert(rating.performance(light,fixture.constants,fm5.drive))
assert(fast.zeroTo60<base.zeroTo60 and fast.sixtyTo100<base.sixtyTo100,'lighter accelerates faster')
-- anchoring: measured stock car shows its rig figures; changes scale them
local seedCars={hawk_fm5={config='6024e',measured={zeroTo60=4.2,sixtyTo100=5.0,brake60=31,brake120=129,lat60=1.21},
 model={zeroTo60=base.zeroTo60,sixtyTo100=base.sixtyTo100,brake60=base.brake60,brake120=base.brake120,lat60=base.lat60,lat120=base.lat120}}}
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
jsonReadFile=function(path)
 if path:find('performance%-seed') then return {cars=seedCars} end
 if path:find('ratings%-seed') then return {entries={},constants={}} end
 return {models={},parts={}}
end
readFile=function() return '{}' end;jsonDecode=function() return {models={}} end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local stock=R.anchorPerformance('hawk_fm5',base)
assert(math.abs(stock.zeroTo60-4.2)<1e-9 and math.abs(stock.brake60-31)<1e-9 and stock.measured,'stock car = rig figures')
assert(math.abs(stock.lat120-1.21*base.lat120/base.lat60)<1e-9,'g at 120 mph scaled from the measured 60 mph figure')
assert(stock.estimated and stock.estimated.topSpeed and stock.topSpeed==base.topSpeed,'top speed without a measured seed stays a marked estimate')
for k in pairs(stock.estimated) do assert(k=='topSpeed','existing measured figures remain anchored') end
local tuned=R.anchorPerformance('hawk_fm5',fast)
assert(math.abs(tuned.zeroTo60-4.2*fast.zeroTo60/base.zeroTo60)<1e-9 and tuned.zeroTo60<4.2,'change scales the rig figure')
local other=R.anchorPerformance('unknown_car',base)
assert(not other.measured and other.estimated.zeroTo60 and other.zeroTo60==base.zeroTo60,'unmeasured: model estimate, marked')
seedCars.hawk_fm5.measured.topSpeed=75;seedCars.hawk_fm5.model.topSpeed=base.topSpeed
local speed=R.anchorPerformance('hawk_fm5',fast)
assert(math.abs(speed.topSpeed-75*fast.topSpeed/base.topSpeed)<1e-9 and not speed.estimated,'measured top speed anchors when available')
-- rating replies go through onStatic, which also routes stats replies: it must
-- never crash (preview.10 to v2.10.0.104 indexed an undeclared statsRequests: every
-- rating reply failed, cars stayed "Rating pending")
assert(pcall(R.onStatic,35044,'2',{mass=1269.4}),'onStatic with a rating reply')
print('PASS: onStatic routes rating replies without the stats bookkeeping crashing')
-- the shipped seed: one entry per measured stock car, rig and model figures
local seed=io.open('client/lua/ge/extensions/raceprep/performance-seed.json'):read('*a')
assert(select(2,seed:gsub('"measured"',''))>=50,'measured performance for the fleet')
print(string.format('PASS: performance panel figures (FM5 model 0-60 %.1f s, rig 4.2 s), mass effect, rig anchoring and estimates',base.zeroTo60))
