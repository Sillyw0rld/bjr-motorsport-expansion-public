-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Approved policy: full density costs 3% grip, linear fade over 10 minutes.
-- Fading is lazy: a cell's amount is brought up to date only when the cell is
-- touched (upload, delta, join, save), and expiries come from per-second
-- buckets, so uploads and the 10 s delta scale with what changed, not with
-- every marble on the map (2026-10-17: 62 ms delta builds at 50k cells).
local M={LIFETIME=600,GRIP_LOSS=.03,SAVE_EVERY=300}
function M.new(api)
 local R=dofile(api.path..'/RubberMap.lua')
 local store=R.new{read=api.read,write=api.write,path=api.path,filePrefix='marbles_',maxCells=50000}
 local now=api.now or os.time
 local self={store=store}
 local buckets,bucketed,zeros={},{},{}
 local lastSave=-1e12
 local function init(c,at)
  c.expiry=c.expiry or (c.t or at)+M.LIFETIME
  c.fade=c.fade or c.a/math.max(1,c.expiry-(c.t or at))
 end
 -- bring one cell to time `at`; true when it just reached zero
 local function refresh(c,at)
  init(c,at)
  local amount=at>=c.expiry and 0 or math.max(0,c.a-math.max(0,at-(c.t or at))*c.fade)
  local hit=amount==0 and c.a>0
  c.a,c.t=amount,at
  return hit
 end
 local function bucket(key,k,expiry)
  local b=buckets[key];if not b then b={};buckets[key]=b end
  local s=math.floor(expiry);local list=b[s];if not list then list={};b[s]=list end
  list[#list+1]=k
 end
 -- incremental expiry: only cells whose lifetime ended since the last call
 function self.expire(level)
  local cells,key=store.map(level);if not cells then return end
  local at=now()
  if not bucketed[key] then
   bucketed[key]=true
   for k,c in pairs(cells) do init(c,at);bucket(key,k,c.expiry) end
  end
  local changed=false
  for s,list in pairs(buckets[key] or {}) do
   if s<=at then
    for _,k in ipairs(list) do
     local c=cells[k]
     if c and c.expiry<=at and c.a>0 then
      c.a,c.t=0,at;store.changed[key][k]=true;store.dirty[key]=true
      zeros[key]=zeros[key] or {};zeros[key][k]=true;changed=true
     end
    end
    buckets[key][s]=nil
   end
  end
  if changed and store.bump then store.bump(key) end
 end
 -- full refresh of every cell (joins and saves only)
 function self.decay(level)
  local cells,key=store.map(level);if not cells then return end
  local at=now();local changed=false
  for k,c in pairs(cells) do
   local before=c.a
   if refresh(c,at) then store.changed[key][k]=true;store.dirty[key]=true;zeros[key]=zeros[key] or {};zeros[key][k]=true end
   if c.a~=before then changed=true end
  end
  if changed and store.bump then store.bump(key) end
 end
 function self.add(level,wire,max)
  if type(wire)~='string' or #wire>512000 then return 0 end
  self.expire(level)
  local cells,key=store.map(level);if not cells then return 0 end
  local at=now();local limit=math.min(3000,max or 3000)
  -- bring only the touched cells up to date before the store adds on top
  local seen=0
  for row in wire:gmatch('[^;]+') do
   seen=seen+1;if seen>limit then break end
   local x,y=row:match('^(%-?%d+),(%-?%d+),')
   local c=x and cells[tonumber(x)..':'..tonumber(y)]
   if c then refresh(c,at) end
  end
  local n,count=0,0
  for row in wire:gmatch('[^;]+') do
   count=count+1;if count>limit then break end
   local added=store.add(level,row,1)
   if added>0 then
    local x,y=row:match('^(%-?%d+),(%-?%d+),')
    local k=tonumber(x)..':'..tonumber(y);local c=cells[k]
    c.a=math.min(1,c.a);c.t=at;c.expiry=at+M.LIFETIME;c.fade=c.a/M.LIFETIME
    bucket(key,k,c.expiry)
    if zeros[key] then zeros[key][k]=nil end
    n=n+added
   end
  end
  return n
 end
 -- wheels took marbles off cells: rows "x,y,amount" (2026-10-21). Each cell is
 -- brought up to date, loses the amount and keeps its expiry; the change goes
 -- out with the normal delta, an emptied cell as an explicit zero.
 function self.take(level,wire,max)
  if type(wire)~='string' or #wire>512000 then return 0 end
  self.expire(level)
  local cells,key=store.map(level);if not cells then return 0 end
  local at=now();local limit=math.min(3000,max or 3000);local n,count=0,0
  for row in wire:gmatch('[^;]+') do
   count=count+1;if count>limit then break end
   local x,y,a=row:match('^(%-?%d+),(%-?%d+),([%d%.]+)$')
   a=tonumber(a);local k=x and tonumber(x)..':'..tonumber(y);local c=k and cells[k]
   if c and a and a==a and a>0 then
    refresh(c,at)
    if c.a>0 then
     c.a=math.max(0,c.a-math.min(1,a))
     c.fade=c.a/math.max(1,c.expiry-at)
     store.changed[key][k]=true;store.dirty[key]=true
     if c.a<=0 then zeros[key]=zeros[key] or {};zeros[key][k]=true end
     n=n+1
    end
   end
  end
  if n>0 and store.bump then store.bump(key) end
  return n
 end
 local function withLifetime(level,wire)
  local cells=store.map(level);local rows={}
  for row in wire:gmatch('[^;]+') do
   local x,y=row:match('^(%-?%d+),(%-?%d+),')
   local c=cells[x..':'..y]
   -- a cached join snapshot may name a cell removed since: skip it
   if c then rows[#rows+1]=row..','..string.format('%.1f',math.max(0,(c.expiry or now())-now())) end
  end
  return table.concat(rows,';')
 end
 function self.full(level,size)
  self.decay(level);local chunks=store.full(level,size)
  for i,w in ipairs(chunks) do chunks[i]=withLifetime(level,w) end
  return chunks
 end
 function self.takeChanged(level)
  self.expire(level)
  local cells,key=store.map(level);if not cells then return '',0 end
  local at=now()
  for k in pairs(store.changed[key]) do local c=cells[k];if c then refresh(c,at) end end
  local wire,n=store.takeChanged(level);wire=withLifetime(level,wire)
  -- Send explicit zeroes once, then reclaim space so a long session cannot
  -- fill the cap with expired cells.
  local removed=false
  for k in pairs(zeros[key] or {}) do
   local c=cells[k]
   if c and c.a<=0 then cells[k]=nil;store.counts[key]=store.counts[key]-1;removed=true end
  end
  -- removals change what a joining player must receive (the join snapshot is cached by revision)
  if removed and store.bump then store.bump(key) end
  zeros[key]={}
  return wire,n
 end
 function self.clean(level)
  local _,key=store.map(level)
  if key then buckets[key],bucketed[key],zeros[key]={},nil,{} end
  return store.set(level,'clean')
 end
 -- Marbles last ten minutes: persist every SAVE_EVERY seconds (or when forced,
 -- e.g. on a map change) instead of on every 60 s rubber save.
 function self.save(force)
  local at=now()
  if not force and at-lastSave<M.SAVE_EVERY then return 0 end
  lastSave=at
  for level,_ in pairs(store.maps) do if store.dirty[level] then self.decay(level) end end
  return store.save()
 end
 return self
end
return M
