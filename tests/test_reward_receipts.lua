local P=dofile('server/RacePrep/Persistence.lua');local R=dofile('server/RacePrep/ProgressionRewards.lua');local Progress=dofile('server/RacePrep/Progression.lua')
local disk={},{};local sent={};local fail=false;local leagueReady=false;local online={a=true}
local api={copy=P.copy,read=function(n) return P.copy(disk[n]) end,exists=function(n) return disk[n]~=nil end,
 write=function(n,v) if fail and n=='progression.json' then return false end;disk[n]=P.copy(v);return true end,
 settings=function() return {licences={demotion='immediately'}} end,blocked=function() return false end,log=function() end,
 reward=function(id,r) if online[id] then sent[#sent+1]={id=id,reward=r} end end,event=function() return leagueReady end}
local m=Progress.new(api)
m.change(function(s) s.drivers.a=R.init({xp=R.threshold(2)-50,licence='Rookie',profile={}}) end)
local row={status='FIN',position=1,racerKey='a',class='B'}
local res={source='bjr-api',runID='one',raceName='Track',rows={row,{position=2,status='FIN'}},awards={{id='clean',winners={{racerKey='a'}}}}}
local rows={{id='a',name='A',profile={races=5,finished=5,safety=3},skill=2000,row=row},{id='offline',name='Offline',profile={},skill=1000,row={status='DNF'}}}
fail=true;m.record(res,rows,true);assert(#sent==0)
fail=false;m.flush();assert(#sent==1 and sent[1].id=='a')
local receipt=sent[1].reward;local sum=0;for _,line in ipairs(receipt.lines) do sum=sum+line.xp end
assert(sum==170 and receipt.total==170 and receipt.after.xp-receipt.before.xp==sum)
assert(receipt.after.level>receipt.before.level and receipt.licence.before=='Rookie' and receipt.licence.after=='D')
local names={};for _,a in ipairs(receipt.achievements) do names[a.id]=true;assert(type(a.rarity)=='number' and a.name) end
assert(names.licence_D and names.clean_first)
m.flush();assert(#sent==1,'league retry must not resend')
m=Progress.new(api);m.flush();assert(#sent==1,'restart retry must not resend')
leagueReady=true;m.flush();assert(not m.pending() and #sent==1)
for _,phase in ipairs({'Practice','Qualifying'}) do local r=P.copy(res);r.runID=phase;r.phase={name=phase};assert(not m.record(r,rows,true)) end
assert(#sent==1)
local r=P.copy(res);r.runID='demote';rows[1].profile.safety=0;m.record(r,rows,true)
assert(sent[2].reward.licence.before=='D' and sent[2].reward.licence.after=='Rookie')
local before=#sent;m.backfill({profiles={drivers={}},skills={},results={},score=function() return 1000 end},function(x) return x end);assert(#sent==before)
-- Re-judging a provisional gold to bronze produces a bronze confirmation notice.
local groups={board={class='B',raceName='Track',bests={a={driver='a',name='A',time=10900,verified=true}}}}
m.medals(groups);groups.board.bests.b={driver='b',name='B',time=10000,verified=true};m.medals(groups)
local bronze=false;for _,v in ipairs(sent) do if v.reward.text=='Medal confirmed: Bronze' then bronze=true end end;assert(bronze)
print('PASS: exact XP receipt, level/licence changes, achievements/rarity, offline drop, write/restart retry dedup, phase/backfill exclusion and re-judged bronze notice')
