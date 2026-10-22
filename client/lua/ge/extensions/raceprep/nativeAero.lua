-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Native (BeamNG) car aero for the rating (formula v7). Native cars carry no
-- Automation aero data: their drag and downforce come from mesh triangles.
-- native-aero.json holds the engine's own force on each factory config under
-- a 200 km/h headwind (static probe, tools/build_native_aero.py) and the parts
-- carrying its aero triangles. A custom build uses the factory config of the
-- same model whose aero parts match best (ties: alphabetical, so stable).
local M={}
local data
local function load()
    if data==nil then
        data=jsonReadFile and jsonReadFile('/lua/ge/extensions/raceprep/native-aero.json') or false
        for _,m in pairs(data and data.models or {}) do
            m.vocab={} for _,p in ipairs(m.parts or {}) do m.vocab[p]=true end
        end
    end
    return data
end
local function result(c,source)
    return {cdA=c.cdA,dfF200=c.dfF200,dfR200=c.dfR200,source=source}
end
-- nearest-config results per model + aero-part set (computed once per build)
local nearCache={}
--- probed aero for model/config, else the closest factory config by aero parts
function M.lookup(model,config,parts)
    local d=load()
    local m=d and d.models and d.models[model]
    if not m then return nil end
    local exact=m.configs[tostring(config or ''):lower()]
    if exact then return result(exact,'probe') end
    local have,haveN,list={},0,{}
    for _,p in pairs(parts or {}) do if m.vocab[p] and not have[p] then have[p]=true;haveN=haveN+1;list[#list+1]=p end end
    table.sort(list)
    local key=model..'|'..table.concat(list,',')
    if nearCache[key] then return nearCache[key] end
    local best,bestName,bestScore
    local names={} for name in pairs(m.configs) do names[#names+1]=name end
    table.sort(names)
    for _,name in ipairs(names) do
        local c=m.configs[name]
        local inter=0
        for _,ix in ipairs(c.aeroParts or {}) do if have[m.parts[ix+1]] then inter=inter+1 end end
        local union=#(c.aeroParts or {})+haveN-inter
        local score=union>0 and inter/union or 0
        if not bestScore or score>bestScore then best,bestName,bestScore=c,name,score end
    end
    if not best then return nil end
    nearCache[key]=result(best,string.format('nearest factory config %s (aero parts %.0f%% alike)',bestName,bestScore*100))
    return nearCache[key]
end
M._reset=function() data=nil;nearCache={} end
return M
