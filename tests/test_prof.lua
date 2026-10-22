-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- frame-spike report (raceprep/prof): spikes name BJR:ME's share; only our handlers are wrapped
local P=dofile('client/lua/ge/extensions/raceprep/prof.lua')
local logs={}
local function log(l,t,m) logs[#logs+1]=m end
for _=1,50 do P.tick(.011,log) end
assert(#logs==0,'steady frames are not reported')
P.add('ev:RacePrepRubberDelta',7.5);P.add('raceprepBJR',.1)
P.tick(.060,log)
assert(#logs==1 and logs[1]:find('Frame spike 60 ms') and logs[1]:find('ev:RacePrepRubberDelta 7.5'),tostring(logs[1]))
assert(not logs[1]:find('raceprepBJR'),'tiny shares are left out')
P.tick(.011,log);P.tick(.070,log);assert(#logs==1,'at most one report every 2 s')
-- hook: only raceprep-tagged handlers are timed
local registered={}
_G.AddEventHandler=function(name,fn,src) registered[name]=fn end
P.hook()
local mine=function() return 'mine' end;local theirs=function() return 'theirs' end
AddEventHandler('RacePrepRatings',mine,'raceprepRatings');AddEventHandler('BJIEvent',theirs,'BJI')
assert(registered.BJIEvent==theirs,'other handlers pass through unchanged')
assert(registered.RacePrepRatings~=mine and registered.RacePrepRatings()=='mine','ours are wrapped and still work')
local before=_G.AddEventHandler;P.hook();assert(_G.AddEventHandler==before,'hooking twice does not stack')
-- other extensions (BeamNG's profiler hook) are listed apart, biggest first; the report also goes to its own file
do
 local P2=dofile('client/lua/ge/extensions/raceprep/prof.lua');local logs2,written={},nil
 writeFile=function(path,text) written={path,text} end
 extensions={setProfiler=function(p) extensions.p=p end}
 assert(P2.profileExtensions(true) and extensions.p==P2.extProfiler)
 for _=1,50 do P2.tick(.011,function(_,_,m) logs2[#logs2+1]=m end) end
 P2.add('extensions.beamjoy_main.onUpdate',28);P2.add('extensions.core_weather.onUpdate',2);P2.add('raceprepBJR',.5)
 P2.tick(.045,function(_,_,m) logs2[#logs2+1]=m end)
 assert(logs2[1]:find('BJR:ME 0.5 ms: raceprepBJR 0.5') and logs2[1]:find('extensions: beamjoy_main.onUpdate 28.0, core_weather.onUpdate 2.0'),logs2[1])
 assert(written and written[1]=='/raceprep_spikes.log' and written[2]:find('beamjoy_main'),'spike file written at once')
end
print('PASS: frame-spike report names BJR:ME share; only BJR:ME handlers timed')
