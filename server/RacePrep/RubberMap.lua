-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Server authority for per-map tyre-metres. Pure Lua, injected file I/O.
-- Deltas are additive; broadcasts/snapshots contain absolute values. BeamMP
-- transports ordered events; callers must not resend a delta as a retry.
local M={}
local function num(v,lo,hi)
 v=tonumber(v)
 if not v or v~=v or v<lo or v>hi then return nil end
 return v
end
local function levelKey(value)
 if type(value)~='string' or #value>128 or not value:match('^[%w_%-]+$') then return nil end
 return value:lower()
end
local function coord(value) return num(value,-1000000,1000000) end
local function cellKey(k)
 if type(k)~='string' then return end
 local x,y=k:match('^(%-?%d+):(%-?%d+)$')
 x,y=coord(x),coord(y)
 if x and y then return x,y end
end
function M.new(api)
 local self={maps={},changed={},dirty={},counts={},revision={},fullCache={}}
 local cap=math.max(1,math.min(150000,tonumber(api.maxCells) or 150000))
 -- Flat files avoid creating a directory or touching legacy rubber.json.
 local prefix=api.filePrefix or 'rubber_'
 local function file(key) return api.path..'/'..prefix..key..'.json' end
 local function bump(key) self.revision[key]=(self.revision[key] or 0)+1 end
 self.bump=bump
 local function map(level)
  local key=levelKey(level);if not key then return nil end
  if not self.maps[key] then
   local loaded=api.read(file(key));local cells={};local count=0
   for k,c in pairs(type(loaded)=='table' and type(loaded.cells)=='table' and loaded.cells or {}) do
    local x,y=cellKey(k)
    if x and type(c)=='table' and num(c.a,0,1e9) and num(c.z,-1e5,1e5) and num(c.fx,-1.5,1.5) and num(c.fy,-1.5,1.5) and count<cap then
     cells[x..':'..y]={a=c.a,z=c.z,fx=c.fx,fy=c.fy,t=num(c.t,0,1e12),expiry=num(c.expiry,0,1e12),fade=num(c.fade,0,1)};count=count+1
    end
   end
   self.maps[key],self.changed[key],self.counts[key],self.revision[key]=cells,{},count,0
  end
  return self.maps[key],key
 end
 self.map=map
 function self.add(level,wire,maxCells)
  if type(wire)~='string' or #wire>512000 then return 0 end
  local cells,key=map(level);if not cells then return 0 end
  local n,seen=0,0
  local limit=math.max(1,math.min(3000,tonumber(maxCells) or 3000))
  for part in wire:gmatch('[^;]+') do
   seen=seen+1;if seen>limit then break end
   local ix,iy,z,a,fx,fy=part:match('^(%-?%d+),(%-?%d+),([^,]+),([^,]+),([^,]+),([^,]+)$')
   ix,iy,z,a,fx,fy=coord(ix),coord(iy),num(z,-1e5,1e5),num(a,0,500),num(fx,-1.5,1.5),num(fy,-1.5,1.5)
   if ix and iy and z and a and fx and fy and a>0 then
    local k=ix..':'..iy;local c=cells[k]
    if not c and self.counts[key]<cap then
     c={z=z,a=0,fx=fx,fy=fy};cells[k]=c;self.counts[key]=self.counts[key]+1
    end
    if c then
     local total=math.min(1e9,c.a+a);local weight=a/math.max(a,c.a+a)
     -- A road driven both ways must not average to a zero direction vector.
     if c.fx*fx+c.fy*fy<0 then fx,fy=-fx,-fy end
     c.a,c.z=total,c.z+(z-c.z)*.2
     c.fx,c.fy=c.fx*(1-weight)+fx*weight,c.fy*(1-weight)+fy*weight
     self.changed[key][k],self.dirty[key]=true,true;n=n+1
    end
   end
  end
  if n>0 then bump(key) end
  return n
 end
 local function wire(cells,keys)
  local parts={}
  for k in pairs(keys) do
   local c=cells[k];local ix,iy=cellKey(k)
   if c and ix then parts[#parts+1]=string.format('%d,%d,%.2f,%.3f,%.3f,%.3f',ix,iy,c.z,c.a,c.fx,c.fy) end
  end
  table.sort(parts);return table.concat(parts,';'),#parts
 end
 function self.takeChanged(level)
  local cells,key=map(level);if not cells then return '',0 end
  local out,n=wire(cells,self.changed[key]);self.changed[key]={};return out,n
 end
 function self.full(level,size)
  local cells,key=map(level);if not cells then return {} end
  size=math.max(1,math.min(3000,math.floor(tonumber(size) or 1000)))
  local rev=self.revision[key] or 0
  local cached=self.fullCache[key]
  if cached and cached.rev==rev and cached.size==size then
   local copy={};for i=1,#cached.chunks do copy[i]=cached.chunks[i] end
   return copy
  end
  local keys,chunks={},{}
  for k in pairs(cells) do keys[#keys+1]=k end
  table.sort(keys)
  local batch={}
  for i=1,#keys,size do
   local n=0
   for j=i,math.min(#keys,i+size-1) do
    local k=keys[j];local c=cells[k]
    if c then
     local sep=k:find(':',1,true)
     if sep then n=n+1;batch[n]=string.format('%s,%s,%.2f,%.3f,%.3f,%.3f',k:sub(1,sep-1),k:sub(sep+1),c.z,c.a,c.fx,c.fy) end
    end
   end
   for j=n+1,#batch do batch[j]=nil end
   if n>0 then chunks[#chunks+1]=table.concat(batch,';') end
  end
  local saved={};for i=1,#chunks do saved[i]=chunks[i] end
  self.fullCache[key]={rev=rev,size=size,chunks=saved}
  return chunks
 end
 function self.set(level,mode,full)
  local cells,key=map(level);if not cells then return false end
  if mode=='clean' then self.maps[key],self.changed[key],self.counts[key]={},{},0
  else
   local target=num(mode,0,1);full=num(full or 80,.001,1e9)
   if not target or not full then return false end
   local top=0;for _,c in pairs(cells) do top=math.max(top,c.a) end
   for k,c in pairs(cells) do c.a=top>0 and c.a*target*full/top or target*full;self.changed[key][k]=true end
  end
  self.dirty[key]=true;bump(key);return true
 end
 function self.count(level) local _,key=map(level);return key and self.counts[key] or 0 end
 function self.save()
  local saved=0
  for key in pairs(self.dirty) do
   local ok,value=pcall(api.write,file(key),{schemaVersion=1,cells=self.maps[key]})
   if ok and value then self.dirty[key]=nil;saved=saved+1 end
  end
  return saved
 end
 return self
end
return M
