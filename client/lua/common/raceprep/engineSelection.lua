-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local S={}
local Effects=require('common/raceprep/engineEffects')
local catalog
function S.catalog()
    if not catalog then catalog=jsonDecode(readFile('/lua/common/raceprep/engine-parts.json')) end
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
    return c.models[model]
end
function S.spec(model,parts,vars,data)
    local info=S.info(model,parts)
    if not info then return nil end
    local spec={stockRevLimit=info.stockRevLimit,stockInertia=info.stockInertia,stockForcedInduction=info.stockForcedInduction}
    for _,name in pairs(parts or {}) do
        local p=info.parts[name]
        if p then for k,value in pairs(p.effect) do spec[k]=value end end
    end
    -- Compiled generated-part data supports newly introduced wheel/engine
    -- parts without guessing effects from display labels.
    for k,value in pairs((data or {}).raceprepEngine or {}) do spec[k]=value end
    vars=vars or {}
    spec.ecuGain=tonumber(vars['$rpECUGain']) and tonumber(vars['$rpECUGain'])/100 or spec.ecuGain or 1
    spec.camGain=tonumber(vars['$rpCamGain']) and tonumber(vars['$rpCamGain'])/100 or spec.camGain or 1
    spec.boostGain=tonumber(vars['$rpBoostGain']) and tonumber(vars['$rpBoostGain'])/100 or spec.boostGain or 1
    spec.antiLag=spec.inductionRace and (tonumber(vars['$rpAntiLag']) or tonumber(spec.antiLag) or 0)>=.5
    local ok,reason=Effects.required(spec)
    if not ok then return nil,reason end
    return spec
end
return S
