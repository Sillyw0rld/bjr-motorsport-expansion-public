local A=dofile('server/RacePrep/AutoRating.lua');local P=dofile('server/RacePrep/Persistence.lua')
assert(A.config('/vehicles/covet/13s_M.pc')=='13s_M')
assert(A.rated({e={model='covet',config='13s_M',pi=500}},{model='covet',config='13s_M'},'e'));assert(not A.rated({e={model='covet',config='race',pi=600}},{model='covet',config='13s_M'},'e'))
assert(not A.rated({upgrade={model='covet',config='13s_M',pi=700}},{model='covet',config='13s_M'}),'an upgraded build of the named config does not satisfy its factory identity')
local clients={{pid=1,ready=true,free=true,idle=30,staff=false},{pid=2,ready=true,free=true,idle=30,staff=true}}
assert(A.choose(clients,false).pid==2);clients[2].free=false;assert(not A.choose(clients,false));assert(A.choose(clients,true).pid==1)
clients[1].rivals=true;assert(not A.choose(clients,true));clients[1].rivals=false;clients[1].idle=29;assert(not A.choose(clients,true));clients[1].idle=30
local now=100000;local disk;local messages={};local rated=false;clients[2].free=true
local api={now=function()return now end,read=function()return disk end,exists=function()return disk~=nil end,write=function(s)disk=P.copy(s);return true end,copy=P.copy,cars=function()return{{model='covet',name='Covet',config='13s_M'}}end,rated=function()return rated end,clients=function()return clients end,send=function(pid,p)messages[#messages+1]=p end,token=function()return'job-'..now end,localOnly=false}
local queue=A.new(api);queue.tick();assert(queue.view().items[1].status=='rating');assert(disk.cars.covet.attempts==1)
assert(not queue.message(1,{id=messages[1].id,action='done'}),'foreign client ignored')
assert(not queue.message(2,{id=messages[1].id,action='done'}),'unvalidated done cannot complete')
clients[2].idle=0;queue.tick();assert(queue.view().items[1].status=='pending'and messages[#messages].action=='stop')
clients[2].idle=30
for n=2,3 do queue.tick();assert(disk.cars.covet.attempts==n);now=now+31;queue.tick()end
assert(queue.view().items[1].status=='failed');queue=A.new(api);queue.tick();assert(queue.view().items[1].status=='failed','cap survives restart')
now=now+86400;queue.tick();assert(queue.view().items[1].status=='rating');rated=true;queue.tick();assert(queue.view().rated==1 and not queue.view().running)
api.read=function()return {schema=99}end;assert(A.new(api).view().error)
-- 2.31.1: the synced worker car never appears while anyone races or runs Rivals
local others={{pid=1,ready=true,free=false,idle=0,staff=false},{pid=2,ready=true,free=true,idle=30,staff=true}}
assert(not A.choose(others,false),'another player racing blocks a synced job')
others[1].free=true;others[1].rivals=true;assert(not A.choose(others,false),'another player in Rivals blocks a synced job')
others[1].rivals=false;assert(A.choose(others,false).pid==2)
api.read=function()return disk end;rated=false;now=now+86400;clients=others;api.clients=function()return clients end;queue=A.new(api);queue.tick();assert(queue.view().items[1].status=='rating')
others[1].free=false;queue.tick();assert(queue.view().items[1].status~='rating'and messages[#messages].action=='stop'and disk.cars.covet.reason:find('race or Rivals'),'running job stops when someone starts racing')
local W=dofile('client/lua/ge/extensions/raceprep/autoRatingWorker.lua');local spawned,deleted,entered,active=0,0,0,false;local current={id=7,speed=0};local packets={}
local worker=W.new{current=function()return current end,free=function()return not active end,spawn=function()spawned=spawned+1;return 8 end,delete=function(id)assert(id==8);deleted=deleted+1 end,enter=function(id)assert(id==7);entered=entered+1 end,freeCamera=function()end,rated=function()return false end,send=function(p)packets[#packets+1]=p end}
worker.receive{action='start',id='early',index=1,total=1};assert(spawned==0)
worker.update(31);worker.receive{action='start',id='good',index=1,total=1};assert(spawned==1 and entered==1 and worker.view().active)
current.speed=1;worker.update(.01);assert(deleted==1 and not worker.view().active and packets[#packets].action=='abort','driving aborts next frame')
current.speed=0;worker.update(31);worker.receive{action='start',id='race',index=1,total=1};active=true;worker.update(.01);assert(deleted==2 and not worker.view().active,'race abort')
local source=assert(io.open('client/lua/ge/extensions/raceprepRatings.lua')):read('*a');assert(source:find('Not rated yet',1,true)and source:find('Rating…',1,true));local server=assert(io.open('server/RacePrep/RacePrep.lua')):read('*a');assert(server:find('localOnly=false',1,true),'synced fallback is staff only')
print('PASS: default-config missing detection, staff/idle/race selection, aborts, validation-only completion, persistent 3/day cap, server-wide race/Rivals hold, selector states, corrupt safety and client disposal')
