-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Compile a private factory reference. No spawn, tuning or physics mutation.
local N={}
function N.reference(id,i,cfg,vd)
 local S=require('common/raceprep/engineSelection');local info=S.info(i.model,vd.activeParts)
 if not info or not info.native then return end
 local source=jsonReadFile('/vehicles/'..i.model..'/'..tostring(i.config)..'.pc')
 local base=deepcopy(cfg)
 if source and source.parts and source.parts.Camso_Engine==nil then
  base.partsTree=nil;base.parts=deepcopy(source.parts);base.vars=deepcopy(source.vars or {})
 else
  local function reset(node)
   if node.chosenPartName==info.stockEngine then node.children={};return true end
   for _,child in pairs(node.children or {})do if reset(child)then return true end end
  end
  if not base.partsTree or not reset(base.partsTree)then return end
  base.parts=nil;base.vars={}
 end
 local ok,bundle=pcall(require('jbeam/loader').loadJbeam,id,nil,vd.directoriesLoaded,base)
 if not ok or not bundle or not bundle.vdata then return end
 local found=false;for _,name in pairs(bundle.vdata.activeParts or {})do if name==info.stockEngine then found=true end end
 if not found and source then
  -- A factory config cannot supply a swapped-in engine's stock reference.
  base=deepcopy(cfg);base.parts=nil;base.vars={}
  local function reset(node)
   if node.chosenPartName==info.stockEngine then node.children={};return true end
   for _,child in pairs(node.children or {})do if reset(child)then return true end end
  end
  if not base.partsTree or not reset(base.partsTree)then return end
  ok,bundle=pcall(require('jbeam/loader').loadJbeam,id,nil,vd.directoriesLoaded,base)
  if not ok or not bundle then return end
 end
 local b=bundle.vdata;local data={powertrain=b.powertrain,nativeTier=1}
 for path,name in pairs(vd.activeParts or {})do
  if name~=(b.activeParts or {})[path]then
   local key=(tostring(path):match('/([^/]+)/[^/]+$')or tostring(path)):lower();local p=(vd.activePartsData or {})[name]or{}
   local title=(p.information or {}).name or name;if type(title)=='table'then title=title.txt or name end;title=tostring(title):lower()
   if key:find('intake')or key:find('exhaust')or key:find('ecu')or key:find('management')or key:find('internals')or key:find('camshaft')or key:find('longblock')or key:find('turbo')or key:find('supercharger')then
    data.nativePartsChanged=true
    local stage=tonumber(title:match('stage[%s_]*(%d)'))
    if stage then data.nativeTier=math.max(data.nativeTier,math.min(3,stage))
    elseif title:find('race')then data.nativeTier=math.max(data.nativeTier,(key:find('internals')or key:find('cam'))and 3 or 2)end
   end
  end
 end
 for _,p in pairs(b.powertrain or {})do
  data[p.name]=b[p.name]
  for _,k in ipairs({'turbocharger','supercharger'})do local key=(b[p.name]or{})[k];if key then data[key]=b[key]end end
 end
 -- Normalize upgraded hardware at its maximum adjustable boost, then reuse
 -- that fixed multiplier for physics/live tuning. Stock presets stay stock.
 if data.nativePartsChanged then
  local maximum=deepcopy(cfg);maximum.vars=deepcopy(cfg.vars or {});local changed=false
  for name,def in pairs(vd.variables or {})do
   local key=tostring(name):lower();local value=tonumber(def.max)
   local rev=key:find('revlimit') and key:find('rpm')
   if value and value==value and value>0 and value<(rev and 50000 or 10000) and (key:find('wastegate')or key:find('boost')or rev)then
    maximum.vars[name]=value;changed=true
   end
  end
  if changed then
   local valid,full=pcall(require('jbeam/loader').loadJbeam,id,nil,vd.directoriesLoaded,maximum)
   if not valid or not full or not full.vdata then return nil end
   local v=full.vdata;local top={powertrain=v.powertrain}
   for _,p in pairs(v.powertrain or {})do
    top[p.name]=v[p.name]
    for _,k in ipairs({'turbocharger','supercharger'})do local key=(v[p.name]or{})[k];if key then top[key]=v[key]end end
   end
   data.nativeMax=top
  end
 end
 return data
end
return N
