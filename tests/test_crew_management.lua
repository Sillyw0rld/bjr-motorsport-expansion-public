local C=dofile('server/RacePrep/Crews.lua')
local M=dofile('server/RacePrep/MotorsportSettings.lua')
local P=dofile('server/RacePrep/Persistence.lua')
local settings=M.sanitize({});assert(settings.permissions.manageCrews=='mod')
assert(not M.allowed(settings,'manageCrews','player'));assert(M.allowed(settings,'manageCrews','mod'))
assert(M.allowed(M.sanitize({permissions={manageCrews='admin'}}),'manageCrews','admin'))
local s=C.new();local function act(who,p,staff) return C.apply(s,who,p,4,100,staff,function() return true end) end
for _,colour in ipairs(C.COLOURS) do assert(C.colour(colour)) end
for _,colour in ipairs({'#ffffff','#ff881a','red','',false}) do assert(not C.colour(colour));assert(not act('a',{action='create',name='Alpha',tag='AA',colour=colour})) end
assert(act('a',{action='create',name='Alpha',tag='AA',colour=C.COLOURS[1]}));local id=s.members.a
assert(act('a',{action='invite',driver='b'}));assert(act('b',{action='accept',crew=id}))
local cases={rename={name='Renamed'},retag={tag='NEW'},recolour={colour=C.COLOURS[2]},makeLeader={driver='b'},removeMember={driver='b'},remove={}}
for action,extra in pairs(cases) do
 local before=P.copy(s);local p=P.copy(extra);p.action=action;p.crew=id
 assert(not act('a',p,false),'even a leader needs staff permission for '..action)
 assert(s.crews[id].name==before.crews[id].name and s.crews[id].members.b,'refusal must preserve state')
 assert(act('staff',p,true),'staff action '..action);s=before
end
assert(not act('staff',{action='recolour',crew=id,colour='#123456'},true))
assert(act('c',{action='request',crew=id}));assert(act('a',{action='declineRequest',crew=id,driver='c'}));assert(not s.crews[id].requests.c)
assert(act('staff',{action='removeMember',crew=id,driver='a'},true));assert(s.crews[id].leader=='b');assert(not s.members.a)
assert(C.valid(s))
local function source(path) local f=assert(io.open(path));local v=f:read('*a');f:close();return v end
local main=source('server/RacePrep/RacePrep.lua')
assert(main:find("features.league.action(id,p,allowedTo(pid,'manageCrews'))",1,true))
assert(main:find("MP.RegisterEvent('onPlayerJoin','RacePrepProgressJoin')",1,true))
assert(main:find("MP.RegisterEvent('RacePrepGetProgress','RacePrepGetProgress')",1,true))
local ge=source('client/lua/ge/extensions/raceprepBJR.lua');assert(ge:find("H.send('RacePrepSetMotorsport',p)",1,true))
print('PASS: nine swatches, all six staff actions require Manage crews, leader handover, decline requests, join/menu progress and full settings transport')

local changes={scope='crews',crews={maxMembers=8},seasons={crewScorers=3,mode='open'},permissions={rules='everyone'},discordRivalsRecords=true}
local scoped=assert(M.patch(settings,changes,nil,false,true))
assert(scoped.crews.maxMembers==8 and scoped.seasons.crewScorers==3)
assert(scoped.permissions.rules=='admin' and scoped.seasons.mode==settings.seasons.mode and not scoped.discordRivalsRecords)
local general=P.copy(changes);general.scope=nil
local rulesOnly=assert(M.patch(settings,general,nil,true,false))
assert(not M.patch(settings,changes,nil,true,false))
local adminScoped=assert(M.patch(settings,changes,nil,true,true));assert(adminScoped.permissions.rules=='admin' and not adminScoped.discordRivalsRecords)
assert(rulesOnly.crews.maxMembers==4 and rulesOnly.seasons.crewScorers==2)
assert(not M.patch(settings,changes,nil,false,false))
assert(not M.patch(settings,{crews={maxMembers=8}},nil,false,true))
-- Execute the production join/menu sender against a resolved profile, without a tick.
local chunk=assert(main:match('(local function sendPlayerProgress.-)function RacePrepProgressTick'))
local sent,refreshed={},{}
local env=setmetatable({features={progress={refresh=function(id) refreshed[id]=true end,payload=function(pid,ids) return {self=ids[tostring(pid)]} end,send=function(pid,p) sent[pid]=p end},rating={score=function(n)return n end},league={view=function()return {}end}},
 MP={GetPlayerName=function(id)return id==7 and 'Alex' end,GetPlayers=function()return {[7]='Alex'} end,RegisterEvent=function()end},
 skillKey=function(id)return 'key-'..id end,Skill={hash=function(_,key)return 'salted-'..key end,START=1500},skills={salt='test',players={}},raceControl={driverProfile=function()return {}end},host={level='smallgrid'},resultHistory={view=function()return {rivalGroups={}}end},Util={JsonEncode=function(v)return v end}}, {__index=_G})
local loader=assert(loadstring(chunk));setfenv(loader,env);loader();env.RacePrepProgressJoin(7)
assert(refreshed['salted-key-7'] and sent[7].self=='salted-key-7','resolved join sends own view immediately without waiting for the tick')
print('PASS: crew settings cannot change unrelated rules; rules permission cannot bypass Manage crews; production join sends immediately')
