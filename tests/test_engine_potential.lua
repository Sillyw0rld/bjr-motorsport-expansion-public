-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local E=require('common/raceprep/engineEffects')
local function copy(t)local o={};for k,v in pairs(t)do o[k]=v end;return o end
local function spec(hp,layout,litres,forced,stage)
 local s=copy(E.PACKAGES[stage or 3]);s.layout=layout;s.litres=litres;s.stockForcedInduction=forced;s.potentialEnabled=true
 return s
end
local function near(a,b,eps)assert(math.abs(a-b)<(eps or 1e-7),a..' != '..b)end
-- Stage 3 includes the Sport displacement part: the engine counts as 6 % bigger.
local na=spec(150,'I4',2,false);near(E.potential(na),320*1.06);near(E.gain(150,na),(320*1.06-150)*.7)
near(E.potential(spec(150,'I4',2,false,2)),320)
local race=spec(150,'I4',2,false);race.displacement='race';near(E.potential(race),320*1.12)
na.allowedTurbo=true;near(E.potential(na),320*1.06)
local turbo=copy(na);turbo.induction='turbo_small';near(E.potential(turbo),848);near(E.gain(150,turbo),(848-150)*.7)
for stage=1,3 do
 local forced=spec(150,'I4',2,false,stage);forced.induction='turbo_small'
 near(E.gain(150,forced),({650,650,698})[stage]*({.15,.4,.7})[stage])
end
near(E.gain(1200,spec(1200,'I4',2,true)),60)
local biankaSize=(6.407287905668126*1.06/8)^.25
local bianka=spec(1255,'V16',6.407287905668126,true);near(E.potential(bianka),2000*biankaSize,.01);near(E.gain(1255,bianka),(2000*biankaSize-1255)*.7,.01)
local v12=spec(500,'V12',6.5,false);near(E.gain(500,v12),(1060-500)*.7)
-- Small 8+ cylinder engines rev higher: fourth-root scaling below the reference size.
near(E.potential(spec(1017,'V12',3.56,true,2)),1600*.6^.25);near(E.potential(spec(500,'V8',4,true,2)),1500*.8^.25)
near(E.potential(spec(500,'V8',5,true,2)),1500);near(E.potential(spec(300,'V6',2.5,true,2)),1100*2.5/3.5)
-- Donor identity, never recipient power or displacement.
local recipient=spec(1200,'I4',2,true);local donor=spec(150,'I3',1.6,false)
near(E.gain(150,donor),(212-150)*.7);assert(E.gain(1200,recipient)~=E.gain(150,donor))
local missing=copy(E.PACKAGES[3]);missing.potentialEnabled=true
local raw=E.rawFactor(8000,8000,missing,true)-1
near(E.gain(300,missing),300*raw);near(E.gain(1000,missing),1000*raw*.25);near(E.gain(650,missing),650*raw*.625)
local missingSport=copy(E.PACKAGES[1]);missingSport.potentialEnabled=true;near(E.gain(1000,missingSport),30)
local reference={{0,0},{4000,150*7127/8000},{8000,150*7127/8000}}
for stage=1,3 do
 local s=spec(150,'I4',2,false,stage);local curve,limit=E.curve(reference,8000,s,true,1,50)
 near(E.peak(curve),150+E.gain(150,s),1e-5)
 assert(limit==E.revLimit(8000,s))
 -- Every subset of a package remains within that package's peak allowance.
 local names={};for k in pairs(E.PACKAGES[stage])do names[#names+1]=k end
 for mask=0,2^#names-1 do
  local chosen={layout='I4',litres=2,potentialEnabled=true}
  for i,k in ipairs(names)do if math.floor(mask/2^(i-1))%2==1 then chosen[k]=E.PACKAGES[stage][k]end end
  assert(E.gain(150,chosen)<=E.gain(150,s)+1e-8)
 end
end
local charged=spec(150,'I4',2,false);charged.induction='turbo_large'
local curve=E.curve(reference,8000,charged,true,1,50);near(E.peak(curve),150+(848-150)*.7,1e-5)
local lower=E.curve(reference,8000,charged,false,.2,50);assert(E.peak(lower)<150+(848-150)*.7)
local pi=E.curve(reference,8000,charged,'pi',1,50);assert(E.peak(pi)<=150+(848-150)*.7+1e-5)
local baseline={{0,0},{8000,150*7127/8000}};local native={{0,0},{8000,600*7127/8000}}
local limited=E.limitNative(native,baseline,charged);near(E.peak(limited),150+(848-150)*.7)
-- Selection must carry the donor's identity, not just accept a hand-built spec.
readFile=function()return 'catalog'end
local donor={stockEngine='donor',stockRevLimit=7000,layout='I3',litres=1.6,parts={}}
for field,value in pairs(E.PACKAGES[3])do donor.parts[field]={effect={[field]=value}}end
jsonDecode=function()return {models={recipient={layout='V16',litres=8,parts={}}},swaps={rp_swap_test_engine={engineInfo=donor}}}end
local S=require('common/raceprep/engineSelection');local parts={engine='rp_swap_test_engine'}
for field in pairs(E.PACKAGES[3])do parts[field]=field end
local swapped=S.spec('recipient',parts,{},{});assert(swapped.layout=='I3'and swapped.litres==1.6 and swapped.stockRevLimit==7000)
near(E.gain(150,swapped),(212-150)*.7)
near(E.potential({layout='2-rotor',stockForcedInduction=true}),700)
assert(not pcall(E.settings,{schema=99}))
print('PASS: NA/fitted forced, tune floor, Bianka V16, NA V12, small 8+ cylinder scaling, displacement parts, donor potential, fallback taper, package/subset bounds, curve/runtime/PI normalization and native adapter')
