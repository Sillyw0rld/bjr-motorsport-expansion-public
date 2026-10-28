local R=dofile('server/RacePrep/ProgressionRewards.lua')
local P=dofile('server/RacePrep/Persistence.lua')
local Progress=dofile('server/RacePrep/Progression.lua')
local League=dofile('server/RacePrep/League.lua')
local Backfill=dofile('server/RacePrep/ProgressionBackfill.lua')
local S=dofile('server/RacePrep/Seasons.lua')
local now=S.civil(2026,10,27);local disk={};local blocked={};local fail;local league
local api={now=function() return now end,read=function(n) return P.copy(disk[n]) end,exists=function(n) return disk[n]~=nil end,copy=P.copy,
 write=function(n,v) if fail==n then return false end;disk[n]=P.copy(v);return true end,
 settings=function() return {seasons={mode='monthly',medals=true,minRaces=0},licences={}} end,
 blocked=function(id) return blocked[id]==true end,log=function() end,deferEvents=true,
 snapshot=function(_,res) local ids={};for _,r in ipairs(res.rows) do ids[#ids+1]=r.rivalDriver end;return league.snapshot(ids) end,
 event=function(job) return league.score(job) end}
local progress=Progress.new(api)
local la={};for k,v in pairs(api) do la[k]=v end
la.drivers=function() return progress.data().drivers end;la.known=function() return true end
la.grant=function() return true end;league=League.new(la)
local a={driver='a',name='A',runID='a1',time=10000,model='car',verified=true}
local b={driver='b',name='B',runID='b1',time=10400,model='car',verified=true}
local groups={['layout:rules:B']={raceName='Track',class='B',bests={a=a}}}
local key='layout:rules:B'
assert(progress.medals(groups));local d=progress.driver('a')
assert(d.medals[key].tier==3 and d.medals[key].provisional and d.xp==0)
assert(not d.achievements.gold_first and not d.achievements.gold_5)
assert(#league.view('a').current.tables.drivers==0,'no provisional season points')
assert(not progress.medals(groups) and progress.driver('a').xp==0,'no repeated provisional payments')
-- Another lap by the same competitor does not confirm the board.
groups[key].bests.another=P.copy(a);groups[key].bests.another.runID='a2'
progress.medals(groups);assert(progress.driver('a').medals[key].provisional)
groups[key].bests.another=nil
-- A blocked second competitor cannot confirm.
groups[key].bests.b=b;b.verified=false;progress.medals(groups);assert(progress.driver('a').medals[key].provisional);b.verified=true;blocked.b=true;progress.medals(groups);assert(progress.driver('a').medals[key].provisional)
blocked.b=nil
-- Confirm in the following season, without any new lap from the first driver.
local first=league.view('a').current.id;now=league.view('a').current.ends+1;league.tick()
assert(league.view('a').current.id~=first)
fail='seasons.json';assert(progress.medals(groups));assert(progress.driver('a').xp==200 and not progress.driver('a').medals[key].provisional)
assert(progress.pending(),'confirmation retained until points journal succeeds')
fail=nil;progress=Progress.new(api);assert(progress.pending());assert(progress.flush());assert(not progress.pending())
local rows=league.view('a').current.tables.drivers;local scores={};for _,r in ipairs(rows) do scores[r.id]=r.points end
assert(scores.a==20 and scores.b==10,'confirmation-time season and correct tiers')
assert(#league.view('a').history[1].tables.drivers==0)
assert(progress.driver('a').achievements.gold_first and progress.driver('b').xp==100)
assert(not progress.medals(groups));assert(progress.driver('a').xp==200)
-- Upgrading a confirmed silver pays only the increase, for both XP and points.
b.time=10100;assert(progress.medals(groups));assert(progress.driver('b').xp==200)
local scores2={};for _,r in ipairs(league.view('a').current.tables.drivers) do scores2[r.id]=r.points end
assert(scores2.b==20,'silver 10 plus gold increase 10, not another 20')
-- Moderation cannot revoke already confirmed rewards.
blocked.b=true;progress.medals(groups);assert(not progress.driver('a').medals[key].provisional and progress.driver('a').xp==200)
-- Difference-only upgrade, and five provisional golds do not unlock gold_5.
local lone={};for i=1,5 do lone['p'..i]={bests={a=a},class='B'} end
progress.medals(lone);assert(not progress.driver('a').achievements.gold_5)
for _,g in pairs(lone) do g.bests.b=b end;blocked.b=nil;progress.medals(lone);assert(progress.driver('a').achievements.gold_5)
-- A new season never repays an unchanged confirmed medal.
now=league.view('a').current.ends+1;league.tick();progress.medals(groups)
assert(#league.view('a').current.tables.drivers==0)
-- The live check and backfill use the same board calculation (including blocked competitors).
local function res(r) return {kind='rivals',verified=true,verification={version=1,method='beammp-server-crossings'},runID=r.runID,raceName='Track',recordContext={layout='layout',rulesKey='rules'},rows={{rivalDriver=r.driver,name=r.name,class='B',model=r.model,verified=true,best={verified=true,time=r.time}}}} end
for _,confirm in ipairs({false,true}) do
 local input={profiles={drivers={}},skills={},score=function() return 1000 end,results={res(a)}}
 if confirm then input.results[#input.results+1]=res(b) end
 local state={drivers={}};assert(Backfill.run(state,input,function(x) return x end,{licences={}},function() return false end))
 local live={drivers={}};local g=P.copy(groups);g[key].bests.b=confirm and b or nil;R.boards(live,g,function() return false end)
 assert(state.drivers.a.xp==live.drivers.a.xp and state.drivers.a.medals[key].provisional==live.drivers.a.medals[key].provisional)
 assert(state.drivers.a.achievements.gold_first==live.drivers.a.achievements.gold_first)
 assert(not Backfill.run(state,input,function(x) return x end,{},function() return false end))
end
-- A lone first lap is provisional gold; a much faster second driver must not confirm it as gold.
do
 local s={drivers={}};local no=function() return false end
 local g={board={raceName='T',class='B',bests={x={driver='x',name='X',time=60000,verified=true}}}}
 R.boards(s,g,no);assert(s.drivers.x.medals.board.tier==3 and s.drivers.x.medals.board.provisional and s.drivers.x.xp==0)
 g.board.bests.y={driver='y',name='Y',time=55500,verified=true} -- X is 8.1 % off: bronze
 local _,awards=R.boards(s,g,no);local m=s.drivers.x.medals.board
 assert(m.tier==1 and not m.provisional and s.drivers.x.xp==50 and m.best==55500,'re-judged at confirmation')
 assert(not s.drivers.x.achievements.gold_first and s.drivers.y.achievements.gold_first)
 for _,a in ipairs(awards) do if a.id=='x' then assert(a.tier==1) end end
 -- more than 10 % off: the provisional medal is removed, nothing paid
 local s2={drivers={}};local g2={board={raceName='T',class='B',bests={x={driver='x',name='X',time=60000,verified=true}}}}
 R.boards(s2,g2,no);g2.board.bests.y={driver='y',name='Y',time=50000,verified=true}
 R.boards(s2,g2,no);assert(s2.drivers.x.medals.board==nil and s2.drivers.x.xp==0,'removed when out of range')
 -- a confirmed, paid medal never drops
 g.board.bests.z={driver='z',name='Z',time=50000,verified=true};R.boards(s,g,no)
 assert(s.drivers.x.medals.board.tier==1 and s.drivers.x.xp==50 and s.drivers.y.medals.board.tier==3)
end
print('PASS: provisional medals, distinct/unblocked competitors, 1-to-2 confirmation without a lap, retry/dedup, confirmation season, retained confirmation, gold achievements and backfill agreement')
