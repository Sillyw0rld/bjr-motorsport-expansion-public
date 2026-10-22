-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local E=require('common/raceprep/engineEffects')
-- forced induction on a naturally aspirated engine needs an upgraded radiator (shop only)
local na={induction='turbo_small',stockForcedInduction=false}
local ok,why=E.shopRequired(na);assert(not ok and why:find('radiator'),'turbo kit without radiator refused in the shop')
assert(E.required(na),'runtime spec unaffected: already-fitted cars keep their engine effects')
na.radiator='sport';assert(E.shopRequired(na),'High performance radiator allows the kit')
assert(E.shopRequired({induction='stock_upgrade',stockForcedInduction=true,forged=true}),'existing turbo upgrade needs no radiator')
assert(E.shopRequired({}),'no forced induction, no requirement')
assert(E.mass({radiator='race'})==5 and E.mass({radiator='sport'})==3)
-- very slight PI bump through the parts-based bonus
local P=dofile('client/lua/ge/extensions/raceprep/tuningPolicy.lua')
local vd={activeParts={['/a/hub/rp_x_radiator/rp_x_radiator_race']='rp_x_radiator_race'},
  activePartsData={rp_x_radiator_race={information={name='Race radiator'},raceprepEngine={radiator='race'}}}}
local bonus,parts,share=P.bonus(vd,500);assert(share==.01 and bonus==5,'Race radiator +1 %: '..tostring(share))
vd.activePartsData.rp_x_radiator_race.raceprepEngine.radiator='sport'
_,_,share=P.bonus(vd,500);assert(share==.005,'High performance radiator +0.5 %')
local b2,s2=P.catalogBonus({x='rp_x_radiator_race'},{rp_x_radiator_race='radiator_race'},500);assert(s2==.01 and b2==5)
print('PASS: radiator shop rule (forced induction on NA), runtime unaffected, mass, +0.5 % / +1 % PI share')
