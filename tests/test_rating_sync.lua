-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- rating sync (2026-10-17): the server sends the whole store once, then
-- deltas; seed entries come without parts and get them back from the local seed
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
local seedParts={['/main']='car_body',['/main/engine']='engine_x'}
jsonReadFile=function(path)
 if path:find('ratings%-seed') then return {entries={['m/c/1']={model='m',config='c',pi=500,class='C',source='measured',parts=seedParts}},baselines={['m/c']='m/c/1'},constants={}} end
 return {models={},parts={}}
end
readFile=function() return '{}' end
local decoded
jsonDecode=function(s) return decoded and decoded[s] or {models={}} end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
decoded={
 full={entries={['m/c/1']={model='m',config='c',pi=500,class='C',source='measured'},['m/x/2']={model='m',config='x',pi=600,class='B',source='computed',parts={a='rp_engine'}}},
  constants={v=1},vehicles={['5']={['5-1']='m/x/2'}}},
 add={delta=true,entries={['m/y/3']={model='m',config='y',pi=650,class='B',source='computed',parts={b='p'}}},vehicles={['7']={['7-2']='m/y/3'}}},
 gone={delta=true,entries={},vehicles={['5']={['5-1']=false}}},
 left={delta=true,entries={},vehicles={['7']=false}},
}
R.onRatings('full')
assert(R.getConfig('m','c').pi==500 and R.getConfig('m','c').parts and R.getConfig('m','c').parts['/main/engine']=='engine_x','seed entry: parts restored from the local seed')
assert(R.remoteVehicles['5']['5-1']=='m/x/2')
R.onRatings('add')
assert(R.remoteVehicles['5']['5-1']=='m/x/2' and R.remoteVehicles['7']['7-2']=='m/y/3','delta merges, keeps the rest')
assert(R.getServerVehicle('7-2') and R.getServerVehicle('7-2').pi==650,'new entry usable')
R.onRatings('gone');assert(R.remoteVehicles['5']['5-1']==nil,'deleted car removed')
R.onRatings('left');assert(R.remoteVehicles['7']==nil,'player who left removed')
assert(R.getConfig('m','c').pi==500,'full store entries survive deltas')
decoded.present={delta=true,entries={['m/y/3']={model='m',config='y',pi=586,pi_speed=600,pi_technical=570,class='B',source='computed',parts={b='p'},
 presentation={tuningShare=.015,weightShare=0,carName='Hawk Vipere S'}}},vehicles={['7']={['7-2']='m/y/3'}}}
R.onRatings('present')
assert(R.getServerVehicle('7-2').pi==595,'remote view includes the owner bonus, exactly once: 586 -> 595')
assert(R.getServerVehicle('7-2').pi==595,'repeated reads cannot compound bonuses')
print('PASS: rating sync: full store once, deltas merge, removals, seed parts restored')
