-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Resolve canonical fixed reduction along actual engine-to-wheel paths.
-- A torsionReactor can carry the final drive on native FWD cars and EVs.
-- Never multiply reductions on parallel branches as though they were in series.
local M={}
local function positive(x)
    return type(x)=='number' and x==x and x>0 and x<math.huge
end
function M.resolve(rows,sections,driven,engineNames)
    local devices={}
    for _,row in pairs(rows or {}) do
        if not row.name or devices[row.name] then return nil,'Missing/duplicate powertrain device' end
        local d={}
        for k,v in pairs(row) do d[k]=v end
        for k,v in pairs((sections or {})[row.name] or {}) do d[k]=v end
        devices[row.name]=d
    end
    local results,seenWheels={},{}
    for _,d in pairs(devices) do
        if d.connectedWheel and driven[d.connectedWheel] then
            if seenWheels[d.connectedWheel] then return nil,'Multiple drives for wheel '..d.connectedWheel end
            seenWheels[d.connectedWheel]=true
            local ratio,visited,cur,gearboxes=1,{},d,0
            while cur and not engineNames[cur.name] do
                if visited[cur.name] then return nil,'Powertrain cycle at '..cur.name end
                visited[cur.name]=true
                if tostring(cur.type):lower():find('gearbox',1,true) then
                    gearboxes=gearboxes+1
                elseif cur.gearRatio~=nil then
                    if not positive(cur.gearRatio) then return nil,'Invalid fixed ratio at '..cur.name end
                    ratio=ratio*cur.gearRatio
                end
                cur=devices[cur.inputName]
            end
            if not cur then return nil,'Incomplete wheel path: '..d.connectedWheel end
            if gearboxes>1 then return nil,'Multiple gearboxes on wheel path: '..d.connectedWheel end
            if not positive(ratio) then return nil,'Invalid effective final drive' end
            results[#results+1]={wheel=d.connectedWheel,engine=cur.name,ratio=ratio,gearboxes=gearboxes}
        end
    end
    for name,enabled in pairs(driven or {}) do
        if enabled and not seenWheels[name] then return nil,'No powertrain path for driven wheel '..name end
    end
    if #results==0 then return nil,'No driven-wheel paths' end
    table.sort(results,function(a,b) return a.wheel<b.wheel end)
    local lo,hi=math.huge,0
    for _,path in ipairs(results) do lo,hi=math.min(lo,path.ratio),math.max(hi,path.ratio) end
    -- The existing v6 evaluator uses one final-drive ratio. Report unequal
    -- branches explicitly instead of silently replacing them with a maximum.
    if hi-lo>math.max(1e-6,hi*1e-5) then
        return nil,'Unequal wheel-path reductions require per-branch evaluation',results
    end
    return {{name='nativeEffectiveFinalDrive',ratio=lo}},nil,results
end
return M
