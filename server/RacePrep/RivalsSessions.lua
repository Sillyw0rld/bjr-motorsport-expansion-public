-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Personal free-roam time attacks. Never starts a BJR event or changes its rules.
local Verification=dofile(debug.getinfo(1).source:gsub("^@", ""):gsub("\\", "/"):gsub("RivalsSessions.lua$", "RivalsVerification.lua"))
local Challenges=dofile(debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):gsub('RivalsSessions.lua$','Challenges.lua'))
local ClassBuild=dofile(debug.getinfo(1).source:gsub("^@", ""):gsub("\\", "/"):gsub("RivalsSessions.lua$", "ClassBuild.lua"))
local Rating=dofile(debug.getinfo(1).source:gsub("^@", ""):gsub("\\", "/"):gsub("RivalsSessions.lua$", "RatingStore.lua"))
local M={}
local function finite(n,lo,hi) return type(n)=='number' and n==n and n>=lo and n<=hi end
function M.new(api)
 local sessions,requests,serial={},{},0
 local lastPoll=-math.huge
 local function token() serial=serial+1;return api.token()..':'..serial end
 local self={}
 local function reply(pid,p) api.send(pid,'RacePrepRivalsSession',p) end
 local function refuse(pid,text) reply(pid,{error=text});return false end
 function self.active(pid) return sessions[pid]~=nil end
 function self.stop(pid) sessions[pid]=nil;reply(pid,{stopped=true}) end
 function self.disconnect(pid) sessions[pid]=nil;requests[pid]=nil end
 function self.start(pid,p)
  local now=api.now()
  if api.blocked(api.driver(pid)) then return refuse(pid,'You are blocked from Rivals boards. Contact Motorsport staff.') end
  if not api.clock or not api.position then return refuse(pid,'Server verification APIs unavailable.') end
  if requests[pid] and now-requests[pid]<2 then return refuse(pid,'Wait a moment before starting another challenge.') end
  requests[pid]=now
  if api.inRace(pid) then return refuse(pid,'Leave the BJR race before starting a Rivals run.') end
  local weekly,weeklyError
  if p.weekly==true and api.weekly then weekly,weeklyError=api.weekly();if not weekly or weeklyError then return refuse(pid,weeklyError or 'Weekly challenge is unavailable.') end end
  local rotation=p.rotation and api.rotation and api.rotation(p.rotation)
  if p.rotation and not rotation then return refuse(pid,'This published challenge is no longer available.')end
  local group=rotation and rotation.board or weekly and {id=weekly.challenge,raceID=weekly.raceID,raceName=weekly.raceName,layout=weekly.layout,rulesKey=weekly.rulesKey,rules=weekly.rules,class=weekly.class,bests={weekly.target}} or (api.group and api.group(p.challenge) or api.groups()[p.challenge])
  if not group then return refuse(pid,'Challenge is no longer available; refresh records.') end
  local race=api.race(group.raceID);local rules=api.currentRules and api.currentRules(group) or api.rules(group.raceID)
  if not race or type(race.gates)~='table' or #race.gates<2 or #race.gates>1024 or api.layout(race)~=group.layout or api.rulesKey(rules,group)~=group.rulesKey then return refuse(pid,'This challenge uses a different layout or rules. Ask staff to restore them or choose a current challenge.') end
  local car=api.car(pid,p.vehicle)
  if not car or car.class~=group.class then return refuse(pid,'Choose a rated car in '..group.class..' and wait for its current rating.') end
  local classWhy=ClassBuild.refusal(rules,car,api.factory and api.factory(car),Rating.classOf);if classWhy then return refuse(pid,classWhy)end
  if rules.specModel and rules.specModel~='' and car.model~=rules.specModel then return refuse(pid,'This challenge requires '..rules.specModel..'.') end
  if rules.specConfig and rules.specConfig~='' and car.config~=rules.specConfig then return refuse(pid,'This challenge requires configuration '..rules.specConfig..'.') end
  local target=rotation and rotation.target
  for _,row in pairs(not rotation and group.bests or {}) do
   if weekly or (row.runID==p.runID and row.driver==p.competitor and row.model==p.model) then target=row;break end
  end
  if not target and p.practice~=true and not rotation then return refuse(pid,'Target changed; refresh records and choose it again.') end
  if target and (target.verified~=true or api.blocked(target.driver,target.runID)) then return refuse(pid,'This target is unverified or was removed by staff.') end
  local signature,why=api.config(pid,car.vehicle,car)
  if not signature then return refuse(pid,why or 'Server vehicle configuration unavailable.') end
  local verifier,geometryError=Verification.new(race,car.speedCeiling)
  if not verifier then return refuse(pid,geometryError) end
  local runToken=token()
  local s={id=runToken,lapToken=token(),signature=signature,verifier=verifier,checked=0,car=car,level=api.level(),raceID=group.raceID,layout=group.layout,rulesKey=group.rulesKey,
   rules=rules,group=group,scorer=group.type and Challenges.newRun(group.type,group.options),rotation=rotation,weeklyID=weekly and weekly.id,weeklyEnds=weekly and weekly.ends,driver=api.driver(pid),started=now,lastLap=now,target=target,number=0}
  if not s.driver then return refuse(pid,'Driver identity is unavailable.') end
  sessions[pid]=s
  reply(pid,{id=runToken,lapToken=s.lapToken,level=s.level,raceID=s.raceID,raceName=group.raceName,track=race,rules=rules,
   challengeType=group.type,options=group.options,rotationID=rotation and rotation.id,weeklyID=weekly and weekly.id,model=car.model,buildKey=car.key,class=car.class,pi=car.pi,target=target and {name=target.name,time=target.lapTime or target.time,metric=target.metric,model=target.model,verified=true},reference=target and (not group.type or Challenges.TYPES[group.type].ghost) and api.trace(target)})
  return true
 end
 local function changed(pid,s)
  local now=api.now();local current=api.car(pid,s.car.vehicle);local race=api.race(s.raceID)
  if api.blocked(s.driver) then return 'Driver blocked from Rivals.' end
  if s.weeklyID and s.target and api.blocked(s.target.driver,s.target.runID) then return 'Weekly target removed by staff; this challenge is unavailable.' end
  if s.rotation and (now>=s.rotation.ends or s.rotation.target and api.blocked(s.rotation.target.driver,s.rotation.target.runID))then return 'Published challenge expired or target removed.'end
  if (s.weeklyEnds and now>=s.weeklyEnds) or now-s.started>7200 or api.inRace(pid) or api.level()~=s.level then return 'Track or activity changed; start a fresh run.' end
  if not current or current.key~=s.car.key or current.pi~=s.car.pi then return 'Car changed; start a fresh Rivals run.' end
  local signature=api.config(pid,s.car.vehicle,s.car)
  if signature~=s.signature then return 'Car changed: server parts or tune differ.' end
  if not race or api.layout(race)~=s.layout or api.rulesKey(api.currentRules and api.currentRules(s.group) or api.rules(s.raceID),s.group)~=s.rulesKey then return 'Track or rules changed; start a fresh run.' end
 end
 local function rotate(pid,s,message,lap)
  s.claim=nil;s.proof=nil;s.lapToken=token()
  if s.scorer and lap and lap.valid==false then s.scorer.reset()end
  reply(pid,{id=s.id,lapToken=s.lapToken,message=message,lap=lap})
 end
 local function resolve(pid,s)
  if not s.claim or not s.proof then return end
  local p,proof=s.claim,s.proof
  local why=proof.reason
  if not why and (p.valid~=true or not finite(p.cuts,0,0)) then why='Invalid lap reported by the game.' end
  if not why and math.abs(p.time-proof.time)>proof.tolerance then
   why=p.time<proof.time and 'Timing mismatch: game time shorter than server time (slow motion or clock mismatch).' or 'Timing mismatch between game and server.'
  end
  if why then rotate(pid,s,why,{valid=false,verified=false});return false end
  why=changed(pid,s)
  if why then sessions[pid]=nil;return refuse(pid,why) end
  s.number=s.number+1
  local now=api.now();local best={time=proof.time,lap=s.number,trace=proof.trace,verified=true}
  if s.scorer then
   local score,reason=s.scorer.add(proof,true)
   if not score then rotate(pid,s,reason,{time=proof.time,valid=true,verified=true});return false end
   best.time=score.time;best.metric=score.metric;best.lapTime=score.lapTime;best.trace=score.trace;best.ghost=score.ghost
  end
  local res={kind='rivals',verified=true,verification={version=1,method='beammp-server-crossings',gameTime=p.time,tolerance=proof.tolerance},
   challengeType=s.group and s.group.type,rotationID=s.rotation and s.rotation.id,weeklyID=s.weeklyID,completedAt=now,key='rivals:'..s.id..':'..s.number,runID='rivals:'..s.id..':'..s.number,level=s.level,raceID=s.raceID,raceName=api.name(s.raceID),
   date=os.date('!%Y-%m-%dT%H:%M:%SZ'),recordContext={layout=s.layout,rulesKey=s.rulesKey,rules=s.rules,type=s.group and s.group.type,options=s.group and s.group.options,preset=s.group and s.group.preset},rows={{name=api.nameOf(pid),model=s.car.model,
    car=s.car.car,class=s.car.class,pi=s.car.pi,verified=true,lapList={{lap=s.number,time=proof.time,verified=true,class=s.car.class,pi=s.car.pi,model=s.car.model}},
    buildKey=api.build(s.signature),rivalDriver=s.driver,best=best,status='FIN'}}}
  local saved=api.save(res)
  rotate(pid,s,saved and ((s.weeklyID and s.target and proof.time<s.target.time and 'Weekly target beaten! ' or '')..'Server-verified lap saved. Refresh challenges to see the board.') or 'Lap could not be saved; check server storage.',
   {time=proof.time,valid=saved==true,verified=saved==true})
  if saved and s.scorer and s.scorer.complete then sessions[pid]=nil;reply(pid,{stopped=true,message='Race-distance challenge completed.'})end
  return saved
 end
 function self.lap(pid,p)
  local s=sessions[pid]
  if not s or p.id~=s.id then return refuse(pid,'Rivals run expired; start it again.') end
  local now=api.clock()
  if s.lastPost and now-s.lastPost<200 then return false end;s.lastPost=now
  if p.lapToken~=s.lapToken or s.claim then reply(pid,{id=s.id,message='Replayed or out-of-order lap token refused.'});return false end
  if not finite(p.time,5000,1800000) then rotate(pid,s,'Invalid lap time.',{valid=false,verified=false});return false end
  if not s.proof and not s.verifier.running() then rotate(pid,s,s.verifier.reason() or 'No server-observed gate crossings.',{valid=false,verified=false});return false end
  -- Client trace intentionally ignored. Only server samples become references.
  s.claim={time=p.time,valid=p.valid,cuts=p.cuts,at=now}
  return resolve(pid,s)
 end
 function self.poll()
  if not api.clock then return end
  local now=api.clock()
  if now-lastPoll<40 then return end;lastPoll=now
  for pid,s in pairs(sessions) do
   if now-s.checked>=1000 then
    s.checked=now;local why=changed(pid,s)
    if why then sessions[pid]=nil;refuse(pid,why) end
   end
   if sessions[pid] then
    local raw,err=api.position(pid,s.car.vehicle)
    if s.scorer then local message=s.scorer.position(now,raw,err);if message then reply(pid,{id=s.id,message=message})end end
    local proof=s.verifier.sample(now,raw,err)
    local why=s.verifier.reason()
    if why and why~=s.reported then
     s.reported=why;s.proof=nil;rotate(pid,s,why,{valid=false,verified=false})
    elseif not why then s.reported=nil end
    if proof then
     if s.proof then rotate(pid,s,'Previous lap confirmation expired.',{valid=false,verified=false}) end
     s.proof=proof;resolve(pid,s)
    end
    if sessions[pid] and ((s.claim and now-s.claim.at>Verification.POST_WINDOW) or (s.proof and now-s.proof.finished>Verification.POST_WINDOW)) then
     rotate(pid,s,'Lap confirmation expired; no matching server finish.',{valid=false,verified=false})
    end
   end
  end
 end
 function self.vehicleEvent(pid,vid,reason)
  local s=sessions[pid]
  if not s or tostring(s.car.vehicle)~=tostring(pid)..'-'..tostring(vid) then return end
  if reason=='Reset' then
   if s.scorer then s.scorer.reset()end
   s.verifier.reset('Reset: cross the start line for a new lap.');s.reported=s.verifier.reason()
   rotate(pid,s,s.reported,{valid=false,verified=false})
  else sessions[pid]=nil;refuse(pid,'Car changed: '..reason..'. Start a fresh Rivals run.') end
 end
 function self.handle(pid,p)
  if type(p)~='table' then return end
  if p.action=='start' then return self.start(pid,p) elseif p.action=='stop' then if sessions[pid] and p.id==sessions[pid].id then return self.stop(pid) end elseif p.action=='lap' then return self.lap(pid,p) end
 end
 return self
end
return M
