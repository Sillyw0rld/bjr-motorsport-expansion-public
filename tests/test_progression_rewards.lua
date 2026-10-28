local R=dofile('server/RacePrep/ProgressionRewards.lua')
local P=dofile('server/RacePrep/Persistence.lua')
assert(R.medal(10200,10000)==3 and R.medal(10500,10000)==2 and R.medal(11000,10000)==1 and R.medal(11001,10000)==0)
assert(R.level(0)==1 and R.level(12599)==9 and R.level(12600)==10 and R.threshold(10)==12600)
local d=R.init({});assert(R.medalAward(d,'b',10900,10000));assert(d.xp==50)
R.medalAward(d,'b',10400,10000);assert(d.xp==100);R.medalAward(d,'b',10000,10000);assert(d.xp==200)
R.medalAward(d,'b',10900,10000);assert(d.xp==200 and d.medals.b.tier==3)
local s={drivers={d={name='Driver',profile={finished=100,wins=10,podiums=20,kilometres=5000},earnedLicences={D=true,C=true,B=true,A=true,Pro=true}}}}
for i=1,25 do
 local row={name='Driver',playerID=1,racerKey='r',status='FIN',position=1,class=({'A','B','C','D','S'})[(i-1)%5+1],total=10000,incidents={samples=5,maxGap=2,firstAt=0,lastAt=10,contacts=0}}
 local awards={};for _,id in ipairs({'clean','comeback','fastest'}) do awards[#awards+1]={id=id,winners={{racerKey='r'}}} end
 local res={source='bjr-api',runID='r'..i,phaseCount=3,rows={row,{position=2,status='DNF'}},awards=awards}
 assert(R.race(s,{result=res,rows={{id='d',name='Driver',profile=s.drivers.d.profile,row=row}},pole='r',startPole='r'}))
 assert(not R.race(s,{result=res,rows={}}),'race deduplication')
end
assert(s.drivers.d.xp==25*170,'100 finish +20 beaten +50 clean')
local before=s.drivers.d.xp
for _,phase in ipairs({'practice','qualifying','Practice','Qualifying'}) do assert(not R.race(s,{result={source='bjr-api',phase={name=phase}},rows={}})) end
assert(s.drivers.d.xp==before)
local res={kind='rivals',verified=true,verification={version=1,method='beammp-server-crossings'},runID='lap',level='map',weeklyID='w',recordContext={layout='l',rulesKey='r'},rows={{name='Driver',rivalDriver='d',class='B',model='car',verified=true,best={time=10000,verified=true}}}}
local weekly={id='w',level='map',layout='l',rulesKey='r',class='B',target={time=11000,verified=true}}
local blocked=function() return false end
assert(R.rival(s,res,10000,weekly,blocked));local xp=s.drivers.d.xp;R.rival(s,res,10000,weekly,blocked);assert(s.drivers.d.xp==xp)
for i=2,5 do res.recordContext.layout='l'..i;res.weeklyID='w'..i;weekly.id=res.weeklyID;weekly.layout=res.recordContext.layout;R.rival(s,res,10000,weekly,blocked) end
for i=1,5 do R.medalAward(s.drivers.d,'confirmed'..i,10000,10000) end
res.completedAt=100
assert(R.rival(s,res,nil,{rotations={{id='daily',kind='daily',xp=100,starts=0,ends=200,available=true,level='map',board={id='l5:r:B'}}}},blocked))
s.drivers.d.xp=R.threshold(50);R.finish(s.drivers.d)
for _,a in ipairs(R.catalogue) do if not a[1]:match('^season_') and a[1]~='crew_champion' then assert(s.drivers.d.achievements[a[1]],a[1]) end end
assert(R.pick(s.drivers.d,'licence_Pro'));s.drivers.d.licence='D';assert(R.title(s.drivers.d)=='Pro' and s.drivers.d.achievements.licence_Pro)
assert(not R.pick(s.drivers.d,'not-earned'))
s.drivers.other={eligible=true,achievements={}};s.drivers.spectator={eligible=false,achievements={}}
local rows=R.achievements(s,s.drivers.d);assert(rows[1].rarity==50 and rows[1].base==2,'rarity base excludes connections without finishes/laps')
local clean={drivers={}}
res.rows[1].verified=false;assert(not R.rival(clean,res,10000,weekly,blocked) and next(clean.drivers)==nil)
res.rows[1].verified=true;assert(not R.rival(clean,res,10000,weekly,function() return true end) and next(clean.drivers)==nil)
print('PASS: medal thresholds/difference XP, every 2.23 achievement, rarity base, titles, level curve, all XP sources, weekly/race deduplication and trusted-only scoring')
