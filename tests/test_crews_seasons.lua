local C=dofile('server/RacePrep/Crews.lua');local S=dofile('server/RacePrep/Seasons.lua')
local c=C.new();local known=function() return true end
local function action(id,p,staff) return C.apply(c,id,p,4,100,staff,known) end
assert(action('a',{action='create',name='Alpha',tag='ALP',colour='#ff8a1f'}));local crew=c.members.a
for _,id in ipairs({'b','c','d'}) do assert(action('a',{action='invite',crew=crew,driver=id}));assert(action(id,{action='accept',crew=crew})) end
assert(not action('a',{action='invite',crew=crew,driver='e'}),'size cap')
assert(not action('b',{action='create',name='Other',tag='OTH',colour='#ff8a1f'}),'one crew per driver')
assert(action('a',{action='handover',driver='b'}));assert(c.crews[crew].leader=='b')
assert(action('b',{action='leave'}));assert(c.crews[crew].leader=='a','oldest member takes over')
assert(action('e',{action='request',crew=crew}));assert(action('a',{action='approve',crew=crew,driver='e'}))
assert(not action('e',{action='rename',crew=crew,name='No'}));assert(action('staff',{action='rename',crew=crew,name='Renamed'},true));assert(c.crews[crew].name=='Renamed')
assert(C.valid(c));assert(action('staff',{action='remove',crew=crew},true));assert(not c.members.a and not next(c.crews))
assert(action('a',{action='create',name='Solo',tag='SOL',colour='#ff8a1f'}));assert(action('a',{action='leave'}));assert(next(c.crews)==nil)
-- Calendar periods ignore the host timezone, including leap dates/year changes.
assert(S.civil(1970,1,1)==0);assert(S.date('2028-02-29')==S.civil(2028,3,1));assert(not S.date('2027-02-29'))
local now=S.civil(2026,10,27)+3600
for _,mode in ipairs({'weekly','monthly','custom','open'}) do
 local st=S.new();assert(S.start(st,{mode=mode,customEnd='2026-11-15'},now))
 if mode=='weekly' then assert(st.current.starts==S.civil(2026,10,26) and st.current.ends==S.civil(2026,11,2))
 elseif mode=='monthly' then assert(st.current.starts==S.civil(2026,10,1) and st.current.ends==S.civil(2026,11,1))
 elseif mode=='custom' then assert(st.current.ends==S.civil(2026,11,16)) else assert(st.current.ends==nil) end
 local awards={};assert(S.close(st,C.new(),now+100,awards));assert(#st.history==1 and #st.hallOfFame==1)
end
-- Race scoring: crew best two, retained old-crew points, drop worst, class tables.
c=C.new();local function join(id) assert(C.apply(c,id,{action='accept',crew=c.members.a},4,100,false,known)) end
assert(C.apply(c,'a',{action='create',name='Alpha',tag='ALP',colour='#ff8a1f'},4,100,false,known));crew=c.members.a
for _,id in ipairs({'b','c'}) do assert(C.apply(c,'a',{action='invite',driver=id},4,100,false,known));join(id) end
local st=S.new();assert(S.start(st,{mode='monthly',minRaces=1,medals=true,weekly=true},now))
local function race(key,position,at)
 local rows={};local res={source='bjr-api',runID=key,completedAt=at or now+10,rows={}}
 for i,id in ipairs({'a','b','c'}) do local row={status='FIN',position=(position or {})[i] or i,class='B'};rows[#rows+1]={id=id,name=id,row=row};res.rows[#res.rows+1]=row end
 assert(S.race(st,res,rows,c,function() return true end));assert(not S.race(st,res,rows,c,function() return true end))
end
race('one');local tables=S.tables(st.current,c)
assert(tables.drivers[1].points==30 and tables.crews[1].points==53,'25+5 and best two (25+5)+(18+5)')
assert(C.apply(c,'a',{action='leave'},4,100,false,known));local old=crew
assert(C.apply(c,'a',{action='create',name='Beta',tag='BET',colour='#ff8a1f'},4,100,false,known));local new=c.members.a
race('two');tables=S.tables(st.current,c);local by={};for _,r in ipairs(tables.crews) do by[r.id]=r end
assert(by[old].points==53+23+20 and by[new].points==30,'earned race points remain with old crew')
for i,id in ipairs({'b','c','x'}) do assert(S.bonus(st,id,id,'medal','board',i,'B',11000-i*100,now+20,c)) end
assert(not S.bonus(st,'b','b','medal','board',1,'B',10900,now+30,c),'per-board dedup')
assert(S.bonus(st,'b','b','weekly','week',1,'B',10000,now+30,c));assert(not S.bonus(st,'b','b','weekly','week',1,'B',10000,now+40,c))
st.current.settings.dropWorst=1;st.current.settings.minRaces=3;st.current.settings.perClass=true
tables=S.tables(st.current,c);assert(not tables.drivers[1].ranked and tables.drivers[1].position==nil and tables.drivers[1].class=='B')
st.current.settings.minRaces=1;local awards={};S.close(st,c,now+100,awards)
assert(#st.history[1].tables.drivers>0 and #st.history[1].tables.crews>0)
assert(#st.hallOfFame[1].drivers>0 and #st.hallOfFame[1].crews>0)
assert(next(awards)~=nil);assert(S.valid(st))
print('PASS: crews create/invite/accept/request/size/leave/handover/staff/one-crew, calendar modes, scoring, retained contributions, bonuses, drop/minimum/class tables and both history/Hall views')
-- Per-class points count only class finishers; official rows stay unchanged.
do
 local P=dofile('server/RacePrep/Persistence.lua')
 local rows={
  {id='a1',row={class='A',position=1,status='FIN'}},
  {id='b_dnf',row={class='B',position=2,status='DNF'}},
  {id='b_dsq',row={class='B',position=3,status='FIN',disqualified=true}},
  {id='a2',row={class='A',position=4,status='FIN'}},
  {id='b1',row={class='B',position=5,status='FIN'}},
  {id='b2',row={class='B',position=6,status='FIN'}}}
 local original=P.copy(rows);local crews={members={a1='c',a2='c',b1='c',b2='c',b_dnf='c',b_dsq='c'},crews={c={name='Crew',tag='CRW'}}}
 for _,perClass in ipairs({true,false}) do
  local season=S.new();S.start(season,{mode='open',perClass=perClass,clean=false},now)
  assert(S.race(season,{runID='mixed',completedAt=now+1},rows,crews,function() return false end))
  local scores={};for _,e in ipairs(season.current.entries) do scores[e.driver]=e end
  assert(scores.b_dnf.points==0 and scores.b_dsq.points==0)
  assert(scores.a1.points==25)
  if perClass then assert(scores.a2.points==18 and scores.b1.points==25 and scores.b2.points==18 and scores.b1.win)
  else assert(scores.a2.points==12 and scores.b1.points==10 and scores.b2.points==8 and not scores.b1.win) end
  local t=S.tables(season.current,crews)
  if perClass then assert(#t.crews==2 and t.crews[1].points==43 and t.crews[2].points==43) else assert(t.crews[1].points==37) end
 end
 for i,r in ipairs(rows) do assert(r.row.position==original[i].row.position and r.row.status==original[i].row.status) end
end
print('PASS: mixed-class finisher positions, class wins/crew scores, overall positions and unchanged official rows')

-- An official finisher without a progression profile still occupies a class place.
do
 local season=S.new();S.start(season,{mode='open',perClass=true,clean=false},now)
 local official={{status='FIN',position=1,class='B'},{status='FIN',position=2,class='B'}}
 assert(S.race(season,{runID='unknown-profile',completedAt=now+1,rows=official},{{id='known',name='Known',row=official[2]}},C.new(),function() return false end))
 assert(season.current.entries[1].points==18 and not season.current.entries[1].win)
end
