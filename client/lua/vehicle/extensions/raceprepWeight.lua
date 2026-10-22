-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- A native body's fixed scalenodeWeight scales the dry nodes at compile time.
-- Fuel tanks add their contents afterwards, so scale only their public node-
-- mass coefficient as well. Fuel volume, energy and consumption stay intact.
-- No base-game file changes or function replacement; every apply uses a copy
-- of the storage's original coefficient, including after a physics reset.
local M={}
function M.apply(scale)
    scale=tonumber(scale or (v and v.data and v.data.raceprepBody or {}).scale)
    -- The compiled JBeam value can travel through a float32 field. Compare
    -- within its precision, then use the exact intended stage multiplier.
    local stage
    if scale then
        for _,target in ipairs({1,.96,.93,.85}) do
            if math.abs(scale-target)<1e-6 then stage=target;break end
        end
    end
    if not stage then
        M.lastError='Unsupported native body scale'
        return false
    end
    for _,storage in pairs(energyStorage.getStorages() or {}) do
        if storage.type=='fuelTank' and type(storage.fuelNodeMassCoef)=='number' then
            if storage._raceprepWeightBase==nil then storage._raceprepWeightBase=storage.fuelNodeMassCoef end
            storage.fuelNodeMassCoef=storage._raceprepWeightBase*stage
            if storage.updateGFX then storage:updateGFX(0) end
        end
    end
    M.lastError=nil
    return true
end
return M
