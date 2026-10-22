-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Canonical/live rating input copied without changing the physics vehicle.
local M={}
function M.build(i,vd,live,vars,upgradeCatalog)
    -- A compact shadow table is transferred to the vehicle VM. Physics, actual
    -- fuel, drive mode, tuning and the live powertrain are never changed.
    local data={nodes={},wheels={},powertrain=vd.powertrain,vehicleController=vd.vehicleController,
        downforceModel=vd.downforceModel,dragModel=vd.dragModel,raceprepPower=vd.raceprepPower,raceprepAero=vd.raceprepAero}
    data.model=i.model
    data.engineSpec=require('common/raceprep/engineSelection').spec(i.model,vd.activeParts,vars or {},vd)
    for cid,n in pairs(vd.nodes) do data.nodes[cid]={nodeWeight=n.nodeWeight,pos=n.pos} end
    -- formula v6: springs and sway bars of the fitted parts at their default
    -- settings (this bundle was compiled with no tuning vars: tuning never
    -- changes PI)
    data.suspension=require('common/raceprep/suspensionExtract').extract(vd)
    data.refNodes=vd.refNodes
    local compounds,gripScale,brakeScale={},{},{}
    for _,axle in ipairs({'front','rear'}) do
        local stock=upgradeCatalog.stocks and upgradeCatalog.stocks[i.model..'/'..axle]
        if stock then compounds[axle]=stock.compound end
    end
    for _,partName in pairs(i.parts or {}) do
        local part=upgradeCatalog.parts and upgradeCatalog.parts[partName]
        if part and part.kind=='tyre' then
            if part.compound~='stock' then compounds[part.axle]=part.compound end
            -- Super Soft: Soft's Automation grip plus the tyre simulation's
            -- extra (1.05x against Soft's 1.03x), counted in the rating
            if tonumber(part.ratingGripScale) then gripScale[part.axle]=tonumber(part.ratingGripScale) end
        elseif part and part.kind=='brake' and tonumber(part.ratingBrakeScale) and not live then
            -- race brakes: rated at their best Brake Power (150 %), like other race parts
            brakeScale[part.axle]=tonumber(part.ratingBrakeScale)
        end
    end
    for cid,w in pairs(vd.wheels or {}) do
        local axle=tostring(w.name):sub(1,1)=="F" and "front" or "rear"
        local scale=gripScale[axle] or 1
        data.wheels[cid]={name=w.name,node1=w.node1,node2=w.node2,
        radius=w.radius,tireWidth=w.tireWidth,noLoadCoef=w.noLoadCoef and w.noLoadCoef*scale,brakeTorque=w.brakeTorque and w.brakeTorque*(brakeScale[axle] or 1),
        fullLoadCoef=w.fullLoadCoef and w.fullLoadCoef*scale,loadSensitivitySlope=w.loadSensitivitySlope,frictionCoef=w.frictionCoef,
        abs=(w.enableABS or w.enableABSactuator) and true or false,
        compound=compounds[axle]} end
    for _,p in pairs(vd.powertrain or {}) do
        if vd[p.name] then data[p.name]=vd[p.name] end
        local jd=vd[p.name] or {}
        for _,field in ipairs({'turbocharger','supercharger','nitrousOxideInjection'}) do
            if jd[field] then data[jd[field]]=vd[jd[field]] end
        end
    end
    data.statsLive=live or nil
    return data
end
return M
