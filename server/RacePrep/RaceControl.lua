-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Server-side control state is supplied by the small BeamJoyCore bridge.
local C={}
local function finite(v,min,max)
 v=tonumber(v);return v and v==v and v>=min and v<=max and v or nil
end
C.new=function(api)
 local Championship=dofile(api.path .. '/Championship.lua')
 local series=api.read(api.path .. '/championships.json')
 if type(series)~='table' or type(series.series)~='table' then series=Championship.new() end
 local Stats=dofile(api.path .. '/DriverStats.lua')
 local profiles=api.read(api.path .. '/drivers.json')
 if type(profiles)~='table' or type(profiles.drivers)~='table' then profiles=Stats.new() end
 profiles.seen=profiles.seen or {}
 local Persist=api.persistence or dofile(api.path..'/Persistence.lua')
 local pendingFile=api.path..'/records-pending.json'
 local pending=api.read(pendingFile) or {}
 local function saveSeries() return Persist.write(api.path..'/championships.json',series) end
 local function saveProfiles() return Persist.write(api.path..'/drivers.json',profiles) end
 local native=api.host and api.host.enabled
 local runs,runTelemetry={},{}
 local neutral={phase="none",participants={},falseStarts={},hazards={}}
 local self={state={phase='none',participants={},falseStarts={}},last={},lastOrder={}}
 self.pendingRecords=function() return next(pending)~=nil end
 self.driverProfile=function(key) return key and profiles.drivers[key] end
 local function atomicWrite(path,value)
  if api.write then return api.write(path,value) end
  local f=io.open(path..'.tmp','w');if not f then return false end
  local ok=f:write(Util.JsonEncode(value));local closed=f:close()
  if not ok or not closed then os.remove(path..'.tmp');return false end
  return os.rename(path..'.tmp',path)~=nil
 end
 local rubber=dofile(api.path..'/RubberMap.lua').new{read=api.read,write=atomicWrite,path=api.path}
 self.rubberMap=rubber
 local marbles=dofile(api.path..'/MarbleMap.lua').new{read=api.read,write=atomicWrite,path=api.path}
 self.marbleMap=marbles
 local marbleReports,marbleTakes={},{}
 -- Hirochi / ETK800 844_track_M: 7205 main-line cells, five laps, 2026-10-14.
 -- Mean tyre-metres per cell / car-lap; tools/analyse_rubber_calibration.py.
 local PER_LAP=1.401124923
 local rubberReports,rubberRequests={},{}
 local lastRubberPublish,lastRubberSave=-1e9,os.time()
 local telemetry={}
 local function selectRun(id)
  if not native then return end
  if id then
   runs[id]=runs[id] or {runID=id,falseStarts={},hazards={}}
   runTelemetry[id]=runTelemetry[id] or {};self.state=runs[id];telemetry=runTelemetry[id]
  else self.state=neutral;telemetry={} end
 end
 local function selectPlayer(pid) if native then selectRun(api.host.runFor(pid)) end end

 -- Track settings per map (track.json), set by admins in the Track window
 -- (Race Prep menu): rubber (on/off, level, build-up and grip) and wind. The
 -- rubber level stays between races and sessions; driving adds to it.
 local TRACK_DEFAULTS={rubber={enabled=false,initial=20,buildKm=50,lapsToFull=40,dryBonus=3,wetPenalty=5,marbleSize=5,marbleSizeFar=12},
  wind={enabled=false,speedKmh=15,direction=0,gustKmh=5,gustPeriod=12},
  -- weather: off = the map's own; on = everyone gets these values for the
  -- fields BeamJoy does not already sync (client weather.lua decides per field)
  weather={enabled=false,cloudCover=0.3,fogDensity=0.0002,rainDrops=0,tempNoon=24,tempDusk=19,tempMidnight=13,tempDawn=15}}
 local track=api.read(api.path .. '/track.json')
 if type(track)~='table' or type(track.levels)~='table' then
  track={schema=1,levels={}}
  -- 1.5.1-1.5.3 kept only the rubber distance (rubber.json)
  local old=api.read(api.path .. '/rubber.json')
  for key,e in pairs(type(old)=='table' and type(old.levels)=='table' and old.levels or {}) do
   track.levels[key]={amount=e.full==true and 1 or math.min(1,.2+(tonumber(e.metres) or 0)/50000)}
  end
 end
 local function mapKey(level)
  level=tostring(level or ''):lower():gsub('^/?levels/',''):gsub('/.*$','')
  return level~='' and #level<=128 and level:match('^[%w_%-]+$') and level or nil
 end
 local function saveTrack()
  local file=io.open(api.path .. '/track.json.tmp','w');if not file then return false end
  file:write(Util.JsonPrettify(Util.JsonEncode(track)));file:close()
  return os.rename(api.path .. '/track.json.tmp',api.path .. '/track.json')~=nil
 end
 local function trackEntry(key)
  local e=track.levels[key]
  if not e then e={};track.levels[key]=e end
  for group,defaults in pairs(TRACK_DEFAULTS) do
   e[group]=type(e[group])=='table' and e[group] or {}
   for k,v in pairs(defaults) do if e[group][k]==nil then e[group][k]=v end end
  end
  if tonumber(e.amount)==nil then e.amount=e.rubber.initial/100 end
  e.windSince=e.windSince or os.time()
  return e
 end
 local function trackView()
  local key=mapKey(self.state.level)
  if not key then return nil end
  local e=trackEntry(key)
  return {level=key,rubber=e.rubber,wind=e.wind,weather=e.weather,windElapsed=os.time()-e.windSince,rubberCells=rubber.count(key)}
 end
 --- a map's track weather (for BJR's weather sync), nil for an unknown map
 self.weatherFor=function(level)
  local key=mapKey(level);return key and trackEntry(key).weather or nil
 end
 -- what the rubber module applies
 local function rubberView()
  local v=trackView()
  if not v then return {enabled=false} end
  return {level=v.level,enabled=v.rubber.enabled==true,lapsToFull=v.rubber.lapsToFull,perLap=PER_LAP,
   dryBonus=v.rubber.dryBonus,wetPenalty=v.rubber.wetPenalty,marbleSize=v.rubber.marbleSize,marbleSizeFar=v.rubber.marbleSizeFar}
 end
 local lastSignatures,lastPublishAt={},{}
 local function stateKey()
  return native and tostring(self.state.runID or 'neutral') or 'default'
 end
 -- what changes the clients' view (not the countdown, which they keep themselves)
 local function signature()
  local s=self.state
  local parts={tostring(s.phase),tostring(s.runID),tostring(s.raceID),tostring(s.fullCourseYellow),
   table.concat(s.participants or {},','),tostring(s.tournament),tostring(s.level)}
  local keys={}
  for k in pairs(s.hazards or {}) do keys[#keys+1]='h'..k end
  for k in pairs(s.falseStarts or {}) do keys[#keys+1]='f'..k end
  table.sort(keys);parts[#parts+1]=table.concat(keys,',')
  local r=rubberView();parts[#parts+1]=table.concat({tostring(r.enabled),tostring(r.lapsToFull),tostring(r.dryBonus),tostring(r.wetPenalty),tostring(r.marbleSize),tostring(r.marbleSizeFar)},':')
  return table.concat(parts,'|')
 end
 local function publish(target)
  if api.identity and MP.GetPlayers then self.state.driverStats=Stats.view(profiles,api.identity,(native and api.host.names) or MP.GetPlayers()) end
  self.state.rules=api.rules(self.state.raceID,self.state.runID)
  self.state.track=trackView()
  self.state.rubber=rubberView()
  self.state.rubberLevel=nil
  self.state.championship=Championship.view(series)
  local k=stateKey()
  if not target then lastSignatures[k],lastPublishAt[k]=signature(),os.time() end
  local encoded=Util.JsonEncode(self.state)
  if native and not target then
   for pid in pairs(MP.GetPlayers()) do
    if api.host.runFor(pid)==self.state.runID then MP.TriggerClientEvent(tonumber(pid),'RacePrepControl',encoded) end
   end
  else MP.TriggerClientEvent(target or -1,'RacePrepControl',encoded) end
 end
 -- everyone: on change; during a grid or race also every 2 s (clients treat
 -- the race state as stale after 6 s)
 local function publishIfNeeded()
  local k=stateKey()
  local live=self.state.phase=='grid' or self.state.phase=='race'
  if signature()~=lastSignatures[k] or (live and os.time()-(lastPublishAt[k] or -1e9)>=2) then publish() end
 end
 local CHUNKS_PER_TICK=32
 local rubberQueues={}
 local function stepRubberQueues()
  for pid,q in pairs(rubberQueues) do
   local sent=0
   while q.at<=#q.items and sent<CHUNKS_PER_TICK do
    local item=q.items[q.at];q.at=q.at+1;sent=sent+1
    MP.TriggerClientEvent(pid,item.event,item.wire)
   end
   if q.at>#q.items then rubberQueues[pid]=nil end
  end
 end
 local function sendRubber(pid)
  local key=mapKey(self.state.level);if not key then return end
  if pid==-1 then rubberQueues={} end
  MP.TriggerClientEvent(pid,'RacePrepRubberReset',key)
  MP.TriggerClientEvent(pid,'RacePrepMarbleReset',key)
  local items={}
  for _,wire in ipairs(rubber.full(key,1000)) do items[#items+1]={event='RacePrepRubberDelta',wire=key..'|'..wire} end
  for _,wire in ipairs(marbles.full(key,1000)) do items[#items+1]={event='RacePrepMarbleDelta',wire=key..'|'..wire} end
  if #items>0 then
   rubberQueues[pid]={items=items,at=1}
   stepRubberQueues()
  else rubberQueues[pid]=nil end
 end
 self.sendRubber=sendRubber
 self.stepRubberQueues=stepRubberQueues
 self.addRubberCells=function(pid,wire)
  local key=mapKey(self.state.level)
  if not key or not trackEntry(key).rubber.enabled or type(wire)~='string' or #wire>512000 then return 0 end
  if MP.GetPlayerName and not MP.GetPlayerName(pid) then return 0 end
  local now=os.time()
  if rubberReports[pid] and now-rubberReports[pid]<2 then return 0 end
  rubberReports[pid]=now
  return rubber.add(key,wire,3000)
 end
 --- weather changed in BJR's own panel: kept in this map's track settings so
 --- both show the same (only while BJR:ME's weather is on for the map)
 self.weatherFromBJR=function(level,w,by)
  local key=mapKey(level);if not key or type(w)~='table' then return false end
  local e=trackEntry(key);if e.weather.enabled~=true then return false end
  local limits={cloudCover={0,2},fogDensity={0,0.05},tempNoon={-40,60},tempDusk={-40,60},tempMidnight={-40,60},tempDawn={-40,60}}
  local changed=false
  for k,range in pairs(limits) do
   local v=finite(w[k],range[1],range[2])
   if v and (not tonumber(e.weather[k]) or math.abs(v-e.weather[k])>1e-4) then e.weather[k]=math.floor(v*10000+.5)/10000;changed=true end
  end
  if changed then saveTrack();lastSignatures={};publish();print('[BJR:ME] Track weather updated from BJR\'s weather panel'..(by and (' ('..tostring(by)..')') or '')) end
  return changed
 end
 self.snapshot=function(p)
  if type(p)~='table' then return end
  if native then selectRun(p.runID) end
  if native and self.state.phaseIndex and p.phaseIndex and self.state.phaseIndex~=p.phaseIndex then
   self.state.falseStarts={};self.state.hazards={};self.state.incidents={}
   runTelemetry[p.runID]={};telemetry=runTelemetry[p.runID]
  end
  local oldMap,newMap=mapKey(self.state.level),mapKey(p.level)
  if native and p.runID then oldMap=mapKey(neutral.level) end
  if oldMap and oldMap~=newMap then rubber.save();marbles.save(true) end
  if not native and p.runID~=self.state.runID then
   if self.state.runID then
    self.last[self.state.runID]=self.state;self.lastOrder[#self.lastOrder+1]=self.state.runID
    if #self.lastOrder>16 then self.last[table.remove(self.lastOrder,1)]=nil end
   end
   self.state={falseStarts={},hazards={}}
   telemetry={}
  end
  for _,k in ipairs({'raceID','runID','phase','phaseName','phaseIndex','phaseCount','remaining','participants','racerKeys','racerKeyByPlayer','level','elapsed','raceName','tournament'}) do self.state[k]=p[k] end
  if oldMap~=newMap and newMap then rubberReports={};marbleReports={};sendRubber(-1) end
  self.state.falseStarts=self.state.falseStarts or {}
  self.state.hazards=self.state.hazards or {}
  for pid,h in pairs(self.state.hazards) do if os.time()-h.lastSeen>3 then self.state.hazards[pid]=nil end end
  publishIfNeeded()
 end
 self.event=function(pid,p)
  if native and type(p)=='table' then
   if api.host.runFor(pid)~=p.runID then return end
   selectRun(p.runID)
  end
  local s=self.state
  if type(p)~='table' or not s.runID or p.runID~=s.runID or s.phase~='race' then return end
  local member=false;for _,id in ipairs(s.participants or {}) do if tonumber(id)==tonumber(pid) then member=true end end
  if not member then return end
  local rules=api.rules(s.raceID,s.runID)
  if p.kind=='telemetry' then
   local speed=finite(p.speed,0,150)
   local q=p.position
   if not speed or type(q)~='table' or not finite(q.x,-1e7,1e7) or not finite(q.y,-1e7,1e7) or not finite(q.z,-1e7,1e7) then return end
   local id=tostring(pid);local prev=telemetry[id] or {};local now=os.time()
   if prev.lastSeen and now-prev.lastSeen>3 then prev.stoppedAt=nil end
   if rules.yellowFlags and (s.elapsed or 0)>10 and speed<2 then
    prev.stoppedAt=prev.stoppedAt or now
    if now-prev.stoppedAt>=3 then s.hazards[id]={position=q,lastSeen=now,playerID=pid} end
   else prev.stoppedAt=nil;s.hazards[id]=nil end
   s.incidents=s.incidents or {}
   local incidentKey=tostring((s.racerKeyByPlayer or {})[id] or id)
   local inc=s.incidents[incidentKey] or {contacts=0,distance=0};s.incidents[incidentKey]=inc
   if prev.position and prev.lastSeen then
    local dx,dy,dz=q.x-prev.position.x,q.y-prev.position.y,q.z-prev.position.z
    local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
    if dist<=math.min(100,math.max(speed,prev.speed or 0)*math.max(.5,now-prev.lastSeen)+10) then
     inc.distance=inc.distance+dist
    end
   end
   inc.samples=(inc.samples or 0)+1;inc.firstAt=inc.firstAt or now;inc.lastAt=now
   if prev.lastSeen then inc.maxGap=math.max(inc.maxGap or 0,now-prev.lastSeen) end
   prev.lastSeen=now;prev.position={x=q.x,y=q.y,z=q.z};prev.speed=speed
   telemetry[id]=prev
   return
  end
  if p.kind=='contact' and (s.remaining or 0)<=0 then
   -- reported by the driver's game when its car takes a hard hit (raceprep/
   -- director: who was closing on whom just before). verdict: "self" (no
   -- other car: wall, spin), "other" (the other car hit me), "me" (I hit
   -- it), "shared" (no clear fault). The car that was hit loses nothing.
   s.incidents=s.incidents or {}
   s.contactPairs=s.contactPairs or {}
   local me=tostring(pid)
   local other=p.other~=nil and tostring(p.other) or nil
   local otherMember=false
   if other then for _,x in ipairs(s.participants or {}) do if tostring(x)==other then otherMember=true end end end
   local verdict=p.verdict
   if not otherMember then other=nil;verdict='self' end
   local pair=other and ((me<other) and (me..'-'..other) or (other..'-'..me)) or me
   local now=os.time()
   if s.contactPairs[pair] and now-s.contactPairs[pair]<4 then return end -- the other car's copy
   s.contactPairs[pair]=now
   local function add(key,weight)
    key=tostring((s.racerKeyByPlayer or {})[key] or key)
    local inc=s.incidents[key] or {contacts=0,distance=0};s.incidents[key]=inc
    inc.contacts=inc.contacts+weight
   end
   local function hit(key)
    key=tostring((s.racerKeyByPlayer or {})[key] or key)
    local inc=s.incidents[key] or {contacts=0,distance=0};s.incidents[key]=inc
    inc.hitBy=(inc.hitBy or 0)+1
   end
   if verdict=='self' or not other then add(me,1)
   elseif verdict=='me' then add(me,1);hit(other)
   elseif verdict=='other' then add(other,1);hit(me)
   else add(me,.5);add(other,.5) end
   return
  end
  if p.kind=='falseStart'  and rules.startLights and rules.startType~='rolling' and
    finite(s.remaining,-1000,10000) then
   local racerKey=(s.racerKeyByPlayer or {})[tostring(pid)] or tostring(pid)
   if s.falseStarts[racerKey] then return end
   local penalty=math.max(0,tonumber(rules.falseStartPenaltySeconds) or 5)*1000
   s.falseStarts[racerKey]=penalty
   if native and penalty>0 and api.penalize and not (api.localPenalties and api.localPenalties()) then api.penalize(s.runID,racerKey,penalty,'False start') end
   publish()
  end
 end
 self.applyPenalties=function(res)
  local s=res.runID and (self.state.runID==res.runID and self.state or (native and runs[res.runID] or self.last[res.runID]))
  if not s or tostring(s.raceID)~=tostring(res.raceID) then return end
  res.level=s.level or res.level
  -- BJR without race.penalize: its times lack the penalties, BJR:ME adds them (as 2.16 did)
  local inBJR=native and not (api.localPenalties and api.localPenalties())
  for _,row in ipairs(res.rows or {}) do
   row.incidents=(s.incidents or {})[tostring(row.racerKey or row.playerID)]
   local penalty=(s.falseStarts or {})[tostring(row.racerKey or row.playerID)]
   if penalty then
    -- BJR already included race.penalize in totalMs. Keep the tag for stats/UI.
    if not inBJR then
     if row.total then row.total=row.total-(tonumber(row.falseStartPenalty) or 0)+penalty end
     row.penalty=(tonumber(row.penalty) or 0)-(tonumber(row.falseStartPenalty) or 0)+penalty
    end
    row.falseStart=true;row.falseStartPenalty=penalty
   end
  end
  -- BJR also orders lapped and disqualified finishers. Sorting only by time
  -- here could move a lapped or disqualified car ahead of its rightful place.
  if inBJR then return end
  -- re-sorted by penalised time; lapped and disqualified cars keep BJR's order
  -- among themselves (no total, sorted by position)
  table.sort(res.rows,function(a,b)
   if native and (a.disqualified or b.disqualified) and a.disqualified~=b.disqualified then return not a.disqualified end
   if native and (a.laps or 0)~=(b.laps or 0) then return (a.laps or 0)>(b.laps or 0) end
   if a.total and b.total then
    if a.total~=b.total then return a.total<b.total end
    return (a.position or 999)<(b.position or 999)
   end
   if a.total or b.total then return a.total~=nil end
   return (a.position or 999)<(b.position or 999)
  end)
  for i,row in ipairs(res.rows) do row.position=i;if row.total and res.rows[1].total then row.gap=row.total-res.rows[1].total end end
 end
 self.validRun=function(res)
  local s=res.runID and (self.state.runID==res.runID and self.state or (native and runs[res.runID] or self.last[res.runID]))
  return s and tostring(s.raceID)==tostring(res.raceID) or false
 end
 local function flushRecords()
  for key,job in pairs(pending) do
   local beforeSeries,beforeProfiles=Persist.copy(series),Persist.copy(profiles)
   local identity=function(_,row) return row and job.identities[tostring(row.racerKey or row.playerID)] end
   local seriesOK=true
   local active=series.active;series.active=job.seriesID
   local changed=Championship.record(series,job.result,identity,job.tournament);series.active=active
   if changed then
    seriesOK=saveSeries();if not seriesOK then series=beforeSeries end
   end
   local profilesOK=true
   if Stats.record(profiles,job.result,identity,job.safety) then
    profilesOK=saveProfiles();if not profilesOK then profiles=beforeProfiles end
   end
   if seriesOK and profilesOK then
    if api.progression then api.progression(job,profiles) end
    pending[key]=nil;lastSignatures={};publish() end
  end
  if not Persist.write(pendingFile,pending) then print('[BJR:ME] Could not save record retry queue; check disk space/permissions.') end
 end
 self.recordResult=function(res)
  local s=res.runID and (self.state.runID==res.runID and self.state or (native and runs[res.runID] or self.last[res.runID]))
  local identity=api.resultIdentity and function(pid,row) return api.resultIdentity(res.runID,tonumber(pid),row) end or api.identity
  if not identity then return end
  local ids={}
  for _,row in ipairs(res.rows or {}) do ids[tostring(row.racerKey or row.playerID)]=identity(tonumber(row.playerID),row) end
  local key=tostring(res.runID or res.key)
  pending[key]={progressionSnapshot=api.progressionSnapshot and api.progressionSnapshot(res),result=Persist.copy(res),identities=ids,seriesID=series.active,tournament=s and s.tournament,safety=api.rules(res.raceID,res.runID).safetyRating==true}
  if not Persist.write(pendingFile,pending) then print('[BJR:ME] Record retry queue is in memory only; keep server running until storage is available.') end
  flushRecords()
 end
 local nextRecordRetry=0

 function RacePrepControlSnapshot(data)
  if native then return end
  local ok,p=pcall(Util.JsonDecode,data or '')
  if ok then self.snapshot(p) end
 end
 function RacePrepControlEvent(pid,data)
  local ok,p=pcall(Util.JsonDecode,data or '')
  if ok then self.event(pid,p) end
 end
 function RacePrepGetControl(pid) selectPlayer(pid);publish(pid) end
 -- admin (SetConfig): change the current map's track settings
 -- {rubber={enabled,initial,buildKm,dryBonus,wetPenalty,marbleSize,marbleSizeFar}, wind={enabled,
 --  speedKmh,direction,gustKmh,gustPeriod}, amount (0-1: set the rubber level;
 --  "clean" = the starting rubber, 1 = fully rubbered)}
 local LIMITS={rubber={initial={0,100},buildKm={1,500},lapsToFull={10,400},dryBonus={0,10},wetPenalty={0,20},marbleSize={1,10},marbleSizeFar={1,25}},
  wind={speedKmh={0,120},direction={0,360},gustKmh={0,60},gustPeriod={2,120}},
  weather={cloudCover={0,2},fogDensity={0,0.05},rainDrops={0,5000},tempNoon={-40,60},tempDusk={-40,60},tempMidnight={-40,60},tempDawn={-40,60}}}
 self.setTrack=function(p)
  local key=mapKey(self.state.level)
  if not key or type(p)~='table' then return false end
  local e=trackEntry(key)
  for group,limits in pairs(LIMITS) do
   local g=type(p[group])=='table' and p[group] or nil
   if g then
    if type(g.enabled)=='boolean' then e[group].enabled=g.enabled end
    for k,range in pairs(limits) do
     local v=finite(g[k],range[1],range[2]);if v then e[group][k]=k=='lapsToFull' and math.floor(v+.5) or v end
    end
   end
  end
  if p.amount=='clean' then rubber.set(key,'clean');marbles.clean(key);sendRubber(-1)
  else local a=finite(p.amount,0,1);if a then rubber.set(key,a,PER_LAP*e.rubber.lapsToFull);sendRubber(-1) end end
  saveTrack()
  return true
 end
 -- the admin windows show this reply (refusals used to be silent)
 local function adminStatus(pid,text) if MP.TriggerClientEvent then MP.TriggerClientEvent(pid,'RacePrepAdminStatus',text) end end
 local NO_PERMISSION='Not saved: your BeamJoy group is not allowed to do this (Motorsport settings > Permissions).'
 function RacePrepTrackSet(pid,data)
  selectPlayer(pid)
  if native and not api.host.fresh() then adminStatus(pid,'Not saved: waiting for the BeamJoy-Revived plugin API (BJR 2.0 or newer, started with the server).');return end
  if not api.canEdit or not api.canEdit(pid) then adminStatus(pid,NO_PERMISSION);return end
  local ok,p=pcall(Util.JsonDecode,data or '')
  if ok and self.setTrack(p) then
   lastSignatures={};publish();adminStatus(pid,'Track settings saved.')
   if api.onTrack then pcall(api.onTrack) end
  else adminStatus(pid,'Not saved: no track loaded or invalid request.') end
 end
 MP.RegisterEvent('RacePrepTrackSet','RacePrepTrackSet')
 function RacePrepChampionship(pid,data)
  if not api.canEdit or not api.canEdit(pid) then adminStatus(pid,NO_PERMISSION);return end
  local ok,p=pcall(Util.JsonDecode,data or '')
  if not ok or type(p)~='table' then return end
  local s=Championship.active(series)
  if p.action=='create' then s=Championship.create(series,p.name,os.time(),p.linkTournament)
  elseif not s then return
  elseif p.action=='addRound' and s.status=='draft' and api.race then
   local race=api.race(p.level,p.raceID)
   if not race then return end
   if #s.rounds>=50 then return end
   s.rounds[#s.rounds+1]={level=p.level,raceID=p.raceID,name=race.name}
  elseif p.action=='start' and s.status=='draft' and #s.rounds>0 then s.status='running'
  elseif p.action=='stop' then s.status='stopped'
  else return end
  saveSeries();lastSignatures={};publish()
 end
 MP.RegisterEvent('RacePrepChampionship','RacePrepChampionship')
 function RacePrepYellow(pid,data)
  selectPlayer(pid)
  local control=api.canControl or api.canEdit
  if not control or not control(pid) then adminStatus(pid,NO_PERMISSION);return end
  local ok,p=pcall(Util.JsonDecode,data or '')
  if ok and type(p)=='table' and self.state.phase=='race' then self.state.fullCourseYellow=p.enabled==true;publish() end
 end
 function RacePrepControlDisconnect(pid)
  rubberReports[pid]=nil;rubberRequests[pid]=nil;marbleReports[pid]=nil;marbleTakes[pid]=nil;rubberQueues[pid]=nil
  self.state.hazards=self.state.hazards or {};self.state.hazards[tostring(pid)]=nil;telemetry[tostring(pid)]=nil
 end
 MP.RegisterEvent('RacePrepYellow','RacePrepYellow')
 MP.RegisterEvent('onPlayerDisconnect','RacePrepControlDisconnect')
 function RacePrepRubberAdd(pid,payload)
  if type(payload)~='string' then return end
  local level,wire=payload:match('^([^|]+)|(.+)$')
  if level==mapKey(self.state.level) then self.addRubberCells(pid,wire) end
 end
 function RacePrepMarbleAdd(pid,payload)
  if type(payload)~='string' or #payload>512000 then return end
  local key=mapKey(self.state.level);local level,wire=payload:match('^([^|]+)|(.+)$')
  if not key or key~=level or not trackEntry(key).rubber.enabled then return end
  if MP.GetPlayerName and not MP.GetPlayerName(pid) then return end
  local now=os.time();if marbleReports[pid] and now-marbleReports[pid]<2 then return end
  marbleReports[pid]=now;marbles.add(key,wire,3000)
 end
 MP.RegisterEvent('RacePrepMarbleAdd','RacePrepMarbleAdd')
 -- marbles a player's wheels took off cells (thinning, not clearing)
 function RacePrepMarbleTake(pid,payload)
  if type(payload)~='string' or #payload>512000 then return end
  local key=mapKey(self.state.level);local level,wire=payload:match('^([^|]+)|(.+)$')
  if not key or key~=level or not trackEntry(key).rubber.enabled then return end
  if MP.GetPlayerName and not MP.GetPlayerName(pid) then return end
  local now=os.time();if marbleTakes[pid] and now-marbleTakes[pid]<2 then return end
  marbleTakes[pid]=now;marbles.take(key,wire,3000)
 end
 MP.RegisterEvent('RacePrepMarbleTake','RacePrepMarbleTake')
 function RacePrepRubberGet(pid)
  if MP.GetPlayerName and not MP.GetPlayerName(pid) then return end
  local now=os.time();if rubberRequests[pid] and now-rubberRequests[pid]<10 then return end
  rubberRequests[pid]=now;sendRubber(pid)
 end
 MP.RegisterEvent('RacePrepRubberAdd','RacePrepRubberAdd')
 MP.RegisterEvent('RacePrepRubberGet','RacePrepRubberGet')
 function RacePrepControlTick()
  if next(pending) and os.time()>=nextRecordRetry then nextRecordRetry=os.time()+5;flushRecords() end
  if native then selectRun(nil) end
  MP.TriggerGlobalEvent('RacePrepControlSnapshotPing','')
  stepRubberQueues()
  if native then
   for id in pairs(runs) do if not api.host.runs[id] and api.host.fresh() then runs[id]=nil;runTelemetry[id]=nil;lastSignatures[id]=nil;lastPublishAt[id]=nil end end
   publishIfNeeded()
  end
  local now=os.time();local key=mapKey(self.state.level)
  if key and now-lastRubberPublish>=10 then
   lastRubberPublish=now
   local function broadcast(store,event)
    local wire,n=store.takeChanged(key)
    if n<=0 then return end
    local batch,count={},0
    for row in wire:gmatch('[^;]+') do
     batch[#batch+1]=row;count=count+1
     if count==1000 then MP.TriggerClientEvent(-1,event,key..'|'..table.concat(batch,';'));batch,count={},0 end
    end
    if count>0 then MP.TriggerClientEvent(-1,event,key..'|'..table.concat(batch,';')) end
   end
   broadcast(rubber,'RacePrepRubberDelta');broadcast(marbles,'RacePrepMarbleDelta')
  end
  if now-lastRubberSave>=60 then lastRubberSave=now;rubber.save();marbles.save() end
 end
 MP.RegisterEvent('RacePrepControlSnapshot','RacePrepControlSnapshot')
 MP.RegisterEvent('RacePrepControlEvent','RacePrepControlEvent')
 MP.RegisterEvent('RacePrepGetControl','RacePrepGetControl')
 MP.RegisterEvent('RacePrepControlTick','RacePrepControlTick')
 MP.CreateEventTimer('RacePrepControlTick',500)
 return self
end
return C
