-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local root='./'
local store=dofile(root..'server/RacePrep/RatingStore.lua')
local identity=dofile(root..'server/RacePrep/RatingIdentity.lua')
local rating=dofile(root..'client/lua/ge/extensions/raceprep/rating.lua')
local p={model='car',config='default',parts={['/main']='car',['/main/engine']='engine'},pi=550,pi_speed=580,pi_technical=520}
local e,key=store.validate(p,identity);assert(e and e.class=='B')
assert(identity.hash({b='two',a='one'})==identity.hash({a='one',b='two'}))
assert(identity.hash({a='one'})~=identity.hash({a='two'}))
local entries={[key]={pi=497,source='measured'}}
local accepted,changed=store.accept(entries,p,identity);assert(accepted==key and not changed and entries[key].pi==497)
entries[key].source='estimated from sibling';store.accept(entries,p,identity);assert(entries[key].source=='estimated from sibling')
local unknown={};accepted,changed=store.accept(unknown,p,identity);assert(changed and unknown[key].source=='computed')
for _,n in ipairs({99,2501,550.5,math.huge,-math.huge}) do local q={};for k,v in pairs(p) do q[k]=v end;q.pi=n;assert(not store.validate(q,identity)) end
do local q={};for k,v in pairs(p) do q[k]=v end;q.pi=1100;local hi=assert(store.validate(q,identity));assert(hi.raw.pi==1100 and hi.pi==store.curve(1100) and hi.class=='P') end
local q={};for k,v in pairs(p) do q[k]=v end;q.pi=0/0;assert(not store.validate(q,identity))
q.pi=550;q.parts={};assert(not store.validate(q,identity));q.parts={a='x\n'};assert(not store.validate(q,identity))
local all=store.classes(nil,nil);for _,c in ipairs(rating.classes) do assert(all[c]) end
local onlyB={};for _,c in ipairs(rating.classes) do onlyB[c]=c=='B' end
local checked=store.classes(onlyB,all);assert(checked.B and not checked.C)
assert(rating.violation({allowedClasses=checked},{class='C',pi=497})=='Class C is not allowed')
assert(not rating.violation({allowedClasses=checked},{class='B',pi=550}))
assert(rating.violation({piMin=501,piMax=600},{class='C',pi=497}))
assert(not rating.violation({piMin=501,piMax=600},{class='B',pi=550}))
assert(rating.violation({piMin=501,piMax=600},nil))
assert(not rating.violation({allowedClasses=all,piMin=false,piMax=false},nil))
assert(store.bound(false,600)==false and store.bound(500.6,false)==501 and store.bound(math.huge,false)==false)
print('PASS: rating identity, protected measured/sibling entries, unknown reports, invalid data, class rules, PI ranges and pending ratings')
