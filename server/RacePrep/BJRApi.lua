-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BeamJoy-Revived plugin API bridge (BJR 1.11+: Resources/Server/BeamJoyServer/api).
-- BJR:ME never edits BJR. Through BJR's own API:
--  * grid order: the gridOrder hook answers with our order (qualifying,
--    reverse top N, handicap), instead of wrapping BJR's raceReady;
--  * race results: the RaceFinished event (every lap and sector, BJR's staff
--    penalties in totalMs), instead of polling BJR's sessions. Our automatic
--    penalties are layered on top downstream (BJRHost.results).
-- Lives in our own plugin folder, so `bj update` cannot remove it.
local M={}

--- RaceFinished data -> the result format the host sidecar used (RacePrepBJRResult)
function M.result(d)
 local res={key='bjr:'..tostring(d.sessionId),runID=d.sessionId,raceID=d.raceId,raceName=d.raceName,level=d.map,
  laps=d.laps,date=os.date('!%Y-%m-%dT%H:%M:%SZ'),rows={},source='bjr-api'}
 for i,r in ipairs(d.results or {}) do
  local row={playerID=r.id,name=r.name,car=r.vehicle or '',model=r.vehicle,status=r.finished and 'FIN' or 'DNF',
   disqualified=r.disqualified==true or nil,laps=#(r.laps or {}),lapList={},bjrPenaltyMs=r.penaltyMs,position=i}
  for _,f in ipairs(r.fields or {}) do
   if f.plugin=='RacePrep' then
    if f.key=='car' then row.car=f.value
    elseif f.key=='class_pi' then
     local class,pi=tostring(f.value):match('^([EDCBASRPX]) (%d+)$')
     pi=tonumber(pi);if pi and pi>=100 and pi<=999 then row.class=class;row.pi=pi end
    end
   end
  end
  for _,l in ipairs(r.laps or {}) do
   local sectors={}
   for k,t in ipairs(l.sectorsMs or {}) do sectors[k]=t end
   row.lapList[#row.lapList+1]={lap=l.lap,time=l.timeMs,sectors=sectors}
  end
  -- BJR's race time with its staff penalties; ours are added on top
  if r.finished then row.total=r.totalMs end
  res.rows[#res.rows+1]=row
 end
 return res
end

--- the gridOrder hook's answer: our order, limited to the racers in the lobby
function M.gridAnswer(order,racers)
 if type(order)~='table' or #order==0 then return {} end
 local present={}
 for _,r in ipairs(racers or {}) do if r.id then present[tonumber(r.id)]=true end end
 local ids,seen={},{}
 for _,e in ipairs(order) do
  local id=tonumber(type(e)=='table' and e.playerID or e)
  if id and present[id] and not seen[id] then ids[#ids+1]=id;seen[id]=true end
 end
 return #ids>0 and {order=ids} or {}
end

-- BJR:ME's entry in BJR's menu rail: a page drawn by BJR itself (its look,
-- its rail, side panel and Full-window tab). Its buttons open BJR:ME's window
-- on that section.
M.PAGE='motorsport'          -- the rail panel (small): cars and shortcuts
M.PAGE_FULL='motorsportfull' -- the full-window tab: opens BJR:ME's own window full screen
M.ACTIONS={setup=true,upgrades=true,rules=true,results=true,track=true,full=true}
--- the page for one player: their cars' class / PI, and where to go
function M.pageBlocks(cars,staff)
 local b={{type='heading',text='Your cars',sub='Class and Performance Index'}}
 if #cars==0 then
  b[#b+1]={type='text',text='Spawn a car to see its rating.',color='muted'}
 else
  for i,c in ipairs(cars) do
   if i>8 then break end
   b[#b+1]={type='row',cells={{text=c.name,grow=true},{text=c.class and (c.class..' '..tostring(c.pi)) or 'Rating pending',
    color=c.class and 'accent' or 'muted',bold=true,align='right'}}}
  end
 end
 b[#b+1]={type='divider'}
 b[#b+1]={type='buttons',items={{id='setup',label='Car setup',style='primary'},{id='upgrades',label='Upgrades'}}}
 b[#b+1]={type='buttons',items={{id='rules',label='Race rules'},{id='results',label='Results'}}}
 if staff then b[#b+1]={type='buttons',items={{id='track',label='Track & weather'}}} end
 return b
end

--- the full-window tab's own content (BJR:ME opens full screen on top of it)
function M.fullBlocks()
 return {{type='heading',text='Motorsport Expansion',sub='Opened full screen'},
  {type='text',text='Closed it? Open it again here.',color='muted'},
  {type='buttons',items={{id='full',label='Open full screen',style='primary'}}}}
end

--- a map's track weather (track.json) -> BJR's environment.set: BJR then
--- syncs cloud cover, fog and the day's air temperature to every player,
--- joiners included. Rain and the gusting wind stay BJR:ME's own (BJR has no
--- rain; gusts are worked out on each game from the shared wind clock).
--- nil when there is nothing to send (weather off).
function M.weatherPayload(w)
 if type(w)~='table' or w.enabled~=true then return nil end
 local function n(v,lo,hi) v=tonumber(v);return v and v==v and math.max(lo,math.min(hi,v)) or nil end
 local weather={cloudCover=n(w.cloudCover,0,2)}
 local fog=n(w.fogDensity,0,.05);if fog then weather.fogDensity=fog*1000 end -- BJR uses the panel's units (x1000)
 local noon,dusk,midnight,dawn=n(w.tempNoon,-40,60),n(w.tempDusk,-40,60),n(w.tempMidnight,-40,60),n(w.tempDawn,-40,60)
 -- the game's day: 0 noon, .25 dusk, .5 midnight, .75 dawn, 1 noon again
 if noon and dusk and midnight and dawn then weather.temperatureCurveOverrideC={{0,noon},{.25,dusk},{.5,midnight},{.75,dawn},{1,noon}} end
 if next(weather)==nil then return nil end
 return {weatherSync=true,weather=weather}
end

--- BJR's synced weather (environment.get / EnvironmentChanged's weather) ->
--- BJR:ME's track weather fields, for changes made in BJR's own panel: cloud
--- cover, fog (BJR's panel units / 1000) and the day curve read at noon, dusk,
--- midnight and dawn. Only fields BJR has are returned.
function M.weatherFromBJR(w)
 if type(w)~='table' then return {} end
 local out={}
 if tonumber(w.cloudCover) then out.cloudCover=tonumber(w.cloudCover) end
 if tonumber(w.fogDensity) then out.fogDensity=tonumber(w.fogDensity)/1000 end
 local c=w.temperatureCurveOverrideC
 if type(c)=='table' and #c>=2 then
  local function at(t)
   for i=1,#c-1 do
    local a,b=c[i],c[i+1]
    if t>=a[1] and t<=b[1] then return b[1]>a[1] and a[2]+(b[2]-a[2])*(t-a[1])/(b[1]-a[1]) or a[2] end
   end
   return t<c[1][1] and c[1][2] or c[#c][2]
  end
  out.tempNoon,out.tempDusk,out.tempMidnight,out.tempDawn=at(0),at(.25),at(.5),at(.75)
 end
 return out
end

--- every BJR API hook, method and event BJR:ME uses, by feature (logged at
--- start: available or missing on this BeamJoy-Revived)
M.USES={
 {'Grid','hook','gridOrder','starting order: qualifying, reverse, handicap'},
 {'Race','event','RaceCountdown','race start, grid lock, race weekend'},
 {'Race','event','RaceFinished','race results, race weekend'},
 {'Race','event','RaceClosed','race end cleanup'},
 {'Race','method','races.sessions','race sessions, every second'},
 {'Race','event','RacesChanged','race layouts reloaded'},
 {'Results','method','results.setFields','car and class / PI on results'},
 {'Weather','method','environment.set','track weather through BJR weather sync'},
 {'Weather','event','EnvironmentChanged','weather changed in BJR read back'},
 {'Players','method','players.online','groups for permissions, staff, names'},
 {'Players','event','PlayerLeft','player cleanup'},
 {'Map','event','MapChanged','map changes'},
 {'Menu','method','pages.register','Motorsport page in the BJR menu'},
}
--- server.info's methods / events -> {ok={...}, missing={...}} lines for the log
function M.report(info)
 local has={method={},event={}}
 for _,m in ipairs(type(info)=='table' and type(info.methods)=='table' and info.methods or {}) do has.method[m]=true end
 for _,e in ipairs(type(info)=='table' and type(info.events)=='table' and info.events or {}) do has.event[e]=true end
 local ok,missing={},{}
 for _,u in ipairs(M.USES) do
  local group,kind,name,what=u[1],u[2],u[3],u[4]
  local present
  if kind=='hook' then present=has.method['hooks.register'] else present=has[kind][name] end -- hooks register through hooks.register
  local line=string.format('%-8s %s %s (%s)',group,name,kind,what)
  if present then ok[#ok+1]=line else missing[#missing+1]=line end
 end
 return {ok=ok,missing=missing}
end

--- o = {path = our plugin folder, log, gridOrder(raceID) -> {{playerID}...}|nil,
---      result(res), ready(info), cars(playerID) -> {{name, class, pi}},
---      staff(playerID) -> bool, open(playerID, section)}.
--- nil when this BeamJoy has no API (older BJR, BJI).
function M.start(o)
 local root=o.path:match('^(.*)/[^/]+$')
 local helper=root and root..'/BeamJoyServer/api/BeamJoyAPI.lua'
 local f=helper and io.open(helper,'r')
 if not f then return nil end
 f:close()
 local ok,BJ=pcall(dofile,helper)
 if not ok or type(BJ)~='table' then o.log('BJR API helper failed to load: '..tostring(BJ));return nil end
 BJ.init('RacePrep')
 -- the first successful answer of each method BJR:ME calls, once in the log
 local answered,call={},BJ.call
 BJ.call=function(method,params,callback)
  return call(method,params,function(ok,result)
   if ok and not answered[method] then answered[method]=true;o.log('BJR API ✓ '..tostring(method)..' answered') end
   if callback then return callback(ok,result) end
  end)
 end
 local openedCars,fieldSignatures,lockedGrids={},{},{}
 local weatherSent -- what was last sent, so an unchanged preset is not sent again
 --- the current map's track weather (see M.weatherPayload); w=nil or off: nothing sent
 BJ.syncWeather=function(w)
  local p=M.weatherPayload(w)
  if not p or not BJ.call then return false end
  local sig=BJ.json and BJ.json.stringify and BJ.json.stringify(p) or nil
  if sig and sig==weatherSent then return false end
  -- noted when sent, not when answered: BJR's API coming up and the map
  -- being learnt both sync at startup, and sent the same preset twice
  weatherSent=sig
  BJ.call('environment.set',p,function(ok,err)
   if ok then o.log('Track weather synced through BJR (clouds, fog, air temperature)')
   else
    if weatherSent==sig then weatherSent=nil end -- refused: try again next time
    o.log('BJR weather sync: '..tostring(err and (err.message or err.code) or err))
   end
  end)
  return true
 end
 BJ.gridLocked=function(id) return lockedGrids[tostring(id)]==true end
 BJ.on('RaceCountdown',function(d)
  if d and d.sessionId then lockedGrids[tostring(d.sessionId)]=true end
  if d and o.countdown then o.countdown(d) end
 end)
 BJ.refreshCars=function(pid)
  if openedCars[tonumber(pid)] and BJ.updatePage then
   BJ.updatePage(M.PAGE,M.pageBlocks(o.cars and o.cars(pid) or {},o.staff and o.staff(pid)),{tonumber(pid)})
  end
 end
 -- Public BJR plugin fields appear on its native results and on the PB that
 -- run sets. Never stamp a current car's PI onto an unrelated old record.
 BJ.setCarFields=function(runID,pid,e)
  if not BJ.call or not e or not e.pi or BJ.gridLocked(runID) then return end
  local key=tostring(runID)..':'..tostring(pid)
  local name=e.carName or e.car or tostring(e.model or ''):gsub('_',' ')
  local badge=tostring(e.class)..' '..tostring(e.pi)
  local sig=name..'|'..badge
  if fieldSignatures[key]==sig then return end
  BJ.call('results.setFields',{sessionId=runID,playerId=tonumber(pid),fields={
   {key='car',label='Car',value=name,color='muted'},
   {key='class_pi',label='Class / PI at race start',value=badge,color='accent'},
  }},function(ok,err)
   if ok then fieldSignatures[key]=sig else o.log('BJR car labels: '..tostring(err and err.message or err)) end
  end)
 end
 BJ.on('RaceClosed',function(d)
  lockedGrids[tostring(d and d.sessionId)]=nil
  local prefix=tostring(d and d.sessionId)..':'
  for key in pairs(fieldSignatures) do if key:sub(1,#prefix)==prefix then fieldSignatures[key]=nil end end
 end)
 BJ.on('PlayerLeft',function(d) local pid=d and tonumber(d.id);if pid then openedCars[pid]=nil end end)
 BJ.on('MapChanged',function(d) if o.mapChanged then o.mapChanged(d) end end)
 -- weather changed in BJR's own panel (not by BJR:ME): read back into the track settings
 BJ.on('EnvironmentChanged',function(d)
  if type(d)~='table' or d.by=='RacePrep' or not o.environmentChanged then return end
  o.environmentChanged(M.weatherFromBJR(d.weather),d.by)
 end)
 BJ.on('RacesChanged',function(d) if o.racesChanged then o.racesChanged(d) end end)
 BJ.onReady(function(info)
  o.log('BJR plugin API ready (BeamJoy '..tostring(info and info.beamjoy and info.beamjoy.version)..')')
  weatherSent=nil -- BJR (re)started: send the track weather again
  local r=M.report(info)
  for _,line in ipairs(r.ok) do o.log('BJR API ✓ '..line) end
  for _,line in ipairs(r.missing) do o.log('BJR API ✗ '..line..' missing on this BeamJoy-Revived: that feature is off') end
  if o.ready then o.ready(info) end
 end)
 if BJ.page then
  BJ.page({id=M.PAGE,title='Motorsport Expansion',label='Motorsport',icon='flag',where='rail',
   blocks=M.pageBlocks({},false)})
  BJ.page({id=M.PAGE_FULL,title='Motorsport Expansion',label='Motorsport',icon='flag',where='full',
   blocks=M.fullBlocks()})
  BJ.onPageOpened(function(pageId,by)
   if type(by)~='table' or not by.id then return end
   if pageId==M.PAGE then
    openedCars[tonumber(by.id)]=true
    BJ.updatePage(M.PAGE,M.pageBlocks(o.cars and o.cars(by.id) or {},o.staff and o.staff(by.id)),{by.id})
   elseif pageId==M.PAGE_FULL and o.open then
    -- BJR's full window: show BJR:ME's own full window, not the small page stretched
    o.open(by.id,'full')
   end
  end)
  BJ.onPageAction(function(pageId,action,_,by)
   if (pageId==M.PAGE or pageId==M.PAGE_FULL) and M.ACTIONS[action] and type(by)=='table' and by.id and o.open then o.open(by.id,action) end
  end)
 end
 BJ.hook('gridOrder',function(q)
  local s=type(q)=='table' and q.session or {}
  return M.gridAnswer(o.gridOrder(s.raceId),q and q.racers)
 end)
 BJ.on('RaceFinished',function(d) if type(d)=='table' then o.result(M.result(d)) end end)
 return BJ
end
return M
