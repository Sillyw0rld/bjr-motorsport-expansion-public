-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local A=require('ge/extensions/raceprep/anchorSelection')
local petrol={model='car',config='base',pi=300,source='measured',formula={pi=310},
    parts={['/body']='wagon',['/body/engine']='petrol',['/body/gearbox']='manual'}}
local diesel={model='car',config='diesel',pi=290,source='measured',formula={pi=320},
    parts={['/body']='wagon',['/body/engine']='diesel',['/body/gearbox']='auto'}}
local seed={entries={z=petrol,a=diesel},baselines={['car/base']='z',['car/diesel']='a'}}
assert(A.select(seed,'car','base')==petrol,'explicit config baseline')
assert(A.select(seed,'car','diesel')==diesel,'diesel must not anchor to petrol')
assert(A.select(seed,'car','saved',{['/body']='wagon',['/body/engine']='diesel',
    ['/body/gearbox']='auto',['/body/mod']='rp_native_holder'})==diesel,'renamed saved setup')
assert(A.select(seed,'car','unknown',{['/body']='wagon'})==nil,'ambiguous match stays unanchored')
assert(A.select(seed,'car')==nil,'no arbitrary pairs order fallback')
assert(A.select({entries={only=petrol}},'car')==petrol,'preserve Automation single-baseline behavior')
seed.baselines={}
assert(A.select(seed,'car','diesel')==diesel,'unique exact config without baseline index')
seed.entries={only={model='car',source='computed',pi=300,formula={pi=300}}}
assert(A.select(seed,'car')==nil,'never anchor to another prediction')
print('PASS: deterministic config/parts-aware anchors and ambiguous baseline rejection')
