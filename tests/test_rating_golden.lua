-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local fixture=dofile(arg[1] or 'tests/fixtures/rating-golden.lua')
local rating=dofile(arg[2] or 'client/lua/ge/extensions/raceprep/rating.lua')
local count,maxError=0,0
for _,f in ipairs(fixture.fixtures) do
 local r,err=rating.compute(f.static,fixture.constants,f.drive);assert(r,f.model..": "..tostring(err))
 for _,field in ipairs({"pi","pi_speed","pi_technical"}) do
  local delta=math.abs(r[field]-f.expected[field]);maxError=math.max(maxError,delta)
  assert(delta<=3,string.format("%s %s expected %d got %d",f.model,field,f.expected[field],r[field]))
 end
 assert(r.class==rating.classOf(r.pi));count=count+1
end
for _,test in ipairs({{300,"E"},{301,"D"},{400,"D"},{401,"C"},{500,"C"},{501,"B"},{600,"B"},{601,"A"},{700,"A"},{701,"S"},{800,"S"},{801,"R"},{900,"R"},{901,"P"},{998,"P"},{999,"X"}}) do assert(rating.classOf(test[1])==test[2]) end
assert(rating.violation({allowedClasses={C=false}},{class="C",pi=475}));assert(not rating.violation({allowedClasses={B=true}},{class="B",pi=550}))
assert(rating.violation({piMin=500},{class="C",pi=475}));assert(rating.violation({piMax=600},{class="A",pi=650}));assert(rating.violation({piMax=600},nil))
print(string.format("PASS: %d cars / 165 ratings, maximum error %d PI; class boundaries and class/PI limits pass",count,maxError))
