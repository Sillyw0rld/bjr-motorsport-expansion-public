local P=dofile('server/RacePrep/Persistence.lua');local League=dofile('server/RacePrep/League.lua');local S=dofile('server/RacePrep/Seasons.lua');local C=dofile('server/RacePrep/Crews.lua')
local function fixture(mode)
 local e={now=S.civil(2026,10,27),disk={},fail=false,awards={}}
 local api={now=function() return e.now end,copy=P.copy,read=function(n) return P.copy(e.disk[n]) end,exists=function(n) return e.disk[n]~=nil end,
 write=function(n,v) if e.fail==n then return false end;e.disk[n]=P.copy(v);return true end,
 grant=function(list) for id,awards in pairs(list) do e.awards[id]=e.awards[id] or {};for a in pairs(awards) do e.awards[id][a]=true end end;return true end,
 settings=function() return {crews={maxMembers=4},seasons={mode=mode,customEnd='2026-11-15',repeating=true,minRaces=0,medals=true,weekly=true}} end,
 drivers=function() return {a={name='A'},b={name='B'},c={name='C'}} end,known=function() return true end,blocked=function() return false end,log=function() end}
 e.api=api;e.league=League.new(api);return e
end
for _,mode in ipairs({'weekly','monthly','custom','open'}) do
 local e=fixture(mode);local before=e.league.view('a').current
 if before.ends then e.now=before.ends+1;assert(e.league.tick());local after=e.league.view('a');assert(#after.history==1 and after.current.id~=before.id)
  if mode=='custom' then assert(after.current.ends-after.current.starts==before.ends-before.starts) end
 else e.now=e.now+100;assert(not e.league.action('a',{area='season',action='end'},false));assert(e.league.action('staff',{area='season',action='end'},true));assert(#e.league.view('a').history==1) end
end
local e=fixture('monthly');assert(e.league.action('a',{action='create',name='Alpha',tag='ALP',colour='#ff8a1f'},false))
local id=e.league.crew('a').id;assert(e.league.action('a',{action='invite',driver='b'},false));assert(e.league.action('b',{action='accept',crew=id},false))
local row={status='FIN',position=1,class='B',racerKey='r',playerID=1};local result={source='bjr-api',runID='one',completedAt=e.now+1,rows={row},awards={}}
local job={result=result,rows={{id='a',name='A',row=row}}};assert(e.league.score(job));assert(e.league.score(job));assert(e.league.view('a').current.tables.drivers[1].points==25)
e.fail='seasons.json';assert(not e.league.action('staff',{area='season',action='end'},true));assert(e.disk['league-pending.json'].crews,'journal survives partial publication')
e.fail=false;local recovered=League.new(e.api);local view=recovered.view('a');assert(#view.history==1 and #view.hallOfFame==1 and view.current.status=='active')
assert(e.awards.a.season_champion and e.awards.a.season_top3 and e.awards.a.crew_champion and e.awards.b.crew_champion,'awards include current champion crew members')
assert(recovered.action('staff',{area='season',action='rename',name='New name'},true));assert(recovered.view('a').current.name=='New name')
assert(recovered.action('staff',{area='season',action='extend',date='2027-01-01'},true));assert(recovered.view('a').current.ends==S.civil(2027,1,2))
for _,file in ipairs({'crews.json','seasons.json','league-pending.json'}) do local old=e.disk[file];e.disk[file]='corrupt';local bad=League.new(e.api);assert(bad.broken() and bad.view('a').error and e.disk[file]=='corrupt');e.disk[file]=old end
-- Best two medal/weekly contributors, not all members, and board/week dedup.
local c=C.new();local known=function() return true end
assert(C.apply(c,'a',{action='create',name='Crew',tag='CRW',colour='#ff8a1f'},4,e.now,false,known))
local crew=c.members.a
for _,d in ipairs({'b','c'}) do C.apply(c,'a',{action='invite',driver=d},4,e.now,false,known);assert(C.apply(c,d,{action='accept',crew=crew},4,e.now,false,known)) end
local s=S.new();S.start(s,{mode='open',medals=true,weekly=true,minRaces=0},e.now)
for i,d in ipairs({'a','b','c'}) do S.bonus(s,d,d,'medal','board',i,'B',11000-i*100,e.now+1,c);S.bonus(s,d,d,'weekly','week',1,'B',11000-i*100,e.now+1,c) end
assert(S.tables(s.current,c).crews[1].points==50,'best 10+20 medals and best two weekly 10+10')
local old=crew;C.apply(c,'a',{action='leave'},4,e.now,false,known);C.apply(c,'a',{action='create',name='Next',tag='NXT',colour='#ff8a1f'},4,e.now,false,known)
S.bonus(s,'a','a','medal','board',3,'B',9000,e.now+2,c)
local teams={};for _,r in ipairs(S.tables(s.current,c).crews) do teams[r.id]=r end
assert(teams[c.members.a].points==15,'new crew gets only the newly earned medal increase')
assert(teams[old].points==50,'old contributions do not move with driver')
print('PASS: all season modes/repetition, staff controls, journal recovery/awards, corrupt files, best-two bonus scoring, deduplication and crew-switch retention')
-- Queue capture prevents a driver switching crews before scoring from moving points.
local q=fixture('monthly');assert(q.league.action('a',{action='create',name='Before',tag='BEF',colour='#ff8a1f'},false))
local before=q.league.crew('a').id
local capture=q.league.snapshot({'a'})
q.now=q.now+1;assert(q.league.action('a',{action='leave'},false));assert(q.league.action('a',{action='create',name='After',tag='AFT',colour='#ff8a1f'},false))
local late=P.copy(job);late.crewSnapshot=capture;late.result.completedAt=q.now-1
assert(q.league.score(late));local ts=q.league.view('a').current.tables.crews;assert(ts[1].id==before and ts[1].points==25)
-- An expired season waits for pending source writes; historical event time is scored first.
local v=q.league.view('a').current;q.now=v.ends+1;q.api.canClose=function() return false end
assert(q.league.tick() and #q.league.view('a').history==0)
late.result.runID='late';late.result.completedAt=v.ends-1;assert(q.league.score(late))
q.api.canClose=function() return true end;assert(q.league.tick());assert(q.league.view('a').history[1].tables.crews[1].points==50)
-- Repeat off ends without a successor.
local f=fixture('weekly');local config=f.api.settings();config.seasons.repeating=false;f.api.settings=function() return config end
f.now=f.league.view('a').current.ends+1;f.league.tick();assert(f.league.view('a').current.status=='ended')
-- Non-table corrupt roots remain untouched, including JSON false.
for _,value in ipairs({false,12}) do f.disk['crews.json']=value;local corrupt=League.new(f.api);assert(corrupt.broken() and f.disk['crews.json']==value) end
print('PASS: queued membership snapshot, delayed rollover, repeat off and non-table corruption')
