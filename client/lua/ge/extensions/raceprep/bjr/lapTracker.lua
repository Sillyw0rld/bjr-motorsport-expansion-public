-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR practice/qualifying: follow the native gate-parent graph rather than
-- treating parallel branches as consecutive checkpoints. Race timing itself
-- stays with BJR. Point-to-point runs start at gate 1 and end at a finish gate.
local Gates=require('ge/extensions/raceprep/lapTracker')
local T={};T.__index=T
local function contains(list,x) for _,n in ipairs(list or {}) do if n==x then return true end end end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function cross(g,a,b)
 local dx,dy=b.x-a.x,b.y-a.y;local sx,sy=g.b.x-g.a.x,g.b.y-g.a.y
 local denom=dx*sy-dy*sx;if math.abs(denom)<1e-10 then return end
 local qx,qy=g.a.x-a.x,g.a.y-a.y
 local t,u=(qx*sy-qy*sx)/denom,(qx*dy-qy*dx)/denom
 if t>0 and t<=1 and u>=0 and u<=1 then local z=a.z+(b.z-a.z)*t;if z>=g.zMin and z<=g.zMax then return t end end
end
function T.new(race)
 local self=setmetatable({race=race,gates={},state='out',cuts=0,lapNo=0},T)
 for i,g in ipairs(race.gates or {}) do
  local built=Gates.buildGates({{{pos=g.pos,dir=g.dir,radius=(g.width or 10)/2,height=g.height or 10}}})
  self.gates[i]=built[1] and built[1][1]
 end
 self.bounds={}
 if not race.branchingEnabled then
  if race.manualSectors then for i,g in ipairs(race.gates) do if g.sector and i>1 and i<#race.gates then self.bounds[#self.bounds+1]=i end end
  else
   local cumulative={0};for i=2,#race.gates do cumulative[i]=cumulative[i-1]+distance(race.gates[i-1].pos,race.gates[i].pos) end
   local total=cumulative[#race.gates] or 0
   if race.loopable and #race.gates>1 then total=total+distance(race.gates[#race.gates].pos,race.gates[1].pos) end
   local count=math.max(1,math.min(race.sectorCount or 3,#race.gates))
   local floor=race.loopable and 1 or 0;local last=floor
   for n=1,count-1 do
    local target=total*n/count;local found=#race.gates
    if total<=0 then found=math.ceil(#race.gates*n/count)
    else for i=last+1,#race.gates do if cumulative[i]>=target then found=i;break end end end
    found=math.min(math.max(found,last+1),#race.gates-(count-n)+floor)
    if found>1 then self.bounds[#self.bounds+1]=found end;last=found
   end
  end
 end
 return self
end
function T:valid() return #self.gates>=2 end
function T:cut() if self.state=='lap' then self.cuts=self.cuts+1 end end
function T:current(t) if self.state=='lap' then return t-self.lapStart end end
function T:startLap(at,id)
 self.state='lap';self.lapStart=at;self.last=id;self.cuts=0;self.void=nil;self.lapDist=0;self.splits={};self.lapNo=self.lapNo+1
end
function T:sectorTimes(lap) return lap.sectors end
function T:update(t,pos)
 if not pos or not self:valid() then return end
 local a,t0=self.prev,self.prevT;self.prev=pos;self.prevT=t
 if not a then return end
 local dist=distance(a,pos)
 if dist>Gates.JUMP_M then self.state='out';self.last=nil;return end
 self.lapDist=(self.lapDist or 0)+dist
 local hits={}
 for id,g in ipairs(self.gates) do local f=cross(g,a,pos);if f then hits[#hits+1]={id=id,f=f} end end
 table.sort(hits,function(x,y) return x.f<y.f end)
 local result
 for _,hit in ipairs(hits) do
  local id=hit.id;local gate=self.race.gates[id];local at=t0+(t-t0)*hit.f
  local first=(gate.step or id)==1
  if self.state=='out' then
   if first then self:startLap(at,id) end
  elseif id~=self.last then
   local finish=self.race.loopable and first or not self.race.loopable and (gate.isFinish or not self.race.branchingEnabled and id==#self.gates)
   local allowed
   if self.race.branchingEnabled then
    if self.race.loopable and first then
     -- A loop may close after a terminal branch only. Driving from an early
     -- checkpoint straight back to gate 1 is an incomplete lap.
     allowed=true
     for j,nextGate in ipairs(self.race.gates) do if j~=id and contains(nextGate.parents,self.last) then allowed=false end end
    else allowed=contains(gate.parents,self.last) end
   else allowed=self.race.loopable and first and self.last==#self.gates or id==self.last+1 end
   if finish then
    local elapsed=at-self.lapStart
    if elapsed>=Gates.MIN_LAP_MS then
     result={lap=self.lapNo,time=math.floor(elapsed+.5),cuts=self.cuts,void=self.void,incomplete=not allowed,distance=math.floor(self.lapDist),splits=self.splits}
     result.valid=allowed and self.cuts==0 and not self.void
     local sectors,prev={},0
     for _,bound in ipairs(self.bounds) do local split=self.splits[bound];if split then sectors[#sectors+1]=split-prev;prev=split end end
     sectors[#sectors+1]=result.time-prev;result.sectors=sectors
     if self.race.loopable then self:startLap(at,id) else self.state='out';self.last=nil end
    end
   elseif allowed then self.last=id;self.splits[id]=math.floor(at-self.lapStart+.5) end
  end
 end
 return result
end
return T
