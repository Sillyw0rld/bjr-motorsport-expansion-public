local B=dofile('server/RacePrep/ChallengeCatalogue.lua');local P=dofile('server/RacePrep/Persistence.lua');local C=dofile('server/RacePrep/Challenges.lua');local R=dofile('server/RacePrep/ProgressionRewards.lua')
local now=1793000000;local disk;local writes=0;local groups={};local race={id=1,name='Empty layout',loopable=true,startPositions={{pos={x=0,y=0,z=0}}},gates={{pos={x=0,y=0,z=0},dir={x=1,y=0,z=0}},{pos={x=100,y=0,z=0},dir={x=1,y=0,z=0}}}}
local preset={id='endurance',name='Endurance',offered=true}
local api={read=function()return disk end,exists=function()return disk~=nil end,write=function(s)disk=P.copy(s);writes=writes+1;return true end,copy=P.copy,now=function()return now end,level=function()return'map'end,settings=function()return{}end,race=function()return race end,races=function()return{race}end,rules=function()return{tyreWear='on'}end,preset=function()return preset end,presets=function()return{preset}end,presetRules=function()return{tyreWear='on'}end,hash=function(_,v)return v end,layout=function()return'layout'end,band=function(c)if c=='B'then return 501,600 end end,classes=function()return{'B'}end,groups=function()return groups end,blocked=function()return false end}
local b=B.new(api);local page=b.page({class='B'},'me');assert(page.total==7 and #page.items==7);assert(page.items[1].empty and #page.items[1].rows==0)
local g=assert(b.get(page.items[1].id));assert(g.type=='bestLap');assert(g.id=='layout:'..B.rulesKey(api.hash,g.rules)..':B','legacy lap key unchanged')
local picks=b.rotations();assert(#picks==3 and writes==1);local types={};for _,p in ipairs(picks)do assert(not types[p.board.type]);types[p.board.type]=true;assert(p.starts<=now and p.ends>now);assert(p.kind=='daily'and p.xp==100 or p.kind=='weekly'and p.xp==250)end
local again=b.rotations();assert(writes==1 and again[1].id==picks[1].id)
local dailyEnd=picks[1].ends;now=dailyEnd;local reset=b.rotations();assert(reset[1].id~=picks[1].id and reset[2].id==picks[2].id)
assert((picks[2].starts+259200)%604800==0,'Monday UTC')
now=picks[2].ends;local weekly=b.rotations();assert(weekly[2].id~=picks[2].id)
-- First score wins the empty published target exactly once.
local pick=weekly[1];pick.available=true;local board=pick.board;local score=C.metric(board.type,board.type=='consistency'and 0 or board.type=='cleanStreak'and 1 or board.type=='tyreSaver'and 2 or board.type=='speedTrap'and 50 or 10000);score.verified=true
local res={kind='rivals',verified=true,verification={version=1,method='beammp-server-crossings'},level='map',completedAt=now,recordContext=board,rows={{rivalDriver='me',verified=true,name='Me',class='B',best=score}}}
local state={drivers={}};assert(R.rival(state,res,nil,{rotations={pick}},api.blocked));assert(state.drivers.me.xp==100);assert(not R.rival(state,res,nil,{rotations={pick}},api.blocked));assert(state.drivers.me.xp==100)
res.completedAt=pick.ends;state={drivers={}};R.rival(state,res,nil,{rotations={pick}},api.blocked);assert(state.drivers.me.xp==0,'expired publication pays nothing')
-- A virtual board is startable before any file exists.
local F=dofile('tests/rivals_fixture.lua');local env=F.new();env.api.group=function(id)return id=='empty'and{raceID=1,class='B',layout='layout',rulesKey='rules',rules={},type='bestLap',options={},bests={}}end;env.ms=3000
assert(env.manager.start(1,{challenge='empty',practice=true,vehicle='1-0'}))
-- Fail closed on corrupt publication files and failed publication writes.
api.read=function()return {schema=99}end;assert(#B.new(api).rotations()==0)
api.read=function()end;api.exists=function()return false end;api.write=function()return false end;assert(#B.new(api).rotations()==0)
print('PASS: seven virtual empty boards, legacy identity, start before first result, frozen distinct rotations, UTC resets, once-only XP and damaged/write-failed publication safety')
