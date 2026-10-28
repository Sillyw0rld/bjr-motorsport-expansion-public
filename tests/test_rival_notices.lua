local N=dofile('server/RacePrep/RivalNotices.lua');local P=dofile('server/RacePrep/Persistence.lua')
local disk,fail=nil,false;local blocked={};local sends,posts={},{};local enabled=false;local level='map';local groups={}
local api={read=function() return P.copy(disk) end,exists=function() return disk~=nil end,copy=P.copy,
 write=function(v) if fail then return false end;disk=P.copy(v);return true end,log=function() end,
 blocked=function(id,run) return blocked[id]==true or blocked[run]==true end,recordsEnabled=function() return enabled end,
 record=function(p) posts[#posts+1]=p end,send=function(id,p) sends[#sends+1]={id=id,p=p} end,
 level=function() return level end,groups=function() return groups end}
local m=N.new(api)
local function best(id,time,run) return {driver=id,name=id,time=time,runID=run or id,model='car',verified=true} end
local function lap(id,time,run) return {kind='rivals',verified=true,verification={version=1,method='beammp-server-crossings'},runID=run or id,level='map',raceName='Race',recordContext={layout='layout',rulesKey='rules'},rows={{rivalDriver=id,name=id,class='B',model='car',verified=true,best={time=time,verified=true}}}} end
local board='layout:rules:B'
local before={bests={x=best('x',15000),y=best('y',14000),z=best('z',16000)}}
assert(m.record(lap('x',13000,'one'),before))
assert(#m.view('y')==1 and #m.view('x')==0 and #m.view('z')==0,'only previously faster Y, never self')
assert(m.view('y')[1].text=='x beat your time at Race · B by 1.00 s')
assert(#posts==0,'off by default')
assert(not m.record(lap('x',13000,'one'),before),'duplicate source')
assert(not m.record(lap('x',15500,'slower'),before),'must improve personal board best')
-- X with no previous time can notify every slower eligible competitor.
local y={bests={y=best('y',14000),z=best('z',15000),unverified=best('unverified',17000)}};y.bests.unverified.verified=false
assert(m.record(lap('new',12000,'new'),y));assert(#m.view('z')==1 and #m.view('unverified')==0)
blocked.blocked=true;assert(not m.record(lap('blocked',10000,'blocked'),y));blocked.blocked=nil
blocked.removed=true;assert(not m.record(lap('x',10000,'removed'),y));blocked.removed=nil
local invalid=lap('invalid',10000);invalid.rows[1].verified=false;assert(not m.record(invalid,y))
-- Holder change only: improvements by the same holder never post.
enabled=true
assert(m.record(lap('y',13000,'same-holder'),{bests={y=best('y',14000)}}));assert(#posts==0)
assert(m.record(lap('new-holder',11000,'record'),y));assert(#posts==1 and posts[1].runID=='record')
assert(m.record(lap('seed',11000,'seed'),nil));assert(#posts==1,'an empty-board seed has no previous holder to replace')
-- Ghost resolves CURRENT best (including a newer run/model), not the caused lap.
groups[board]={bests={x=best('x',12500,'new-current')}}
local notice=m.view('y')[#m.view('y')]
assert(notice.enabled and notice.target.runID=='new-current')
level='other';assert(not m.view('y')[#m.view('y')].enabled and m.view('y')[#m.view('y')].reason=='Join map to race this ghost')
level='map';blocked['new-current']=true;assert(m.view('y')[#m.view('y')].reason=='This lap is no longer available');blocked['new-current']=nil
local target=m.target('y',notice.id);assert(target.runID=='new-current' and target.challenge==board and target.competitor=='x')
-- Failed checked writes are not exposed as saved; retry publishes once.
fail=true;local old=#m.view('y');assert(not m.record(lap('retry',10000,'retry'),y));assert(#m.view('y')==old)
fail=false;assert(m.retry());assert(#m.view('y')==old+1)
-- Newest-first cap and join delivery of five, independent of client muting.
for i=1,25 do m.record(lap('driver'..i,10000-i,'cap'..i),{bests={y=best('y',20000)}}) end
local view=m.view('y');assert(#view==20 and view[1].runID=='cap25' and view[20].runID=='cap6')
assert(m.deliver('y','join'));assert(#sends[#sends].p.items==5 and sends[#sends].p.items[1].runID=='cap25')
for i=1,5 do assert(disk.inboxes.y[i].seen) end;assert(not disk.inboxes.y[6].seen)
-- Moderation drops notices caused by that specific removed source lap.
blocked.cap25=true;assert(m.prune());assert(m.view('y')[1].runID=='cap24')
for _,n in ipairs(disk.inboxes.y) do assert(n.runID~='cap25') end
-- Corrupt and unparseable files, including false, are preserved without writes.
for _,bad in ipairs({false,'bad',{schema=1,serial=0,inboxes={x='bad'},runs={}}}) do
 disk=bad;local broken=N.new(api);assert(broken.broken());assert(not broken.record(lap('x',9000,'bad'),y));assert(not broken.prune());assert(disk==bad)
end
print('PASS: overtakes/no prior time, self/blocked/unverified/moderated exclusions, cap/newest order, five join notices/seen, current ghost/map/availability, holder-only Discord/default off, checked retries and corrupt preservation')

-- The existing webhook and checked queue carry record posts, with names only.
local Settings=dofile('server/RacePrep/MotorsportSettings.lua')
assert(Settings.DEFAULTS.discordRivalsRecords==false and not Settings.sanitize({},{}).discordRivalsRecords)
assert(Settings.sanitize({discordRivalsRecords=true},{}).discordRivalsRecords)
local D=dofile('server/RacePrep/DiscordAwards.lua');local files={}
files['/fixture/awards-discord.json']={enabled=true,webhook='https://discord.com/api/webhooks/123/token'}
local discord=D.new{path='/fixture',read=function(p) return P.copy(files[p]) end,exists=function(p) return files[p]~=nil end,
 write=function(p,v) files[p]=P.copy(v);return true end,copy=P.copy,log=function() end,token=function() return 'abcdef' end,now=function() return 1 end}
discord.record({runID='record-id',driver='PRIVATE-SALTED-ID',name='X @everyone',raceName='Race',class='B',time=12345})
discord.record({runID='record-id',name='X',raceName='Race',class='B',time=12345})
local queue=files['/fixture/awards-discord-queue.json'];assert(#queue.items==1)
local body=queue.items[1].body;assert(body.embeds[1].title=='Rivals record · Race')
assert(not body.embeds[1].fields[1].value:find('PRIVATE',1,true) and #body.allowed_mentions.parse==0)
print('PASS: empty-board seed silent, sanitized Discord default off, shared webhook/queue dedup and no salted identifiers in posts')
