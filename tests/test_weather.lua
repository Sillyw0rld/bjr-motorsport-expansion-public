-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race Prep weather: per-field ownership (BeamJoy first), apply/restore,
-- temperature curve refresh via the editor-dirty flag, unavailable rain.
package.path='client/lua/?.lua;'..package.path
local W=require('ge/extensions/raceprep/weather')

-- engine stubs
local env={cloud=1.2,fog=0.00008,rain=nil}
core_environment={
 getCloudCover=function() return env.cloud end,setCloudCover=function(v) env.cloud=v end,
 getFogDensity=function() return env.fog end,setFogDensity=function(v) env.fog=v end,
 getPrecipitation=function() return env.rain end,setPrecipitation=function(v) env.rain=v end,
}
local li={curve={{0,15},{1,15}},dirty=false,cached={{0,15},{1,15}}}
function li:getTemperatureCurveC() local o={} for i,p in ipairs(self.curve) do o[i]={p[1],p[2]} end return o end
function li:setTemperatureCurveC(c) self.curve=c end
function li:isEditorDirty() return self.dirty end
function li:setEditorDirty(v) self.dirty=v end
scenetree={findClassObjects=function(c) return c=='LevelInfo' and {'theLevelInfo'} or {} end,findObject=function() return li end}
local level='mosport'
getCurrentLevelIdentifier=function() return level end

local track={level='mosport',weather={enabled=true,cloudCover=0.3,fogDensity=0.002,rainDrops=400,tempNoon=30,tempDusk=24,tempMidnight=16,tempDawn=18}}
local clock=0
local function tick() clock=clock+2.5;W.update(track,clock) end

-- no BeamJoy weather: Race Prep controls everything it can
tick()
assert(env.cloud==0.3 and env.fog==0.002,'clouds and fog set')
assert(W.status.rain=='no rain on this map' and env.rain==nil,'map without rain: reported, nothing written')
assert(li.curve[1][2]==30 and li.curve[3][2]==16 and li.curve[5][2]==30,'temperature curve noon/dusk/midnight/dawn')
assert(li.dirty==true,'level flagged so BeamNG re-reads its cached curve')
tick();assert(li.dirty==false,'flag cleared on the next update')
assert(W.status.cloud=='Motorsport Expansion' and W.status.temperature=='Motorsport Expansion')

-- BJR weather sync takes cloud cover and fog: Race Prep stops writing them
beamjoy_environment={data={weatherSync=true,weather={cloudCover=0.9,fogDensity=1.5,windSpeed=0.1}}}
env.cloud,env.fog=0.9,0.0015
tick()
assert(env.cloud==0.9 and env.fog==0.0015,'BeamJoy-synced fields are never written')
assert(W.status.cloud=='synced through BJR' and W.status.fog=='synced through BJR' and W.status.temperature=='Motorsport Expansion','temperature stays with Race Prep')
-- BJR adds temperature to its sync later: Race Prep yields that too
beamjoy_environment.data.weather.tempCurve={{0,20},{1,20}}
tick();assert(W.status.temperature=='synced through BJR')
beamjoy_environment=nil

-- original BeamJoy's weather control owns all four fields
BJI_Env={Data={controlWeather=true}}
tick();assert(W.status.cloud=='synced through BJR' and W.status.rain=='synced through BJR' and W.status.temperature=='synced through BJR')
BJI_Env=nil

-- setting off: the map's own values come back
env.rain=0
tick();assert(env.rain==400,'rain applied once the map has rain')
track.weather.enabled=false
tick()
assert(env.rain==0,'rain restored');assert(W.status.cloud=='map default')
-- restore() after a temperature change puts the map's original curve back
-- (fresh module and map state: earlier BeamJoy ownership dropped the saved original)
package.loaded['ge/extensions/raceprep/weather']=nil;W=require('ge/extensions/raceprep/weather')
li.curve={{0,15},{1,15}};beamjoy_environment=nil;track.weather.enabled=true
tick();tick();assert(li.curve[1][2]==30)
W.restore();assert(li.curve[1][2]==15 and li.curve[2][2]==15,'original temperature curve restored')

-- another map: untouched
track.weather.enabled=true;track.level='other'
env.cloud=1.0;tick();assert(env.cloud==1.0,'settings for another map are ignored')
print('PASS: weather per-field ownership (BJR sync, original BeamJoy), apply/restore, temperature curve refresh, maps without rain')

-- wind ownership: BJR's weather writes skip the wind fields while Race Prep's track wind is on
local E=require('ge/extensions/raceprep/raceEnvironment')
local written={}
local original=function(state) for k,v in pairs(state) do written[k]=v end end
beamjoy_environment={baseFunctions={core_environment={setState=original}},data={weatherSync=true,weather={}}}
local gw={x=0,y=0,z=0}
core_environment.getGroundWind=function() return gw end
core_environment.setGroundWind=function(x,y,z) gw={x=x,y=y,z=z} end
E.update({level=level,windElapsed=0,wind={enabled=true,speedKmh=20,direction=0,gustKmh=0,gustPeriod=12}},1,1)
beamjoy_environment.baseFunctions.core_environment.setState({cloudCover=0.5,windSpeed=0.3,groundWind={x=9,y=9,z=0},cloudWindDirection={x=1,y=0},fogDensity=2})
assert(written.cloudCover==0.5 and written.fogDensity==2,'BJR still sets cloud cover and fog')
assert(written.windSpeed==nil and written.groundWind==nil and written.cloudWindDirection==nil,'BJR wind fields held for Race Prep')
E.restore()
assert(beamjoy_environment.baseFunctions.core_environment.setState==original,'BJR function restored when Race Prep lets go')
print('PASS: Race Prep track wind keeps BJR weather sync off the wind fields, reversibly')
