-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local E=dofile('client/lua/common/raceprep/engineEffects.lua')
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b)) end
near(E.factor(2400,8000,{intake='race'}),1)
near(E.factor(5600,8000,{intake='race'}),1.06)
near(E.factor(3200,8000,{exhaust='race'}),1)
near(E.factor(6400,8000,{exhaust='race'}),1.06)
near(E.factor(3000,8000,{cam='race'}),.9)
near(E.factor(6000,8000,{cam='race'}),1.12)
near(E.factor(7000,8000,{intake='race',exhaust='race',ecu='race'}),1.06*1.06*1.05)
assert(E.revLimit(8000,{cam='race',forged=true,ecu='race'})==9300)
assert(E.revLimit(8000,{cam='race'})==8000)
local curve={{0,0},{1000,200},{7200,180},{8000,190}}
local points,limit=E.curve(curve,8000,{cam='race',forged=true},true)
assert(limit==9000)
local peak=E.torque(curve,8000,8000,{cam='race',forged=true},true)*8000
for _,p in ipairs(points) do if p[1]>8000 then assert(p[1]*p[2]<=peak+1e-8,'extra RPM increased peak power') end end
near(E.boost(0,{induction='turbo_small'},4000,8000,1,.5),1)
near(E.boost(0,{induction='turbo_large'},6000,8000,1,.5),1/3)
near(E.boost(1,{induction='turbo_large'},6000,8000,0,.25),0)
assert(not E.required({induction='turbo_large'}))
assert(E.required({induction='turbo_large',forged=true}))
assert(not E.required({induction='turbo_small',stockForcedInduction=true}))
assert(E.required({induction='stock_upgrade',stockForcedInduction=true,forged=true}))
assert(not E.required({induction='stock_upgrade',stockForcedInduction=true}))
near(E.boost(0,{induction='turbo_small',turboLayout='twin'},4000,8000,1,.35),1)
near(E.boost(0,{induction='turbo_small',turboLayout='twin_scroll'},4000,8000,1,.4),1)
near(E.boost(0,{induction='turbo_small',inductionRace=true,antiLag=true},4000,8000,1,.25),1)
near(E.factor(8000,8000,{induction='turbo_small',turboLayout='twin'}),1.38)
near(E.factor(4000,8000,{induction='supercharger_sport',superchargerType='centrifugal'}),1.075)
near(E.factor(1600,8000,{induction='supercharger_sport',superchargerType='roots'}),1.30)
near(E.factor(8000,8000,{induction='supercharger_sport',superchargerType='roots'}),1.27)
near(E.factor(8000,8000,{induction='stock_upgrade',pressurePoints={{0,2},{8000,2}}}),1.075)
assert(E.mass({displacement='sport',induction='turbo_large',intercooler=true,oilcooler=true})==40)
-- A race tuning slider changes physics but its rated curve stays the same.
near(E.factor(7000,8000,{ecu='race',ecuGain=.2},true),E.factor(7000,8000,{ecu='race',ecuGain=1},true))
assert(E.factor(7000,8000,{ecu='race',ecuGain=.2},false)<E.factor(7000,8000,{ecu='race',ecuGain=1},false))
print('engine effects: RPM ramps, stacking, rev extension, dependency, mass, lag and rated sliders passed')

-- intercooler: +2 % on boosted engines only
do
    local E=dofile('client/lua/common/raceprep/engineEffects.lua')
    local na=E.factor(5000,8000,{intercooler=true},true)
    local stockTurbo=E.factor(5000,8000,{intercooler=true,stockForcedInduction=true},true)
    local added=E.factor(7000,8000,{intercooler=true,induction='supercharger_sport',superchargerType='roots'},true)/
                E.factor(7000,8000,{induction='supercharger_sport',superchargerType='roots'},true)
    assert(na==1 and math.abs(stockTurbo-1.02)<1e-9 and math.abs(added-1.02)<1e-9)
    -- PI mode discounts turbo lag; dyno (rated=true) does not
    local dyno=E.factor(7000,8000,{induction='turbo_small',turboLayout='single'},true)
    local pi=E.factor(7000,8000,{induction='turbo_small',turboLayout='single'},'pi')
    assert(math.abs(dyno-1.40)<1e-9 and math.abs(pi-1.36)<1e-9)
    print('engine effects: intercooler on boosted engines only, turbo lag PI discount passed')
end
