-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Factory parts lists for the seed's BeamNG configs, which the seed rates by
-- key only (tools/build_native_identity.py). Read the first time Rivals needs
-- one; a list is returned only if it reproduces the key's parts hash.
local N={}
function N.new(api) -- api: {read(path)->table|nil, path, hash(parts)->hex}
 local data,loaded
 local cache={} -- key -> parts, or false when the list does not reproduce the hash
 local self={}
 function self.parts(key)
  if type(key)~='string' then return end
  local model,config,h=key:match('^([^/]+)/(.+)/(%x+)$')
  if not model then return end
  if cache[key]~=nil then return cache[key] or nil end
  if not loaded then
   loaded=true
   local ok,d=pcall(api.read,api.path..'/native-identity.json')
   if ok and type(d)=='table' and d.schemaVersion==1 and type(d.models)=='table' then data=d.models end
  end
  local m=data and data[model];local c=type(m)=='table' and type(m.configs)=='table' and m.configs[config]
  if type(c)~='table' or c.hash~=h or type(m.paths)~='table' or type(m.parts)~='table' then return end
  local parts={}
  local function put(list)
   for _,e in ipairs(type(list)=='table' and list or {}) do
    local p,v=type(e)=='table' and m.paths[e[1]],type(e)=='table' and m.parts[e[2]]
    if type(p)=='string' and type(v)=='string' then parts[p]=v end
   end
  end
  put(m.base)
  for _,i in ipairs(type(c.drop)=='table' and c.drop or {}) do local p=m.paths[i];if p then parts[p]=nil end end
  put(c.set)
  if api.hash(parts)~=h then cache[key]=false;return end
  cache[key]=parts
  return parts
 end
 return self
end
return N
