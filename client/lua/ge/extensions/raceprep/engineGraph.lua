-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Native ImGui graph: same axes for stock/current, one panel per unit.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local G={}
function G.draw(curves)
    if not curves then return end
    local im=ui_imgui
    local width=math.max(200,im.GetContentRegionAvail().x)
    local height=135
    local origin=im.GetCursorScreenPos()
    local draw=im.GetWindowDrawList()
    local colors={im.GetColorU322(im.ImVec4(.55,.55,.55,1)),im.GetColorU322(im.ImVec4(.2,.9,.8,1))}
    local rpmMax=0
    for _,curve in ipairs({curves.stock,curves.current}) do for _,p in ipairs(curve) do rpmMax=math.max(rpmMax,p[1]) end end
    if rpmMax<=0 then return end
    for panel=1,2 do
        local x=origin.x+(panel-1)*width/2+42
        local y=origin.y+22
        local w=width/2-58
        local h=height-45
        local peak=0
        local function value(p) return panel==1 and p[2]*.73756214928 or p[1]*p[2]*math.pi/30/745.699871582 end
        for _,curve in ipairs({curves.stock,curves.current}) do for _,p in ipairs(curve) do peak=math.max(peak,value(p)) end end
        peak=math.max(1,peak)*1.05
        for line=0,4 do
            local gy=y+h-line*h/4
            im.ImDrawList_AddLine(draw,im.ImVec2(x,gy),im.ImVec2(x+w,gy),im.GetColorU322(im.ImVec4(.4,.4,.4,.35)),1)
        end
        for index,curve in ipairs({curves.stock,curves.current}) do
            local last
            for _,point in ipairs(curve) do
                local pos=im.ImVec2(x+w*point[1]/rpmMax,y+h*(1-math.max(0,value(point))/peak))
                if last then im.ImDrawList_AddLine(draw,last,pos,colors[index],index==1 and 1.5 or 2) end
                last=pos
            end
        end
        local white=im.GetColorU322(im.ImVec4(1,1,1,1))
        im.ImDrawList_AddText1(draw,im.ImVec2(x,y-19),white,panel==1 and 'Torque (lb-ft)' or 'Power (hp)')
        im.ImDrawList_AddText1(draw,im.ImVec2(x-40,y),white,string.format('%.0f',peak))
        im.ImDrawList_AddText1(draw,im.ImVec2(x,y+h+3),white,'0')
        im.ImDrawList_AddText1(draw,im.ImVec2(x+w-70,y+h+3),white,string.format('%g rpm',rpmMax))
    end
    im.Dummy(im.ImVec2(width,height))
    Text('Grey: stock | Teal: current steady dyno curve. Turbo lag affects driving, not this steady curve.',{color=BJI.Utils.Style.TEXT_COLORS.DISABLED,wrap=true})
end
return G
