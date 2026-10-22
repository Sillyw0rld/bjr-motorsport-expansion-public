-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared deterministic gusts drive BeamNG's native physical wind API.
local E={status=nil}
local baselineLevel
local baseline,lastApply=nil,-1e9
E.wind=function(rules,elapsed,seed)
 local hash=0;for i=1,#tostring(seed or '') do hash=(hash*31+tostring(seed):byte(i))%997 end
 local t=math.max(0,elapsed or 0);local period=math.max(2,tonumber(rules.windGustPeriod) or 12)
 local gust=(tonumber(rules.windGustKmh) or 0)*(.6*math.sin(t*math.pi*2/period+hash)+.4*math.sin(t*math.pi*2/(period*.37)+hash*1.7))
 local speed=math.max(0,(tonumber(rules.windSpeedKmh) or 0)+gust)/3.6
 local angle=(tonumber(rules.windDirection) or 0)*math.pi/180
 return speed*math.cos(angle),speed*math.sin(angle),speed*3.6
end
-- Clouds follow the track wind (1.8.9): the steady wind (no gusts) at the
-- cloud layer's altitude by the wind profile law v(h) = v10 * (h / 10 m)^(1/7)
-- (open terrain; about 1.9x at 0.8 km, 2.1x at 2 km), veered 20 degrees
-- clockwise as real wind turns with height (northern hemisphere). BeamNG's
-- CloudLayer.windSpeed is 100 m/s per unit (measured in 0.39: 0.2 -> 20.0 m/s,
-- 0.4 -> 40.0 m/s). BeamJoy's weather sync uses raceprepCloudWindSpeed while set.
E.CLOUD_MS_PER_UNIT=100
E.CLOUD_VEER=20
E.cloud=function(speedKmh,direction,altitudeKm)
 local h=math.max(300,math.min(4000,(tonumber(altitudeKm) or 1)*1000))
 local ms=math.max(0,tonumber(speedKmh) or 0)/3.6*(h/10)^(1/7)
 local angle=((tonumber(direction) or 0)-E.CLOUD_VEER)*math.pi/180
 return ms/E.CLOUD_MS_PER_UNIT,math.cos(angle),math.sin(angle),ms*3.6
end
local cloudBaseline,lastCloud=nil,-1e9
local function restoreClouds()
 rawset(_G,'raceprepCloudWindSpeed',nil)
 if cloudBaseline and core_environment and getCurrentLevelIdentifier and getCurrentLevelIdentifier()==cloudBaseline.level then
  -- BeamJoy rewrites its own cloud speed when it controls the weather
  if core_environment.setWindSpeed and cloudBaseline.speed then core_environment.setWindSpeed(cloudBaseline.speed) end
  if core_environment.setCloudWindDirection and cloudBaseline.dir then core_environment.setCloudWindDirection(cloudBaseline.dir.x,cloudBaseline.dir.y) end
 end
 cloudBaseline=nil;E.cloudStatus=nil
end
local function updateClouds(wind,level,clock)
 if not (core_environment and core_environment.getWindSpeed and core_environment.setWindSpeed and core_environment.setCloudWindDirection) then return end
 if clock-lastCloud<1 then return end;lastCloud=clock
 if core_environment.getWindSpeed()==nil then return end -- no cloud layer on this map
 if not cloudBaseline then
  local d=core_environment.getCloudWindDirection and core_environment.getCloudWindDirection()
  cloudBaseline={level=level,speed=core_environment.getWindSpeed(),dir=d and {x=d.x,y=d.y}}
 end
 local units,dx,dy,kmh=E.cloud(wind.speedKmh,wind.direction,core_environment.getCloudAltitudeKm and core_environment.getCloudAltitudeKm())
 rawset(_G,'raceprepCloudWindSpeed',units)
 if math.abs((core_environment.getWindSpeed() or 0)-units)>1e-4 then core_environment.setWindSpeed(units) end
 local d=core_environment.getCloudWindDirection and core_environment.getCloudWindDirection()
 if not d or math.abs(d.x-dx)>1e-3 or math.abs(d.y-dy)>1e-3 then core_environment.setCloudWindDirection(dx,dy) end
 E.cloudStatus=string.format('Clouds %.0f km/h',kmh)
end
-- BJR weather sync (development branch) also syncs cloud wind and the
-- physical ground wind. While Race Prep's track wind is on for the map, its
-- gusting wind owns those three fields: BJR's weather writes (made through its
-- saved copy of core_environment.setState) pass everything except them, so
-- BJR keeps cloud cover and fog. Reversible; BJR's data and what it sends to
-- the server are never changed.
E.WIND_FIELDS={windSpeed=true,groundWind=true,cloudWindDirection=true}
local held=nil
local function holdBJRWind(on)
 local bjr=rawget(_G,'beamjoy_environment')
 local base=bjr and type(bjr.baseFunctions)=='table' and bjr.baseFunctions.core_environment
 if on and base and type(base.setState)=='function' then
  if held and held.base==base and base.setState==held.wrapper then return end
  local original=base.setState
  local wrapper=function(state,...)
   if type(state)=='table' then
    local copy={}
    for k,v in pairs(state) do if not E.WIND_FIELDS[k] then copy[k]=v end end
    if next(copy)==nil then return end
    return original(copy,...)
   end
   return original(state,...)
  end
  base.setState=wrapper
  held={base=base,original=original,wrapper=wrapper}
 elseif not on and held then
  if held.base.setState==held.wrapper then held.base.setState=held.original end
  held=nil
 end
end
E.holdBJRWind=holdBJRWind
-- What the game is actually doing now (Track window read-out): the physical
-- ground wind read back from the engine (gust included) and the air
-- temperature. towards: same convention as the setting (0 = +x, 90 = +y);
-- bearing: compass, clockwise from north.
E.live=function()
 if not core_environment then return nil end
 local out={raceprepWind=E.status~=nil}
 local v=core_environment.getGroundWind and core_environment.getGroundWind()
 if v then
  local x,y=tonumber(v.x) or 0,tonumber(v.y) or 0
  out.windKmh=math.sqrt(x*x+y*y)*3.6
  out.windTowards=(math.deg(math.atan2(y,x))+360)%360
  out.windBearing=(math.deg(math.atan2(x,y))+360)%360
 end
 local ok,k=pcall(function() return core_environment.getTemperatureK and core_environment.getTemperatureK() end)
 if ok and tonumber(k) then out.airC=k-273.15 end
 return out
end
E.restore=function()
 holdBJRWind(false)
 if baseline and (not getCurrentLevelIdentifier or getCurrentLevelIdentifier()==baselineLevel) and core_environment and core_environment.setGroundWind then core_environment.setGroundWind(baseline.x,baseline.y,baseline.z) end
 baseline=nil;baselineLevel=nil;E.status=nil
 restoreClouds()
end
-- track: the server's per-map view (Track window): {level, wind = {enabled,
-- speedKmh, direction, gustKmh, gustPeriod}, windElapsed}. Applies on that map
-- in free roam, sessions and races; gusts follow the server's wind clock.
E.update=function(track,clock,receivedAt)
 local level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()
 local wind=track and track.wind
 local active=wind and wind.enabled and (not track.level or tostring(track.level):lower()==tostring(level or ''):lower())
 if not active then E.restore();return end
 if not core_environment or not core_environment.getGroundWind or not core_environment.setGroundWind then
  E.status='Physical wind API unavailable';return
 end
 holdBJRWind(true)
 if not baseline then baselineLevel=level;local v=core_environment.getGroundWind();baseline={x=v.x,y=v.y,z=v.z} end
 if clock-lastApply<.25 then return end;lastApply=clock
 local rules={windSpeedKmh=wind.speedKmh,windDirection=wind.direction,windGustKmh=wind.gustKmh,windGustPeriod=wind.gustPeriod}
 local elapsed=(tonumber(track.windElapsed) or 0)+math.max(0,clock-(receivedAt or clock))
 local x,y,speed=E.wind(rules,elapsed,track.level)
 core_environment.setGroundWind(x,y,0)
 local cok=pcall(updateClouds,wind,level,clock)
 E.status=string.format('Wind %.1f km/h towards %.0f deg (gust +/- %.0f)%s',speed,wind.direction or 0,wind.gustKmh or 0,
  cok and E.cloudStatus and ('; '..E.cloudStatus) or '')
end
return E
