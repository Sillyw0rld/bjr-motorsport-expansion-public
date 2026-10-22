-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR plugin API bridge (2026-10-17): grid order through BJR's gridOrder hook,
-- results from BJR's RaceFinished event; our penalties layered on BJR's times
local A=dofile('server/RacePrep/BJRApi.lua')
-- RaceFinished as BJR 1.11's services/api.lua builds it
local d={sessionId=7,raceId=3,raceName='Imola',map='imola',laps=2,results={
 {position=1,id=1,name='Ana',vehicle='etk800',finished=true,disqualified=false,totalMs=125000,bestLapMs=61000,penaltyMs=5000,
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
H.cuts[7]={['1']={['1']=2}}
H.results(res,{trackLimits='penalty',cutPenaltyAfter=1,cutPenaltySeconds=3})
assert(a.total==128000 and a.penalty==3000,'one counted cut, +3 s on top of BJR total 125 s')
-- grid order answer: only racers in this lobby, BJR's order for the rest
local ans=A.gridAnswer({{playerID=3},{playerID=1},{playerID=9},{playerID=3}},{{id=1},{id=3},{id=4}})
assert(#ans.order==2 and ans.order[1]==3 and ans.order[2]==1,'listed racers present, deduplicated')
assert(next(A.gridAnswer(nil,{{id=1}}))==nil and next(A.gridAnswer({},{{id=1}}))==nil,'no order: BJR keeps its own')
-- start(): loads BJR's helper from BeamJoyServer/api; nil without it
local tmp=os.tmpname();os.remove(tmp);os.execute('mkdir -p '..tmp..'/BeamJoyServer/api '..tmp..'/RacePrep')
assert(A.start({path=tmp..'/Nope/RacePrep',log=print})==nil,'no API: old path')
local f=io.open(tmp..'/BeamJoyServer/api/BeamJoyAPI.lua','w')
f:write("local BJ={hooks={},events={},updates={}} function BJ.init(n) BJ.name=n end function BJ.onReady(fn) BJ.readyFn=fn end function BJ.hook(n,fn) BJ.hooks[n]=fn end function BJ.on(e,fn) BJ.events[e]=fn end "..
 "function BJ.page(p) BJ.pages=BJ.pages or {} BJ.pages[p.id]=p BJ.pageDef=BJ.pageDef or p end function BJ.updatePage(id,blocks,players) BJ.updates[#BJ.updates+1]={id=id,blocks=blocks,players=players} end "..
 "function BJ.onPageOpened(fn) BJ.opened=fn end function BJ.onPageAction(fn) BJ.action=fn end function BJ.call(m,p,cb) BJ.calls=BJ.calls or {};BJ.calls[#BJ.calls+1]={method=m,params=p};if cb then cb(true,{}) end end return BJ")
f:close()
local got,ready,opened
local BJ=A.start({path=tmp..'/RacePrep',log=function() end,gridOrder=function(raceID) assert(raceID==3) return {{playerID=2},{playerID=1}} end,
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
BJ.readyFn({beamjoy={version='1.11.0'}});assert(ready)
local o=BJ.hooks.gridOrder({session={raceId=3},racers={{id=1},{id=2}}})
assert(o.order[1]==2 and o.order[2]==1,'hook answers with our order')
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
print('PASS: BJR API bridge: results from RaceFinished (penalties layered), gridOrder hook, menu rail page, helper loading')
