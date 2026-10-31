-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Engine conversion catalogue and parts-tree changes. Physical donor parts
-- are generated at build time; no engine mesh or drivetrain conversion.
local C={}
local catalog
function C.catalog()
    if not catalog then
        catalog=(jsonReadFile and jsonReadFile('/vehicles/rp_engine_swaps/raceprep/rp_swap_library.json')) or {models={}}
    end
    return catalog
end
function C.info(model) return C.catalog().models[model] end
function C.view(model)
    local info=C.info(model)
    if not info then return {} end
    if info._view then return info._view end
    local out={}
    for _,o in ipairs(info.options or {}) do
        if o.reason then out[#out+1]={layout=o.layout,reason=o.reason} end
    end
    info._view=out
    return out
end
local function clone(t)
    if type(t)~='table' then return t end
    local o={};for k,v in pairs(t) do o[k]=clone(v) end;return o
end
local function find(t,id)
    if t.id==id then return t end
    for key,child in pairs(t.children or {}) do
        if key==id then return child end
        local match=find(child,id);if match then return match end
    end
end
function C.option(model,name)
    local info=C.info(model);if not info then return nil end
    if name==info.stockEngine then return {part=name,structure=info.stockStructure,resetVars=info.stockDefaults,stock=true} end
    for _,o in ipairs(info.options or {}) do if o.part==name and not o.reason then return o end end
end
function C.tooltip(model,name)
    local option=C.option(model,name)
    if not option or option.stock then return nil end
    local fit=option.fit
    if fit and fit.method=='automation-bay-envelope' then
        local size=fit.limitSizeXYZ
        return string.format('Automation bay screen: %.0f × %.0f × %.0f cm usable (width × length × height), with 2 cm allowed per side. Engine orientation matches this car. Full accessory and mesh clearance has not been verified.',size[1]*100,size[2]*100,size[3]*100)
    end
    return 'Conservative original-block fit: reliable Automation bay measurements are unavailable for this pairing. Full accessory and mesh clearance has not been verified.'
end
function C.change(tree,path,name,model,vars)
    local option=C.option(model,name)
    if not option then return nil,'Engine conversion is not compatible with this car.' end
    local result=clone(tree);local node=result
    for _,id in ipairs(path) do node=node.children and node.children[id];if not node then return nil,'Engine slot changed.' end end
    local transmission=node.children and node.children.Camso_Transmission
    local structure=node.children and node.children.Camso_engine_structure
    local previous=C.option(model,node.chosenPartName)
    local tank=find(result,'Camso_FuelTank')
    local fuel=option.fuelTank
    local stockTank=C.info(model).stockFuelTank
    if fuel and not tank then return nil,'Fuel tank slot is unavailable for this conversion.' end
    if tank and (fuel or stockTank) then
        tank.chosenPartName=fuel and fuel.part or stockTank
        tank.children={}
    end
    -- Clear the recipient's optional engine hub, including any generated
    -- cam/intake/boost parts. Donor camso hubs are built into the new engine.
    local hub=find(result,'camso_tuning_parameters_engine')
    if hub then hub.chosenPartName='';hub.children={} end
    node.chosenPartName=name;node.children={}
    if transmission then node.children.Camso_Transmission=transmission end
    node.children.Camso_engine_structure={id='Camso_engine_structure',chosenPartName=option.structure,
        children=structure and structure.children or {}}
    local reset={['$rpECUGain']=100,['$rpCamGain']=100,['$rpFactoryBoost']=115,['$rpBoostGain']=100,['$rpAntiLag']=0}
    -- Reset variables from the outgoing donor too, preventing residual boost
    -- or rev-limit settings. Chassis/fuel settings and visual offsets stay put.
    for _,o in ipairs(C.info(model).options or {}) do
        for key,value in pairs(o.resetVars or {}) do reset[key]=value end
    end
    for key,value in pairs(C.info(model).stockDefaults or {}) do reset[key]=value end
    for key,value in pairs(option.resetVars or {}) do reset[key]=value end
    local newVars=clone(vars or {})
    for key,value in pairs(reset) do newVars[key]=value end
    local restore=clone(vars or {})
    for key,value in pairs(reset) do if restore[key]==nil then restore[key]=value end end
    for key,value in pairs((previous or {}).resetVars or {}) do if (vars or {})[key]==nil then restore[key]=value end end
    return result,nil,newVars,restore
end
return C
