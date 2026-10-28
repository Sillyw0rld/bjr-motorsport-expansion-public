-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Native models come from the shipped 0.40 catalogue. Mod models need a
-- discovered main JBeam/configuration and a source archive still present.
local C={}
function C.new(api)
 local cached,at={},-math.huge
 local self={}
 function self.list()
  if api.now()-at<30 then return cached end
  local rows,seen={},{}
  local native=api.read(api.path..'/series-native-cars.json') or {}
  for _,car in ipairs(native.models or {}) do
   local m=type(car)=='table' and car.model
   if type(m)=='string' and m:match('^[%w_-]+$') then rows[#rows+1]={model=m,name=type(car.name)=='string' and car.name or m,config=car.config,source='BeamNG'};seen[m]=true end
  end
  local index=api.read(api.path..'/updater/server-car-catalogue.json')
  if type(index)=='table' and index.schema==1 and type(index.models)=='table' then
   for _,car in ipairs(index.models) do
    local m=type(car)=='table' and car.model
    if type(m)=='string' and m:match('^[%w_-]+$') and type(car.archive)=='string' and car.archive:match('^[^/\\]+$') and car.archive:lower():match('%.zip$') and
     api.exists(api.client..'/'..car.archive) and not seen[m] then
     rows[#rows+1]={model=m,name=type(car.name)=='string' and car.name or m,config=car.config,source='Server mod'};seen[m]=true
    end
   end
  end
  local state=api.read(api.path..'/updater/generation-state.json') or {}
  for m,r in pairs(not index and type(state.inputs)=='table' and state.inputs.cars or {}) do
   local archive=type(r)=='table' and type(r.stamp)=='table' and type(r.stamp[1])=='string' and r.stamp[1]:gsub('\\','/'):match('([^/]+)$')
   if type(m)=='string' and m:match('^[%w_-]+$') and archive and archive:lower():match('%.zip$') and api.exists(api.client..'/'..archive) and not seen[m] then
    rows[#rows+1]={model=m,name=m:gsub('_',' '),config=r.config,source='Server mod'};seen[m]=true
   end
  end
  table.sort(rows,function(a,b) return a.name:lower()<b.name:lower() end)
  cached,at=rows,api.now();return rows
 end
 function self.has(model) for _,r in ipairs(self.list()) do if r.model==model then return true end end;return false end
 return self
end
return C
