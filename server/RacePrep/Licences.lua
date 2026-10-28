-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local L={names={'Rookie','D','C','B','A','Pro'},letters={'R','D','C','B','A','P'}}
L.bars={{races=0,safety=0,skill=0},{races=5,safety=2,skill=0},{races=15,safety=3,skill=0},
 {races=30,safety=3,skill=3000},{races=50,safety=4,skill=3400},{races=100,safety=4.5,skill=3800}}
function L.rank(name) for i,n in ipairs(L.names) do if n==name then return i end end;return 0 end
function L.settings(v)
 v=type(v)=='table' and v or {};local n=tonumber(v.races) or 3;if n~=n then n=3 end
 return {demotion=(v.demotion=='immediately' or v.demotion=='never') and v.demotion or 'after',races=math.max(1,math.min(10,math.floor(n)))}
end
function L.update(d,p,skill,settings,scored)
 settings=L.settings(settings);p=p or {};local rank=L.rank(d.licence);if rank<1 then rank=1 end
 local eligible=1
 for i,b in ipairs(L.bars) do if (p.races or 0)>=b.races and (p.safety or 0)>=b.safety and (skill or 0)>=b.skill then eligible=i end end
 if eligible>rank then rank=eligible;d.below=0
 elseif scored then
  if (p.safety or 0)<L.bars[rank].safety then
   d.below=(d.below or 0)+1
   if settings.demotion=='immediately' or (settings.demotion=='after' and d.below>=settings.races) then rank=math.max(1,rank-1);d.below=0 end
  else d.below=0 end
 end
 d.licence=L.names[rank];d.earnedLicences=d.earnedLicences or {};for i=1,rank do d.earnedLicences[L.names[i]]=true end
 return d
end
function L.refusal(minimum,d)
 local need=L.rank(minimum);if need>1 and (not d or L.rank(d.licence)<need) then return 'This event requires licence '..minimum..' or higher.' end
end
function L.view(d,p,skill)
 d=d or {};p=p or {};local rank=math.max(1,L.rank(d.licence));local b=L.bars[rank+1]
 local requirements
 if b then
  local grade=({[2]='C+',[3]='B+',[4]='A+',[4.5]='S'})[b.safety] or ''
  requirements={{name='Races',value=p.races or 0,required=b.races,decimals=0},{name='Safety '..grade,value=p.safety or 0,required=b.safety,decimals=1}}
  if b.skill>0 then requirements[#requirements+1]={name='Skill',value=skill or 1000,required=b.skill,decimals=0} end
  for _,r in ipairs(requirements) do r.gap=math.max(0,r.required-r.value) end
 end
 return {licence=L.names[rank],letter=L.letters[rank],below=d.below or 0,next=b and L.names[rank+1],requirements=requirements}
end
return L
