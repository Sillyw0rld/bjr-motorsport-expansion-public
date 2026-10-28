-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared eligibility and bounded draft search; never fits a part.
local B={CLASSES={'D','C','B','A','S','R'}}
function B.band(class,classOf)
 local lo,hi;for pi=100,999 do if classOf(pi)==class then lo=lo or pi;hi=pi end end;return lo,hi
end
function B.refusal(rules,car,factory,classOf)
 local target=rules and rules.targetClass;if not target or target==''then return end
 local lo,hi=B.band(target,classOf);if not lo then return 'Invalid target class.'end
 if not factory or type(factory.pi)~='number'then return 'Waiting for this car’s factory PI.'end
 if factory.pi>hi then return "This car's factory PI is already above "..target end
 if not car or type(car.pi)~='number'then return 'Waiting for the current car PI.'end
 local label='Your car is '..classOf(car.pi)..' '..car.pi..': '
 if car.pi>hi then return label..(car.pi-hi)..' PI over the '..target..' limit'end
 if car.pi<lo then return label..(lo-car.pi)..' PI below the '..target..' minimum'end
end
local function copy(t)local out={};for k,v in pairs(t or {})do out[k]=v end;return out end
local function key(t)local a={};for k,v in pairs(t)do a[#a+1]=k..'='..v end;table.sort(a);return table.concat(a,'|')end
B.key=key
-- One async evaluation at a time. Balanced search shares budget across grip,
-- brakes, weight and power before repeatedly spending in one category.
function B.search(api,mode)
 local cap=api.cap-(mode=='fit'and 0 or 5)
 local draft=copy(api.draft);local categories={'grip','brakes','weight','power','other'}
 local self={mode=mode,checked=0,steps=0,cycleSteps=0};local round=1;local index=0;local candidates={};local best;local base
 local seen={};local frontier={{draft=draft}};local fitIndex=0;local fitResult
 function self.step()
  if self.done then return self.result,self.message end
  if mode=='fit'then
   -- Best-first subset search of reversible downgrades, checking each combined
   -- build with the shared predictor. Keep the closest verified PI <= cap.
   local state=frontier[1]
   if not state then self.done=true;self.result=fitResult and fitResult.draft;self.message=fitResult and 'Review the smallest predicted reduction found.'or'No permitted fit was found.';return self.result,self.message end
   local signature=key(state.draft)
   if seen[signature]then table.remove(frontier,1);return end
   local e,why,pending=api.predict(state.draft);if pending then return end
   seen[signature]=true;self.checked=self.checked+1;table.remove(frontier,1)
   if e then
    if e.pi<=cap then if not fitResult or e.pi>fitResult.pi then fitResult={pi=e.pi,draft=state.draft}end
    else for _,o in ipairs(api.options)do if o.remove and not state.draft[o.row]and api.allowed(o)then local nextDraft=copy(state.draft);nextDraft[o.row]=o.name;frontier[#frontier+1]={draft=nextDraft}end end end
   end
   if self.checked>=api.limit or #frontier==0 then frontier={}end
   return
  end
  if not base then local e,why,pending=api.predict(draft);if pending then return end;if not e then self.done=true;self.message=why or'Estimate unavailable.';return end;base=e.pi;if base>cap then self.done=true;self.result=draft;self.predictedPI=base;self.message='Use Fit to class or remove parts first.';return draft,self.message end end
  if index<#api.options then
   index=index+1;local o=api.options[index]
   if o.category==categories[round]and api.allowed(o)and draft[o.row]~=o.name and not o.remove then
    local proposal=copy(draft);proposal[o.row]=o.name
    local e,why,pending=api.predict(proposal)
    if pending then index=index-1;return end
    self.checked=self.checked+1
    if e and e.pi<=cap and e.pi>base then
     local budget=(cap-base)/math.max(1,5-round);local distance=math.abs((e.pi-base)-budget)
     if not best or distance<best.distance or distance==best.distance and e.pi>best.pi then best={draft=proposal,pi=e.pi,distance=distance}end
    end
   end
   return
  end
  if best then draft=best.draft;base=best.pi;self.steps=self.steps+1 end
  best=nil;index=0;round=round+1
  if round>#categories then round=1;if not self.cycleSteps or self.cycleSteps==self.steps then self.done=true;self.result=draft;self.predictedPI=base;self.message='Review the balanced draft; estimated PI '..base..' / '..cap..' (5 PI margin).';return draft,self.message end;self.cycleSteps=self.steps end
  if self.checked>=api.limit or self.steps>=12 or base==cap then self.done=true;self.result=draft;self.predictedPI=base;self.message='Review the balanced draft; estimated PI '..base..' / '..cap..' (5 PI margin).';return draft,self.message end
 end
 return self
end
return B
