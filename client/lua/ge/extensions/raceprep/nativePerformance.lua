-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Config-specific performance anchors for native cars only.
local M={}
local cachedCars,cachedIndex
local function index(cars)
    if cachedCars==cars then return cachedIndex end
    local out={entries={},baselines={}}
    for key,e in pairs(cars or {}) do
        if e.native==true and type(e.vehicleModel)=='string' and type(e.config)=='string' then
            out.entries[key]={model=e.vehicleModel,config=e.config,parts=e.parts,
                source='measured',pi=100,formula={},performance=e}
            out.baselines[e.vehicleModel..'/'..e.config:lower()]=key
        end
    end
    cachedCars,cachedIndex=cars,out
    return out
end
function M.select(cars,model,config,parts)
    local i=index(cars)
    local key=i.baselines[model..'/'..tostring(config or ''):lower()]
    if key then return i.entries[key].performance,key end
    local entry,k=require('ge/extensions/raceprep/anchorSelection').select(i,model,nil,parts)
    return entry and entry.performance,k
end
return M
