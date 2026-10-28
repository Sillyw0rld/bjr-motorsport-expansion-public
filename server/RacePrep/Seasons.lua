-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S={}
local function num(v,lo,hi,default) v=tonumber(v);if not v or v~=v then return default end;return math.floor(math.max(lo,math.min(hi,v))) end
-- Gregorian civil date to days since Unix epoch; independent of local timezone.
function S.civil(y,m,d)
 y=y-(m<=2 and 1 or 0);local era=math.floor(y/400);local yo=y-era*400
 local mp=m+(m>2 and -3 or 9);local doy=math.floor((153*mp+2)/5)+d-1
 return (era*146097+yo*365+math.floor(yo/4)-math.floor(yo/100)+doy-719468)*86400
end
function S.date(value)
 if type(value)~='string' then return end
 local y,m,d=value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$');y,m,d=tonumber(y),tonumber(m),tonumber(d)
 if not y or y<2020 or y>2200 or m<1 or m>12 then return end
 local leap=y%4==0 and (y%100~=0 or y%400==0);local days=({31,leap and 29 or 28,31,30,31,30,31,31,30,31,30,31})[m]
 if d<1 or d>days then return end;return S.civil(y,m,d)+86400
end
function S.settings(v)
 v=type(v)=='table' and v or {};local mode=v.mode
 if mode~='weekly' and mode~='custom' and mode~='open' then mode='monthly' end
 local points={};for i,p in ipairs(type(v.points)=='table' and v.points or {25,18,15,12,10,8,6,4,2,1}) do if i<=100 then points[i]=num(p,0,1000,0) end end
 return {name=type(v.name)=='string' and v.name:sub(1,80) or 'Server season',mode=mode,customEnd=type(v.customEnd)=='string' and v.customEnd or '',
  repeating=v.repeating~=false,race=v.race~=false,clean=v.clean~=false,cleanPoints=num(v.cleanPoints,0,1000,5),medals=v.medals==true,
  bronze=num(v.bronze,0,1000,5),silver=num(v.silver,0,1000,10),gold=num(v.gold,0,1000,20),weekly=v.weekly==true,weeklyPoints=num(v.weeklyPoints,0,1000,10),
  perClass=v.perClass==true,minRaces=num(v.minRaces,0,1000,1),dropWorst=num(v.dropWorst,0,1000,0),crewScorers=num(v.crewScorers,1,12,2),points=points}
end
function S.new() return {schema=1,serial=0,history={},hallOfFame={},seen={}} end
function S.valid(s)
 if type(s)~='table' or s.schema~=1 or type(s.history)~='table' or type(s.hallOfFame)~='table' or type(s.seen)~='table' or type(s.serial)~='number' then return false end
 local c=s.current
 if c then
  if type(c)~='table' or type(c.entries)~='table' or type(c.medals)~='table' or type(c.weekly)~='table' or type(c.settings)~='table' or type(c.starts)~='number' then return false end
  local cfg=c.settings
  if type(cfg.points)~='table' then return false end
  for _,k in ipairs({'crewScorers','minRaces','dropWorst','cleanPoints','bronze','silver','gold','weeklyPoints'}) do if type(cfg[k])~='number' or cfg[k]~=cfg[k] or cfg[k]<0 or cfg[k]==math.huge then return false end end
  for _,e in ipairs(c.entries) do if type(e)~='table' or type(e.driver)~='string' or type(e.points)~='number' or type(e.class)~='string' or (e.kind=='race' and e.crew and type(e.crewPoints)~='number') then return false end end
 end
 for _,h in ipairs(s.history) do if type(h)~='table' or type(h.tables)~='table' or type(h.tables.drivers)~='table' or type(h.tables.crews)~='table' then return false end end
 for _,h in ipairs(s.hallOfFame) do if type(h)~='table' or type(h.drivers)~='table' or type(h.crews)~='table' then return false end end
 return true
end
function S.start(s,settings,now,following,duration)
 local cfg=S.settings(settings);local starts,ends=now
 if cfg.mode=='weekly' then starts=following and now or math.floor((now+259200)/604800)*604800-259200;ends=(math.floor((now+259200)/604800)+1)*604800-259200
 elseif cfg.mode=='monthly' then local t=os.date('!*t',now);starts=following and now or S.civil(t.year,t.month,1);ends=S.civil(t.month==12 and t.year+1 or t.year,t.month==12 and 1 or t.month+1,1)
 elseif cfg.mode=='custom' then ends=duration and now+duration or S.date(cfg.customEnd);if not ends or ends<=now then return false,'Choose a future custom end date.' end end
 s.serial=s.serial+1;s.current={id='season-'..s.serial,name=cfg.name,starts=starts,ends=ends,duration=duration or (ends and ends-starts),settings=cfg,entries={},medals={},weekly={},status='active'}
 return true
end
local function crew(s,id,crews)
 local cid=crews.members[id];local c=cid and crews.crews[cid];return cid,c and c.name,c and c.tag
end
local function add(c,e) c.entries[#c.entries+1]=e end
function S.race(s,res,rows,crews,clean)
 local c=s.current;if not c or c.status~='active' then return false end
 local key='race:'..tostring(res.runID or res.key)
 if s.seen[key] then return false end
 if not res.completedAt or res.completedAt<c.starts or (c.ends and res.completedAt>=c.ends) then return false end
 local entries={};local byCrew={};local classPosition={}
 if c.settings.perClass then
  -- Count all official finishers, including a row with no stored driver profile.
  local finishers=res.rows
  if not finishers or #finishers==0 then finishers={};for _,r in ipairs(rows) do finishers[#finishers+1]=r.row end end
  for _,r in ipairs(rows) do
   local row=r.row or {}
   if row.status=='FIN' and not row.disqualified and type(row.position)=='number' then
    local position=1
    for _,other in ipairs(finishers) do
     if other.status=='FIN' and not other.disqualified and (other.class or 'Unclassified')==(row.class or 'Unclassified') and (other.position or math.huge)<(row.position or math.huge) then position=position+1 end
    end
    classPosition[r.id]=position
   end
  end
 end
 for _,r in ipairs(rows) do
  local row=r.row or {};local cid,name,tag=crew(s,r.id,crews)
  local finish=row.status=='FIN' and not row.disqualified;local position=row.position;if c.settings.perClass then position=classPosition[r.id] end
  local points=finish and c.settings.race and (c.settings.points[position] or 0) or 0
  if c.settings.clean and clean(res,row) then points=points+c.settings.cleanPoints end
  local e={driver=r.id,name=r.name,kind='race',event=key,points=points,crew=cid,crewName=name,crewTag=tag,crewPoints=0,
   finished=finish,position=position or 100000,class=row.class or 'Unclassified',win=finish and position==1,at=res.completedAt}
  entries[#entries+1]=e
  if cid then local k=cid..(c.settings.perClass and ':'..e.class or '');byCrew[k]=byCrew[k] or {};table.insert(byCrew[k],e) end
 end
 for _,list in pairs(byCrew) do table.sort(list,function(a,b) if a.finished~=b.finished then return a.finished end;return a.position<b.position or a.position==b.position and a.driver<b.driver end)
  for i=1,math.min(#list,c.settings.crewScorers) do list[i].crewPoints=list[i].points end
 end
 for _,e in ipairs(entries) do add(c,e) end;s.seen[key]=true;return true
end
function S.bonus(s,id,name,kind,event,tier,class,time,at,crews)
 local c=s.current;if not c or c.status~='active' or at<c.starts or c.ends and at>=c.ends then return false end
 if kind=='medal' and not c.settings.medals or kind=='weekly' and not c.settings.weekly then return false end
 local ledger=kind=='medal' and c.medals or c.weekly;local key=id..':'..event;local old=ledger[key] or 0
 if tier<=old then return false end
 local value=kind=='medal' and ({c.settings.bronze,c.settings.silver,c.settings.gold})[tier] or c.settings.weeklyPoints
 local previous=kind=='medal' and old>0 and ({c.settings.bronze,c.settings.silver,c.settings.gold})[old] or (old>0 and c.settings.weeklyPoints or 0)
 local cid,cname,tag=crew(s,id,crews)
 add(c,{driver=id,name=name,kind=kind,event=kind..':'..event,points=math.max(0,value-previous),crew=cid,crewName=cname,crewTag=tag,class=class or 'Unclassified',time=time,at=at})
 ledger[key]=tier;return true
end
function S.tables(c,crews)
 local drivers,teams={},{};local bonus={}
 for _,e in ipairs(c.entries) do
  local class=c.settings.perClass and e.class or 'Overall';local k=class..':'..e.driver
  local d=drivers[k] or {id=e.driver,name=e.name,class=class,points=0,races=0,wins=0,racePoints={}};drivers[k]=d
  if e.kind=='race' then d.races=d.races+1;d.wins=d.wins+(e.win and 1 or 0);d.racePoints[#d.racePoints+1]=e.points else d.points=d.points+e.points end
  if e.crew then
   local tk=class..':'..e.crew;local current=crews.crews[e.crew]
   local t=teams[tk] or {id=e.crew,name=current and current.name or e.crewName,tag=current and current.tag or e.crewTag,class=class,points=0,races=0,wins=0,events={},winEvents={},contributions={}};teams[tk]=t
   if e.kind=='race' then
    if not t.events[e.event] then t.races=t.races+1;t.events[e.event]=true end
    if e.win and not t.winEvents[e.event] then t.wins=t.wins+1;t.winEvents[e.event]=true end
    t.points=t.points+e.crewPoints;t.contributions[e.driver]=(t.contributions[e.driver] or 0)+e.crewPoints
   else
    local bk=tk..':'..e.event;bonus[bk]=bonus[bk] or {team=t,rows={}}
    local r=bonus[bk].rows[e.driver] or {id=e.driver,points=0,time=e.time or math.huge};bonus[bk].rows[e.driver]=r;r.points=r.points+e.points;r.time=math.min(r.time,e.time or math.huge)
   end
  end
 end
 for _,b in pairs(bonus) do
  local rows={};for _,r in pairs(b.rows) do rows[#rows+1]=r end
  table.sort(rows,function(a,b) return a.time<b.time or a.time==b.time and (a.points>b.points or a.points==b.points and a.id<b.id) end)
  for i=1,math.min(#rows,c.settings.crewScorers) do local r=rows[i];b.team.points=b.team.points+r.points;b.team.contributions[r.id]=(b.team.contributions[r.id] or 0)+r.points end
 end
 local function sorted(map,driver)
  local out={}
  for _,r in pairs(map) do
   if driver then table.sort(r.racePoints,function(a,b) return a>b end);for i=1,math.max(0,#r.racePoints-c.settings.dropWorst) do r.points=r.points+r.racePoints[i] end;r.racePoints=nil end
   r.ranked=r.races>=c.settings.minRaces;r.events=nil;r.winEvents=nil;out[#out+1]=r
  end
  table.sort(out,function(a,b) if a.class~=b.class then return a.class<b.class end;if a.ranked~=b.ranked then return a.ranked end;if a.points~=b.points then return a.points>b.points end;if a.wins~=b.wins then return a.wins>b.wins end;return a.id<b.id end)
  local positions={};for _,r in ipairs(out) do if r.ranked then positions[r.class]=(positions[r.class] or 0)+1;r.position=positions[r.class] end end;return out
 end
 return {drivers=sorted(drivers,true),crews=sorted(teams,false)}
end
function S.close(s,crews,now,awards)
 local c=s.current;if not c or c.status~='active' then return false end
 local tables=S.tables(c,crews);local snapshot={id=c.id,name=c.name,starts=c.starts,ends=now,tables=tables,settings=c.settings}
 s.history[#s.history+1]=snapshot;local hall={id=c.id,name=c.name,ends=now,drivers={},crews={}}
 for _,r in ipairs(tables.drivers) do if r.position and r.position<=3 then
  hall.drivers[#hall.drivers+1]=r;awards[r.id]=awards[r.id] or {};awards[r.id].season_top3=true;if r.position==1 then awards[r.id].season_champion=true end
 end end
 for _,r in ipairs(tables.crews) do if r.position and r.position<=3 then
  hall.crews[#hall.crews+1]=r
  if r.position==1 then
   for id,intervals in pairs(crews.history or {}) do
    for _,m in ipairs(intervals) do if m.crew==r.id and m.joined<=now and (not m.left or m.left>now) then awards[id]=awards[id] or {};awards[id].crew_champion=true end end
   end
  end
 end end
 s.hallOfFame[#s.hallOfFame+1]=hall;c.status='ended';return true
end
return S
