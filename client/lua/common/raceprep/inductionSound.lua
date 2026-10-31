-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Audio only. Never writes engine state, electrics, torque or spool.
local S={}
local Effects=require('common/raceprep/engineEffects')
local bindings,states={},{}
local events={spin='event:>Vehicle>Forced_Induction>Turbo_01>turbo_spin',
 hiss='event:>Vehicle>Forced_Induction>Turbo_01>turbo_hiss',
 bov='event:>Vehicle>Forced_Induction>Turbo_01>turbo_bov',
 flutter='event:>Vehicle>Forced_Induction>Turbo_02>turbo_bov',
 whine='event:>Vehicle>Forced_Induction>Supercharger_01>supercharger'}
-- Defaults from BeamNG 0.40 turbocharger.lua / supercharger.lua.
local rpmToAV=.10471971768
local turboPitchPerAV=.05*.01*rpmToAV
local turboVolumePerAV=.04*.01*rpmToAV
local hissPerPascal=.04*.00014503773773
local scPitchPerAV=.65*.01*rpmToAV
local scVolumePerPascal=.01/6894.757293178
local releaseVolume=.3
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function ramp(v,a,b)return clamp((v-a)/(b-a),0,1)end
local function eligible(s)
 local k=s and s.induction
 return k=='turbo_small' or k=='turbo_large' or k=='turbo_sequential' or k=='twin_charged' or k=='supercharger_sport' or k=='supercharger_race'
end
function S.hasStockDevice(devices)
 for _,e in pairs(devices or {})do
  if e.turbocharger and e.turbocharger.isExisting or e.supercharger and e.supercharger.isExisting then return true end
 end
 return false
end
local function discard(engine)
 local st=states[engine]
 if st then
  for _,source in pairs(st.sources)do obj:stopSFX(source);obj:deleteSFXSource(source)end
  states[engine]=nil
 end
end
function S.reset(engine)
 if engine then discard(engine);bindings[engine]=nil
 else
  for e in pairs(states)do discard(e)end
  bindings={}
 end
end
function S.configure(engine,spec)
 S.reset(engine)
 if eligible(spec)then bindings[engine]=spec end
end
local function signature(spec,node)
 return table.concat({spec.induction,tostring(spec.inductionRace),spec.turboLayout or '',spec.superchargerType or '',tostring(spec.stockRevLimit),tostring(spec.boostGain),tostring(spec.antiLag),tostring(node)},':')
end
local function create(st,key,event,oneShot)
 if st.sources[key]then return st.sources[key]end
 local source
 if oneShot then source=obj:createSFXSource2(event,'AudioDefaultLoop3D','BJRMEInductionRelease',st.node,0)
 else source=obj:createSFXSource(event,'AudioDefaultLoop3D','BJRMEInduction'..key,st.node)end
 if source then st.sources[key]=source;obj:setVolumePitch(source,0,0)end
 return source
end
local function volume(st,key,v,p)
 local source=st.sources[key]
 if source then obj:setVolumePitch(source,v,p)end
end
local function silence(st)
 for key,source in pairs(st.sources)do
  obj:setVolumePitch(source,0,0)
  if key=='release'then obj:stopSFX(source)end
 end
 st.previousPressure=0;st.previousLoad=0;st.releasing=false
end
local function spin(st,key,spool,peakRPM,mix,size)
 local av=peakRPM*rpmToAV*clamp(spool,0,1)
 volume(st,key,av*turboVolumePerAV*mix*size,av*turboPitchPerAV)
end
local function update(engine,spec,dt)
 local k=spec.induction;local limit=spec.stockRevLimit or engine.maxRPM or 8000
 local rpm=math.max(0,(engine.outputAV1 or 0)*30/math.pi)
 local throttle=clamp(engine.throttle or 0,0,1);local spool=clamp(engine.raceprepBoost or 0,0,1)
 local node=engine.engineNodeID or 0;local sig=signature(spec,node)
 local st=states[engine]
 if st and(st.spec~=spec or st.signature~=sig)then discard(engine);st=nil end
 if not st then
  -- Per-source deletion is required: never delete other vehicle audio or leak
  -- silent handles on older game APIs. Current supported game exposes it.
  if not obj or type(obj.deleteSFXSource)~='function'then return end
  st={spec=spec,signature=sig,node=node,sources={},cooldown=0,previousPressure=0,previousLoad=0,releasing=false}
  states[engine]=st
  if k:find('turbo',1,true)or k=='twin_charged'then
   create(st,'spin',events.spin);create(st,'hiss',events.hiss)
   if k=='turbo_sequential'then create(st,'largeSpin',events.spin)end
  end
  if k:find('supercharger',1,true)or k=='twin_charged'then create(st,'whine',events.whine)end
 end
 st.cooldown=math.max(0,st.cooldown-dt)
 if(engine.ignitionCoef or 1)<=0 or engine.isDisabled or engine.isStalled or rpm<200 then silence(st);return end
 local gauge=Effects.gauge(spec,rpm,limit,throttle,spool)
 local pressure=(gauge.turboBoost or 0)*1000
 local maxPressure=gauge.maxBoost*1000
 local size=k=='turbo_small'and .85 or 1.1
 if k=='turbo_sequential'then
  local takeover=ramp(rpm/limit,.45,.60)
  spin(st,'spin',spool,160000,1-.7*takeover,.85)
  spin(st,'largeSpin',spool,110000,takeover,1.1)
 else
  local mix=k=='twin_charged'and ramp(rpm/limit,.50,.65)or 1
  spin(st,'spin',spool,k=='turbo_small'and 160000 or 110000,mix,size)
 end
 volume(st,'hiss',math.max(0,pressure*hissPerPascal),1)
 if st.sources.whine then
  local drive=spec.superchargerType=='centrifugal'and 4 or 2
  local blowerRPM=rpm*drive;local maxRPM=limit*drive
  local mix=1
  if k=='twin_charged'then
   local baseline=Effects.gauge(spec,rpm,limit,throttle,0).superchargerBoost
   mix=baseline>0 and clamp(gauge.superchargerBoost/baseline,0,1)or 0
  end
  local pressureVolume=clamp(gauge.superchargerBoost*1000*scVolumePerPascal,0,15)
  local maxPressureVolume=math.min(maxPressure*scVolumePerPascal,15)
  local rpmVolume=clamp(blowerRPM*maxPressureVolume/math.max(1,maxRPM)*.5,0,15)*throttle*mix
  volume(st,'whine',math.max(pressureVolume,rpmVolume),math.max(0,blowerRPM*rpmToAV*scPitchPerAV))
 end
 local load=engine.instantEngineLoad or throttle
 local requested=engine.requestedThrottle or throttle
 local low=load<.05 or requested<=0 or st.previousLoad-load>.3
 local notLimited=engine.revLimiterWasActiveTimer==nil or engine.revLimiterWasActiveTimer>.1
 local ignitionNotCut=(engine.ignitionCutTime or 0)<=0
 local holding=spec.antiLag and spool>0
 local release=st.sources.spin and low and notLimited and ignitionNotCut and not holding
 local stored=math.max(pressure,st.previousPressure)
 if release and not st.releasing and st.cooldown<=0 and stored>1000 and maxPressure>0 then
  local source=create(st,'release',spec.inductionRace and events.bov or events.flutter,true)
  if source then
   obj:setVolumePitchCT(source,clamp(stored/maxPressure,0,1)*size,1,releaseVolume,0)
   obj:cutSFX(source);obj:playSFX(source)
  end
  st.cooldown=.5
 end
 st.releasing=release and true or false
 st.previousPressure=pressure;st.previousLoad=load
end
function S.update(devices,dt)
 dt=math.max(0,dt or 0)
 local seen={}
 for _,e in pairs(devices or {})do seen[e]=true end
 for e in pairs(bindings)do if not seen[e]then S.reset(e)end end
 if S.hasStockDevice(devices)then
  for e in pairs(states)do discard(e)end
  return
 end
 for _,e in pairs(devices or {})do
  local spec=bindings[e]
  if eligible(spec)then update(e,spec,dt)else discard(e)end
 end
end
return S
