-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Pure server-observation timing. No client event can manufacture a crossing.
local V={INTERVAL=50,MAX_GAP=350,POST_WINDOW=1500}
local function finite(v,lo,hi) return type(v)=='number' and v==v and v>=lo and v<=hi end
V.finite=finite
local function vec(v)
 if type(v)~='table' then return end
 local x,y,z=v[1] or v.x,v[2] or v.y,v[3] or v.z
 if finite(x,-1000000,1000000) and finite(y,-1000000,1000000) and finite(z,-100000,100000) then return {x=x,y=y,z=z} end
end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function contains(t,v) for _,x in ipairs(t or {}) do if x==v then return true end end end
function V.new(race,ceiling)
 local s={race=race,gates={},ceiling=ceiling,trace={},lastGate=nil}
 if not finite(ceiling,30,300) or type(race)~='table' or type(race.gates)~='table' or #race.gates<2 or #race.gates>1024 then return nil,'Unsupported gate geometry.' end
 for i,g in ipairs(race.gates) do
  if type(g)~='table' then return nil,'Unsupported gate '..i end
  local p,d=vec(g.pos),vec(g.dir);local w,h=g.width or 10,g.height or 10
  if not p or not d or d.x*d.x+d.y*d.y<1e-10 or not finite(w,.1,10000) or not finite(h,.1,10000) then return nil,'Unsupported gate '..i end
  if race.branchingEnabled then
   if type(g.parents)~='table' then return nil,'Unsupported gate parents.' end
   for _,parent in ipairs(g.parents) do if not finite(parent,1,#race.gates) or parent%1~=0 then return nil,'Unsupported gate parents.' end end
  end
  local len=math.sqrt(d.x*d.x+d.y*d.y)
  s.gates[i]={pos=p,dir={x=d.x/len,y=d.y/len},width=w,height=h}
 end
 local maxStep=0;for i,g in ipairs(race.gates)do maxStep=math.max(maxStep,g.step or i)end
 local function sectorGate(id,finish)
  local g=race.gates[id]
  if race.manualSectors then return g.sector==true or finish end
  local steps=race.loopable and maxStep or maxStep-1
  local at=finish and steps or (g.step or id)-1
  for k=1,math.min(steps,race.sectorCount or 3)do if at==math.ceil(steps*k/math.min(steps,race.sectorCount or 3))then return true end end
  return false
 end
 local self={}
 function self.reset(reason)
  s.prev=nil;s.lastGate=nil;s.start=nil;s.trace={};s.reason=reason;s.over=0;s.maxGap=V.INTERVAL;s.sectors={};s.sectorAt=nil
 end
 self.reset()
 function self.running() return s.start~=nil end
 function self.reason() return s.reason end
 function self.sample(now,raw,err)
  if not finite(now,0,1e15) then self.reset('Server clock unavailable.');return end
  local p=type(raw)=='table' and vec(raw.pos)
  local tim=type(raw)=='table' and raw.tim
  if err~='' or not p or not finite(tim,0,1e15) then
   if s.seen and now-s.seen>V.MAX_GAP then self.reset('Position data unavailable.');s.seen=nil end
   return
  end
  -- tim is client-originated: use it ONLY to detect unchanged/out-of-order cache,
  -- never to time laps. There is no server receive timestamp in this API.
  if s.packet~=nil and tim<=s.packet then
   if s.seen and now-s.seen>V.MAX_GAP then self.reset('Stale position data.');s.seen=nil end
   return
  end
  s.packet=tim;s.seen=now
  local a,t0=s.prev,s.prevAt;s.prev=p;s.prevAt=now
  if not a then return end
  local dt=now-t0
  if dt<=0 or dt>V.MAX_GAP then self.reset('Position sampling gap.');s.prev=p;s.prevAt=now;return end
  s.maxGap=math.max(s.maxGap,dt)
  local dist=distance(a,p)
  -- 5 m quantisation/jitter allowance, plus the generous rated ceiling.
  if dist>5+s.ceiling*dt/1000 then self.reset('Teleport / implausible position jump.');s.prev=p;s.prevAt=now;return end
  if dist/(dt/1000)>s.ceiling then s.over=(s.over or 0)+dt else s.over=0 end
  if s.over>=500 then self.reset('Sustained speed exceeds rated performance.');s.prev=p;s.prevAt=now;return end
  local hits={}
  for i,g in ipairs(s.gates) do
   local da=(a.x-g.pos.x)*g.dir.x+(a.y-g.pos.y)*g.dir.y
   local db=(p.x-g.pos.x)*g.dir.x+(p.y-g.pos.y)*g.dir.y
   if da<0 and db>=0 then
    local f=-da/(db-da);local x,y,z=a.x+(p.x-a.x)*f,a.y+(p.y-a.y)*f,a.z+(p.z-a.z)*f
    if math.abs((x-g.pos.x)*g.dir.y-(y-g.pos.y)*g.dir.x)<=g.width/2 and z>=g.pos.z-3.5 and z<=g.pos.z+g.height then hits[#hits+1]={id=i,f=f} end
   end
  end
  table.sort(hits,function(x,y) return x.f<y.f end)
  local result
  for _,hit in ipairs(hits) do
   local id=hit.id;local gate=race.gates[id];local first=(gate.step or id)==1
   local at=t0+dt*hit.f
   if not s.start then
    if first then s.start=at;s.lastGate=id;s.reason=nil;s.trace={};s.maxGap=dt;s.sectors={};s.sectorAt=at end
   elseif id~=s.lastGate then
    local allowed
    if race.branchingEnabled then
     if race.loopable and first then
      allowed=true;for j,g in ipairs(race.gates) do if j~=id and contains(g.parents,s.lastGate) then allowed=false end end
     else allowed=contains(gate.parents,s.lastGate) end
    else allowed=(race.loopable and first and s.lastGate==#race.gates) or id==s.lastGate+1 end
    local finish=(race.loopable and first) or (not race.loopable and (gate.isFinish or (not race.branchingEnabled and id==#race.gates)))
    if not allowed then
     self.reset('Missed gate '..tostring((s.lastGate or 0)+1)..'.')
     if first then s.start=at;s.lastGate=id end
     break
    elseif finish then
     if s.sectorAt then s.sectors[#s.sectors+1]=math.floor(at-s.sectorAt+.5) end
     local elapsed=at-s.start
     result={time=math.floor(elapsed+.5),trace=s.trace,sectors=s.sectors,started=s.start,crossedAt=at,tolerance=math.min(750,100+2*s.maxGap),finished=now}
     if elapsed<5000 or elapsed>1800000 then result.reason='Lap duration outside supported range.' end
     s.start=race.loopable and at or nil;s.lastGate=race.loopable and id or nil;s.trace={};s.maxGap=dt;s.sectors={};s.sectorAt=race.loopable and at or nil
    else
     if sectorGate(id,false) and s.sectorAt then s.sectors[#s.sectors+1]=math.floor(at-s.sectorAt+.5);s.sectorAt=at end
     s.lastGate=id
    end
   end
  end
  if s.start and #s.trace<2400 and (not s.traceAt or now-s.traceAt>=200) then
   s.trace[#s.trace+1]={t=math.max(0,math.floor(now-s.start)),g=s.lastGate,x=p.x,y=p.y,z=p.z};s.traceAt=now
  end
  return result
 end
 return self
end
-- Match the complete server-received parts map to the rated active-parts map.
-- BeamMP simplifies config.partsTree to slot IDs, preserving full paths on
-- collisions. Missing/default-only configurations cannot establish identity.
function V.config(raw,decode,canonical,parts,model)
 if type(raw)~='string' or #raw>1048576 then return nil,'Server vehicle configuration unavailable.' end
 local ok,d=pcall(decode,raw:match('({.*)$') or '')
 if not ok or type(d)~='table' or d.jbm~=model or type(d.vcf)~='table' or type(d.vcf.parts)~='table' or type(parts)~='table' then return nil,'Server parts identity unavailable.' end
 -- Rated paths are slot path + part name (every rated path on the live server,
 -- 2026-10-27), so that reading wins; reading the path itself as a slot is
 -- only a fallback. Mixing them made a slot ID that is also a part name used
 -- in other slots (three incandescent_red_21W bulbs) look ambiguous.
 local rated,bySlot,byPath={},{},{}
 local function alias(map,slot,part,path)
  if not slot or slot=='' then return end
  slot=slot:gsub('/+$','')
  local bucket=map[slot] or {};map[slot]=bucket
  if bucket[part]==nil then bucket[part]=path elseif bucket[part]~=path then bucket[part]=false end
 end
 local ratedCount=0
 for path,part in pairs(parts) do
  if type(path)~='string' or type(part)~='string' then return nil,'Unsupported rated parts.' end
  ratedCount=ratedCount+1;if ratedCount>2000 then return nil,'Too many rated parts.' end
  rated[path]=part
  local clean=path:gsub('/+$','');local tail=clean:match('([^/]+)$')
  alias(byPath,clean,part,path);alias(byPath,tail,part,path)
  if tail==part then
   local parent=clean:match('^(.*)/[^/]+$')
   alias(bySlot,parent,part,path);alias(bySlot,parent and parent:match('([^/]+)$'),part,path)
  end
 end
 local covered={};local count=0
 for slot,part in pairs(d.vcf.parts) do
  if type(slot)~='string' or type(part)~='string' then return nil,'Unsupported server parts.' end
  if part~='' then
   local id=slot:gsub('/+$','');local found=bySlot[id] and bySlot[id][part]
   if found==nil then found=byPath[id] and byPath[id][part] end
   if found==false then return nil,'Ambiguous server parts identity.' end
   if not found then return nil,'Server parts differ from the rated build.' end
   covered[found]=true;count=count+1
  end
 end
 if count==0 then return nil,'Empty server parts identity.' end
 for path,part in pairs(rated) do
  if not covered[path] and not ((path=='/main' or path=='main' or path:gsub('/+$','')=='/'..tostring(d.vcf.mainPartName or d.jbm)) and part==(d.vcf.mainPartName or d.jbm)) then return nil,'Rated parts missing from server configuration.' end
 end
 -- Tune variables, differential setup and engine swaps are included. Ignore
 -- presentation-only paint/license fields; an edit event still ends the run.
 return canonical({model=d.jbm,parts=d.vcf.parts,vars=d.vcf.vars or {},main=d.vcf.mainPartName})
end
return V
