-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Drivetrain conversion catalogue and parts-tree changes (FWD, RWD, AWD).
-- Generated from the approved Elver drivetrain donors; preserves the fitted
-- engine (stock or converted), engine upgrades, transmission and gearing.
local D={}
local catalog
function D.catalog()
    if not catalog then
        catalog=(jsonReadFile and jsonReadFile('/vehicles/rp_drivetrain_conversions/raceprep/rp_drivetrain_library.json')) or {models={}}
    end
    return catalog
end
function D.info(model) return D.catalog().models[model] end
function D.view(model)
    local info=D.info(model)
    if not info then return {} end
    if info._view then return info._view end
    local out={}
    for _,o in ipairs(info.options or {}) do
        if o.reason and o.layout~=info.stockDrive then
            out[#out+1]={layout=o.layout,reason=o.reason}
        end
    end
    info._view=out
    return out
end
local function clone(t)
    if type(t)~='table' then return t end
    local o={};for k,v in pairs(t) do o[k]=clone(v) end;return o
end
local function find(t,id)
    if type(t)~='table' then return nil end
    if t.id==id then return t end
    for key,child in pairs(t.children or {}) do
        if key==id then return child end
        local match=find(child,id);if match then return match end
    end
end
function D.option(model,name)
    local info=D.info(model);if not info or not name or name=='' then return nil end
    if name==info.stockTransferCase then
        return {
            part=name,
            layout=info.stockDrive,
            frontDiff=info.stockFrontDiff or '',
            rearDiff=info.stockRearDiff or '',
            finalDriveRatio=info.stockFinalDrive,
            resetVars=info.stockDefaults or {},
            stock=true,
            title='Stock drivetrain ('..tostring(info.stockDrive)..')',
        }
    end
    for _,o in ipairs(info.options or {}) do
        if o.part==name and not o.reason then return o end
    end
end
function D.currentLayout(model,tree,activeParts)
    local info=D.info(model)
    local tcNode=tree and find(tree,'Camso_TransferCase')
    local tcPart=tcNode and tcNode.chosenPartName
    if (not tcPart or tcPart=='') and type(activeParts)=='table' then
        for slot,partName in pairs(activeParts) do
            if tostring(slot):find('Camso_TransferCase',1,true) then tcPart=partName;break end
        end
    end
    local opt=tcPart and D.option(model,tcPart)
    if opt and opt.layout then return opt.layout end
    if tcPart then
        local u=tostring(tcPart):upper()
        if u:find('AWD',1,true) or u:find('4WD',1,true) then return 'AWD' end
        if u:find('FWD',1,true) then return 'FWD' end
        if u:find('RWD',1,true) then return 'RWD' end
    end
    return info and info.stockDrive or nil
end
--- Preserve the fitted Camso_TransferCase subtree when Camso_Transmission is replaced.
function D.carry(oldTree,newTree)
    local oldTC=oldTree and find(oldTree,'Camso_TransferCase')
    local newTrans=newTree and find(newTree,'Camso_Transmission')
    if oldTC and newTrans then
        newTrans.children=newTrans.children or {}
        if not newTrans.children.Camso_TransferCase or (newTrans.children.Camso_TransferCase.chosenPartName or '')=='' then
            newTrans.children.Camso_TransferCase=clone(oldTC)
        end
    end
    return newTree
end
local function ensureAxleSlot(root,suspId,slotId)
    local node=find(root,slotId)
    if node then return node end
    local susp=find(root,suspId)
    if susp then
        susp.children=susp.children or {}
        susp.children[slotId]={id=slotId,chosenPartName='',children={}}
        return susp.children[slotId]
    end
end
function D.change(tree,path,name,model,vars)
    local info=D.info(model)
    local option=D.option(model,name)
    if not info or not option then return nil,'Drivetrain conversion is not compatible with this car.' end
    local result=clone(tree);local node=result
    for _,id in ipairs(path or {}) do
        node=node.children and node.children[id]
        if not node then return nil,'Transfer case slot changed.' end
    end
    local previous=D.option(model,node.chosenPartName)
    node.chosenPartName=name;node.children={}
    if option.centerDiffSlot and option.defaultCenterDiff then
        node.children[option.centerDiffSlot]={
            id=option.centerDiffSlot,
            chosenPartName=option.defaultCenterDiff,
            children={},
        }
    end
    local front=ensureAxleSlot(result,'Camso_suspension_F','Camso_differential_front')
    if front then
        if option.layout=='RWD' then
            front.chosenPartName='';front.children={}
        elseif option.stock then
            if front.chosenPartName~=option.frontDiff then
                front.chosenPartName=option.frontDiff or '';front.children={}
            end
        elseif (front.chosenPartName or '')=='' then
            front.chosenPartName=option.frontDiff or info.defaultFrontDiff or '';front.children={}
        end
    end
    local rear=ensureAxleSlot(result,'Camso_suspension_R','Camso_differential_rear')
    if rear then
        if option.layout=='FWD' then
            rear.chosenPartName='';rear.children={}
        elseif option.stock then
            if rear.chosenPartName~=option.rearDiff then
                rear.chosenPartName=option.rearDiff or '';rear.children={}
            end
        elseif (rear.chosenPartName or '')=='' then
            rear.chosenPartName=option.rearDiff or info.defaultRearDiff or '';rear.children={}
        end
    end
    local reset={}
    for _,o in ipairs(info.options or {}) do
        for k,v in pairs(o.resetVars or {}) do reset[k]=v end
    end
    for k,v in pairs(info.stockDefaults or {}) do reset[k]=v end
    for k,v in pairs(option.resetVars or {}) do reset[k]=v end
    local newVars=clone(vars or {})
    for k,v in pairs(reset) do newVars[k]=v end
    local restore=clone(vars or {})
    for k,v in pairs(reset) do if restore[k]==nil then restore[k]=v end end
    for k,v in pairs((previous or {}).resetVars or {}) do if (vars or {})[k]==nil then restore[k]=v end end
    return result,nil,newVars,restore
end
return D
