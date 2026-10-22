-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Server: per-map weather settings (defaults, limits, published view).
-- Client: BJR race start time on BJR main and on the development branch.
local now=100;os.time=function() return now end
local wires={};local count=0
Util={JsonEncode=function(p) count=count+1;local s='wire'..count;wires[s]=p;return s end,JsonDecode=function(s) return wires[s] end,JsonPrettify=function(s) return s end}
MP={GetPlayers=function() return {} end,GetPlayerName=function(id) return tostring(id) end,
 RegisterEvent=function() end,CreateEventTimer=function() end,TriggerGlobalEvent=function() end,TriggerClientEvent=function() end}
-- keep the repository clean: track.json writes stay in memory
local saved
local realOpen,realRename=io.open,os.rename
io.open=function(path,mode)
 if mode=='w' and tostring(path):find('track%.json%.tmp$') then
  local buf={};return {write=function(_,s) buf[#buf+1]=s end,close=function() saved=table.concat(buf) end}
 end
 return realOpen(path,mode)
end
os.rename=function(a,b) if tostring(a):find('track%.json%.tmp$') then return true end return realRename(a,b) end
local c=dofile('server/RacePrep/RaceControl.lua').new{path='server/RacePrep',rules=function() return {} end,read=function() return nil end}
c.snapshot({level='test',phase='none',participants={}})
-- an old track.json entry (no weather group) gets the defaults, off
assert(c.setTrack({wind={enabled=false}}))
local view=wires[saved] and wires[saved].levels.test
assert(view and view.weather and view.weather.enabled==false and view.weather.tempNoon==24,'weather defaults, off')
-- values are clamped to their limits; invalid ones are ignored
assert(c.setTrack({weather={enabled=true,cloudCover=0.5,fogDensity=9,rainDrops=-5,tempNoon=31,tempDusk='x',tempMidnight=12,tempDawn=-80}}))
local w=wires[saved].levels.test.weather
assert(w.enabled==true and w.cloudCover==0.5 and w.tempNoon==31 and w.tempMidnight==12,'valid values saved')
assert(w.fogDensity==0.0002 and w.rainDrops==0 and w.tempDusk==19 and w.tempDawn==15,'out-of-range or invalid values ignored')
io.open,os.rename=realOpen,realRename
print('PASS: per-map weather settings: defaults for old files, limits, admin values saved')

-- race start time on GetCurrentTimeMillis()'s clock
package.path='client/lua/?.lua;'..package.path
local H=require('ge/extensions/raceprep/bjr/host')
GetCurrentTimeMillis=function() return 50000 end
assert(H.raceStartMs({raceStartTimeMs=42000})==42000,'BJR main: raceStartTimeMs as is')
beamjoy_clockSync={localMs=function() return 9000 end}
-- development: started 3 s ago on the synchronised clock -> 3 s ago on ours
assert(H.raceStartMs({raceStartLocalMs=6000})==47000,'BJR development: synchronised start converted')
assert(H.raceStartMs({})==nil,'no race start yet')
print('PASS: race start time on BJR main and on the development branch (synchronised clock)')
