local L=dofile('server/RacePrep/Licences.lua')
for i,b in ipairs(L.bars) do local d={};L.update(d,{races=b.races,safety=b.safety},b.skill,{},false);assert(d.licence==L.names[i]) end
local d={licence='Pro'};L.update(d,{races=100,safety=4},1000,{demotion='immediately'},true);assert(d.licence=='A','one step only')
d={licence='B'};local p={races=30,safety=2};L.update(d,p,1000,{races=3},true);assert(d.below==1)
L.update(d,p,1000,{races=3},false);assert(d.below==1,'unscored leaves counter')
L.update(d,{races=30,safety=3},1000,{races=3},false);assert(d.below==1,'unscored recovery does not reset')
L.update(d,{races=30,safety=3},1000,{races=3},true);assert(d.below==0)
for _=1,3 do L.update(d,p,1000,{races=3},true) end;assert(d.licence=='C')
d={licence='Pro'};for _=1,20 do L.update(d,{races=100,safety=0},1000,{demotion='never'},true) end;assert(d.licence=='Pro')
L.update(d,{races=100,safety=4.5},1000,{},true);assert(d.licence=='Pro','skill loss never demotes')
for _,hook in ipairs({'raceJoin','raceReady'}) do assert(L.refusal('B',{licence='C'}));assert(not L.refusal('B',{licence='B'})) end
local P=dofile('server/RacePrep/Persistence.lua');local disk={};local fail=false
local api={read=function(n) return P.copy(disk[n]) end,exists=function(n) return disk[n]~=nil end,copy=P.copy,
 write=function(n,v) if fail and n=='progression.json' then return false end;disk[n]=P.copy(v);return true end,settings=function() return {} end,log=function() end}
local m=dofile('server/RacePrep/Progression.lua').new(api)
fail=true;m.record({source='bjr-api',runID='a'},{{id='salted',name='Test',profile={races=5,safety=3},skill=2000}},true);assert(not m.driver('salted'))
fail=false;m.flush();assert(m.driver('salted').licence=='D');m.flush();assert(m.driver('salted').below==0)
disk['progression.json']='bad';local bad=dofile('server/RacePrep/Progression.lua').new(api);assert(bad.broken() and bad.refusal('D','salted'));assert(disk['progression.json']=='bad')
print('PASS: licence thresholds, all demotion modes, scored-only counter, skill loss, both entry hooks, retries and corrupt-state refusal')
