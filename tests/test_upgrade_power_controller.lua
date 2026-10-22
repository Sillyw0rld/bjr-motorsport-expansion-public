-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local calls,loads=0,0
extensions={load=function(name) assert(name=='raceprepPower');loads=loads+1 end,
 raceprepPower={apply=function() calls=calls+1 end}}
local c=dofile('client/lua/vehicle/controller/raceprepPower.lua')
assert(c.type=='auxiliary' and type(c.init)=='function','BeamNG requires init even for a late-stage controller')
c.init({});assert(calls==0)
c.initLastStage();assert(calls==1 and loads==1)
c.reset();assert(calls==2 and loads==2)
print('power controller: required init, late initialization and reset passed')
