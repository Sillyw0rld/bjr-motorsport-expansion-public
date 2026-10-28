-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR plugin API bridge (2026-10-17): grid order through BJR's gridOrder hook,
-- results from BJR's event-level RaceFinished; BJR penalties stay authoritative
local A=dofile('server/RacePrep/BJRApi.lua')
-- BeamMP names loaded chunks without Lua's optional @ prefix. Exercise the
-- actual loader with those names rather than mocking debug.getinfo itself.
do
 local file=assert(io.open('server/RacePrep/BJRApi.lua'));local source=file:read('*a');file:close()
 for _,case in ipairs({
  {'Resources/Server/RacePrep/BJRApi.lua','Resources/Server/RacePrep/Weekend.lua'},
  {'@Resources/Server/RacePrep/BJRApi.lua','Resources/Server/RacePrep/Weekend.lua'},
  {'@/srv/beammp/Resources/Server/RacePrep/BJRApi.lua','/srv/beammp/Resources/Server/RacePrep/Weekend.lua'},
  {'C:\\BeamMP\\Resources\\Server\\RacePrep\\BJRApi.lua','C:/BeamMP/Resources/Server/RacePrep/Weekend.lua'},
 }) do
  local loaded
  local env=setmetatable({dofile=function(path)
   assert(path==case[2],'incorrect module path: '..path);loaded=true
   return dofile('server/RacePrep/Weekend.lua')
  end},{__index=_G})
  local chunk=assert(loadstring(source,case[1]));setfenv(chunk,env)
  assert(type(chunk().start)=='function' and loaded,'module loads for '..case[1])
 end
end
-- RaceFinished as BJR 1.11's services/api.lua builds it
local d={sessionId=7,raceId=3,raceName='Imola',map='imola',laps=2,results={
 {position=1,id=1,racerKey='rk-ana',name='Ana',vehicle='etk800',finished=true,disqualified=false,totalMs=125000,bestLapMs=61000,penaltyMs=5000,
  laps={{lap=1,timeMs=61000,sectorsMs={20000,21000,20000}},{lap=2,timeMs=59000,sectorsMs={19000,20000,20000}}}},
 {id=2,name='Ben',vehicle='sbr',finished=false,disqualified=true,laps={{lap=1,timeMs=63000,sectorsMs={21000,21000,21000}}}},
}}
local res=A.result(d)
assert(res.runID==7 and res.raceID==3 and res.level=='imola' and res.key=='bjr:7' and res.source=='bjr-api')
local a,b=res.rows[1],res.rows[2]
assert(a.playerID==1 and a.status=='FIN' and a.total==125000 and a.laps==2 and a.bjrPenaltyMs==5000,'BJR total incl. its staff penalty')
assert(a.lapList[2].time==59000 and a.lapList[2].sectors[1]==19000)
assert(b.status=='DNF' and b.disqualified and b.total==nil and b.position==2)
d.results[1].fields={{plugin='Other',key='class_pi',value='X 999'},{plugin='RacePrep',key='car',value='Hawk Vipere S'},{plugin='RacePrep',key='class_pi',value='B 595'}}
local tagged=A.result(d).rows[1];assert(tagged.car=='Hawk Vipere S' and tagged.pi==595 and tagged.class=='B','recover only our frozen tags if host metadata has already expired')
-- our automatic penalties go on top of BJR's time (owner: layer, don't replace)
local H=dofile('server/RacePrep/BJRHost.lua')
H.cuts[7]={['rk-ana']={['1']=2}}
H.results(res,{trackLimits='penalty',cutPenaltyAfter=1,cutPenaltySeconds=3})
assert(a.total==125000 and a.penalty==5000,'BJR total and penalty remain authoritative; no double addition')
-- grid order answer: only racers in this lobby, BJR's order for the rest
local ans=A.gridAnswer({{racerKey='rk3'},{racerKey='rk1'},{racerKey='rk9'},{racerKey='rk3'}},{{id=1,racerKey='rk1'},{id=3,racerKey='rk3'},{id=4,racerKey='rk4'}})
assert(ans.by=='racerKey' and #ans.order==2 and ans.order[1]=='rk3' and ans.order[2]=='rk1','stable racer keys, present and deduplicated')
assert(next(A.gridAnswer(nil,{{id=1,racerKey='rk1'}}))==nil and next(A.gridAnswer({},{{id=1,racerKey='rk1'}}))==nil,'no order: BJR keeps its own')
-- start(): loads BJR's helper from BeamJoyServer/api; nil without it
local tmp=os.tmpname();os.remove(tmp);os.execute('mkdir -p '..tmp..'/BeamJoyServer/api '..tmp..'/RacePrep')
assert(A.start({path=tmp..'/Nope/RacePrep',log=print})==nil,'no API: old path')
local f=io.open(tmp..'/BeamJoyServer/api/BeamJoyAPI.lua','w')
f:write("local BJ={hooks={},events={},updates={}} function BJ.init(n) BJ.name=n end function BJ.onReady(fn) BJ.readyFn=fn end function BJ.hook(n,fn) BJ.hooks[n]=fn end function BJ.on(e,fn) BJ.events[e]=fn end function BJ.formats(x) BJ.formatDefs=x end "..
 "function BJ.page(p) BJ.pages=BJ.pages or {} BJ.pages[p.id]=p BJ.pageDef=BJ.pageDef or p end function BJ.updatePage(id,blocks,players) BJ.updates[#BJ.updates+1]={id=id,blocks=blocks,players=players} end "..
 "function BJ.onPageOpened(fn) BJ.opened=fn end function BJ.onPageAction(fn) BJ.action=fn end function BJ.call(m,p,cb) BJ.calls=BJ.calls or {};BJ.calls[#BJ.calls+1]={method=m,params=p};if cb then cb(true,{}) end end return BJ")
f:close()
local got,ready,opened
local BJ=A.start({path=tmp..'/RacePrep',log=function() end,gridOrder=function(raceID) assert(raceID==3) return {{racerKey='rk2'},{racerKey='rk1'}} end,
 result=function(r) got=r end,ready=function() ready=true end,
 cars=function(pid) return pid==5 and {{name='etk800 · 844_track_M',class='A',pi=612}} or {} end,staff=function(pid) return pid==5 end,
 open=function(pid,section) opened={pid=pid,section=section} end})
-- BJR menu: a rail panel (small page) and a full-window tab that opens BJR:ME's own window full screen
assert(BJ.pageDef.id=='motorsport' and BJ.pageDef.title=='Motorsport Expansion' and BJ.pageDef.icon=='flag' and BJ.pageDef.where=='rail')
assert(BJ.pages.motorsportfull and BJ.pages.motorsportfull.where=='full','full-window tab registered separately')
BJ.opened('motorsportfull',{id=7,name='Cy'});assert(opened and opened.pid==7 and opened.section=='full','full tab opens our window full screen')
opened=nil;BJ.action('motorsportfull','full',{},{id=7});assert(opened and opened.section=='full','its button reopens it')
opened=nil
BJ.opened('motorsport',{id=5,name='Ana'})
local u=BJ.updates[1];assert(u.players[1]==5,'their own content')
local txt='';for _,b in ipairs(u.blocks) do for _,c in ipairs(b.cells or {}) do txt=txt..' '..tostring(c.text) end;for _,it in ipairs(b.items or {}) do txt=txt..' ['..it.id..']' end end
assert(txt:find('A 612') and txt:find('%[setup%]') and txt:find('%[track%]'),'cars and staff button: '..txt)
BJ.opened('motorsport',{id=6,name='Ben'})
local t2='';for _,b in ipairs(BJ.updates[2].blocks) do t2=t2..tostring(b.text);for _,it in ipairs(b.items or {}) do t2=t2..' ['..it.id..']' end end
assert(t2:find('Spawn a car') and not t2:find('%[track%]'),'no cars, no staff button')
BJ.action('motorsport','upgrades',{},{id=6});assert(opened.pid==6 and opened.section=='upgrades')
opened=nil;BJ.action('motorsport','evil',{},{id=6});BJ.action('other','setup',{},{id=6});assert(opened==nil,'only our page, only known sections')
assert(BJ and BJ.name=='RacePrep' and BJ.hooks.gridOrder and BJ.events.RaceFinished)
-- 2.32.0: the weekend format registers only on a BJR with phases (real API lists)
local bjrInfo=assert(loadstring(io.popen('python3 -I tests/json2lua.py tests/fixtures/bjr-api-info.json'):read('*a')))()
local releasedInfo=bjrInfo.released_2_0_1;releasedInfo.beamjoy={version='2.0.1'}
BJ.readyFn(releasedInfo);assert(ready and BJ.formatDefs==nil and BJ.caps and not BJ.caps.phases,'released 2.0.1: classic weekends, no format')
local devInfo=bjrInfo.development_2488;devInfo.beamjoy={version='2.0.1'}
BJ.readyFn(devInfo);assert(BJ.caps.phases)
assert(BJ.formatDefs and BJ.formatDefs[1].id=='weekend' and BJ.formatDefs[1].result=='last','formats.register payload')
BJ.openWeekend({raceID=3,practiceMinutes=0,qualifyingMinutes=6,raceLaps=9,name='Test weekend'})
local openedCall=table.remove(BJ.calls)
assert(openedCall.method=='race.open' and openedCall.params.raceId==3 and openedCall.params.options.result=='last')
assert(#openedCall.params.options.phases==2 and openedCall.params.options.phases[1].name=='Qualifying' and openedCall.params.options.phases[2].laps==9,'race.open exact optional-phase payload')
local o=BJ.hooks.gridOrder({session={raceId=3,phase={name='Race',ranking='position'}},racers={{id=1,racerKey='rk1'},{id=2,racerKey='rk2'}}})
assert(o.by=='racerKey' and o.order[1]=='rk2' and o.order[2]=='rk1','hook answers by racer key')
assert(next(BJ.hooks.gridOrder({session={raceId=3,phaseCount=3,phase={name='Qualifying',ranking='best',countsToEvent=false}},racers={{racerKey='rk1'}}}))==nil,'grid hook is race phase only')
local q=A.qualifyingView({{phase={name='Practice',ranking='best'},results={{racerKey='practice'}}},{phase={name='Qualifying',ranking='best'},results={{id=8,racerKey='stable-8',name='Rejoined',bestLapMs=61000}}}})
assert(q.rows[1].racerKey=='stable-8' and q.rows[1].best==61000,'qualifying comes from previous by stable racer key')
local Sessions=dofile('server/RacePrep/Sessions.lua')
local previous={{phase={name='Qualifying',ranking='best',countsToEvent=false},results={{id=1,racerKey='rk1',bestLapMs=60000},{id=2,racerKey='rk2',bestLapMs=62000},{id=3,racerKey='rk3'}}}}
local racers={{id=8,racerKey='rk1'},{id=2,racerKey='rk2'},{id=3,racerKey='rk3'}}
local quali=A.qualifyingView(previous)
local qualifyingOrder=A.gridAnswer(Sessions.gridOrder('qualifying',quali,{},2),racers)
assert(qualifyingOrder.order[1]=='rk1' and qualifyingOrder.order[2]=='rk2','reconnected player 8 retains player 1 qualifying position')
local reversed=A.gridAnswer(Sessions.gridOrder('reverse',quali,{},2),racers)
assert(reversed.order[1]=='rk2' and reversed.order[2]=='rk1' and reversed.order[3]=='rk3','reverse top two leaves untimed racer behind')
local handicap=A.gridAnswer(Sessions.gridOrder('handicap',nil,{rk1=700,rk2=500,rk3=600},2),racers)
assert(handicap.order[1]=='rk2' and handicap.order[2]=='rk3' and handicap.order[3]=='rk1','handicap answers by stable racer key')
-- track limits: a qualifying lap with a cut sets no grid place (BJR's best lap still counts it)
local cutPrevious={{phase={name='Practice'},results={}},{phase={name='Qualifying',ranking='best',countsToEvent=false},results={
 {id=1,racerKey='rk1',bestLapMs=60000,laps={{lap=1,timeMs=60000},{lap=2,timeMs=62500}}},
 {id=2,racerKey='rk2',bestLapMs=61000,laps={{lap=1,timeMs=61000}}},
 {id=3,racerKey='rk3',bestLapMs=59000,laps={{lap=1,timeMs=59000}}}}}}
local askedPhase
local cutQuali=A.qualifyingView(cutPrevious,function(i) askedPhase=i;return {rk1={['1']=1},rk3={['1']=2}} end)
assert(askedPhase==2,'cuts read for the qualifying phase index')
assert(cutQuali.rows[1].racerKey=='rk2' and cutQuali.rows[2].racerKey=='rk1' and cutQuali.rows[2].best==62500,'cut lap ignored, next valid lap counts')
assert(cutQuali.rows[3].racerKey=='rk3' and cutQuali.rows[3].best==nil,'only cut laps: no valid time, starts behind')
local cutGrid=A.gridAnswer(Sessions.gridOrder('qualifying',cutQuali,{},0),racers)
assert(cutGrid.order[1]=='rk2' and cutGrid.order[2]=='rk1' and cutGrid.order[3]=='rk3','grid follows valid laps')
assert(A.qualifyingView(cutPrevious,function() return nil end).rows[1].racerKey=='rk3','no cut record: BJR best laps as before')
BJ.events.RacePhaseFinished({sessionId=7,raceId=3,phaseIndex=2,phase={name='Qualifying'},results={}})
assert(got==nil,'practice and qualifying do not enter event history/stats')
BJ.events.RaceFinished(d);assert(got and got.runID==7,'RaceFinished feeds our results')
local before=#BJ.updates;BJ.refreshCars(5);assert(#BJ.updates==before+1,'open rail page refreshes after upgrade')
BJ.refreshCars(99);assert(#BJ.updates==before+1,'no updates to players who never opened the page')
BJ.setCarFields('run',5,{model='car',carName='Hawk Vipere S',class='B',pi=595})
local c=BJ.calls[1];assert(c.method=='results.setFields' and c.params.sessionId=='run' and c.params.playerId==5)
assert(c.params.fields[1].value=='Hawk Vipere S' and c.params.fields[2].value=='B 595','native results/PB labels through public API')
BJ.setCarFields('run',5,{model='car',carName='Hawk Vipere S',class='B',pi=595});assert(#BJ.calls==1,'identical fields do not spam BJR')
BJ.setCarFields('run',5,{model='car',carName='Hawk Vipere S',class='A',pi=604});assert(#BJ.calls==2,'new grid setup refreshes fields')
BJ.events.RaceCountdown({sessionId='run'});assert(BJ.gridLocked('run'))
BJ.setCarFields('run',5,{model='car',carName='Other car',class='A',pi=650});assert(#BJ.calls==2,'countdown freezes labels independently of metadata polling')
BJ.events.RaceClosed({sessionId='run'});assert(not BJ.gridLocked('run'),'release per-race caches on close')
local callsBefore=#BJ.calls
BJ.events.RaceCountdown({sessionId='penalty-test'})
BJ.penalize('penalty-test','rk1',5000,'False start')
assert(#BJ.calls==callsBefore,'BJR refuses countdown penalties: defer until green')
BJ.events.RaceGreenLight({sessionId='penalty-test'})
assert(#BJ.calls==callsBefore+1 and BJ.calls[#BJ.calls].method=='race.penalize' and BJ.calls[#BJ.calls].params.racerKey=='rk1')
BJ.events.RaceGreenLight({sessionId='penalty-test'})
assert(#BJ.calls==callsBefore+1,'duplicate green never repeats the penalty')
BJ.events.RaceCountdown({sessionId='cancelled'})
BJ.penalize('cancelled','rk1',5000,'False start')
BJ.events.RaceClosed({sessionId='cancelled'})
BJ.events.RaceGreenLight({sessionId='cancelled'})
assert(#BJ.calls==callsBefore+1,'closed countdown discards pending penalties')
assert(not BJ.calls[1].params.name,'never rewrites an unrelated historic leaderboard entry')
-- weather changed in BJR's own panel, read back (two-way, 2.14.3)
local back=A.weatherFromBJR({cloudCover=.8,fogDensity=.5,windSpeed=3,temperatureCurveOverrideC={{0,30},{.25,24},{.5,16},{.75,18},{1,30}}})
assert(back.cloudCover==.8 and math.abs(back.fogDensity-.0005)<1e-12 and back.tempNoon==30 and back.tempDusk==24 and back.tempMidnight==16 and back.tempDawn==18 and back.windSpeed==nil)
local mid=A.weatherFromBJR({temperatureCurveOverrideC={{0,20},{.5,10},{1,20}}})
assert(mid.tempDusk==15 and mid.tempMidnight==10 and mid.tempDawn==15,'curve read between its points')
assert(next(A.weatherFromBJR(nil))==nil and next(A.weatherFromBJR({}))==nil)
-- track weather through BJR's weather sync (2.0): clouds, fog (panel units), day curve
assert(A.weatherPayload(nil)==nil and A.weatherPayload({enabled=false,cloudCover=1})==nil,'weather off: nothing sent')
local wp=A.weatherPayload({enabled=true,cloudCover=.4,fogDensity=.0002,rainDrops=900,tempNoon=28,tempDusk=22,tempMidnight=15,tempDawn=17})
assert(wp.weatherSync==true and wp.weather.cloudCover==.4 and math.abs(wp.weather.fogDensity-.2)<1e-9,'fog in BJR panel units')
local c=wp.weather.temperatureCurveOverrideC
assert(#c==5 and c[1][1]==0 and c[1][2]==28 and c[2][2]==22 and c[3][1]==.5 and c[3][2]==15 and c[5][1]==1 and c[5][2]==28,'noon/dusk/midnight/dawn day curve')
assert(wp.weather.rainDrops==nil and wp.weather.windSpeed==nil,'rain and wind stay BJR:ME-side')
assert(A.weatherPayload({enabled=true,tempNoon=99})==nil and A.weatherPayload({enabled=true,cloudCover=1,tempNoon=20}).weather.temperatureCurveOverrideC==nil,'incomplete curve not sent')
BJ.json={stringify=function(t) local function enc(v) if type(v)=='table' then local k={} for key in pairs(v) do k[#k+1]=tostring(key) end table.sort(k) local o={} for _,key in ipairs(k) do o[#o+1]=key..'='..enc(v[key] or v[tonumber(key)]) end return '{'..table.concat(o,',')..'}' end return tostring(v) end return enc(t) end}
local before=#BJ.calls
assert(BJ.syncWeather({enabled=true,cloudCover=.4,fogDensity=.0002,tempNoon=28,tempDusk=22,tempMidnight=15,tempDawn=17}))
local sent=BJ.calls[#BJ.calls];assert(#BJ.calls==before+1 and sent.method=='environment.set' and sent.params.weatherSync==true)
assert(not BJ.syncWeather({enabled=true,cloudCover=.4,fogDensity=.0002,tempNoon=28,tempDusk=22,tempMidnight=15,tempDawn=17}) and #BJ.calls==before+1,'unchanged preset not sent again')
assert(not BJ.syncWeather({enabled=false}) and #BJ.calls==before+1,'weather off: BJR keeps its own')
BJ.readyFn({beamjoy={version='2.0.0'}})
assert(BJ.syncWeather({enabled=true,cloudCover=.4,fogDensity=.0002,tempNoon=28,tempDusk=22,tempMidnight=15,tempDawn=17}) and #BJ.calls==before+2,'BJR restart: sent again')
-- two syncs before BJR answers (API ready + map learnt at startup): sent once
local answer;local realCall=BJ.call
BJ.call=function(m,p,cb) BJ.calls[#BJ.calls+1]={method=m,params=p};answer=cb end
local n=#BJ.calls
assert(BJ.syncWeather({enabled=true,cloudCover=.9}) and not BJ.syncWeather({enabled=true,cloudCover=.9}) and #BJ.calls==n+1,'second sync before the answer is not sent')
answer(false,{message='busy'})
assert(BJ.syncWeather({enabled=true,cloudCover=.9}) and #BJ.calls==n+2,'refused: sent again next time')
BJ.call=realCall
os.execute('rm -rf '..tmp)
print('PASS: BJR API bridge: one event result, phase payload, racer-key grid, BJR penalties, menu rail and helper loading')
