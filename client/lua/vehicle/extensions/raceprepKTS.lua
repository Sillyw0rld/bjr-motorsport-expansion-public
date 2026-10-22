-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Runtime integration for unmodified KTS through its public surface only: tyre
-- type presets (Race Prep's KTS sync), the road-temperature mailbox (Road
-- Temperature mod) and, for the rubbered line, a wrapper around KTS's public
-- grip-write route (_gripRefresh.applyWheel). Never writes a ZIP or settings file.
local M={status={}}
local target,grips,attached=nil,{},nil
local gripBinding
local function finite(v,lo,hi) v=tonumber(v);return v and v==v and v>=lo and v<=hi and v end
local function get(name) return extensions and extensions[name] or rawget(_G,name) end
local function restore()
 if attached then
  if attached.setRoadTemperatureC then attached.setRoadTemperatureC(nil) end
  if attached.setRubberGrip then attached.setRubberGrip({}) end
 end
 if gripBinding and gripBinding.route.applyWheel==gripBinding.wrapper then
  gripBinding.route.applyWheel=gripBinding.original
  for id,raw in pairs(gripBinding.route.applied or {}) do gripBinding.original(id,raw) end
 end
 gripBinding,attached=nil,nil;grips={};M.status={}
end
local function attach(e)
 local keep=grips;restore();grips=keep;attached=e
 if not e then M.status.reason='KTS is not loaded';return end
 -- Our patched KTS (~/Projects/kts-automation-fix) detects Automation tyres
 -- itself, takes track temperature from the ktsRoadTempC mailbox (fed by the
 -- Road Temperature mod) and exposes setRubberGrip: no runtime hooks needed.
 if e.setRubberGrip and not e.setRoadTemperatureC then
  M.status.automation='patched KTS';M.status.temperature='ktsRoadTempC mailbox';M.status.grip='public API'
  return
 end
 -- Stock KTS (2026-10-20): the vehicle sandbox blocks debug.setupvalue, so no
 -- hidden-variable hooks are attempted. Tyre type comes from KTS's public
 -- setTyreProfilePreset (Race Prep's KTS sync); road temperature from KTS's own
 -- tyreWearMailboxEnvTemp mailbox, fed by Race Prep's roadTemperature extension.
 M.status.automation='tyre type via KTS preset'
 M.status.temperature=e.setRoadTemperatureC and 'public API' or 'KTS mailbox (track temperature)'
 if e.setRubberGrip then M.status.grip='public API'
 elseif type(e._gripRefresh)=='table' and type(e._gripRefresh.applyWheel)=='function' and type(e._gripRefresh.applied)=='table' then
  local route=e._gripRefresh;local original=route.applyWheel
  local wrapper=function(id,value)
   local raw=finite(value,.02,2) or 1
   local ok=original(id,math.max(.02,math.min(2,raw*(grips[tonumber(id)] or 1))))
   if ok then route.applied[tonumber(id)]=raw end -- keep interpolation unmultiplied
   return ok
  end
  gripBinding={route=route,original=original,wrapper=wrapper};route.applyWheel=wrapper
  M.status.grip='guarded KTS grip-write hook'
 end
end
M.setRoadTemperature=function(value)
 target=finite(value,-50,90)
 local e=get('luukstyrethermalsandwear');if e~=attached or (gripBinding and (e._gripRefresh~=gripBinding.route or e._gripRefresh.applyWheel~=gripBinding.wrapper)) then attach(e) end
 if not e then return false end
 if e.setRoadTemperatureC then e.setRoadTemperatureC(target) end
 return M.status.temperature~=nil
end
M.setRubberGrip=function(values)
 local e=get('luukstyrethermalsandwear');if e~=attached or (gripBinding and (e._gripRefresh~=gripBinding.route or e._gripRefresh.applyWheel~=gripBinding.wrapper)) then attach(e) end
 if not e then return false end
 if type(values)~='table' then return false end
 if e.setRubberGrip then e.setRubberGrip(values);return true end
 if not gripBinding then return false end
 if next(values)==nil then grips={}
 else for id,value in pairs(values) do
  id=finite(id,0,100);value=finite(value,.5,1.2)
  if id and id==math.floor(id) and value then grips[id]=value end
 end end
 for id,raw in pairs(gripBinding.route.applied) do gripBinding.wrapper(id,raw) end
 return true
end
M.updateGFX=function()
 local e=get('luukstyrethermalsandwear');if e~=attached or (gripBinding and (e._gripRefresh~=gripBinding.route or e._gripRefresh.applyWheel~=gripBinding.wrapper)) then attach(e) end
end
M.onExtensionUnloaded=restore
M.onReset=function() if attached then M.setRoadTemperature(target) end end
return M
