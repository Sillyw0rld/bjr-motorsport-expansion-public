-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S=dofile('client/lua/common/raceprep/suspensionExtract.lua')
local s=S.extract({beams={{name='spring_FL',beamSpring=33000},{name='spring_FR',beamSpring=33000},
    {name='spring_RL',beamSpring=28000},{name='spring_RR',beamSpring=28000}},torsionbars={
    {partOrigin='etkc_swaybar_F',spring=4073},{partOrigin='etkc_swaybar_R',spring=506},
    {partOrigin='etkc_suspension_F',spring=300000}}})
assert(s.springs.spring_FL==33000)
assert(s.bars.torsionBarFront==4073 and s.bars.torsionBarRear==506)
assert(#s.nativeBarSources==2)
local unchanged=S.extract({torsionbars={{name='torsionBarFront',spring=2000},{name='torsionBarRear',spring=1000}}})
assert(unchanged.bars.torsionBarFront==2000 and unchanged.bars.torsionBarRear==1000)
assert(unchanged.nativeBarSources==nil)
local unknown=S.extract({torsionbars={{spring=200000},{partOrigin='steering_arm_F',spring=300000}}})
assert(next(unknown.bars)==nil)
print('PASS: native sway-bar provenance and unchanged named Automation suspension')
