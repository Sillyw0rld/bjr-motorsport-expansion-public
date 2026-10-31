-- SPDX-License-Identifier: AGPL-3.0-or-later
package.path='client/lua/?.lua;'..package.path
local R=require('ge/extensions/raceprep/rating')
local S=dofile('server/RacePrep/RatingStore.lua')
local I=require('ge/extensions/raceprep/ratingIdentity')
local old={knee=300,cap=999,a=.495,b=.58,c=.29}
local c={curve={knee=300,cap=999,a=.495,b=.58,c=.29,lowRaw=-850},rawRevision=1}
local last=100
for raw=-10000,10000 do
 local pi=R.curve(raw,c)
 assert(pi>=100 and pi<=999 and pi>=last,'monotonic display floor')
 assert(pi==S.curve(raw,c),'client/server mismatch')
 if raw>=300 then assert(pi==R.curve(raw,old),'upper curve changed')end
 last=pi
end
assert(R.curve(300-1e-8,c)==300 and R.curve(300+1e-8,c)==300,'continuous at knee')
assert(R.curve(-850,c)==100 and R.curve(-500,c)>100 and R.curve(0,c)>R.curve(-500,c))
assert(R.curve(-500,false)==100 and R.curve(100,old)==100,'legacy callers retain display bounds')
local payload={model='citybus',config='city',parts={root='citybus'},raw={pi=-776,pi_speed=-720,pi_technical=-886},ratingRevision=1}
local e=assert(S.validate(payload,I,c));assert(e.raw.pi==-776 and e.pi==R.curve(-776,c))
assert(not S.validate({model='citybus',config='city',parts={root='citybus'},pi=-776,pi_speed=-720,pi_technical=-886},I,c),'negative displayed PI must be rejected')
payload.ratingRevision=0;assert(not S.validate(payload,I,c),'stale clipped reports must be rejected')
payload.ratingRevision=1
for _,raw in ipairs({-1000,-200,0,100,900})do
 local a,b=R.bonusRaw(raw,.09),S.bonusRaw(raw,.09)
 assert(a==b and a>=raw,'fitted positive shares must not decrease negative raw PI')
 if raw>=0 then assert(a==raw*(1+.09),'positive bonus arithmetic changed')end
end
local store={entries={stale={source='computed',raw={pi=100}},manual={source='admin',pi=200}},constants={rawRevision=0}}
local _,dropped=S.mergeSeed(store,{entries={},constants=c});assert(dropped==1 and not store.entries.stale and store.entries.manual)
local _,again=S.mergeSeed(store,{entries={},constants=c});assert(again==0,'migration must be idempotent')
print('PASS: unclipped raw validation, monotonic low curve, knee continuity, frozen upper curve, client/server parity, positive bonuses and migration')
