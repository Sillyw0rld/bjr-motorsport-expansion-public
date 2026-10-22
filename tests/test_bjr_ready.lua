-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local ready=true
local h={ready=function() return ready end,vehicle=function() end,notice=function() end,session=function() end}
package.loaded['ge/extensions/raceprep/bjr/host']=h
package.loaded['ge/extensions/raceprep/upgrades']={}
package.loaded['ge/extensions/raceprep/tuningPolicy']={}
FS={fileExists=function() return false end}
local calls=0;local original=function() calls=calls+1 end
beamjoy_raceRunner={ready=original};local row={key='BJRaceReady',callback=original}
beamjoy_communications_ui={handlers={row}};AddEventHandler=function() end
local m=dofile('client/lua/ge/extensions/raceprepBJR.lua')
m.readyProblem=function() return 'Class limit exceeded' end
m.onUpdate(.016)
row.callback(true);assert(calls==0,'native UI saved callback is guarded')
row.callback(false);assert(calls==1,'unready always possible')
m.readyProblem=function() end;row.callback(true);assert(calls==2,'valid ready delegates to BJR')
m.onExtensionUnloaded();assert(row.callback==original and beamjoy_raceRunner.ready==original,'unload restores callbacks')
print('PASS: saved native Ready callback, rule refusal, unready, delegation and restoration')
