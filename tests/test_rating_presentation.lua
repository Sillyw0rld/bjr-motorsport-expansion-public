-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S=dofile('server/RacePrep/RatingStore.lua')
local I=dofile('server/RacePrep/RatingIdentity.lua')
local p={model='car',config='Race setup',parts={a='body'},pi=586,pi_speed=600,pi_technical=570,
 presentation={tuningShare=.015,weightShare=0,carName='Hawk Vipere S'}}
local base=assert(S.validate(p,I));assert(base.config=='Race setup','saved setup names with spaces can sync')
local meta=assert(S.presentation(p));local e=S.present(base,meta)
local want0,want1=S.curve(586),S.curve(586*1.015)
assert(e.pi==want1 and e.class=='B' and e.performancePI==want0 and e.tuningPotentialPI==want1-want0 and e.carName=='Hawk Vipere S')
assert(base.pi==want0 and base.raw.pi==586 and base.presentation==nil,'never replace a base/seed rating with its display value')
p.presentation.weightShare=.03;e=S.present(base,assert(S.presentation(p)))
local want2=S.curve(586*1.045)
assert(e.pi==want2 and e.class=='A' and e.weightBonusPI==S.curve(586*1.03)-want0)
assert(S.present(base,meta).pi==want1,'no compounding across requests')
-- Without constants.curve, the curve is the identity (legacy seed/store behavior).
local legacyBase=assert(S.validate(p,I,{}))
assert(legacyBase.pi==586 and S.present(legacyBase,meta,{}).pi==595 and S.present(legacyBase,assert(S.presentation(p)),{}).pi==612)
for _,bad in ipairs({-.1,.5,math.huge,0/0}) do p.presentation.tuningShare=bad;assert(not S.presentation(p)) end
p.presentation.tuningShare=.015;p.presentation.weightShare=.1;assert(not S.presentation(p))
p.presentation.weightShare=0;p.presentation.carName='bad\nname';assert(not S.presentation(p))
p.config='../bad';assert(not S.validate(p,I),'spaces do not permit path traversal')
print('PASS: identical display/race PI, base preservation, bounded bonus metadata and saved setup identities')
