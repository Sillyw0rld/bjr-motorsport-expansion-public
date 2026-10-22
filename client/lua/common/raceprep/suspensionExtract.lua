-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Preserve the existing named-spring path and read unnamed native sway bars
-- only when their JBeam provenance identifies a front/rear sway-bar part.
local M={}
function M.extract(vd)
    local springs,bars,sources={},{},{}
    for _,b in pairs(vd.beams or {}) do
        if type(b.name)=='string' and b.name:match('^spring_[FR][LR]$') and tonumber(b.beamSpring) then
            springs[b.name]=tonumber(b.beamSpring)
        end
    end
    for _,t in pairs(vd.torsionbars or {}) do
        local value=tonumber(t.spring)
        if value then
            if type(t.name)=='string' then
                bars[t.name]=value
            elseif value>0 then
                local origin=tostring(t.partOrigin or '')
                local axle=origin:match('_swaybar_([FR])_') or origin:match('_swaybar_([FR])$')
                if axle then
                    local key=axle=='F' and 'torsionBarFront' or 'torsionBarRear'
                    bars[key]=(bars[key] or 0)+value
                    sources[#sources+1]={axle=axle,partOrigin=origin,spring=value}
                end
            end
        end
    end
    return {springs=springs,bars=bars,nativeBarSources=#sources>0 and sources or nil}
end
return M
