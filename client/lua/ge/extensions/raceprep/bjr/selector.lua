-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Uses BJR's existing spawn-authorization hook: its selector already calls
-- that hook after the game's own search/type filters. Never enables a denial.
local Rating=require('ge/extensions/raceprep/rating')
local S={};local headerCache={}
function S.reset() headerCache={} end
function S.configKey(config)
 if type(config)~='string' then return end
 return config:match('([^/\\]+)%.pc$') or config
end
function S.check(model,config,rules,ratings)
 if not ratings or not ratings.getConfig then return true end
 local key=S.configKey(config)
 if not key then return true end -- raw parts/captured configs are checked at Ready
 local e=ratings.getConfig(model,key)
 -- Same policy as main: unknown ratings stay visible while collecting;
 -- Ready is still blocked until the live vehicle has a valid rating.
 return not e or not Rating.violation(rules,e)
end
function S.authorize(req,model,config,rules,ratings)
 if req and req.state~=false and not S.check(model,config,rules,ratings) then req.state=false end
end
function S.header(model,rules,ratings,getModel)
 local stamp={model,tostring(rules.piMin),tostring(rules.piMax)}
 for _,c in ipairs(Rating.classes) do stamp[#stamp+1]=tostring((rules.allowedClasses or {})[c]) end
 local key=table.concat(stamp,':');if headerCache[key]~=nil then return headerCache[key] end
 local data=getModel and getModel(model);local configs=data and data.configs
 if type(configs)~='table' then return true end
 local count=0
 for id,c in pairs(configs) do
  count=count+1
  if S.check(model,type(c)=='table' and (c.key or id) or id,rules,ratings) then headerCache[key]=true;return true end
 end
 headerCache[key]=count==0;return count==0
end
function S.wrap(mod,active,rules,ratings,getModel)
 if not mod or type(mod.passesFilters)~='function' then return end
 local original=mod.passesFilters
 local wrapper=function(item,...)
  if not original(item,...) then return false end
  if active() and type(item)=='table' and type(item.model)=='string' and item.config==nil then
   return S.header(item.model,rules(),ratings(),getModel)
  end
  return true
 end
 mod.passesFilters=wrapper
 return {mod=mod,wrapper=wrapper,original=original}
end
function S.restore(binding) if binding and binding.mod.passesFilters==binding.wrapper then binding.mod.passesFilters=binding.original end end
return S
