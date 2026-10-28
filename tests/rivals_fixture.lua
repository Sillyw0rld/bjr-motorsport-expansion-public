-- Offline API-shape fixture, isolated from the live server and AuthKey.
local V=dofile('server/RacePrep/RivalsVerification.lua')
local Sessions=dofile('server/RacePrep/RivalsSessions.lua')
local R=dofile('server/RacePrep/Rivals.lua')
local F={}
function F.race()
 return {gates={{pos={x=0,y=0,z=0},dir={x=1,y=0,z=0},width=20},
  {pos={x=60,y=0,z=0},dir={x=1,y=0,z=0},width=20},
  {pos={x=120,y=0,z=0},dir={x=1,y=0,z=0},width=20}}}
end
function F.samples()
 local rows={}
 for line in io.lines('tests/fixtures/rivals/straight.csv') do
  local t,x,y,z=line:match('^(%d+),([^,]+),([^,]+),([^,]+)$')
  if t then rows[#rows+1]={at=tonumber(t),raw={pos={tonumber(x),tonumber(y),tonumber(z)},rot={0,0,0,1},vel={10,0,0},rvel={0,0,0},tim=tonumber(t)/1000,ping=.05}} end
 end
 return rows
end
function F.new(count)
 local env={ms=0,epoch=1793000000,messages={},saved={},positions={},config='build-a',rated='rated-key',blocked=false,calls=0}
 local car={key='rated-key',class='B',pi=550,model='car',car='Car',vehicle='1-0',speedCeiling=100,parts={['/main']='car',['/main/engine']='engine'}}
 local race=F.race();local group={raceID=1,raceName='Fixture',class='B',layout='layout',rulesKey='rules',bests={}}
 local api={now=function() return env.epoch+env.ms/1000 end,clock=function() return env.ms end,
  token=function() return 'random-fixture' end,level=function() return 'fixture' end,
  driver=function(pid) return 'driver-'..pid end,blocked=function() return env.blocked end,
  car=function(pid) local c={};for k,v in pairs(car) do c[k]=v end;c.vehicle=pid..'-0';c.key=env.rated;return c end,
  config=function() return env.config end,position=function(pid,sid) env.calls=env.calls+1;assert(sid==pid..'-0');return env.positions[pid],'' end,
  inRace=function() return false end,groups=function() return {layout=group} end,race=function() return race end,rules=function() return {} end,
  layout=function() return 'layout' end,rulesKey=function() return 'rules' end,build=function(k) return 'hash:'..k end,
  trace=function() end,name=function() return 'Fixture' end,nameOf=function(pid) return 'Driver '..pid end,
  send=function(pid,event,p) assert(event=='RacePrepRivalsSession');env.messages[pid]=p end,
  save=function(res) env.saved[#env.saved+1]=res;return true end}
 env.api=api;env.manager=Sessions.new(api);env.car=car;env.race=race
 for pid=1,count or 1 do assert(env.manager.start(pid,{challenge='layout',practice=true,vehicle=pid..'-0'})) end
 function env.feed(sample)
  env.ms=sample.at
  for pid=1,count or 1 do env.positions[pid]=sample.raw end
  env.manager.poll()
 end
 function env.post(pid,time,changes)
  local message=env.messages[pid]
  local p={action='lap',id=env.id or message.id,lapToken=message.lapToken or env.token,time=time or 12000,valid=true,cuts=0,trace={{fake=true}}}
  for k,v in pairs(changes or {}) do p[k]=v end
  env.manager.lap(pid,p);return p
 end
 env.id=env.messages[1].id;env.token=env.messages[1].lapToken
 return env
end
F.Verification=V;F.Records=R
return F
