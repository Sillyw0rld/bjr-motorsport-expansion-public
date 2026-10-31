-- SPDX-License-Identifier: AGPL-3.0-or-later
package.path='client/lua/?.lua;'..package.path
local S=require('common/raceprep/inductionSound')
local active,created,deleted,plays={},0,0,0
obj={}
function obj:createSFXSource(event,profile,name,node)
 assert(profile=='AudioDefaultLoop3D' and node==42)
 created=created+1;active[created]={event=event,name=name};return created
end
obj.createSFXSource2=obj.createSFXSource
function obj:setVolumePitch(id,volume,pitch)assert(active[id]);active[id].volume=volume;active[id].pitch=pitch end
function obj:setVolumePitchCT(id,volume,pitch,color)self:setVolumePitch(id,volume,pitch);assert(color==.3)end
function obj:stopSFX(id)assert(active[id])end
function obj:deleteSFXSource(id)assert(active[id]);active[id]=nil;deleted=deleted+1 end
function obj:cutSFX(id)assert(active[id])end
function obj:playSFX(id)assert(active[id]);plays=plays+1;active[id].plays=(active[id].plays or 0)+1 end
local function count()local n=0;for _ in pairs(active)do n=n+1 end;return n end
local function source(name)for _,v in pairs(active)do if v.name=='BJRMEInduction'..(name=='release' and 'Release' or name) then return v end end end
local function engine(rpm)return {engineNodeID=42,outputAV1=(rpm or 6000)*math.pi/30,throttle=1,requestedThrottle=1,instantEngineLoad=1,raceprepBoost=1,ignitionCoef=1}end
local function spec(kind,race)return {induction=kind,inductionRace=race,stockRevLimit=8000}end
local function step(e,dt)S.update({e},dt or .02)end
local function fresh(kind,race,rpm)
 S.reset();assert(count()==0)
 local e,s=engine(rpm),spec(kind,race);S.configure(e,s);step(e);return e,s
end
local function lift(e)e.throttle=0;e.requestedThrottle=0;e.instantEngineLoad=0;step(e)end
local function gas(e,dt)e.throttle=1;e.requestedThrottle=1;e.instantEngineLoad=1;step(e,dt)end
for _,kind in ipairs({'turbo_small','turbo_large','turbo_sequential','twin_charged','supercharger_sport','supercharger_race'})do
 local e,s=fresh(kind,true)
 local n=kind=='turbo_sequential'and 3 or kind=='twin_charged'and 3 or kind:find('supercharger')and 1 or 2
 assert(count()==n,kind..' sources')
 local before=created;step(e);assert(created==before,'no per-frame allocation')
 if kind:find('supercharger')then assert(source('whine')and not source('spin'))
 else assert(source('spin')and source('hiss'))end
 for _,device in ipairs({'turbocharger','supercharger'})do
  local foreign={[device]={isExisting=true}}
  before=created;S.update({e,foreign},.02);assert(count()==0 and before==created,'any stock device suppresses all our sources')
  step(e);assert(count()==n)
 end
end
S.reset()
local guarded=engine();S.configure(guarded,spec('turbo_small',true))
local prior=created
S.update({guarded,{turbocharger={isExisting=true}}},.02)
assert(created==prior and count()==0,'factory guard must run before any creation')
for _,layout in ipairs({'single','twin','twin_scroll'})do
 local e,s=fresh('turbo_small',true);s.turboLayout=layout
 local lastP,lastV=-1,-1
 for _,spool in ipairs({0,.2,.5,1})do
  e.raceprepBoost=spool;step(e)
  local spin=source('spin');assert(spin.pitch>lastP and spin.volume>lastV,'spin must follow spool at fixed RPM')
  lastP,lastV=spin.pitch,spin.volume
 end
 local pitch=source('spin').pitch;e.outputAV1=7000*math.pi/30;step(e)
 assert(source('spin').pitch==pitch,'turbo speed is not engine speed')
end
local e,s=fresh('turbo_small',true);local smallPitch=source('spin').pitch
assert(math.abs(smallPitch-160000*.10471971768*(.05*.01*.10471971768))<1e-12,'native turbo pitch coefficient')
e,s=fresh('turbo_large',true);assert(source('spin').pitch<smallPitch)
for _,race in ipairs({false,true})do
 e,s=fresh('turbo_small',race);local before=plays;lift(e)
 assert(plays==before+1 and source('release').event:find(race and 'Turbo_01' or 'Turbo_02',1,true))
 step(e,.05);assert(plays==before+1,'held lift must not retrigger')
 gas(e,.1);lift(e);assert(plays==before+1,'cooldown')
 gas(e,.51);lift(e);assert(plays==before+2,'rearmed after cooldown')
end
for _,condition in ipairs({'antiLag','limiter','cut','unboosted'})do
 e,s=fresh('turbo_small',true)
 if condition=='antiLag'then s.antiLag=true;step(e)
 elseif condition=='limiter'then e.revLimiterWasActiveTimer=0
 elseif condition=='cut'then e.ignitionCutTime=.2
 else e.raceprepBoost=0;step(e)end
 local before=plays;lift(e);assert(plays==before,condition..' suppresses release')
end
e,s=fresh('supercharger_race',true,2000);e.raceprepBoost=0;step(e)
local low=source('whine');local vp,pp=low.volume,low.pitch
e.outputAV1=6000*math.pi/30;step(e);assert(low.volume>vp and low.pitch>pp,'SC follows RPM with no spool')
lift(e);assert(low.volume==0,'closed throttle silences whine')
e,s=fresh('twin_charged',true,1600)
assert(source('whine').volume>0 and source('spin').volume==0)
e.outputAV1=5600*math.pi/30;e.raceprepBoost=0;step(e)
assert(source('whine').volume>0,'SC remains when turbo has not spooled')
e.raceprepBoost=1;step(e);assert(source('whine').volume==0 and source('spin').volume>0,'spooled turbo replaces SC')
e,s=fresh('turbo_sequential',true,2400)
assert(source('spin').volume>0 and source('largeSpin').volume==0)
e.outputAV1=5600*math.pi/30;step(e)
assert(source('largeSpin').volume>0 and source('largeSpin').pitch<source('spin').pitch)
local before=plays;lift(e);assert(plays==before+1,'one shared BOV for sequential pair')
for _,condition in ipairs({'ignition','stalled','disabled','stopped'})do
 e,s=fresh('turbo_small',true)
 if condition=='ignition'then e.ignitionCoef=0 elseif condition=='stalled'then e.isStalled=true
 elseif condition=='disabled'then e.isDisabled=true else e.outputAV1=0 end
 step(e);for _,v in pairs(active)do assert(v.volume==0)end
 e.ignitionCoef=1;e.isStalled=false;e.isDisabled=false;e.outputAV1=6000*math.pi/30;step(e)
 assert(source('spin').volume>0,'ignition restart resumes loop')
end
e,s=fresh('turbo_small',true)
for i=1,10 do S.configure(e,s);step(e);assert(count()==2,'reset must not stack')end
s.induction='supercharger_race';step(e);assert(count()==1 and source('whine'),'in-place spec change')
S.configure(e,spec('stock'));step(e);assert(count()==0,'removed part')
S.configure(e,s);step(e);S.update({},.02);assert(count()==0,'removed engine')
e,s=fresh('turbo_small',true)
local spool,rpm,throttle=e.raceprepBoost,e.outputAV1,e.throttle
step(e);assert(e.raceprepBoost==spool and e.outputAV1==rpm and e.throttle==throttle,'audio must not change engine inputs')
local P=dofile('client/lua/vehicle/extensions/raceprepPower.lua')
P.publishBoost(e,s,6000,.02,{e}) -- initialize the runtime module without physics
P.onExtensionUnloaded();assert(count()==0,'extension unload cleans its sources')
S.reset();assert(created==deleted,'all owned handles deleted; no delete-all API used')
print('PASS: induction sound ownership, all types/layouts, spool, BOV/flutter/cooldown/cut/anti-lag, crossover, sequential, silence/resume and lifecycle')
