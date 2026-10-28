-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local Challenges=dofile(path..'/Challenges.lua');local Rivals=dofile(path..'/Rivals.lua')
local R={}
R.catalogue={
 {'licence_D','D licence'},{'licence_C','C licence'},{'licence_B','B licence'},{'licence_A','A licence'},{'licence_Pro','Pro licence','Pro'},
 {'first_finish','First finish'},{'first_podium','First podium'},{'first_win','First win','Winner'},{'wins_10','Ten wins'},{'hat_trick','Three wins in a row','Hat-trick Hero'},{'podium_classes_5','Podiums in five classes'},
 {'clean_first','Clean race','Clean Racer'},{'clean_10','Ten clean races in a row'},{'contact_free_25','25 races without contact'},
 {'comeback','Comeback of the race','Comeback Kid'},{'fastest_5','Five fastest-lap awards','Speed Demon'},
 {'km_100','100 km raced'},{'km_1000','1,000 km raced','Iron Man'},{'km_5000','5,000 km raced'},
 {'rivals_first','First verified Rivals lap','Time Attacker'},{'gold_first','First gold medal'},{'gold_5','Gold on five boards'},
 {'daily_first','Daily challenge complete','Daily Challenger'},
 {'weekly_first','Weekly target beaten'},{'weekly_4','Four weekly targets','Weekly Warrior'},
 {'pole','Qualify on pole'},{'win_pole','Win from pole','Pole to Win'},
 {'season_top3','Season top three'},{'season_champion','Season champion','Champion'},
 {'level_10','Level 10'},{'level_25','Level 25'},{'level_50','Level 50'},
 {'crew_champion','Crew champion','Crew Champion'}}
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
function R.profile(p)
 local out={name=type(p.name)=='string' and p.name or nil}
 for _,k in ipairs({'races','wins','podiums','finished','dnf','laps','cuts','contacts','falseStarts','kilometres','safety','safetyRaces'}) do
  local n=tonumber(p[k]);out[k]=n and n==n and n>=0 and n<math.huge and n or 0
 end
 return out
end
function R.init(d)
 d.xp=d.xp or 0;d.achievements=d.achievements or {};d.medals=d.medals or {};d.weekly=d.weekly or {};d.challengeXP=d.challengeXP or {};d.podiumClasses=d.podiumClasses or {};return d
end
function R.unlock(d,id) R.init(d);local fresh=not d.achievements[id];d.achievements[id]=true;return fresh end
function R.level(xp) return math.max(1,math.floor((math.sqrt(25+math.max(0,xp or 0)*.04)-3)/2)) end
function R.threshold(level) return 100*(level-1)*(level+4) end
function R.medal(time,best)
 if type(time)~='number' or type(best)~='number' or best<=0 or time<=0 then return 0 end
 if time<=best*1.02 then return 3 elseif time<=best*1.05 then return 2 elseif time<=best*1.10 then return 1 end;return 0
end
function R.finish(d)
 R.init(d);local p=d.profile or {}
 for licence in pairs(d.earnedLicences or {}) do if licence~='Rookie' then R.unlock(d,'licence_'..licence) end end
 if (p.finished or 0)>0 then d.eligible=true;R.unlock(d,'first_finish') end
 if (p.podiums or 0)>0 then R.unlock(d,'first_podium') end
 if (p.wins or 0)>0 then R.unlock(d,'first_win') end
 if (p.wins or 0)>=10 then R.unlock(d,'wins_10') end
 for _,km in ipairs({100,1000,5000}) do if (p.kilometres or 0)>=km then R.unlock(d,'km_'..km) end end
 local gold=0;for _,m in pairs(d.medals) do if m.tier==3 and not m.provisional then gold=gold+1 end end
 if gold>0 then R.unlock(d,'gold_first') end;if gold>=5 then R.unlock(d,'gold_5') end
 if count(d.weekly)>0 then R.unlock(d,'weekly_first') end;if count(d.weekly)>=4 then R.unlock(d,'weekly_4') end
 if count(d.podiumClasses)>=5 then R.unlock(d,'podium_classes_5') end
 local level=R.level(d.xp);for _,n in ipairs({10,25,50}) do if level>=n then R.unlock(d,'level_'..n) end end
end
local function award(res,row,id)
 for _,a in ipairs(res.awards or {}) do if a.id==id then for _,w in ipairs(a.winners or {}) do
  if (row.racerKey and w.racerKey==row.racerKey) or (row.playerID~=nil and w.playerID==row.playerID) then return true end
 end end end;return false
end
function R.raceAllowed(res)
 local phase=type(res.phase)=='table' and res.phase.name or res.phase or res.phaseName
 return res.source=='bjr-api' and res.kind~='rivals' and res.kind~='qualifying' and res.kind~='practice' and (phase==nil or tostring(phase):lower()=='race')
end
function R.capture(d)
 d=d or {};local a={};for k,v in pairs(d.achievements or {}) do a[k]=v end
 return {xp=d.xp or 0,licence=d.licence or 'Rookie',achievements=a}
end
function R.receipt(s,id,before,lines)
 local d=R.init(s.drivers[id]);local unlocked={}
 for _,a in ipairs(R.achievements(s,d)) do if a.earned and not before.achievements[a.id] then unlocked[#unlocked+1]=a end end
 return {before={xp=before.xp,level=R.level(before.xp),start=R.threshold(R.level(before.xp))},
  after={xp=d.xp,level=R.level(d.xp),next=R.threshold(R.level(d.xp)+1)},lines=lines or {},total=d.xp-before.xp,
  achievements=unlocked,licence={before=before.licence,after=d.licence or 'Rookie'}}
end
function R.race(s,job,before)
 local res=job.result;if not R.raceAllowed(res) then return false end
 s.rewardSeen=s.rewardSeen or {};local key=tostring(res.runID or res.key)
 if s.rewardSeen[key] then return false end
 local receipts,starts={},{}
 for _,r in ipairs(job.rows) do
  local d=R.init(s.drivers[r.id] or {});s.drivers[r.id]=d;d.name=r.name;d.profile=r.profile;d.skill=r.skill
  starts[r.id]=before and before[r.id] or R.capture(d);local lines={}
  local row=r.row or {};local finished=row.status=='FIN' and not row.disqualified
  if finished then
   local beaten=0;for _,other in ipairs(res.rows or {}) do if type(other.position)=='number' and type(row.position)=='number' and other.position>row.position then beaten=beaten+1 end end
   lines={{label='Race finish',xp=100},{label='Cars beaten',count=beaten,rate=20,xp=20*beaten}}
   d.xp=d.xp+100+20*beaten;d.eligible=true;R.unlock(d,'first_finish')
   d.winStreak=row.position==1 and (d.winStreak or 0)+1 or 0
   if row.position and row.position<=3 and row.class then d.podiumClasses[row.class]=true end
  else d.winStreak=0 end
  local clean=finished and award(res,row,'clean')
  d.cleanStreak=clean and (d.cleanStreak or 0)+1 or 0
  if clean then lines[#lines+1]={label='Clean race',xp=50};d.xp=d.xp+50;R.unlock(d,'clean_first') end
  -- Missing evidence is not evidence of a contact-free race.
  local inc=row.incidents or {};local elapsed=tonumber(row.total)
  local covered=finished and elapsed and (inc.samples or 0)>=3 and (inc.maxGap or math.huge)<=10 and type(inc.firstAt)=='number' and type(inc.lastAt)=='number' and inc.lastAt-inc.firstAt>=elapsed/1000*.8
  d.contactStreak=covered and (inc.contacts or 0)==0 and (d.contactStreak or 0)+1 or 0
  if d.winStreak>=3 then R.unlock(d,'hat_trick') end
  if d.cleanStreak>=10 then R.unlock(d,'clean_10') end
  if d.contactStreak>=25 then R.unlock(d,'contact_free_25') end
  if award(res,row,'comeback') then R.unlock(d,'comeback') end
  if award(res,row,'fastest') then d.fastest=(d.fastest or 0)+1;if d.fastest>=5 then R.unlock(d,'fastest_5') end end
  if (res.phaseCount or 1)>1 and job.pole and job.pole==row.racerKey then
   R.unlock(d,'pole')
  end
  if (res.phaseCount or 1)>1 and job.startPole==row.racerKey and job.startPole~=nil and finished and row.position==1 then R.unlock(d,'win_pole') end
  R.finish(d);receipts[r.id]={lines=lines}
 end
 for id,v in pairs(receipts) do receipts[id]=R.receipt(s,id,starts[id],v.lines);receipts[id].kind='race';receipts[id].raceName=res.raceName;receipts[id].runID=res.runID end
 s.rewardSeen[key]=true;return true,receipts
end
-- Legacy medals without the provisional flag were already paid and stay confirmed.
function R.medalAward(d,board,time,best,model,confirmed)
 R.init(d);local earned=R.medal(time,best);local old=d.medals[board]
 local previous=old and old.tier or 0
 local paid=old and not old.provisional and previous or 0
 -- Only a paid medal is kept; a provisional one (set alone) is judged again
 -- against the current best, so a faster newcomer can lower or remove it.
 local tier=math.max(earned,paid)
 if tier==0 then if old then d.medals[board]=nil;R.finish(d);return true end;return false end
 confirmed=confirmed~=false or paid>0
 if tier==previous and (not old.provisional or not confirmed) then return false end
 local xp={0,50,100,200}
 if confirmed then d.xp=d.xp+xp[tier+1]-xp[paid+1] end
 local m={tier=tier,time=time,best=best,model=model,provisional=not confirmed}
 if old and paid>0 and paid>=earned then m.time=old.time;m.best=old.best;m.model=old.model end
 d.medals[board]=m;R.finish(d);return true,confirmed and tier or nil
end
-- Shared by the live medals check and backfill. Distinct, verified, unblocked
-- competitors confirm a board; a previously confirmed medal never regresses.
function R.boards(s,groups,blocked)
 local changed,awards=false,{}
 for key,g in pairs(groups or {}) do
  local best,drivers=nil,{}
  for _,r in pairs(g.bests or {}) do if r.verified and not blocked(r.driver,r.runID) then best=math.min(best or math.huge,r.time);drivers[r.driver]=true end end
  local confirmed=count(drivers)>=2
  for _,r in pairs(g.bests or {}) do if best and r.verified and not blocked(r.driver,r.runID) then
   local d=R.init(s.drivers[r.driver] or {});s.drivers[r.driver]=d;d.name=r.name;d.eligible=true
   changed=R.unlock(d,'rivals_first') or changed
   local update,tier=R.medalAward(d,key,r.time,best,r.model,confirmed);changed=update or changed
   local m=d.medals[key]
   if m and (m.raceName~=g.raceName or m.class~=g.class) then m.raceName=g.raceName;m.class=g.class;changed=true end
   if m and m.time==r.time then m.metric=r.metric;m.type=g.type end
   if tier then awards[#awards+1]={id=r.driver,name=r.name,board=key,tier=tier,class=g.class,time=m.time} end
  end end
 end
 return changed,awards
end
function R.verified(res,row,blocked)
 local best=row.best;local kind=res.challengeType or (res.recordContext and res.recordContext.type)or'bestLap'
 local metric=kind=='bestLap' and type(best)=='table' and type(best.time)=='number' and best.time>=5000 and best.time<=1800000 or kind~='bestLap' and Challenges.validMetric(best,kind)
 return metric and res.kind=='rivals' and res.verified==true and type(res.verification)=='table' and res.verification.version==1 and res.verification.method=='beammp-server-crossings' and row.verified==true and not row.disqualified and row.status~='DSQ' and best.verified==true and not best.invalid and not(blocked and blocked(row.rivalDriver,res.runID))
end
function R.challengeMet(res,row,pick,blocked)
 local c=res.recordContext;local board=type(pick)=='table' and pick.board;local at=res.completedAt
 if not c or not board or board.id~=Rivals.key(c,row.class) or res.level~=pick.level or not at or at<pick.starts or at>=pick.ends or not pick.available then return false end
 local target=pick.target
 return target==nil or target.verified==true and not(blocked and blocked(target.driver,target.runID)) and row.best.time<target.time
end
function R.rival(s,res,best,weekly,blocked)
 local changed=false;local c=res.recordContext
 if not c or not c.layout or not c.rulesKey then return false end
 for _,row in ipairs(res.rows or {}) do if row.rivalDriver and R.verified(res,row,blocked) then
  local d=R.init(s.drivers[row.rivalDriver] or {});s.drivers[row.rivalDriver]=d;d.name=row.name;d.eligible=true
  changed=R.unlock(d,'rivals_first') or changed
  if weekly and type(weekly.target)=='table' and weekly.target.verified==true and not (blocked and blocked(weekly.target.driver,weekly.target.runID)) and weekly.layout==c.layout and weekly.rulesKey==c.rulesKey and weekly.class==row.class and res.weeklyID==weekly.id and res.level==weekly.level and row.best.time<weekly.target.time and not d.weekly[weekly.id] then
   d.weekly[weekly.id]=true;d.xp=d.xp+150;changed=true
  end
  for _,pick in ipairs(weekly and weekly.rotations or {})do
   if R.challengeMet(res,row,pick,blocked)and not d.challengeXP[pick.id]then
    d.challengeXP[pick.id]=pick.xp;d.xp=d.xp+pick.xp;changed=true
    if pick.kind=='weekly'then d.weekly[pick.id]=true else R.unlock(d,'daily_first')end
   end
  end
  R.finish(d)
 end end
 return changed
end
function R.rarity(s)
 local base,counts=0,{}
 for _,d in pairs(s.drivers) do if d.eligible then base=base+1;for a in pairs(d.achievements or {}) do counts[a]=(counts[a] or 0)+1 end end end
 return base,counts
end
function R.achievements(s,d)
 local base,counts=R.rarity(s);local rows={};d=d or {}
 for _,a in ipairs(R.catalogue) do rows[#rows+1]={id=a[1],name=a[2],title=a[3],earned=(d.achievements or {})[a[1]]==true,rarity=base>0 and math.floor((counts[a[1]] or 0)*1000/base+.5)/10 or 0,base=base} end
 return rows
end
function R.pick(d,title)
 for _,a in ipairs(R.catalogue) do if a[1]==title and a[3] and (d.achievements or {})[title] then d.title=title;return true end end
 if title=='' then d.title=nil;return true end;return false
end
function R.title(d) for _,a in ipairs(R.catalogue) do if d and a[1]==d.title and (d.achievements or {})[d.title] then return a[3] end end end
return R
