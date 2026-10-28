-- Reproducible payload benchmark: the same 30 drivers, 6 crews, 12 archived
-- seasons, and one current season are encoded with the old and new shapes.
local P=dofile('server/RacePrep/Persistence.lua')
local R=dofile('server/RacePrep/ProgressionRewards.lua')
local Progress=dofile('server/RacePrep/Progression.lua')
local C=dofile('server/RacePrep/Crews.lua')
local S=dofile('server/RacePrep/Seasons.lua')
local League=dofile('server/RacePrep/League.lua')
local disk={};local ids={};local now=S.civil(2026,10,27)
local api={copy=P.copy,read=function(n) return P.copy(disk[n]) end,exists=function(n) return disk[n]~=nil end,
 write=function(n,v) disk[n]=P.copy(v);return true end,settings=function() return {licences={},seasons={mode='monthly'}} end,log=function() end,blocked=function() return false end}
local progress=Progress.new(api)
local crews=C.new();local seasons=S.new()
local known=function() return true end
for i=1,30 do
 local id=string.format('salted-driver-%02d',i);ids[tostring(i)]=id
 progress.refresh(id,'Driver '..i,{races=50,finished=45,wins=5,podiums=15,safety=4.2,safetyRaces=45,kilometres=1000},3400)
 progress.change(function(s) local d=R.init(s.drivers[id]);d.eligible=true;d.xp=10000;R.unlock(d,'first_win');d.title='first_win' end)
 local leader=ids[tostring(math.floor((i-1)/5)*5+1)]
 if (i-1)%5==0 then assert(C.apply(crews,id,{action='create',name='Crew '..i,tag='C'..i,colour='#ff8a1f'},5,now,false,known))
 else assert(C.apply(crews,leader,{action='invite',driver=id},5,now,false,known));assert(C.apply(crews,id,{action='accept',crew=crews.members[leader]},5,now,false,known)) end
end
local rows={};for i=1,30 do rows[i]={id=ids[tostring(i)],name='Driver '..i,row={status='FIN',position=i,class='B'}} end
for season=1,13 do
 S.start(seasons,{mode='open'},now)
 S.race(seasons,{runID='race-'..season,completedAt=now+1},rows,crews,function() return false end)
 if season<=12 then S.close(seasons,crews,now+2,{}) end
end
disk['crews.json']=crews;disk['seasons.json']=seasons
local la={};for k,v in pairs(api) do la[k]=v end
la.now=function() return now end;la.drivers=function() return progress.data().drivers end;la.known=known;la.grant=function() return true end
local league=League.new(la)
local old={directory=progress.directory(),players={},boardMedals={},self=ids['1'],league=league.view(ids['1'])}
for pid,id in pairs(ids) do old.players[pid]=progress.view(id);old.players[pid].crew=league.crew(id) end
local new=progress.payload(1,ids,league.view(ids['1'],nil,false),{})
for _,entry in ipairs(new.directory) do assert(ids[entry.playerID]==entry.id,'cards resolve by player identity, not display name') end
assert(new.players['1'].achievements and new.players['1'].medals and new.players['1'].id)
for pid,p in pairs(new.players) do if pid~='1' then local n=0;for k in pairs(p) do assert(k=='letter' or k=='title' or k=='crewTag');n=n+1 end;assert(n==3) end end
assert(not new.league.history and not new.league.hallOfFame and #old.league.history==12)
assert(#league.view(ids['1'],1).hallOfFame==12,'on-demand history remains available')
-- Stable compact JSON, sorted object keys; identical encoder for both shapes.
local function encode(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"')..'"' end
 if type(v)~='table' then return tostring(v) end
 local out={};if #v>0 then for _,x in ipairs(v) do out[#out+1]=encode(x) end;return '['..table.concat(out,',')..']' end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
 for _,k in ipairs(keys) do out[#out+1]=encode(k)..':'..encode(v[k]) end;return '{'..table.concat(out,',')..'}'
end
local before,after=#encode(old),#encode(new);assert(after<before*.2)
local sends=0;local send=function(pid,event,wire) assert(event=='RacePrepProgress');sends=sends+1 end
assert(progress.send(1,new,encode,send));assert(not progress.send(1,progress.payload(1,ids,league.view(ids['1'],nil,false),{}),encode,send))
new.players['2'].title='Changed';assert(progress.send(1,new,encode,send));assert(progress.send(2,new,encode,send));progress.disconnect(1);assert(progress.send(1,new,encode,send));assert(sends==4)
print(string.format('PASS: payload 30 drivers / 6 crews / 12 finished seasons: before=%d bytes after=%d bytes reduction=%.1f%%; private own view, compact peers, on-demand archives and per-recipient change detection',before,after,(1-after/before)*100))
-- The periodic bridge must never include progress; dedicated hooks are cached
-- separately and the UI consumes them independently of the 0.5-second snapshot.
local function read(p) local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local bridge=read('client/lua/ge/extensions/raceprepBJR.lua')
assert(not bridge:find('progress=M.progress',1,true));assert(bridge:find("guihooks.trigger('RacePrepBJRProgress',p)",1,true))
assert(bridge:find("guihooks.trigger('RacePrepBJRLeague',p)",1,true))
local js=read('client/ui/modModules/raceprepBJR/raceprepBJR.js')
assert(not js:find('vm.progress=null',1,true),'periodic state must not erase an unchanged cached update')
assert(bridge:find("guihooks.trigger('RacePrepBJRProgress',{})",1,true),'server leave clears the independent cache')
assert(not js:find('state.progress',1,true) and js:find("$on('RacePrepBJRProgress'",1,true))
print('PASS: separate progress/history UI event transport, no periodic snapshot payload')
