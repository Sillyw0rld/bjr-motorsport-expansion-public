local function read(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local P=dofile('server/RacePrep/EventPresets.lua');local Copy=dofile('server/RacePrep/Persistence.lua').copy
local Rating=dofile('server/RacePrep/RatingStore.lua');local src=read('server/RacePrep/RacePrep.lua')
-- Execute the production normalizer, not a second rules implementation.
local defaults=assert(src:match('(local DEFAULT_RULES = .-)local PART_GROUPS'))
local choice=assert(src:match('(local function choice.-)local rules ='))
local normalization=assert(src:match('(local function bool.-)local function save'))
local chunk=assert(loadstring(defaults..assert(src:match('local PART_GROUPS = [^\n]+'))..'\n'..choice..normalization..'\nreturn sanitize,DEFAULT_RULES'))
setfenv(chunk,setmetatable({RatingStore=Rating},{__index=_G}));local sanitize,base=chunk()
local disk,exists,fail,opened=nil,false,false,{}
local api={read=function()return Copy(disk)end,exists=function()return exists end,write=function(s)if fail then return false end;disk=Copy(s);exists=true;return true end,
 sanitize=function(p)return sanitize(p,base)end,cars=function()return {{model='covet',name='Ibishu Covet',config='13s_M'}}end,
 eligibility=function(pid,id)if pid=='busy' then return 'Already in a BJR session.' elseif pid~='player' then return 'Unknown BJR player.' elseif id~='1' then return 'Unknown layout.' end end}
local lib=P.new(api);assert(not lib.broken(),lib.view(true).error)
for _,class in ipairs({'E','D','C','B','A','S','R','P','X'})do
 local r=lib.rules(assert(lib.get('cup-'..class)));local lo,hi=P.band(class)
 assert(r.piMin==lo and r.piMax==hi and Rating.classOf(lo)==class and Rating.classOf(hi)==class)
 for c,on in pairs(r.allowedClasses)do assert(on==(c==class))end;assert(r.trackLimits=='invalid')
end
assert(lib.get('spec:covet').patch.specModel=='covet')
local p={name='Test preset',description='Test rules',category='Fun',offered=true,staffPick=false,patch={piMax=600},defaultLaps=3}
assert(not lib.action({action='save',preset=p},false))
assert(lib.action({action='save',preset=p},true));local custom=disk.items[#disk.items].id
p.staffPick=true;assert(not lib.action({action='save',preset=p},true),'fifth staff pick refused')
assert(lib.action({action='duplicate',id=custom},true));local duplicate=disk.items[#disk.items];assert(not duplicate.staffPick and not duplicate.offered)
local function open(q,pid)return lib.open(pid or 'player',q,function(s)opened[#opened+1]=s end)end
local request={action='open',preset=custom,raceID='1',laps=3,start='standing'}
assert(open(request));assert(opened[1].rules.piMax==600)
assert(not open({action='open',preset=duplicate.id,raceID='1',laps=3,start='standing'}))
for _,field in ipairs({'rules','patch','piMax','offered'})do local q=Copy(request);q[field]={piMax=999};assert(not open(q),'rule tampering refused')end
assert(not open(request,'busy'));assert(not open(request,'unknown'))
assert(lib.assign('run-1',opened[1]));local saved=lib.session('run-1');assert(saved.preset.id==custom and saved.rules.piMax==600)
assert(lib.action({action='remove',id=custom},true));assert(lib.session('run-1').rules.piMax==600,'removal cannot rewrite an active race')
lib=P.new(api);assert(lib.session('run-1').preset.id==custom,'session snapshot survives restart')
assert(lib.close('run-1'));assert(not lib.sessions()['run-1']);assert(lib.session('run-1').preset.id==custom,'completed results retain preset metadata')
local before=Copy(disk);fail=true;assert(not lib.action({action='remove',id='stock'},true));assert(lib.get('stock'));fail=false
for _,bad in ipairs({'broken',false,{schema=1,serial=0,items='corrupt'}})do disk=bad;exists=true;local damaged=P.new(api);assert(damaged.broken());assert(not damaged.action({action='remove',id='stock'},true));assert(disk==bad,'no corrupt-file replacement')end
disk=before
assert(src:find('res.preset=Persistence.copy(selected.preset)',1,true),'preset included in saved result')
-- A 2.28/2.29 library gains the new built-ins once, preserving lobby snapshots.
disk=Copy(before);disk.builtinVersion=nil
local oldItems={};for _,r in ipairs(disk.items)do if r.category~='Build to class'then oldItems[#oldItems+1]=r end end;disk.items=oldItems
for _,r in pairs(disk.sessions or{})do r.rules.targetClass=nil end
exists=true;fail=false;local migrated=P.new(api);assert(not migrated.broken()and migrated.get('build-A')and disk.builtinVersion==231)
assert(migrated.action({action='remove',id='build-A'},true));assert(not P.new(api).get('build-A'),'removed built-in is not re-added on each restart')
disk.builtinVersion='corrupt';assert(P.new(api).broken(),'invalid migration metadata fails closed')
print('PASS: real rules normalization, all class bands, spec server cars, four-pick cap, CRUD/permissions, unoffered and tampered player starts, eligibility, immutable session snapshots/restart, result preset and corrupt-file safety')
