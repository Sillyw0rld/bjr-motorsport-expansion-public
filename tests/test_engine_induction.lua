-- SPDX-License-Identifier: AGPL-3.0-or-later
package.path='client/lua/?.lua;'..package.path
local E=require('common/raceprep/engineEffects')
local function spec(kind)return{induction=kind,inductionRace=true,forged=true,radiator='race',layout='I4',litres=2,potentialEnabled=true,stockRevLimit=8000}end
local large,twin,seq=spec('turbo_large'),spec('twin_charged'),spec('turbo_sequential')
assert(E.induction(1600,8000,twin,true,0)>.4,'supercharger responds before turbo spools')
assert(E.induction(1600,8000,large,true,1)==0)
assert(E.induction(2400,8000,seq,true,1)>.39,'sequential makes boost by 30%')
assert(E.induction(8000,8000,twin,true,1)==E.induction(8000,8000,large,true,1))
assert(E.induction(8000,8000,seq,true,1)==E.induction(8000,8000,large,true,1))
assert(E.boost(0,seq,2400,8000,1,.35)==1)
assert(E.boost(0,large,6400,8000,1,.35)<.3)
assert(E.boost(0,twin,5600,8000,1,.5)==1)
assert(E.induction(5600,8000,twin,true,0)>.4,'supercharger stays engaged until the turbo actually supplies boost')
assert(E.LAG_PI_DISCOUNT.twin_charged<E.LAG_PI_DISCOUNT.turbo_large)
assert(E.LAG_PI_DISCOUNT.turbo_sequential<E.LAG_PI_DISCOUNT.turbo_large)
for _,s in ipairs({twin,seq})do
 assert(E.required(s)and E.shopRequired(s));assert(E.potential(s)==800)
 s.forged=false;assert(not E.required(s));s.forged=true
 s.stockForcedInduction=true;assert(not E.required(s));s.stockForcedInduction=nil
 local points={{0,100},{4000,200},{8000,130}}
 E.prepare(points,8000,s)
 assert(E.peak(E.curve(points,8000,s,true))<=E.peak(points)+E.gain(E.peak(points),s)+.01)
 local rated=E.peak(E.curve(points,8000,s,true));local pi=E.peak(E.curve(points,8000,s,'pi'));assert(pi<rated)
end
local P=dofile('client/lua/vehicle/extensions/raceprepPower.lua')
-- Load shared Effects through normal runtime initialization, without an engine.
powertrain={getDevicesByCategory=function()return{}end};P.applyNativeScales({})
local sent={};electrics={values={}}
streams={willSend=function(name)assert(name=='forcedInductionInfo');return true end}
gui={send=function(name,data)sent[#sent+1]=data end}
local engine={raceprepBoost=1,throttle=1}
for _,kind in ipairs({'turbo_small','turbo_large','supercharger_sport','supercharger_race','twin_charged','turbo_sequential'})do
 local s=spec(kind);P.publishBoost(engine,s,8000,0,{engine})
 local g=sent[#sent];assert(g.boost>0 and g.maxBoost>=g.boost)
 assert(math.abs(electrics.values.boost*6.8947572932-g.boost)<1e-8)
 assert(math.abs(electrics.values.boostMax*6.8947572932-g.maxBoost)<1e-8)
 if kind=='twin_charged'then
  P.publishBoost(engine,s,1600,0,{engine});assert(electrics.values.superchargerBoost>0 and electrics.values.turboBoost==0)
 end
end
engine.throttle=0;P.publishBoost(engine,twin,8000,0,{engine});assert(sent[#sent].boost==0)
for _,device in ipairs({'turbocharger','supercharger'})do
 electrics.values={boost=123,boostMax=456,turboBoost=78,superchargerBoost=9};local n=#sent
 P.publishBoost(engine,twin,8000,0,{engine,{[device]={isExisting=true}}})
 assert(#sent==n and electrics.values.boost==123 and electrics.values.boostMax==456 and electrics.values.turboBoost==78 and electrics.values.superchargerBoost==9,'stock values must not be overwritten')
end
print('PASS: dual induction curves, takeover/spool timing, PI lag, forged/factory restrictions, forced ceiling, stream kPa/electrics psi and factory ownership')
