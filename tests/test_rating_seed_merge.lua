-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='server/RacePrep/?.lua;'..package.path
local S=dofile('server/RacePrep/RatingStore.lua')
local store={entries={
 ['car/a/1']={model='car',source='measured',pi=400},
 ['car/a/2']={model='car',source='computed',anchored=true,pi=430},
 ['other/b/1']={model='other',source='measured',pi=500},
 ['other/b/2']={model='other',source='computed',pi=520},
 ['admin/c/1']={model='admin',source='admin',pi=300},
}}
local seed={entries={
 ['car/a/1']={model='car',source='measured',pi=450},
 ['other/b/1']={model='other',source='measured',pi=500},
 ['admin/c/1']={model='admin',source='measured',pi=350},
 ['new/d/1']={model='new',source='measured',pi=600},
},baselines={['car/a']='car/a/1'},flags={x=1}}
local merged,dropped=S.mergeSeed(store,seed)
assert(store.entries['car/a/1'].pi==450,'re-measured stock rating replaces the old one')
assert(store.entries['car/a/2']==nil and dropped==1,'its anchored computed rating is dropped for recompute')
assert(store.entries['other/b/2'].pi==520,'unchanged stock rating keeps its computed ratings')
assert(store.entries['admin/c/1'].pi==300,'admin rating kept')
assert(store.entries['new/d/1'].pi==600 and store.baselines['car/a']=='car/a/1' and store.flags.x==1)
assert(merged==3)
local again,dropped2=S.mergeSeed(store,seed);assert(dropped2==0,'idempotent once merged')
print('PASS: seed merge replaces re-measured stock ratings and drops their stale anchored ratings; admin kept')
