-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Challenge definitions and scoring consume server-observed proofs only.
local C={ORDER={'bestLap','raceDistance','cleanStreak','consistency','sectorAttack','speedTrap','tyreSaver'}}
C.TYPES={bestLap={name='Best lap',unit='ms',ghost=true},raceDistance={name='Race distance',unit='ms',ghost=true},cleanStreak={name='Clean streak',unit='laps',ghost=true},consistency={name='Consistency',unit='ms',ghost=true},sectorAttack={name='Sector attack',unit='ms',ghost=false},speedTrap={name='Speed trap',unit='m/s',ghost=false},tyreSaver={name='Tyre saver',unit='laps',ghost=true}}
local function finite(v,lo,hi)return type(v)=='number' and v==v and v>=lo and v<=hi end
C.finite=finite
local function num(v,default,lo,hi)if not finite(v,lo,hi)then return default end;return v end
function C.settings(input)
 local p=type(input)=='table' and input or {};local out={types={},daily=p.daily~=false,weekly=p.weekly~=false,distanceLaps=math.floor(num(p.distanceLaps,3,1,1000)),trapWidth=num(p.trapWidth,12,2,50),trapPosition=num(p.trapPosition,50,10,90),tyreSaverMinLaps=math.floor(num(p.tyreSaverMinLaps,2,1,100))}
 for _,kind in ipairs(C.ORDER)do out.types[kind]=not(type(p.types)=='table' and p.types[kind]==false)end;return out
end
-- Lower is better on the existing Rivals ledger. The offset makes zero spread
-- valid; reciprocal scores rank counts/speeds without truncation or ties.
function C.score(kind,value)
 if not C.TYPES[kind] or not finite(value,0,7200000)then return end
 if (kind=='cleanStreak' or kind=='tyreSaver') and (value%1~=0 or value<1 or value>1440) then return end
 if kind=='consistency' and value>1000 then return end
 if kind=='sectorAttack' and (value<1 or value>1800000)then return end
 if kind=='speedTrap' and (value<.01 or value>400)then return end
 if kind=='bestLap'then return value>=5000 and value<=1800000 and value or nil end
 if kind=='cleanStreak' or kind=='tyreSaver' or kind=='speedTrap'then return value>0 and 5000+1000000/value or nil end
 return 5000+value
end
function C.metric(kind,value)
 local time=C.score(kind,value);if not time then return end
 return {time=time,metric={type=kind,value=value,unit=C.TYPES[kind].unit},ghost=C.TYPES[kind].ghost}
end
function C.validMetric(best,kind)
 local m=type(best)=='table' and best.metric
 return type(m)=='table' and m.type==kind and C.TYPES[kind]~=nil and C.score(kind,m.value)==best.time and m.unit==C.TYPES[kind].unit
end
function C.value(kind,time)
 if kind=='bestLap'then return time end
 if kind=='cleanStreak' or kind=='tyreSaver' or kind=='speedTrap'then return time>5000 and 1000000/(time-5000) or nil end
 return time-5000
end
local function vector(v) if type(v)~='table'then return end;local x,y,z=v.x or v[1],v.y or v[2],v.z or v[3] or 0;if finite(x,-1e6,1e6)and finite(y,-1e6,1e6)and finite(z,-1e5,1e5)then return{x=x,y=y,z=z}end end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
C.vector=vector
function C.trap(race,settings)
 local best;local gates=race and race.gates or {}
 for i,g in ipairs(gates)do
  local previous=gates[i-1]or(race.loopable and gates[#gates]);local a,b=previous and vector(previous.pos),vector(g.pos)
  if a and b then
   local length=distance(a,b);local dx,dy=b.x-a.x,b.y-a.y;local len=math.sqrt(dx*dx+dy*dy)
   local d=vector(g.dir);local before=vector(previous.dir)
   local aligned=len>1 and d and before and (dx*d.x+dy*d.y)/(len*math.max(1e-9,math.sqrt(d.x*d.x+d.y*d.y)))>.85 and (dx*before.x+dy*before.y)/(len*math.max(1e-9,math.sqrt(before.x*before.x+before.y*before.y)))>.85
   local connected=not race.branchingEnabled
   if race.branchingEnabled then for _,parent in ipairs(g.parents or {})do if parent==i-1 or i==1 and parent==#gates then connected=true end end end
   if connected and aligned and (not best or length>best.length)then
    local f=(settings.trapPosition or 50)/100
    best={x=a.x+dx*f,y=a.y+dy*f,z=a.z+(b.z-a.z)*f,dx=dx/len,dy=dy/len,width=settings.trapWidth or 12,length=length,from=i==1 and #gates or i-1,to=i}
   end
  end
 end
 return best
end
function C.options(kind,race,settings)
 local out={}
 if kind=='raceDistance'then out.laps=race.loopable and settings.distanceLaps or 1;out.start=race.startPositions and race.startPositions[1];if not out.start then return nil,'Layout has no standing-start position.'end
 elseif kind=='speedTrap'then out.trap=C.trap(race,settings);if not out.trap then return nil,'No straight can be identified from this layout’s gate geometry.'end
 elseif kind=='tyreSaver'then out.minLaps=settings.tyreSaverMinLaps
 elseif kind=='sectorAttack'then out.sectorCount=race.sectorCount or 3;out.manualSectors=race.manualSectors==true end
 return out
end
function C.newRun(kind,options)
 options=options or {};local self={};local times,runBest,streak={},nil,0
 local green,hold,previous,lastAt,lastClock,trapSpeed,lastFinish,total,number,notice=nil,nil,nil,nil,nil,nil,nil,0,0,nil
 local start=kind=='raceDistance' and options.start and vector(options.start.pos)
 function self.reset()
  times={};streak=0;green=nil;hold=nil;previous=nil;lastAt=nil;trapSpeed=nil;lastFinish=nil;total=0;number=0;notice=nil
 end
 function self.position(now,raw,err)
  local p=type(raw)=='table' and vector(raw.pos)
  if err~='' or not p or not finite(now,0,1e15)then previous=nil;lastAt=nil;return end
  if lastAt and now<=lastAt then return end
  local dt=lastAt and now-lastAt;local speed=dt and dt<=350 and distance(previous,p)*1000/dt or nil
  if kind=='raceDistance' and start and (not green or now<green)then
   local near=distance(start,p)<=3
   if not near or speed and speed>.7 then hold=nil;green=nil;notice=nil
   elseif not hold then hold=now
   elseif not green and now-hold>=2000 then green=now+5000 end
   local remaining=green and math.max(0,math.ceil((green-now)/1000))
   local message=remaining and (remaining>0 and 'Standing start: '..remaining..' — hold still' or 'Go!')or'Park on the first grid position and hold still for 2 seconds.'
   if message~=notice then notice=message;previous=p;lastAt=now;return message,green end
  end
  if options.trap and speed then
   local t=options.trap;local a=(previous.x-t.x)*t.dx+(previous.y-t.y)*t.dy;local b=(p.x-t.x)*t.dx+(p.y-t.y)*t.dy
   if a<0 and b>=0 then local f=-a/(b-a);local x,y=previous.x+(p.x-previous.x)*f,previous.y+(p.y-previous.y)*f
    if math.abs((x-t.x)*t.dy-(y-t.y)*t.dx)<=t.width/2 then trapSpeed=math.max(trapSpeed or 0,speed)end
   end
  end
  if kind=='raceDistance' and green and now>=green and notice~='Go!' then notice='Go!';previous=p;lastAt=now;return notice,green end
  previous=p;lastAt=now;lastClock=now
 end
 function self.add(proof,valid)
  if not valid or type(proof)~='table' or proof.reason or not finite(proof.time,5000,1800000)then self.reset();return nil,'Invalid lap: challenge sequence reset.'end
  number=number+1;local value
  if kind=='bestLap'then value=proof.time
  elseif kind=='raceDistance'then
   if not green or not proof.started or proof.started<green or not proof.crossedAt or proof.crossedAt<green then self.reset();return nil,'Use a stationary standing start from the first grid position.'end
   if number>1 and (not lastFinish or math.abs(proof.started-lastFinish)>1)then self.reset();return nil,'Race-distance laps must be consecutive.'end
   lastFinish=proof.crossedAt;total=proof.crossedAt-green
   if number<(options.laps or 3)then return nil,'Race distance: '..number..' / '..(options.laps or 3)..' laps'end
   value=total;self.complete=true
  elseif kind=='cleanStreak'then streak=streak+1;value=streak
  elseif kind=='consistency'then
   times[#times+1]=proof.time;while #times>5 do table.remove(times,1)end
   if #times<5 then return nil,'Consistency: '..#times..' / 5 valid laps'end
   local lo,hi=math.huge,0;for _,t in ipairs(times)do lo=math.min(lo,t);hi=math.max(hi,t)end
   if hi-lo>1000 then return nil,'The last five laps differ by more than 1.0 s.'end;value=hi-lo
  elseif kind=='sectorAttack'then
   for _,t in ipairs(proof.sectors or {})do if finite(t,1,1800000)then value=math.min(value or math.huge,t)end end
   if not value then return nil,'No timed sector gates on this lap.'end
  elseif kind=='speedTrap'then value=trapSpeed;trapSpeed=nil;if not value then return nil,'Cross the marked speed trap during a valid lap.'end
  elseif kind=='tyreSaver'then
   runBest=math.min(runBest or math.huge,proof.time);times[#times+1]=proof.time
   while #times>1440 do table.remove(times,1)end
   streak=0;for i=#times,1,-1 do if times[i]>runBest*1.02 then break end;streak=streak+1 end
   if streak<(options.minLaps or 2)then return nil,'Tyre saver: keep consecutive laps within 2% of your run’s best.'end;value=streak
  end
  local result=C.metric(kind,value);if not result then return nil,'No qualifying score.'end
  result.lapTime=proof.time;result.trace=C.TYPES[kind].ghost and proof.trace or nil
  return result
 end
 return self
end
return C
