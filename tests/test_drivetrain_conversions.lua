-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;client/lua/vehicle/extensions/?.lua;'..package.path
local function parseJson(str)
    local pos=1
    local function skip()
        while pos<=#str do
            local c=str:sub(pos,pos)
            if c==' ' or c=='\t' or c=='\r' or c=='\n' then pos=pos+1 else break end
        end
    end
    local parseVal
    local function parseStr()
        assert(str:sub(pos,pos)=='"')
        pos=pos+1
        local out={}
        while pos<=#str do
            local c=str:sub(pos,pos)
            if c=='"' then pos=pos+1;return table.concat(out) end
            if c=='\\' then
                pos=pos+1
                local esc=str:sub(pos,pos)
                local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
                if esc=='u' then
                    local hex=tonumber(str:sub(pos+1,pos+4),16) or 63
                    out[#out+1]=hex<128 and string.char(hex) or '?'
                    pos=pos+5
                else out[#out+1]=map[esc] or esc;pos=pos+1 end
            else out[#out+1]=c;pos=pos+1 end
        end
        error('unterminated string')
    end
    parseVal=function()
        skip()
        local c=str:sub(pos,pos)
        if c=='"' then return parseStr() end
        if c=='{' then
            pos=pos+1;skip()
            local obj={}
            if str:sub(pos,pos)=='}' then pos=pos+1;return obj end
            while true do
                skip();local k=parseStr();skip()
                assert(str:sub(pos,pos)==':');pos=pos+1
                obj[k]=parseVal();skip()
                local sep=str:sub(pos,pos)
                if sep=='}' then pos=pos+1;return obj end
                assert(sep==',');pos=pos+1
            end
        end
        if c=='[' then
            pos=pos+1;skip()
            local arr={}
            if str:sub(pos,pos)==']' then pos=pos+1;return arr end
            while true do
                arr[#arr+1]=parseVal();skip()
                local sep=str:sub(pos,pos)
                if sep==']' then pos=pos+1;return arr end
                assert(sep==',');pos=pos+1
            end
        end
        if str:sub(pos,pos+3)=='true' then pos=pos+4;return true end
        if str:sub(pos,pos+4)=='false' then pos=pos+5;return false end
        if str:sub(pos,pos+3)=='null' then pos=pos+4;return nil end
        local m=str:match('^[-+%d.eE]+',pos)
        assert(m,'unexpected json at '..pos)
        pos=pos+#m
        return assert(tonumber(m))
    end
    return parseVal()
end
local function readJson(rel)
    local f=assert(io.open('client'..rel,'r'),'missing '..rel)
    local txt=f:read('*a');f:close()
    return parseJson(txt)
end
jsonReadFile=function(path)
    if path:sub(1,1)~='/' then path='/'..path end
    local ok,res=pcall(readJson,path)
    return ok and res or nil
end
readFile=function() return '{}' end
jsonDecode=function() return {models={},swaps={}} end

local EngineConversions=require('ge/extensions/raceprep/engineConversions')
local DrivetrainConversions=require('ge/extensions/raceprep/drivetrainConversions')
local PartsRules=require('ge/extensions/raceprep/partsRules')
local Policy=require('ge/extensions/raceprep/tuningPolicy')
local Setup=require('ge/extensions/raceprep/bjr/setup')
local Rating=require('ge/extensions/raceprep/rating')
local U=require('ge/extensions/raceprep/upgrades')

-- 1. Verify generated library & namespaced JBeam powertrain graphs for RWD, FWD and AWD recipients
local lib=DrivetrainConversions.catalog()
if not (lib and type(lib.models)=='table' and next(lib.models)) then print('SKIP: no generated drivetrain library (parts are generated per server; run tools/generate_upgrades.py first)') return end
assert(lib and lib.version==1 and type(lib.models)=='table','drivetrain library loaded')
assert(#(lib.donors or {})==3,'three approved donors recorded')

local function verifyRecipientGraph(model,expectedStockDrive)
    local info=assert(DrivetrainConversions.info(model),'missing model '..model)
    assert(info.stockDrive==expectedStockDrive,model..' stockDrive mismatch')
    assert(info.ident and info.ident:match('^rp_dt_%x+$'),'namespaced ident required')
    local jbeam=readJson('/vehicles/'..model..'/raceprep/'..info.ident..'_drivetrain.jbeam')
    assert(type(jbeam)=='table','missing generated jbeam for '..model)

    -- Every generated part key and internal slot must be namespaced with info.ident
    for partName,partData in pairs(jbeam) do
        assert(partName:sub(1,#info.ident)==info.ident,'un-namespaced part '..partName)
        local st=assert(partData.slotType,'missing slotType on '..partName)
        assert(st=='Camso_TransferCase' or st=='Camso_differential_front' or st=='Camso_differential_rear'
            or st:sub(1,#info.ident)==info.ident,'unexpected slotType '..st..' on '..partName)
        -- Never include electricMotor devices or hybrid slots, nor beams
        assert(partData.beams==nil,'drivetrain part must not define beams: '..partName)
        if st~='Camso_TransferCase' then
            assert(partData.nodes==nil,'only Camso_TransferCase conversion part may adjust chassis mass nodes: '..partName)
        else
            assert(type(partData.nodes)=='table' and #partData.nodes>10,'transfer case conversion must include chassis mass adjustment nodes: '..partName)
        end
        for _,row in ipairs(partData.powertrain or {}) do
            assert(row[1]~='electricMotor' and row[2]~='frontMotor' and row[2]~='rearMotor','hybrid device in '..partName)
        end
        for _,s in ipairs(partData.slots or {}) do
            if s[1]~='type' then
                assert(not tostring(s[1]):find('ElectricMotor',1,true),'electric slot in '..partName)
                if s[2] and s[2]~='' then
                    assert(jbeam[s[2]]~=nil,'dangling default child '..tostring(s[2])..' in '..partName)
                end
            end
        end
    end

    -- Verify each non-stock conversion option builds a complete powertrain graph to the right wheels
    for _,opt in ipairs(info.options) do
        if opt.layout==expectedStockDrive then
            assert(opt.reason=='Already the stock drivetrain layout')
        else
            assert(not opt.reason,'unexpected incompatibility on '..model..' -> '..opt.layout..': '..tostring(opt.reason))
            local tc=assert(jbeam[opt.part],'missing transferCase part '..tostring(opt.part))
            assert(tc.slotType=='Camso_TransferCase')
            assert(math.abs(opt.finalDriveRatio-info.stockFinalDrive)<1e-6,'recipient final drive ratio must be preserved')
            if opt.layout=='FWD' then
                assert(tc.powertrain[2][1]=='shaft' and tc.powertrain[2][2]=='frontDriveShaft' and tc.powertrain[2][3]=='gearbox')
                assert(opt.frontDiff~='' and opt.rearDiff=='')
                assert(opt.massDeltaKG<0,'FWD must be lighter than RWD/AWD')
            elseif opt.layout=='RWD' then
                assert(tc.powertrain[2][1]=='shaft' and tc.powertrain[2][2]=='transferCase' and tc.powertrain[2][3]=='gearbox')
                local ds=assert(jbeam[info.ident..'_driveshaft_rear'])
                assert(ds.powertrain[2][2]=='rearDriveShaft' and ds.powertrain[2][3]=='transferCase')
                assert(opt.frontDiff=='' and opt.rearDiff~='')
                if expectedStockDrive=='FWD' then assert(opt.massDeltaKG>0,'RWD must be heavier than FWD') end
                if expectedStockDrive=='AWD' then assert(opt.massDeltaKG<0,'RWD must be lighter than AWD') end
            elseif opt.layout=='AWD' then
                local cd=assert(jbeam[opt.defaultCenterDiff])
                assert(cd.powertrain[2][1]=='differential' and cd.powertrain[2][2]=='transferCase' and cd.powertrain[2][3]=='gearbox')
                local dsf=assert(jbeam[info.ident..'_driveshaft_front'])
                local dsr=assert(jbeam[info.ident..'_driveshaft_rear'])
                assert(dsf.powertrain[2][2]=='frontDriveShaft' and dsf.powertrain[2][3]=='transferCase' and dsf.powertrain[2][4]==2)
                assert(dsr.powertrain[2][2]=='rearDriveShaft' and dsr.powertrain[2][3]=='transferCase' and dsr.powertrain[2][4]==1)
                assert(opt.frontDiff~='' and opt.rearDiff~='')
                assert(opt.massDeltaKG>0,'AWD must be heavier than FWD/RWD')
                assert(math.abs((opt.resetVars['$torquesplit'] or 0)-0.65)<1e-6,'AWD default split must be 65% rear')
            end
        end
    end
end

verifyRecipientGraph('hawk_fm5','RWD')
verifyRecipientGraph('neonna_gt','FWD')
verifyRecipientGraph('arrow_awd','AWD')
print('PASS: complete namespaced powertrain graphs verified for RWD (hawk_fm5), FWD (neonna_gt) and AWD (arrow_awd)')

-- 2. Engine conversion + Drivetrain conversion compatibility in BOTH installation orders, Undo, Stock restore, and Transmission replacement
local fm5Info=DrivetrainConversions.info('hawk_fm5')
local fm5Ident=fm5Info.ident
local fm5Jbeam=readJson('/vehicles/hawk_fm5/raceprep/'..fm5Ident..'_drivetrain.jbeam')
local fwdPart=fm5Ident..'_transfercase_fwd'
local awdPart=fm5Ident..'_transfercase_awd'

EngineConversions.catalog=function()
    return {models={hawk_fm5={
        stockEngine='Camso_Engine_stock',
        stockStructure='Camso_engine_structure_stock',
        stockDefaults={['$revLimitRPM']=7000},
        options={{
            part='rp_swap_fly_engine',
            structure='rp_swap_fly_structure',
            title='I3 turbo: 0.97 L, 172 hp (export), Fly Machine',
            model='fly_machine_fly_machine',
            engineKG=92.5,
            massDeltaKG=-100.1,
            resetVars={['$revLimitRPM']=7800},
            runtime='combustionEngine',
        }}
    }}}
end

local function makeBaseTree()
    return {
        id='main',
        chosenPartName='Camso_Trim_fm5',
        children={
            Camso_Engine={
                id='Camso_Engine',
                chosenPartName='Camso_Engine_stock',
                children={
                    Camso_engine_structure={
                        id='Camso_engine_structure',
                        chosenPartName='Camso_engine_structure_stock',
                        children={Camso_engine_mesh={id='Camso_engine_mesh',chosenPartName='Camso_engine_mesh_fm5',children={}}},
                    },
                    Camso_Transmission={
                        id='Camso_Transmission',
                        chosenPartName=fm5Info.stockTransferCase:gsub('TransferCase_RWD','Transmission'),
                        children={
                            Camso_TransferCase={
                                id='Camso_TransferCase',
                                chosenPartName=fm5Info.stockTransferCase,
                                children={},
                            },
                        },
                    },
                },
            },
            Camso_suspension_F={
                id='Camso_suspension_F',
                chosenPartName='Camso_doublewishbone_F',
                children={
                    Camso_differential_front={id='Camso_differential_front',chosenPartName='',children={}},
                },
            },
            Camso_suspension_R={
                id='Camso_suspension_R',
                chosenPartName='Camso_doublewishbone_R',
                children={
                    Camso_differential_rear={id='Camso_differential_rear',chosenPartName=fm5Info.stockRearDiff,children={}},
                },
            },
        },
    }
end

-- Order A: Engine conversion first -> Drivetrain conversion (AWD) -> Race Sequential Gearbox -> Stock engine -> Stock drivetrain
local treeA=makeBaseTree()
local varsA={['$tirepressure_F']=28,['$revLimitRPM']=7000}
local afterEngA,err1,varsAfterEngA=EngineConversions.change(treeA,{'Camso_Engine'},'rp_swap_fly_engine','hawk_fm5',varsA)
assert(afterEngA and not err1)
assert(afterEngA.children.Camso_Engine.chosenPartName=='rp_swap_fly_engine')
assert(afterEngA.children.Camso_Engine.children.Camso_Transmission.children.Camso_TransferCase.chosenPartName==fm5Info.stockTransferCase)

local afterDtA,err2,varsAfterDtA=DrivetrainConversions.change(
    afterEngA,{'Camso_Engine','Camso_Transmission','Camso_TransferCase'},awdPart,'hawk_fm5',varsAfterEngA)
assert(afterDtA and not err2)
-- Swapped engine and structure are preserved!
assert(afterDtA.children.Camso_Engine.chosenPartName=='rp_swap_fly_engine')
assert(afterDtA.children.Camso_Engine.children.Camso_engine_structure.chosenPartName=='rp_swap_fly_structure')
assert(varsAfterDtA['$revLimitRPM']==7800 and varsAfterDtA['$tirepressure_F']==28 and math.abs(varsAfterDtA['$torquesplit']-0.65)<1e-6)
-- Both front and rear differentials + center differential are active!
assert(afterDtA.children.Camso_suspension_F.children.Camso_differential_front.chosenPartName==fm5Ident..'_differential_front_lsd')
assert(afterDtA.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName==fm5Info.stockRearDiff)
local tcNodeA=afterDtA.children.Camso_Engine.children.Camso_Transmission.children.Camso_TransferCase
assert(tcNodeA.chosenPartName==awdPart)
assert(tcNodeA.children[fm5Ident..'_differential_center'].chosenPartName==fm5Ident..'_differential_center_lsd')

-- Changing Camso_Transmission to Race Sequential preserves the AWD Camso_TransferCase subtree!
local afterRaceTrans=U.changedTree(afterDtA,{'Camso_Engine','Camso_Transmission'},'Camso_Transmission_Race')
assert(afterRaceTrans.children.Camso_Engine.children.Camso_Transmission.chosenPartName=='Camso_Transmission_Race')
assert(afterRaceTrans.children.Camso_Engine.children.Camso_Transmission.children.Camso_TransferCase.chosenPartName==awdPart)
assert(afterRaceTrans.children.Camso_Engine.children.Camso_Transmission.children.Camso_TransferCase.children[fm5Ident..'_differential_center'].chosenPartName==fm5Ident..'_differential_center_lsd')

-- Order B: Drivetrain conversion (FWD) first -> Engine conversion -> Stock drivetrain -> Stock engine
local treeB=makeBaseTree()
local afterDtB,err3,varsAfterDtB=DrivetrainConversions.change(
    treeB,{'Camso_Engine','Camso_Transmission','Camso_TransferCase'},fwdPart,'hawk_fm5',{['$revLimitRPM']=7000})
assert(afterDtB and not err3)
assert(afterDtB.children.Camso_suspension_F.children.Camso_differential_front.chosenPartName==fm5Ident..'_differential_front_lsd')
assert(afterDtB.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName=='')

local afterEngB,err4,varsAfterEngB=EngineConversions.change(afterDtB,{'Camso_Engine'},'rp_swap_fly_engine','hawk_fm5',varsAfterDtB)
assert(afterEngB and not err4)
assert(afterEngB.children.Camso_Engine.chosenPartName=='rp_swap_fly_engine')
-- FWD conversion and front/rear differentials preserved across engine swap!
assert(afterEngB.children.Camso_Engine.children.Camso_Transmission.children.Camso_TransferCase.chosenPartName==fwdPart)
assert(afterEngB.children.Camso_suspension_F.children.Camso_differential_front.chosenPartName==fm5Ident..'_differential_front_lsd')
assert(afterEngB.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName=='')
assert(varsAfterEngB['$revLimitRPM']==7800)

-- Restore drivetrain to stock while keeping swapped engine
local afterRestoreDtB=assert(DrivetrainConversions.change(
    afterEngB,{'Camso_Engine','Camso_Transmission','Camso_TransferCase'},fm5Info.stockTransferCase,'hawk_fm5',varsAfterEngB))
assert(afterRestoreDtB.children.Camso_Engine.chosenPartName=='rp_swap_fly_engine')
assert(afterRestoreDtB.children.Camso_Engine.children.Camso_Transmission.children.Camso_TransferCase.chosenPartName==fm5Info.stockTransferCase)
assert(afterRestoreDtB.children.Camso_suspension_F.children.Camso_differential_front.chosenPartName=='')
assert(afterRestoreDtB.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName==fm5Info.stockRearDiff)
print('PASS: engine + drivetrain conversions preserve each other in both orders and across transmission upgrades')

-- 3. Shop listing (U.list), Apply, Undo, Save, Factory-only rules, and Race-part-dependent differential controls
local stateTree=makeBaseTree()
local stateVars={['$tirepressure_F']=28}
local function buildActiveParts(t,prefix,out,outData)
    out=out or {};outData=outData or {}
    local p=t.chosenPartName
    if p and p~='' then
        local k=(prefix or '')..'/'..p
        out[k]=p
        if fm5Jbeam[p] then outData[p]=fm5Jbeam[p] end
    end
    for id,c in pairs(t.children or {}) do
        buildActiveParts(c,(prefix or '')..'/'..id,out,outData)
    end
    return out,outData
end

local function refreshMockVehData()
    local ap,apd=buildActiveParts(stateTree,'',{}, {
        Camso_Trim_fm5={slots2={
            {name='Camso_Engine',default='Camso_Engine_stock',coreSlot=true,description='Engine'},
            {name='Camso_suspension_F',default='Camso_doublewishbone_F',coreSlot=true,description='Front Suspension'},
            {name='Camso_suspension_R',default='Camso_doublewishbone_R',coreSlot=true,description='Rear Suspension'},
        }},
        Camso_Engine_stock={slots2={
            {name='Camso_engine_structure',default='Camso_engine_structure_stock',coreSlot=true},
            {name='Camso_Transmission',default=fm5Info.stockTransferCase:gsub('TransferCase_RWD','Transmission'),coreSlot=true,description='Transmission'},
        }},
        [fm5Info.stockTransferCase:gsub('TransferCase_RWD','Transmission')]={slots2={
            {name='Camso_TransferCase',default=fm5Info.stockTransferCase,coreSlot=true,description='Drive Type'},
        }},
        [fm5Info.stockTransferCase]={slotType='Camso_TransferCase',information={name='Stock RWD'}},
        Camso_doublewishbone_F={slots2={{name='Camso_differential_front',default='',description='Front Differential'}}},
        Camso_doublewishbone_R={slots2={{name='Camso_differential_rear',default=fm5Info.stockRearDiff,description='Rear Differential'}}},
        [fm5Info.stockRearDiff]={slotType='Camso_differential_rear',information={name='Stock Rear Differential'}},
        Camso_differential_rear_race={slotType='Camso_differential_rear',information={name='Race Rear Differential'}},
    })
    return {
        config={model='hawk_fm5',partConfigFilename='vehicles/hawk_fm5/stock.pc',partsTree=stateTree,vars=stateVars},
        vdata={model='hawk_fm5',activeParts=ap,activePartsData=apd,powertrain={{type='camsoEngine'}}},
    }
end

local currentVehData=refreshMockVehData()
core_vehicle_manager={getVehicleData=function() return currentVehData end}
extensions={
    core_vehicle_manager=core_vehicle_manager,
    core_vehicle_partmgmt={
        setPartsTreeConfig=function(t) stateTree=t;currentVehData=refreshMockVehData() end,
        setConfigVars=function(v) stateVars=v;currentVehData.config.vars=v end,
    },
}

local function compatibleForSlot(slotDef)
    local st=slotDef.name or slotDef.type
    if st=='Camso_Engine' then return {'Camso_Engine_stock','rp_swap_fly_engine'} end
    if st=='Camso_TransferCase' then return {fm5Info.stockTransferCase,fwdPart,awdPart,'Camso_TransferCase_RWD_rangebox_unused'} end
    if st=='Camso_differential_front' then
        return {fm5Ident..'_differential_front_lsd',fm5Ident..'_differential_front_race',fm5Ident..'_differential_front_welded'}
    end
    if st=='Camso_differential_rear' then
        return {fm5Info.stockRearDiff,'Camso_differential_rear_race'}
    end
    if st==fm5Ident..'_differential_center' then
        return {fm5Ident..'_differential_center_lsd',fm5Ident..'_differential_center_race',fm5Ident..'_differential_center_welded'}
    end
    return {}
end

-- In stock RWD: U.list shows Drivetrain conversion + Rear Differential, and hides Front Differential!
local rowsRWD=U.list(1,compatibleForSlot,{})
local tcRow,fDiffRow,rDiffRow
for _,r in ipairs(rowsRWD) do
    if r.slot=='Camso_TransferCase' then tcRow=r end
    if r.slot=='Camso_differential_front' then fDiffRow=r end
    if r.slot=='Camso_differential_rear' then rDiffRow=r end
end
assert(tcRow and tcRow.title=='Drivetrain conversion' and #tcRow.options==3,'Stock + FWD + AWD only (unused rangebox filtered)')
assert(tcRow.options[1].name==fm5Info.stockTransferCase and tcRow.options[1].title=='Stock drivetrain (RWD)')
assert(fDiffRow==nil,'Front differential must be hidden while car is RWD')
assert(rDiffRow~=nil,'Rear differential must be shown while car is RWD')

-- Batching a drivetrain conversion with another slot is refused with a clear message
local okBatch,whyBatch=U.applyMany(1,{{tcRow,awdPart},{rDiffRow,'Camso_differential_rear_race'}},'Batch')
assert(not okBatch and whyBatch:find('separately',1,true))

-- Apply FWD conversion via U.applyMany
assert(U.applyMany(1,{{tcRow,fwdPart}},'Drivetrain conversion'))
local rowsFWD=U.list(1,compatibleForSlot,{})
fDiffRow,rDiffRow=nil,nil
for _,r in ipairs(rowsFWD) do
    if r.slot=='Camso_differential_front' then fDiffRow=r end
    if r.slot=='Camso_differential_rear' then rDiffRow=r end
end
assert(fDiffRow~=nil,'Front differential must be shown when converted to FWD')
assert(rDiffRow==nil,'Rear differential must be hidden when converted to FWD')
for _,o in ipairs(fDiffRow.options) do assert(o.name~='','Driven front differential must not offer None') end

-- Differential tuning policy in FWD: stock helical LSD is locked; fitting Race Front Differential unlocks front only
assert(not Policy.raceDifferential(currentVehData.vdata,'front'))
assert(U.applyMany(1,{{fDiffRow,fm5Ident..'_differential_front_race'}},'Front race diff'))
assert(Policy.raceDifferential(currentVehData.vdata,'front'))
assert(not Policy.raceDifferential(currentVehData.vdata,'rear'))
assert(not Policy.raceDifferential(currentVehData.vdata,'centre'))

-- Convert to AWD: preserves the already-fitted Race Front Differential, adds Center Differential and Rear Differential
for _,r in ipairs(U.list(1,compatibleForSlot,{})) do if r.slot=='Camso_TransferCase' then tcRow=r end end
assert(U.applyMany(1,{{tcRow,awdPart}},'AWD conversion'))
assert(stateTree.children.Camso_suspension_F.children.Camso_differential_front.chosenPartName==fm5Ident..'_differential_front_race',
    'existing Race Front Differential preserved when switching FWD -> AWD')
assert(Policy.raceDifferential(currentVehData.vdata,'front'))
assert(not Policy.raceDifferential(currentVehData.vdata,'centre'),'default helical center diff is not a race diff')

local cDiffRow
for _,r in ipairs(U.list(1,compatibleForSlot,{})) do
    if r.slot==fm5Ident..'_differential_center' then cDiffRow=r end
end
assert(cDiffRow~=nil and #cDiffRow.options==3,'Center differential options listed in AWD')
assert(U.applyMany(1,{{cDiffRow,fm5Ident..'_differential_center_race'}},'Race center diff'))
assert(Policy.raceDifferential(currentVehData.vdata,'centre'),'Race Center Differential unlocks centre diff & torque split')

-- Factory-only drivetrain rule rejects converted drivetrain
local origJsonRead=jsonReadFile
jsonReadFile=function(p)
    if p=='vehicles/hawk_fm5/stock.pc' then
        return {parts={Camso_TransferCase=fm5Info.stockTransferCase,Camso_differential_rear=fm5Info.stockRearDiff}}
    end
    return origJsonRead(p)
end
local shortViol=PartsRules.violation(1,{parts={drivetrain='stock'}})
assert(shortViol=='drivetrain must be factory parts','factory drivetrain rule must block conversion')

-- Undo step by step: back to Helical Center Diff -> back to FWD (with Race Front Diff) -> back to FWD (Helical) -> back to Stock RWD
assert(U.undo(1))
assert(not Policy.raceDifferential(currentVehData.vdata,'centre'))
assert(U.undo(1))
assert(DrivetrainConversions.currentLayout('hawk_fm5',stateTree)=='FWD')
assert(U.undo(1))
assert(not Policy.raceDifferential(currentVehData.vdata,'front'))
assert(U.undo(1))
assert(DrivetrainConversions.currentLayout('hawk_fm5',stateTree)=='RWD')
assert(PartsRules.violation(1,{parts={drivetrain='stock'}})==nil,'restored stock drivetrain passes factory rule')
jsonReadFile=origJsonRead

-- 3b. Runtime differential settings (bjiRacePrep.diffSettings) survive conversions and are restored by Undo
stateTree=makeBaseTree()
stateVars={['$tirepressure_F']=28}
currentVehData=refreshMockVehData()
bjiRacePrep={diffSettings={}}
local function rowFor(slotId)
    for _,r in ipairs(U.list(1,compatibleForSlot,{})) do if r.slot==slotId then return r end end
end
local tcRow2=assert(rowFor('Camso_TransferCase'))
local rDiffRow2=assert(rowFor('Camso_differential_rear'))
assert(U.applyMany(1,{{rDiffRow2,'Camso_differential_rear_race'}},'Race rear diff'))
bjiRacePrep.diffSettings[1]={rearDiff={mode='lsd',preload=123,lock=.33,coast=.12}}

-- RWD -> AWD preserves the compatible rear settings, gains no stale ones
assert(U.applyMany(1,{{tcRow2,awdPart}},'Drivetrain conversion'))
local ds=bjiRacePrep.diffSettings[1]
assert(ds.rearDiff and ds.rearDiff.preload==123 and ds.rearDiff.lock==.33,
    'RWD -> AWD must preserve compatible rear LSD settings')
assert(ds.frontDiff==nil and ds.transferCase==nil,'no settings for devices never tuned')

-- editing the live table must not corrupt the stored undo snapshot
ds.rearDiff.preload=777

-- AWD -> FWD removes rearDiff: its settings leave the live table immediately
assert(U.applyMany(1,{{tcRow2,fwdPart}},'Drivetrain conversion'))
assert(bjiRacePrep.diffSettings[1].rearDiff==nil,'removed rear diff keeps no active settings')
assert(bjiRacePrep.diffSettings[1].transferCase==nil,'removed centre diff keeps no active settings')

-- Undo AWD -> FWD: tree, vars and the settings saved at apply-time come back
assert(U.undo(1))
assert(DrivetrainConversions.currentLayout('hawk_fm5',stateTree)=='AWD')
assert(stateTree.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName=='Camso_differential_rear_race')
assert(bjiRacePrep.diffSettings[1].rearDiff and bjiRacePrep.diffSettings[1].rearDiff.preload==777,
    'Undo restores the differential settings saved with the change')

-- Undo RWD -> AWD: back to RWD with the ORIGINAL 123 settings (snapshot survived the live edit)
assert(U.undo(1))
assert(DrivetrainConversions.currentLayout('hawk_fm5',stateTree)=='RWD')
assert(bjiRacePrep.diffSettings[1].rearDiff and bjiRacePrep.diffSettings[1].rearDiff.preload==123,
    'history snapshot is a deep copy, immune to later live-table edits')

-- direct RWD -> FWD -> Undo restores the rear LSD setup end to end
assert(U.applyMany(1,{{tcRow2,fwdPart}},'Drivetrain conversion'))
assert(bjiRacePrep.diffSettings[1].rearDiff==nil)
assert(U.undo(1))
assert(DrivetrainConversions.currentLayout('hawk_fm5',stateTree)=='RWD')
assert(bjiRacePrep.diffSettings[1].rearDiff and bjiRacePrep.diffSettings[1].rearDiff.preload==123,
    'RWD -> FWD -> Undo restores the original rear LSD settings')
assert(stateTree.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName=='Camso_differential_rear_race')

-- ordinary (non-conversion) Undo still works and leaves diff settings alone
assert(U.undo(1)) -- undoes the Race rear diff part fit
assert(stateTree.children.Camso_suspension_R.children.Camso_differential_rear.chosenPartName==fm5Info.stockRearDiff)
bjiRacePrep=nil
print('PASS: differential settings preserved, pruned and restored through conversion + Undo')

-- 4. Verify rating formula responds to driven-layout changes (FWD vs RWD vs AWD) using real seed constants
local seed=readJson('/lua/ge/extensions/raceprep/ratings-seed.json')
local sampleSt={
    mass=1300,comY=0.1,
    geometry={cogHeight=0.50,wheelbase=2.70,trackF=1.55},
    suspension={springF=45000,springR=45000,barF=3000,barR=2500},
    engines={{name='mainEngine',type='camsoEngine',maxRPM=7500,maxPowerRPM=6500,
        torque={{0,0},{1000,260},{2500,340},{4500,390},{6500,370},{7500,310}}}},
    wheels={
        {name='FL',y=-1.35,radius=0.33,tireWidth=0.245,noLoadCoef=1.35,fullLoadCoef=1.1,loadSensitivitySlope=-0.0001,brakeTorque=2400},
        {name='FR',y=-1.35,radius=0.33,tireWidth=0.245,noLoadCoef=1.35,fullLoadCoef=1.1,loadSensitivitySlope=-0.0001,brakeTorque=2400},
        {name='RL',y=1.35,radius=0.33,tireWidth=0.245,noLoadCoef=1.35,fullLoadCoef=1.1,loadSensitivitySlope=-0.0001,brakeTorque=1800},
        {name='RR',y=1.35,radius=0.33,tireWidth=0.245,noLoadCoef=1.35,fullLoadCoef=1.1,loadSensitivitySlope=-0.0001,brakeTorque=1800},
    },
    gearboxes={{name='gearbox',type='dctGearbox',forward={3.2,2.1,1.5,1.15,0.92,0.75}}},
    finalDrives={{name='rearDiff',ratio=4.10}},
    aero={downforceTargetFront=40,downforceTargetRear=60,targetSpeedKMH=200,vehicleArea=0.62},
}
local piFWD=assert(Rating.compute(sampleSt,seed.constants,'FWD'))
local piRWD=assert(Rating.compute(sampleSt,seed.constants,'RWD'))
local piAWD=assert(Rating.compute(sampleSt,seed.constants,'AWD'))
assert(piFWD.pi~=piRWD.pi and piAWD.pi~=piFWD.pi,'rating must reflect driven layout (FWD='..piFWD.pi..', RWD='..piRWD.pi..', AWD='..piAWD.pi..')')
local perfFWD=assert(Rating.performance(sampleSt,seed.constants,'FWD'))
local perfAWD=assert(Rating.performance(sampleSt,seed.constants,'AWD'))
assert(perfAWD.zeroTo60<perfFWD.zeroTo60,'AWD traction improves 0-60 mph vs FWD')

print('PASS: drivetrain conversions shop list, differential unlock, factory rules, Undo/Stock restore and PI recalculation')
