-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Factory engine settings for the rating (owner rules, 2026-10-16/17).
-- Tuning never changes PI, but a factory config's own boost pressure and rev
-- limit are part of the engine as built: BeamNG's hillclimb SBR ships at 24 psi
-- (slider default 12), the Midsize race revs to 8500 rpm (default 6000, which
-- cut its 301 hp to 215). Automation cars: stock until changed with Race Prep.
-- The rating copy keeps only these factory values; the player's own sliders,
-- and every other tuning value (gearing, final drive...), still never count.
local M={}
M.PATTERNS={'^%$wastegate','^%$revLimiterRPM$'}
local function kept(k)
    for _,p in ipairs(M.PATTERNS) do if k:match(p) then return true end end
    return false
end
-- one .pc read per factory config per session (factory files do not change)
local pcCache={}
local function factoryVars(model,config)
    local key=tostring(model)..'/'..tostring(config)
    if pcCache[key]~=nil then return pcCache[key] or nil end
    local vars=nil
    local info=core_vehicles and core_vehicles.getConfig and core_vehicles.getConfig(model,config)
    -- user-saved configs are 'Custom'; official and mod factory configs count
    if type(info)=='table' and info.Source~='Custom' and type(info.pcFilename)=='string' then
        local pc=jsonReadFile and jsonReadFile(info.pcFilename)
        vars=type(pc)=='table' and type(pc.vars)=='table' and pc.vars or {}
    end
    pcCache[key]=vars or false
    return vars
end
M._reset=function() pcCache={} end
--- {['$wastegateStart']=24,['$revLimiterRPM']=8500} for model/config; a saved setup uses the
--- factory config it was saved from
function M.vars(model,config,savedFrom)
    local vars=factoryVars(model,config)
    if not vars and savedFrom then vars=factoryVars(model,savedFrom) end
    local out={}
    for k,v in pairs(vars or {}) do
        if type(k)=='string' and kept(k) and tonumber(v) then out[k]=tonumber(v) end
    end
    return out
end
return M
