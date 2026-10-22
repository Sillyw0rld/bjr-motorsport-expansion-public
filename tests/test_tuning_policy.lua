-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local P=dofile('client/lua/ge/extensions/raceprep/tuningPolicy.lua')
local v={activeParts={transmission='box',diff='diff',suspension='coils',intake='intake'},activePartsData={
 box={information={name='Race transmission'},variables={{'name'},{'$ratio1','range'}}},
 diff={information={name='Stock Race Clutch Rear Differential'},variables={{'$lock','range'}}},
 coils={information={name='Sport Coilovers'},variables={{'$spring','range'}}},
 intake={information={name='Race intake'},variables={{'$intakeNoise','range'}}},
}}
assert(P.allowed(v,'$ratio1',{title='Gear ratios'}))
assert(P.allowed(v,'$lock',{title='Differential lock'}))
local allowed,reason=P.allowed(v,'$spring',{title='Front spring'})
assert(not allowed and reason=='Needs a race suspension')
assert(P.allowed(v,'$tirePressure',{title='Tyre pressure'}))
assert(P.allowed(v,'$brakeBias',{title='Brake balance'}))
assert(P.allowed(v,'$fuel',{title='Fuel'}))
assert(not P.allowed(v,'$nodeWeightScale',{title='Node Weight'}))
v.raceprepAero={kit='street'}
assert(P.allowed(v,'$rpAeroFront',{title='Front downforce'}))
local bonus,parts,share=P.bonus(v,560)
assert(bonus==22 and #parts==2 and math.abs(share-.04)<1e-8)
v.activePartsData.coils.information.name='Race Coilovers'
assert(P.bonus(v,560)==34)
print('tuning policy: exact variable owners, stock race parts, always-tunable controls and policy bonuses passed')

-- axles: race parts unlock only their own axle; diffs per device position
do
    local P=dofile('client/lua/ge/extensions/raceprep/tuningPolicy.lua')
    local vd={activeParts={Camso_coilover_F_doublewishbone='Camso_coilover_F_doublewishbone_race_x',
            Camso_coilover_R_doublewishbone='Camso_coilover_R_doublewishbone_x',
            Camso_differential_rear='Camso_differential_rear_race'},
        activePartsData={Camso_coilover_F_doublewishbone_race_x={information={name='GT Race Front Coilovers'}},
            Camso_coilover_R_doublewishbone_x={information={name='GT Adaptive Rear Coilovers'}},
            Camso_differential_rear_race={information={name='Race Rear Differential'}}}}
    assert(P.axle('$springStiffness_F')=='front' and P.axle('$spring_R')=='rear' and P.axle('Camso_differential_center')=='centre')
    assert(P.allowed(vd,'$springStiffness_F',{title='Front spring rate'}),'race front coilovers unlock front springs')
    local okRear,why=P.allowed(vd,'$springStiffness_R',{title='Rear spring rate'})
    assert(not okRear and why:find('suspension'),'race FRONT coilovers do not unlock REAR springs')
    assert(P.raceDifferential(vd,'rear'),'race rear diff unlocks the rear diff')
    local okFront,whyFront=P.raceDifferential(vd,'front')
    assert(not okFront and whyFront=='Needs a race front differential')
    assert(not P.raceDifferential(vd,'centre'))
    print('tuning policy: axle-specific suspension unlock and per-axle race differentials passed')
end

-- BeamNG 0.39 activeParts keys are full slot paths: ancestors must not count
do
    local P=dofile('client/lua/ge/extensions/raceprep/tuningPolicy.lua')
    local tyre='rp_tyre_x_front_race_medium_p40'
    local vd={activeParts={['/Camso_Trim/Camso_suspension_F/camso_hubs_front_a6a97/Camso_wheels_front/'..tyre]=tyre,
            ['/Camso_Trim/Camso_differential_R/Camso_differential_rear/Camso_differential_rear_race']='Camso_differential_rear_race'},
        activePartsData={[tyre]={information={name='245 mm Race slick Front tyres'}},
            Camso_differential_rear_race={information={name='Race Rear Differential'}}}}
    assert(P.slotId('/a/Camso_wheels_front/'..tyre,tyre)=='Camso_wheels_front')
    assert(P.slotId('Camso_wheels_front',tyre)=='Camso_wheels_front','older plain slot keys still work')
    local points,parts=P.bonus(vd,339)
    assert(#parts==1 and parts[1].role=='differential','race slicks under the suspension slot earn no suspension bonus')
    assert(not P.allowed(vd,'$springStiffness_F',{title='Front spring rate'}),'race slicks do not unlock springs')
    assert(P.raceDifferential(vd,'rear'))
    print('tuning policy: slot paths (race slicks are not suspension parts) passed')
end

-- gear ratios belong to the transmission; cosmetic sound settings stay open
do
    local P=dofile('client/lua/ge/extensions/raceprep/tuningPolicy.lua')
    local vd={activeParts={},activePartsData={}}
    local ok1,why1=P.allowed(vd,'$gear_1',{title='Gear 1'})
    assert(not ok1 and why1=='Needs a race transmission','gear ratios need a race transmission: '..tostring(why1))
    assert(P.allowed(vd,'$gearWhineVolume',{title='Whine Volume'}),'whine volume is cosmetic')
    -- final drive is open on the stock transmission (Automation _f/_r, native plain/axle names)
    for _,n in ipairs({'$finaldrive','$finaldrive_f','$finaldrive_R'}) do
        local ok,why,owner=P.allowed(vd,n,{title='Final Drive Gear Ratio'})
        assert(ok and owner=='final-drive','final drive open without a race transmission: '..n..' '..tostring(why))
    end
    assert(P.allowed(vd,'$fdr',{title='Final Drive'}),'final drive matched by title')
    local ok2,why2=P.allowed(vd,'$brakeCoolingF',{title='Front brake cooling'})
    assert(not ok2 and why2=='Stock part - not adjustable')
    print('tuning policy: gear ratios, cosmetic sounds and plain lock reasons passed')
end

-- race ECU unlocks Automation's rev limiter / idle (defined on the engine part)
-- and Race Prep's ECU timing; race brakes unlock Brake Power (1.8.7)
do
    local P=dofile('client/lua/ge/extensions/raceprep/tuningPolicy.lua')
    local engineVars={{'$revLimitRPM'},{'$revLimitRPMDrop'},{'$idleRPM'}}
    local function car(ecu,brake)
        return {activeParts={['/Camso_Trim/Camso_Engine/Camso_Engine_08bea']='Camso_Engine_08bea',
                ['/Camso_Trim/Camso_Engine/Camso_EngineManagement_08bea/'..ecu]=ecu,
                ['/Camso_Trim/Camso_suspension_F/Camso_brake_F/'..brake]=brake},
            activePartsData={Camso_Engine_08bea={information={name='V8'},variables=engineVars},
                [ecu]={information={name=ecu:find('race') and 'Race Engine Management' or 'Engine Management'}},
                [brake]={information={name=brake},variables={{'$BrakePowerFront'}}}}}
    end
    local race=car('Camso_EngineManagement_race_08bea','rp_brake_x_front_race')
    for name,title in pairs({['$revLimitRPM']='RPM Limit',['$revLimitRPMDrop']='RPM Drop',['$idleRPM']='Idle RPM',
            ['$rpECUGain']='Race ECU timing effect'}) do
        assert(P.allowed(race,name,{title=title}),title..' with a race ECU')
    end
    local stock=car('Camso_EngineManagement_08bea','rp_brake_x_front_sport')
    local ok,why=P.allowed(stock,'$revLimitRPM',{title='RPM Limit'})
    assert(not ok and why=='Needs a race ECU','rev limit needs a race ECU: '..tostring(why))
    assert(P.allowed(race,'$BrakePowerFront',{title='Front Brake Power'}),'race brakes unlock brake power')
    ok,why=P.allowed(stock,'$BrakePowerFront',{title='Front Brake Power'})
    assert(not ok,'sport brakes do not unlock brake power')
    assert(P.allowed(stock,'$brakeOffset_F',{title='Front Brake Offset'}),'brake offset is visual')
    print('tuning policy: race ECU rev limiter / idle, race brake power, visual brake offset passed')
end

-- A Race Final Drive is not a Race Transmission. It must never unlock
-- individual gears through either assembly fallback or synthetic ownership.
do
    local final='rp_dt_sample_finaldrive_front_race'
    local stock='Camso_Transmission_stock'
    local race='Camso_Transmission_race'
    for _,fullPath in ipairs({false,true}) do
        local slot='rp_dt_sample_finaldrive_front'
        local key=fullPath and '/Camso_Trim/Camso_Engine/Camso_Transmission/'..slot..'/'..final or slot
        local vd={activeParts={[key]=final,Camso_Transmission=stock},activePartsData={
            [final]={information={name='Race Front Final Drive'},variables={{'$finaldrive_f','range'}}},
            [stock]={information={name='Stock 6-speed gearbox'},variables={{'$gear_1_race','range'}}}}}
        local function checkLocked()
            local ok,why=P.allowed(vd,'$gear_1_race',{title='Gear 1'})
            assert(not ok and why=='Needs a race transmission','Race Final Drive cannot unlock Gear 1')
            for n=2,6 do assert(not P.allowed(vd,'$gear_'..n..'_race',{title='Gear '..n})) end
            assert(P.allowed(vd,'$finaldrive_f',{title='Front Final Drive'}),'final drive stays adjustable')
        end
        checkLocked()
        vd.raceprepVariableOwners={['$gear_1_race']='transmission'}
        checkLocked() -- synthetic owner map includes the Race Final Drive
        vd.activeParts.Camso_Transmission=race
        vd.activePartsData[race]={information={name='Race 6-speed gearbox'}}
        for n=1,6 do assert(P.allowed(vd,'$gear_'..n..'_race',{title='Gear '..n}),'real Race Transmission still unlocks Gear '..n) end
        vd.activeParts.Camso_Transmission=stock
        vd.activePartsData[race]=nil -- rebuilt bundle contains only fitted part data
        checkLocked() -- reverting gearbox must lock individual gears again
    end
    local Setup=require('ge/extensions/raceprep/bjr/setup')
    local d={config={vars={}},vdata={activeParts={finaldrive=final},activePartsData={
        [final]={information={name='Race Front Final Drive'}}},variables={
        ['$gear_1_race']={title='Gear 1',min=.5,max=5,val=3,default=3},
        ['$finaldrive_f']={title='Front Final Drive',min=.5,max=16,val=4,default=4}}}}
    local rows={};for _,v in ipairs(Setup.variables(d,{},{editable=true,tuningEditable=true})) do rows[v.name]=v end
    assert(not rows['$gear_1_race'].allowed and rows['$finaldrive_f'].allowed,'BJR UI and Apply metadata enforce the same policy')
    print('PASS: Race Final Drive only unlocks final ratio; Race Transmission required for individual gears')
end
