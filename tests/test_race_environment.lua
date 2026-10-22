-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local E=require('ge/extensions/raceprep/raceEnvironment')
local rules={windEnabled=true,windSpeedKmh=36,windDirection=90,windGustKmh=0}
local x,y,speed=E.wind(rules,10,'one');assert(math.abs(x)<1e-6 and math.abs(y-10)<1e-6 and speed==36)
rules.windGustKmh=10
local a,b=E.wind(rules,10,'one');local c,d=E.wind(rules,10,'one');assert(a==c and b==d)
local v={x=1,y=2,z=3};core_environment={getGroundWind=function() return v end,setGroundWind=function(x,y,z) v={x=x,y=y,z=z} end}
getCurrentLevelIdentifier=function() return 'a' end
local track={level='a',windElapsed=10,wind={enabled=true,speedKmh=36,direction=90,gustKmh=10,gustPeriod=12}}
E.update(track,1,1)
assert(v.z==0 and E.status and math.abs(v.x)<1e-6,'track wind applied in free roam (direction 90 = north)')
track.wind.enabled=false;E.update(track,2,2);assert(v.x==1 and v.y==2 and v.z==3,'wind off restores the map wind')
track.wind.enabled=true;track.level='other';E.update(track,3,3);assert(v.x==1,'other map: untouched')
E.update(nil,4,4);assert(v.x==1)
-- clouds follow the steady wind at their altitude (1.8.9)
local units,dx,dy,kmh=E.cloud(36,90,0.8)
assert(math.abs(units-10*80^(1/7)/100)<1e-9 and math.abs(kmh-36*80^(1/7))<1e-9,'wind profile at 0.8 km: about 1.87x')
assert(math.abs(dx-math.cos(math.rad(70)))<1e-9 and math.abs(dy-math.sin(math.rad(70)))<1e-9,'veered 20 deg clockwise')
assert(select(4,E.cloud(36,0,50))<select(4,E.cloud(36,0,4))+1e-9,'altitude capped at 4 km')
local cloud={speed=0.2,dir={x=1,y=0}}
core_environment.getWindSpeed=function() return cloud.speed end
core_environment.setWindSpeed=function(s) cloud.speed=s end
core_environment.getCloudAltitudeKm=function() return 0.8 end
core_environment.getCloudWindDirection=function() return {x=cloud.dir.x,y=cloud.dir.y} end
core_environment.setCloudWindDirection=function(x,y) cloud.dir={x=x,y=y} end
track={level='a',windElapsed=0,wind={enabled=true,speedKmh=36,direction=90,gustKmh=10,gustPeriod=12}}
E.update(track,100,100)
assert(math.abs(cloud.speed-units)<1e-9 and math.abs(rawget(_G,'raceprepCloudWindSpeed')-units)<1e-9,'clouds set, BeamJoy told')
assert(E.status:find('Clouds 67 km/h',1,true),E.status)
local before=cloud.speed;E.update(track,100.5,100.5);assert(cloud.speed==before,'gusts do not move the clouds')
track.wind.enabled=false;E.update(track,102,102)
assert(cloud.speed==0.2 and cloud.dir.x==1 and rawget(_G,'raceprepCloudWindSpeed')==nil,'wind off: clouds handed back')
print('PASS: physical wind units, heading, deterministic gusts, restoration and map guard; clouds at altitude, veer, BeamJoy hand-over')
-- live read-out for the Track window: the engine's ground wind and air temperature
do
 local saved=core_environment
 local x,y=E.wind({windSpeedKmh=36,windDirection=234,windGustKmh=0},0,'x')
 core_environment={getGroundWind=function() return {x=x,y=y,z=0} end,getTemperatureK=function() return 297.45 end}
 local live=E.live()
 assert(math.abs(live.windKmh-36)<1e-6,'speed read back')
 assert(math.abs(live.windTowards-234)<1e-6,'same direction convention as the setting')
 assert(math.abs(live.windBearing-216)<1e-6,'compass bearing (234 deg towards = SW)')
 assert(math.abs(live.airC-24.3)<1e-9,'air temperature in C')
 core_environment=saved
end
print('PASS: live wind and air temperature read back from the game')
