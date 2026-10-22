-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- raceprepKTS on unmodified KTS (2026-10-20): public surface only. No hidden-
-- variable writes (the vehicle sandbox refuses debug.setupvalue); rubber grip
-- through a wrapper on KTS's public grip-write route _gripRefresh.applyWheel.
local realSet=debug.setupvalue;local writes=0
debug.setupvalue=function() writes=writes+1;error('function not allowed by sandbox') end
local M=dofile('client/lua/vehicle/extensions/raceprepKTS.lua')
local actual={}
local route={applied={}}
route.applyWheel=function(id,g) route.applied[id]=g;actual[id]=g;return true end
local e={updateGFX=function() end,_gripRefresh=route}
extensions={luukstyrethermalsandwear=e}
local original=route.applyWheel
assert(pcall(M.updateGFX) and M.setRoadTemperature(45),'temperature handled by the KTS mailbox (Road Temperature mod)')
assert(M.status.temperature=='KTS mailbox (track temperature)' and M.status.automation=='tyre type via KTS preset')
route.applyWheel(0,.9);assert(M.setRubberGrip({[0]=1.03}));assert(math.abs(actual[0]-.927)<1e-8,'rubber reaches the wheel')
for i=1,100 do route.applyWheel(0,route.applied[0]) end
assert(math.abs(actual[0]-.927)<1e-8 and route.applied[0]==.9,'no compounding: KTS keeps its own unmultiplied grip')
assert(M.status.grip=='guarded KTS grip-write hook')
M.setRubberGrip({});assert(actual[0]==.9,'clearing removes rubber')
M.setRubberGrip({[0]=1.5});assert(actual[0]==.9,'out-of-range factor ignored')
M.setRubberGrip({[0]=1.02});M.onExtensionUnloaded();assert(route.applyWheel==original and actual[0]==.9,'unload restores KTS')
-- KTS reloaded (new instance): re-attaches by itself
local route2={applied={}};route2.applyWheel=function(id,g) route2.applied[id]=g;actual[id]=g;return true end
extensions.luukstyrethermalsandwear={updateGFX=function() end,_gripRefresh=route2}
route2.applyWheel(1,1.0);assert(M.setRubberGrip({[1]=1.04}) and math.abs(actual[1]-1.04)<1e-9,'new KTS instance re-wrapped')
-- unknown KTS without the route: fails closed
extensions.luukstyrethermalsandwear={updateGFX=function() end};assert(not M.setRubberGrip({[0]=1.02}),'no route: nothing changed')
assert(writes==0,'never attempts a hidden-variable write')
debug.setupvalue=realSet
print('PASS: stock KTS: rubber grip via public grip-write route, no compounding, restore on unload/reload, no sandboxed writes')
-- KTS with its own public API (patched builds / a future official API) is preferred
do
 local P=dofile('client/lua/vehicle/extensions/raceprepKTS.lua')
 local values={}
 extensions={luukstyrethermalsandwear={setRoadTemperatureC=function(c) values.temp=c end,setRubberGrip=function(v) values.grip=v end}}
 assert(P.setRoadTemperature(33) and values.temp==33 and P.status.temperature=='public API')
 assert(P.setRubberGrip({[0]=1.01}) and values.grip[0]==1.01)
 local got;extensions={luukstyrethermalsandwear={updateGFX=function() end,setRubberGrip=function(v) got=v;return true end}}
 local Q=dofile('client/lua/vehicle/extensions/raceprepKTS.lua')
 assert(Q.setRubberGrip({[1]=1.04}) and got[1]==1.04 and Q.status.grip=='public API')
end
print('PASS: KTS public grip/temperature API used when present')
