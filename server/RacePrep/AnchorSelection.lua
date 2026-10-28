-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Choose a measured baseline reproducibly when a model has multiple configs.
-- Config identity takes priority; renamed saved setups use closest stock parts.
-- An ambiguous match stays unanchored instead of depending on pairs() order.
local M={}
local function eligible(e,model)
    return e and e.model==model and type(e.formula)=='table' and e.source~='computed' and tonumber(e.pi)
end
local function weight(path)
    path=path:lower()
    return (path:find('engine',1,true) or path:find('transmission',1,true) or
        path:find('gearbox',1,true) or path:find('finaldrive',1,true)) and 8 or 1
end
local function stockParts(parts)
    local out={}
    for path,part in pairs(parts or {}) do
        if type(path)=='string' and type(part)=='string' and part~='' and not part:match('^rp_') then out[path]=part end
    end
    return out
end
local function similarity(a,b)
    local match,total=0,0
    for path,part in pairs(a) do
        local w=weight(path);total=total+w
        if b[path]==part then match=match+w end
    end
    for path in pairs(b) do if not a[path] then total=total+weight(path) end end
    return total>0 and match/total or 0
end
function M.select(seed,model,config,parts)
    local entries=seed.entries or {}
    local preferred=config and seed.baselines and seed.baselines[model..'/'..config]
    if preferred and eligible(entries[preferred],model) then return entries[preferred],preferred end
    local candidates={}
    for key,e in pairs(entries) do
        if eligible(e,model) then candidates[#candidates+1]={key=key,entry=e} end
    end
    table.sort(candidates,function(a,b) return a.key<b.key end)
    if #candidates==1 then return candidates[1].entry,candidates[1].key end
    local exact={}
    for _,c in ipairs(candidates) do if config and c.entry.config==config then exact[#exact+1]=c end end
    if #exact==1 then return exact[1].entry,exact[1].key end
    if #exact>1 then candidates=exact end
    local installed=stockParts(parts)
    local best,score,ambiguous=nil,0,false
    for _,c in ipairs(candidates) do
        local value=similarity(installed,stockParts(c.entry.parts))
        if value>score+1e-9 then best,score,ambiguous=c,value,false
        elseif value>0 and math.abs(value-score)<=1e-9 then ambiguous=true end
    end
    if best and not ambiguous then return best.entry,best.key end
end
return M
