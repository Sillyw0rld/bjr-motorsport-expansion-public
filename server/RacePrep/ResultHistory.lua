-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Read-only, bounded history catalogue. Never rewrites race or driver data.
local H={}
local function level(s) return tostring(s or ''):lower():gsub('^/?levels/',''):gsub('/.*$','') end
function H.new(api)
 local cached,cacheLevel,cachedAt
 local self={}
 function self.invalidate() cached=nil end
 function self.view(map)
  map=level(map)
  if cached and cacheLevel==map and os.time()-cachedAt<10 then return cached end
  local files={}
  for _,path in pairs(api.list(api.path) or {}) do
   local name=tostring(path):gsub('\\','/'):match('([^/]+)$')
   if name and name:match('^%d%d%d%d%-%d%d%-%d%d_.*%.json$') and not name:match('_qualifying%.json$') then files[#files+1]=name end
  end
  table.sort(files,function(a,b) return a>b end)
  local out={level=map,items={},records={},limit=20,scanned=0,truncated=#files>1000}
  for i=1,math.min(#files,1000) do
   local ok,res=pcall(api.read,api.path..'/'..files[i]);out.scanned=out.scanned+1
   if ok and type(res)=='table' and type(res.key)=='string' and type(res.rows)=='table' and level(res.level)==map then
    if #out.items<out.limit then out.items[#out.items+1]=res end
    for _,row in ipairs(res.rows) do
     local best=row.best
     if type(best)=='table' and type(best.time)=='number' and best.time>0 and not best.invalid then
      local k=tostring(res.raceID or res.raceName)
      if not out.records[k] or best.time<out.records[k].time then
       out.records[k]={time=best.time,name=row.name or row.playerName,car=row.car or row.model,
        class=row.class,pi=row.pi,date=res.date,raceName=res.raceName,runID=res.runID or res.key}
      end
     end
    end
   end
  end
  cached,cacheLevel,cachedAt=out,map,os.time()
  return out
 end
 return self
end
return H
