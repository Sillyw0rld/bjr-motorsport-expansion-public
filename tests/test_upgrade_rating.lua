-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local fixture=dofile('tests/fixtures/rating-golden.lua')
local catalog=dofile('tests/fixtures/upgrade-parts.lua')
local R=dofile('client/lua/ge/extensions/raceprep/rating.lua')
package.path='client/lua/?.lua;'..package.path
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
jsonReadFile=function(path)
 if path:find('ratings%-seed') then return {entries=catalog.bases,constants=fixture.constants} end
 return {parts=catalog.parts}
end
local Anchors=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local configs={neonna_gt='a6a97',hawk_fm5='6024e'}
local rows={}
for _,f in ipairs(fixture.fixtures) do rows[f.model]=f end
local function predicted(model,st)
 local f=rows[model]
 local base=catalog.bases[model]
 local score=assert(R.compute(st,fixture.constants,f.drive))
 -- The same anchored delta as raceprepRatings.anchor, against the seed.
 local anchored=Anchors.anchor(score,model)
 assert(anchored.anchored,model.." must use stock anchoring")
 return anchored.pi
end
for _,model in ipairs({'neonna_gt','hawk_fm5','guiness_copper'}) do
 local original=rows[model].static
 local last=predicted(model,original)
 for _,percent in ipairs({10,20,35}) do
  local st=clone(original)
  for _,engine in ipairs(st.engines) do for _,point in ipairs(engine.torque) do point[2]=point[2]*(1+percent/100) end end
  local pi=predicted(model,st)
  assert(pi>last,model..' non-increasing stage rating');last=pi
 end
 print(model..' power stage progression passed')
end
for _,model in ipairs({'neonna_gt','hawk_fm5'}) do
 local original=rows[model].static
 local last
 for _,compound in ipairs({'sport','semi_slick','race_hard','race_medium','race_soft'}) do
  local st=clone(original)
  for _,wheel in ipairs(st.wheels) do
   local axle=wheel.name:sub(1,1)=='F' and 'front' or 'rear'
   local donor
   for _,p in pairs(catalog.parts) do
    if p.kind=='tyre' and p.compound==compound and p.axle==axle and p.offsetMM==0 and p.stockPart==('Camso_wheels_'..axle..'_'..configs[model]) then donor=p end
   end
   assert(donor,'No tyre donor')
   wheel.noLoadCoef=donor.coefficients.noLoadCoef;wheel.tireWidth=donor.widthMM/1000
  end
  local pi=predicted(model,st)
  if last then assert(pi>=last,model..' compound order at '..compound) end
  local wide=clone(st)
  for _,wheel in ipairs(wide.wheels) do wheel.tireWidth=wheel.tireWidth+.04 end
  assert(predicted(model,wide)>pi,model..' width rating')
  last=pi
 end
 print(model..' tyre compound / width progression passed')
end
print('anchored upgrade progression passed; native max-point collection requires game validation')
