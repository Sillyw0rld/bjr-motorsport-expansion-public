-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- factory boost counts, the player's tuning does not (owner rule 2026-10-16)
local pcs={['/vehicles/sbr/hillclimb.pc']={vars={['$wastegateStart']=24,['$revLimiterRPM']=8000,['$camber_FR']=0.9}},
 ['/vehicles/sunburst2/rally_am_gravel.pc']={vars={['$wastegateTarget']=10}}}
local configs={['sbr/hillclimb']={Source='BeamNG - Official',pcFilename='/vehicles/sbr/hillclimb.pc'},
 ['sunburst2/rally_am_gravel']={Source='BeamNG - Official',pcFilename='/vehicles/sunburst2/rally_am_gravel.pc'},
 ['sbr/My tune']={Source='Custom',pcFilename='/vehicles/sbr/My tune.pc'}}
pcs['/vehicles/sbr/My tune.pc']={vars={['$wastegateStart']=30}}
core_vehicles={getConfig=function(m,c) return configs[m..'/'..c] end}
jsonReadFile=function(p) return pcs[p] end
local B=require('ge/extensions/raceprep/factoryEngine')
local v=B.vars('sbr','hillclimb')
assert(v['$wastegateStart']==24 and v['$revLimiterRPM']==8000 and v['$camber_FR']==nil,'factory boost and rev limit only')
assert(B.vars('sunburst2','rally_am_gravel')['$wastegateTarget']==10,'lower factory boost counts too')
assert(next(B.vars('sbr','My tune'))==nil,'a player config: its own boost does not count')
assert(B.vars('sbr','My tune','hillclimb')['$wastegateStart']==24,'saved setup: boost of the factory config it came from')
assert(next(B.vars('hawk_fm5','6024e'))==nil,'unknown config: no vars')
print('PASS: rating copy keeps the factory boost and rev limit only')
