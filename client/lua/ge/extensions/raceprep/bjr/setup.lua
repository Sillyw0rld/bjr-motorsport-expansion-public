-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared BJR setup metadata and rule checks. UI uses display units; JBeam
-- remains in its native units. The same checks guard Apply and native Ready.
local P=require('ge/extensions/raceprep/tuningPolicy')
local S={}
function S.finite(n) n=tonumber(n);return n and n==n and math.abs(n)<math.huge and n or nil end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
-- BeamNG setConfigVars replaces config.vars (mergeConfig is shallow). A
-- partial slider/reset update must carry the other applied settings with it.
function S.mergeVars(d,changes)
 local vars={}
 for name,m in pairs(d.vdata.variables or {}) do
  if type(m)=='table' then
   local value=S.finite(m.val) or S.finite(m.default)
   if value then vars[name]=value end
  end
 end
 for name,value in pairs(d.config.vars or {}) do vars[name]=value end
 for name,value in pairs(changes or {}) do vars[name]=value end
 return vars
end
local function different(a,b) return S.finite(a) and S.finite(b) and math.abs(a-b)>1e-4*math.max(1,math.abs(b)) end
function S.aero(name,m)
 if type(m)~='table' then return false end
 local s=(tostring(name)..' '..tostring(m.title)..' '..tostring(m.category)..' '..tostring(m.subCategory)):lower()
 return s:find('aero',1,true) or s:find('downforce',1,true) or name=='$bodyDragCoef' or name=='$frontalAreaAdjust'
end
function S.front(dev,split) return dev.frontOutput==2 and 1-split or split end
function S.split(dev,share) return dev.frontOutput==2 and 1-share or share end
function S.toDisplay(m,n)
 if m.minDis and m.maxDis and m.max~=m.min then return m.minDis+(n-m.min)*(m.maxDis-m.minDis)/(m.max-m.min) end
 return n
end
function S.fromDisplay(m,n)
 if m.minDis and m.maxDis and m.maxDis~=m.minDis then return m.min+(n-m.minDis)*(m.max-m.min)/(m.maxDis-m.minDis) end
 return n
end
function S.diffKind(name,m,owners)
 local text=(tostring(name)..' '..tostring(m.title)..' '..tostring(m.category)):lower()
 local diff=name=='$torquesplit' or P.role(name,m.title)=='differential'
 for _,owner in ipairs((owners or {})[name] or {}) do if P.role(owner.part,owner.title)=='differential' then diff=true end end
 if not diff then return end
 if name=='$torquesplit' then return 'split' end
 if text:find('preload',1,true) then return 'preload' end
 if text:find('coast',1,true) or text:find('revlock',1,true) then return 'coast' end
 if text:find('lock',1,true) then return 'lock' end
 return 'differential'
end
-- Most car files give no step. A fixed 0.01 made springs read "20000.00" and
-- left toe (0.995-1.005) with two positions: use about 1/500 of the range,
-- rounded down to a power of ten.
function S.step(m,lo,hi)
 local step=S.finite(m.step)
 if step and step>0 then return step end
 return 10^math.floor(math.log10((hi-lo)/500))
end
-- Forza-style setup sections (the UI's sub-tabs). Car authors' categories
-- differ, so this reads name, title, category and sub-category together.
-- "advanced": personal settings (camera, force feedback, sound), always free.
-- "hidden": BeamNG's structural and offset multipliers (beam/node scaling,
-- engine offsets, hub/rim stiffness): not race setup, always locked.
local function any(s,words) for _,w in ipairs(words) do if s:find(w,1,true) then return true end end return false end
function S.section(name,m,kind)
 local cat,sub=tostring(m.category or ''):lower(),tostring(m.subCategory or ''):lower()
 local s=(tostring(name)..' '..tostring(m.title)..' '..cat..' '..sub):lower()
 if kind then return 'differential' end
 if S.aero(name,m) then return 'aero' end
 if s:find('coolingduct',1,true) then return 'brakes' end
 if cat:find('camera',1,true) or cat:find('force feedback',1,true) or any(s,{'volume','whine','sound','afterfire','particul','cabinfilter','ffb'}) then return 'advanced' end
 if cat=='vehicle advanced settings' then return 'hidden' end
 if any(s,{'tire pressure','tyre pressure','tirepressure','tyrepressure','psi'}) then return 'tyres' end
 if any(s,{'final drive','finaldrive','$gear_','gear ratio'}) then return 'gearing' end
 if sub=='transfer case' or cat:find('differential',1,true) or any(s,{'coupling','lsd'}) then return 'differential' end
 if any(s,{'boost','turbo','supercharg','rev limit','rpm limit','revlimit','idle','cut time','rpm drop','soft limit','n2o','nitrous','engine','motor','regen','fuel','charge'}) then return 'engine' end
 if any(s,{'sway','anti-roll','antiroll','torsionbar'}) then return 'antiroll' end
 if any(s,{'damp','bump','rebound','shock'}) then return 'damping' end
 if any(s,{'spring','ride height','rideheight'}) then return 'springs' end
 if any(s,{'camber','toe','caster','steer','trackoffset','wheel offset','brakeoffset','brake offset'}) then return 'alignment' end
 if s:find('brake',1,true) then return 'brakes' end
 if cat=='tyres' or cat=='tires' or cat=='wheels' then return 'tyres' end
 return 'other'
end
function S.variables(d,r,flags)
 local out={};local owners=P.owners(d.vdata)
 for name,m in pairs(d.vdata.variables or {}) do
  if type(m)=='table' then
  local lo,hi=S.finite(m.min),S.finite(m.max)
  local val=S.finite((d.config.vars or {})[name]) or S.finite(m.val) or S.finite(m.default)
  if type(name)=='string' and type(m)=='table' and m.hideInUI~=true and (m.type==nil or m.type=='range') and lo and hi and hi>lo and val then
   local allowed,reason=P.allowed(d.vdata,name,m,owners)
   local fuel=name:lower():find('fuel',1,true)~=nil
   local aero=S.aero(name,m)
   local kind=S.diffKind(name,m,owners)
   local section=S.section(name,m,kind)
   if section=='advanced' then allowed,reason=true,nil elseif section=='hidden' then allowed,reason=false,'Not a race setup setting' end
   if name=='$torquesplit' then allowed=P.raceDifferential(d.vdata,'centre');reason=not allowed and 'Needs a race centre differential' or nil end
   if not flags.editable or (not fuel and not flags.tuningEditable) then allowed=false;reason='Locked by BJR session/vehicle restriction' end
   if (kind and r.diff==false) or (fuel and r.fuel==false) or (not fuel and not aero and section~='advanced' and r.tuning==false) or (aero and r.aero==false) or (name=='$torquesplit' and (r.diff==false or r.centreSplit==false)) then allowed=false;reason='Locked by race rules' end
   local row={name=name,title=m.title or name,description=m.description,subCategory=m.subCategory,unit=m.unit or '',category=aero and 'Aero' or name:find('CoolingDuct',1,true) and 'Cooling' or m.category or 'General',
    min=lo,max=hi,minDis=S.finite(m.minDis),maxDis=S.finite(m.maxDis),stepDis=S.finite(m.stepDis),step=S.step(m,lo,hi),
    default=S.finite(m.default),value=clamp(val,lo,hi),allowed=allowed==true,reason=reason,fuel=fuel,aero=aero and true or false,
    section=section,side=P.axle(name,m.title),diffKind=kind}
   row.displayMin=math.min(S.toDisplay(row,lo),S.toDisplay(row,hi));row.displayMax=math.max(S.toDisplay(row,lo),S.toDisplay(row,hi))
   row.displayStep=row.stepDis or math.abs(S.toDisplay(row,lo+row.step)-S.toDisplay(row,lo))
   row.displayValue=S.toDisplay(row,row.value)
   out[#out+1]=row
  end
 end
 end
 table.sort(out,function(a,b) if a.category~=b.category then return a.category<b.category end;return a.title<b.title end)
 return out
end
-- Structural settings ("hidden" section) can still be changed in BeamNG's own
-- tuning menu. Racing requires the car's defaults; node weight is the body
-- upgrade instead (raceprep/weight). Returns {name=default} to reset, or nil.
function S.hiddenChanges(d)
 local out,count={},0
 for name,m in pairs(d.vdata.variables or {}) do
  if type(m)=='table' and name~='$nodeWeightScale' and S.section(name,m)=='hidden' then
   local val=S.finite((d.config.vars or {})[name]) or S.finite(m.val) or S.finite(m.default)
   local def=S.finite(m.default)
   if def and different(val,def) then out[name]=def;count=count+1 end
  end
 end
 return count>0 and out or nil,count
end
function S.hiddenProblem(d)
 local changes,count=S.hiddenChanges(d)
 if changes then return count..' advanced car setting'..(count>1 and 's were' or ' was')..' changed in the BeamNG tuning menu: reset to car defaults (Setup).' end
end
function S.aeroProblem(d,r)
 if r.aero~=false then return end
 if d.vdata.raceprepAero then return 'Aero kit not allowed.' end
 for name,m in pairs(d.vdata.variables or {}) do
  if S.aero(name,m) and m.default and different(S.finite((d.config.vars or {})[name]) or S.finite(m.val) or S.finite(m.default),S.finite(m.default)) then return 'Aero must be stock; reset aero in the Aero tab.' end
 end
end
function S.diffProblem(d,r,settings,devices)
 local owners=P.owners(d.vdata)
 for name,m in pairs(d.vdata.variables or {}) do
  if type(m)=='table' then
   local kind=S.diffKind(name,m,owners)
   local val=S.finite((d.config.vars or {})[name]) or S.finite(m.val) or S.finite(m.default)
   if kind and val and kind~='split' then
    if r.diff==false and different(val,S.finite(m.default)) then return 'Differential tuning must be stock.' end
    local limit=kind=='preload' and (r.maxPreload or 500) or (kind=='lock' or kind=='coast') and ((m.max or 1)>1 and (r.maxLock or 100) or (r.maxLock or 100)/100)
    if limit and (val<0 or val>limit+.00001) then return 'Differential '..kind..' exceeds race limits.' end
   end
  end
 end
 local known={};for _,dev in ipairs(devices or {}) do known[dev.name]=true end
 for name,v in pairs(settings or {}) do if not known[name] and (v.mode~='stock' or v.split~=nil) then return 'Waiting for differential report.' end end
 for _,dev in ipairs(devices or {}) do
  local v=(settings or {})[dev.name]
  if v then
   if v.mode and v.mode~='stock' then
    if r.diff==false then return 'Stock differential required.' end
    if not ({open=true,lsd=true,locked=true})[v.mode] or (r.diffModes or {})[v.mode]==false then return 'Differential mode is not allowed.' end
    if not P.raceDifferential(d.vdata,dev.position) then return 'Fit a race differential before changing it.' end
    if v.mode=='lsd' then
     for k,max in pairs{preload=r.maxPreload or 500,lock=(r.maxLock or 100)/100,coast=(r.maxLock or 100)/100} do
      local n=S.finite(v[k] or dev[k]);if not n or n<0 or n>max+1e-6 then return 'Differential '..k..' exceeds race limits.' end
     end
    end
   end
   if dev.position=='centre' and S.finite(v.split) then
    local share=S.front(dev,v.split)
    if r.diff==false or r.centreSplit==false then
     if different(v.split,dev.stockSplit) then return 'Centre split must be stock.' end
    elseif share<(r.centreSplitMin or .2)-.00001 or share>(r.centreSplitMax or .8)+.00001 then return 'Centre front share outside race limits.' end
   end
  end
  if dev.position=='centre' then
   local m=(d.vdata.variables or {})['$torquesplit']
   local current=m and (S.finite((d.config.vars or {})['$torquesplit']) or S.finite(m.val) or S.finite(m.default))
   if current then
    if r.diff==false or r.centreSplit==false then if different(current,S.finite(m.default)) then return 'Centre split must be stock.' end
    else local share=S.front(dev,current);if share<(r.centreSplitMin or .2)-.00001 or share>(r.centreSplitMax or .8)+.00001 then return 'Centre front share outside race limits.' end end
   end
  end
 end
end
function S.diffApply(d,r,devices,requested)
 local values,vars={},{}
 local byName={};for _,dev in ipairs(devices or {}) do byName[dev.name]=dev end
 for name,v in pairs(requested or {}) do
  local dev=byName[name];if not dev or type(v)~='table' then return nil,nil,'Unknown differential.' end
  local n={mode=v.mode or 'stock'}
  if n.mode=='lsd' then
   for k,max in pairs{preload=r.maxPreload or 500,lock=(r.maxLock or 100)/100,coast=(r.maxLock or 100)/100} do
    local x=S.finite(v[k] or dev[k]);if not x then return nil,nil,'Invalid differential value.' end;n[k]=clamp(x,0,max)
   end
  end
  if dev.position=='centre' and n.mode=='stock' and v.frontShare==nil then
   local m=(d.vdata.variables or {})['$torquesplit'];if m and S.finite(m.default) then vars['$torquesplit']=m.default end
  end
  if dev.position=='centre' and v.frontShare~=nil then
   local share=S.finite(v.frontShare);if not share then return nil,nil,'Invalid front share.' end
   if r.diff==false or r.centreSplit==false then
    if different(S.split(dev,share),dev.stockSplit) then return nil,nil,'Centre split is locked.' end
   else
    if not P.raceDifferential(d.vdata,'centre') then return nil,nil,'Needs a race centre differential.' end
    share=clamp(share,r.centreSplitMin or .2,r.centreSplitMax or .8)
    local m=(d.vdata.variables or {})['$torquesplit']
    local split=S.split(dev,share)
    if m then vars['$torquesplit']=clamp(split,m.min,m.max) else n.split=split end
   end
  elseif v.split~=nil then n.split=S.finite(v.split);if not n.split then return nil,nil,'Invalid split.' end end
  values[name]=n
 end
 local updated={};for k,v in pairs(d.config.vars or {}) do updated[k]=v end;for k,v in pairs(vars) do updated[k]=v end
 local why=S.diffProblem({vdata=d.vdata,config={vars=updated}},r,values,devices);if why then return nil,nil,why end
 return values,vars
end
function S.preset(kind,devices)
 local out={}
 for _,dev in ipairs(devices or {}) do
  out[dev.name]={mode='stock'}
  if kind=='race' and dev.position~='centre' then out[dev.name]={mode='lsd',preload=150,lock=.45,coast=.25}
  elseif kind=='drift' and dev.position=='rear' then out[dev.name]={mode='locked'} end
 end
 return out
end
return S
