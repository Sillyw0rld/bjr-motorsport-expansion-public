-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local report
serialize=function(value) report=value;return '{}' end
obj={getID=function() return 3 end,queueGameEngineLua=function() end}
wheels={wheels={
 {name='FL',wheelID=0,downForceRaw=100,contactMaterialID1=4,contactMaterialID2=11,lastSlip=3,lastSideSlip=2,angularVelocity=10,radius=.3},
 {name='FR',wheelID=1,downForceRaw=0,contactMaterialID1=10},
 {name='RL',wheelID=2,downForceRaw=100,contactMaterialID1=20},
 {name='RR',wheelID=3,downForceRaw=100,contactMaterialID1=29}}}
extensions={luukstyrethermalsandwear={setRubberGrip=function() end}}
local T=dofile('client/lua/vehicle/extensions/raceprepRubberTelemetry.lua')
T.updateGFX(1);assert(not report)
T.enable();T.updateGFX(.1)
assert(report.wheels.FL.road and report.wheels.FL.wet and report.wheels.FL.id==0)
assert(not report.wheels.FR.road and not report.wheels.RL.road)
assert(report.wheels.RR.road and report.patched)
assert(report.wheels.FL.rollingSpeed==3)
T.disable();report=nil;T.updateGFX(1);assert(not report)
print('PASS: grounded asphalt/wet/kerb wheel telemetry, exact wheel IDs, slide and KTS availability')
