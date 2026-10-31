-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S={}
local Effects=require('common/raceprep/engineEffects')
local catalog
local potentialSettings
function S.configure(settings) potentialSettings=Effects.settings(settings) end
function S.settings() return potentialSettings or Effects.settings() end
function S.catalog()
    if not catalog then
        local raw=readFile and readFile('/lua/common/raceprep/engine-parts.json')
        catalog=raw and jsonDecode(raw) or {models={}}
    end
    return catalog
end
-- A conversion selects the donor's upgrade definitions, not the recipient's.
-- Native combustionEngine donors already implement their own part effects.
function S.info(model,parts)
    local c=S.catalog()
    for _,name in pairs(parts or {}) do
        local swap=(c.swaps or {})[name]
        if swap then return swap.engineInfo end
        if type(name)=='string' and name:match('^rp_swap_.*_engine$') then return nil end
    end
    local modelInfo=(c.models or {})[model]
    if modelInfo then return modelInfo end
    for _,name in pairs(parts or {}) do
        if (c.nativeEngines or {})[name] then return c.nativeEngines[name] end
    end
end
function S.spec(model,parts,vars,data)
    local info=S.info(model,parts)
    if not info then return nil end
    local spec={stockRevLimit=info.stockRevLimit,stockInertia=info.stockInertia,stockForcedInduction=info.stockForcedInduction,
        potentialEnabled=true,layout=info.layout,litres=info.litres,potentialSettings=potentialSettings or Effects.settings(),engineID=info.stockEngine}
    for _,name in pairs(parts or {}) do
        local p=(info.parts or {})[name]
        if p then for k,value in pairs(p.effect) do spec[k]=value end end
    end
    -- Compiled generated-part data supports newly introduced wheel/engine
    -- parts without guessing effects from display labels.
    if not info.native then
        for k,value in pairs((data or {}).raceprepEngine or {}) do spec[k]=value end
    end
    -- Factory capability is metadata; a removed charger must not select the
    -- forced ceiling. Compiled data is authoritative for runtime and drafts.
    if not info.native then
        for _,p in pairs((data or {}).powertrain or {}) do
            if p.type=='camsoEngine' then
                local engine=data[p.name] or {}
                spec.stockForcedInduction=(engine.turbocharger and type(data[engine.turbocharger])=='table') or
                    (engine.supercharger and type(data[engine.supercharger])=='table') or false
            end
        end
    end
    if info.native then
        spec.native=true
        for _,p in pairs((data or {}).powertrain or {}) do
            local engine=(data or {})[p.name] or {}
            if p.type=='combustionEngine' then
                spec.fittedForcedInduction=(engine.turbocharger and type(data[engine.turbocharger])=='table') or
                    (engine.supercharger and type(data[engine.supercharger])=='table') or false
            end
        end
    end
    vars=vars or {}
    spec.ecuGain=tonumber(vars['$rpECUGain']) and tonumber(vars['$rpECUGain'])/100 or spec.ecuGain or 1
    spec.camGain=tonumber(vars['$rpCamGain']) and tonumber(vars['$rpCamGain'])/100 or spec.camGain or 1
    spec.boostGain=tonumber(vars['$rpBoostGain']) and tonumber(vars['$rpBoostGain'])/100 or spec.boostGain or 1
    -- Only the fitted Race factory-boost part owns this setup variable.
    if spec.induction=='stock_upgrade' and spec.inductionRace then
        spec.factoryBoostTarget=tonumber(vars['$rpFactoryBoost']) or tonumber((data or{}).raceprepEngine and data.raceprepEngine.factoryBoostTarget)
    end
    spec.antiLag=spec.inductionRace and (tonumber(vars['$rpAntiLag']) or tonumber(spec.antiLag) or 0)>=.5
    local ok,reason=Effects.required(spec)
    if not ok then return nil,reason end
    return spec
end
return S
