-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- formula v7: native cars get the probed aero of their factory config, or of
-- the factory config with the most alike aero parts; Automation cars none
local table_={schema=1,models={etk800={parts={'etk800_body','etk800_bumper_F','etk800_spoiler_race','etk800_lip'},
 configs={['844_m']={cdA=0.82,dfF200=-120,dfR200=40,aeroParts={0,1}},
          ['844_track_m']={cdA=0.9,dfF200=300,dfR200=500,aeroParts={0,1,2,3}}}}}}
jsonReadFile=function(p) assert(p=='/lua/ge/extensions/raceprep/native-aero.json') return table_ end
local A=require('ge/extensions/raceprep/nativeAero')
local e=assert(A.lookup('etk800','844_track_M',{}))
assert(e.cdA==0.9 and e.dfR200==500 and e.source=='probe','factory config: exact (config names are lower-cased)')
local c=assert(A.lookup('etk800','My race build',{a='etk800_body',b='etk800_bumper_F',c='etk800_spoiler_race',d='some_seat'}))
assert(c.cdA==0.9 and c.source:find('844_track_m'),'custom build: closest aero parts ('..c.source..')')
local s=assert(A.lookup('etk800','street',{a='etk800_body',b='etk800_bumper_F'}))
assert(s.cdA==0.82,'street body parts pick the street config')
assert(A.lookup('hawk_fm5','6024e',{})==nil,'Automation and unknown models: no native aero')
A._reset();jsonReadFile=function() return nil end
assert(A.lookup('etk800','844_track_M',{})==nil,'no table shipped: nothing changes')
-- the shipped table, when present, is well formed
local f=io.open('client/lua/ge/extensions/raceprep/native-aero.json')
if f then
 local raw=f:read('*a');f:close()
 assert(raw:find('"models"') and raw:find('"cdA"'),'native-aero.json shape')
end
print('PASS: native aero lookup (exact factory config, nearest aero parts, none for Automation)')
