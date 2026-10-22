-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S=dofile('client/lua/ge/extensions/raceprep/rubberSurface.lua')
getCurrentLevelIdentifier=function() return 'a' end
local original={staticFrictionCoefficient=1.03,slidingFrictionCoefficient=.721}
ground_model=function() return {} end
core_environment={groundModels={AMS2_RUB_0_B4_DRY={cdata=original}}}
be={setGroundModel=function() end}
local opacity=.7
scenetree={findObject=function() return {getField=function() return opacity end,setField=function(_,_,_,v) opacity=tonumber(v) end,reload=function() end} end}
jsonReadFile=function(path)
 if path:find('converter_metadata',1,true) then return {wetPhysics={enabled=true},rubberPhysics={enabled=true,dryBonusPercent=3,materialAssignments={a='AMS2_RUB_0_B4_DRY'}}} end
 return {ams2_racing_line_rubber={}}
end
S.update(true)
assert(math.abs(core_environment.groundModels.AMS2_RUB_0_B4_DRY.cdata.staticFrictionCoefficient-1)<1e-9)
assert(opacity==0)
assert(S.wet,'converter wet roads keep asphalt particle IDs; read physical metadata')
S.update(true);S.restore()
assert(core_environment.groundModels.AMS2_RUB_0_B4_DRY.cdata.staticFrictionCoefficient==1.03 and opacity==.7)
print('PASS: baked rubber normalised once, static ribbon hidden, exact ground/material restoration')
