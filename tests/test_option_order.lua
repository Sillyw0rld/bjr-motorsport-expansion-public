-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Regression: shop option lists must always order Stock -> Sport -> Race.
-- Forced-induction options additionally sort weakest to strongest (the dyno
-- delta U.partEffect returns), keeping same-type hardware adjacent.
package.path='client/lua/?.lua;'..package.path
jsonReadFile=function() return {models={},parts={}} end
readFile=function() return '{}' end
jsonDecode=function() return {models={}} end
local U=require('ge/extensions/raceprep/upgrades')

local indSlot,exhSlot='rp_engine_m_induction','rp_engine_m_exhaust'
local IND={
    small_single_sport={title='Small turbo, single',effect={induction='turbo_small',inductionRace=false,turboLayout='single'}},
    small_single_race={title='Small turbo, single (Race: adjustable boost, anti-lag)',effect={induction='turbo_small',inductionRace=true,turboLayout='single'}},
    small_twin_sport={title='Small turbo, twin',effect={induction='turbo_small',inductionRace=false,turboLayout='twin'}},
    small_twin_race={title='Small turbo, twin (Race: adjustable boost, anti-lag)',effect={induction='turbo_small',inductionRace=true,turboLayout='twin'}},
    large_single_sport={title='Large turbo, single',effect={induction='turbo_large',inductionRace=false,turboLayout='single'}},
    large_single_race={title='Large turbo, single (Race: adjustable boost, anti-lag)',effect={induction='turbo_large',inductionRace=true,turboLayout='single'}},
    ss_cent_sport={title='Sport supercharger, centrifugal',effect={induction='supercharger_sport',inductionRace=false,superchargerType='centrifugal'}},
    ss_cent_race={title='Race supercharger, centrifugal',effect={induction='supercharger_race',inductionRace=true,superchargerType='centrifugal'}},
}
local EXH={
    exh_sport={title='Sport exhaust',effect={powerGain=1.08}},
    exh_race={title='Race exhaust',effect={powerGain=1.16}},
}
local engineInfo={slots={induction=indSlot,exhaust=exhSlot},parts={}}
for n,p in pairs(IND) do p.slot=indSlot;engineInfo.parts[n]=p end
for n,p in pairs(EXH) do p.slot=exhSlot;engineInfo.parts[n]=p end
U.engineInfo=function() return engineInfo end
U.partEffect=function(vehID,n)
    local p=engineInfo.parts[n]
    if p then return p.title,nil,nil,TITLED_HP[n] end
end
-- displayed peak-hp deltas (lowest -> highest per tier)
TITLED_HP={
    small_single_sport=168.5,small_single_race=168.5,
    small_twin_sport=166,small_twin_race=166,
    large_single_sport=204.5,large_single_race=204.5,
    ss_cent_sport=153,ss_cent_race=170,
    exh_sport=12,exh_race=28,
}

local tree={
    id='main',chosenPartName='Body',children={
        Camso_Engine={id='Camso_Engine',chosenPartName='Camso_Engine_stock',children={
            [indSlot]={id=indSlot,chosenPartName='Camso_Induction_stock',children={}},
            [exhSlot]={id=exhSlot,chosenPartName='Camso_Exhaust_stock',children={}},
        }},
        Camso_suspension_R={id='Camso_suspension_R',chosenPartName='Camso_susp_R',children={
            Camso_differential_rear={id='Camso_differential_rear',chosenPartName='Camso_diff_rear_stock',children={}},
        }},
    },
}
local vehData={
    config={model='m',partsTree=tree,vars={}},
    vdata={model='m',powertrain={{type='camsoEngine'}},activeParts={},activePartsData={
        Body={slots2={{name='Camso_Engine',default='Camso_Engine_stock',coreSlot=true},
                      {name='Camso_suspension_R',default='Camso_susp_R',coreSlot=true}}},
        Camso_Engine_stock={slots2={{name=indSlot,default='Camso_Induction_stock'},
                                    {name=exhSlot,default='Camso_Exhaust_stock'}}},
        Camso_susp_R={slots2={{name='Camso_differential_rear',default='Camso_diff_rear_stock'}}},
    }},
}
core_vehicle_manager={getVehicleData=function() return vehData end}
local partInfo={
    Camso_Induction_stock={description='Stock turbo'},
    Camso_Exhaust_stock={description='Stock exhaust'},
    Camso_diff_rear_stock={description='Open differential'},
    diff_sport={description='Sport LSD'},
    diff_race={description='Race Rear Differential'},
}
local function compatible(slotDef)
    local s=slotDef.name or slotDef.type
    -- deliberately scrambled: the list must reorder everything
    if s==indSlot then return {'Camso_Induction_stock','large_single_race','ss_cent_sport','small_single_race','large_single_sport',
                               'ss_cent_race','small_twin_race','small_twin_sport','small_single_sport'} end
    if s==exhSlot then return {'Camso_Exhaust_stock','exh_race','exh_sport'} end
    if s=='Camso_differential_rear' then return {'diff_race','diff_sport'} end
    return {}
end

local rows=U.list(1,compatible,partInfo)
local bySlot={}
for _,r in ipairs(rows) do bySlot[r.slot]=r end

local ind=assert(bySlot[indSlot],'induction row listed')
local got={} for _,o in ipairs(ind.options) do got[#got+1]=o.name end
local want={'Camso_Induction_stock',
    'ss_cent_sport','small_twin_sport','small_single_sport','large_single_sport',
    'small_twin_race','small_single_race','ss_cent_race','large_single_race'}
assert(#got==#want,'induction option count: got '..table.concat(got,', '))
for i=1,#want do assert(got[i]==want[i],
    'induction order mismatch at '..i..': got '..table.concat(got,', ')..' want '..table.concat(want,', ')) end

local exh=assert(bySlot[exhSlot],'exhaust row listed')
assert(exh.options[1].name=='Camso_Exhaust_stock' and exh.options[2].name=='exh_sport' and exh.options[3].name=='exh_race',
    'exhaust must read stock, sport, race')

local diff=assert(bySlot['Camso_differential_rear'],'differential row listed')
assert(diff.options[1].name=='Camso_diff_rear_stock' and diff.options[2].name=='diff_sport' and diff.options[3].name=='diff_race',
    'differential must read stock, sport, race')

print('PASS: options always order stock -> sport -> race; induction weakest to strongest within each tier')
-- Fitting a Race part must not promote it into the Stock tier.
tree.children.Camso_Engine.children[exhSlot].chosenPartName='exh_race'
tree.children.Camso_Engine.children[indSlot].chosenPartName='large_single_race'
local fitted=U.list(1,compatible,partInfo)
for _,r in ipairs(fitted) do
 if r.slot==exhSlot then
  assert(r.options[1].name=='Camso_Exhaust_stock' and r.options[2].name=='exh_sport' and r.options[3].name=='exh_race','fitted Race exhaust must stay in Race tier')
 elseif r.slot==indSlot then
  for i,o in ipairs(r.options)do assert(o.name==want[i],'fitted Race induction must keep its tier and power order')end
 end
end
