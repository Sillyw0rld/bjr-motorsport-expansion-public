-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race signals for the driver (RacePrep add-on): yellow flag warning, start
-- lights and the false-start tag. Drawn at the top of the race HUD (timing
-- box) and in Race control; Race control itself only opens from the menu.
local Text = require("ge/extensions/raceprep/safeText").Text
local director = require("ge/extensions/raceprep/director")

local S = {}

local function drawLamps(l, c)
    local im = ui_imgui
    if im and im.ImDrawList_AddCircleFilled and im.GetWindowDrawList then
        local draw, pos = im.GetWindowDrawList(), im.GetCursorScreenPos()
        local function color(r, g, b) return im.ColorConvertFloat4ToU32(im.ImVec4(r, g, b, 1)) end
        im.ImDrawList_AddRectFilled(draw, pos, im.ImVec2(pos.x + 222, pos.y + 40), color(.04, .04, .04), 5, 0)
        for i = 1, 5 do
            local center = im.ImVec2(pos.x + 23 + (i - 1) * 44, pos.y + 20)
            im.ImDrawList_AddCircleFilled(draw, center, 15, color(.18, .18, .18), 32)
            local lit = l.phase == 'red' and i <= l.count
            im.ImDrawList_AddCircleFilled(draw, center, 12, lit and color(.95, .08, .03) or color(.03, .03, .03), 32)
        end
        im.Dummy(im.ImVec2(222, 44))
    else
        local lamps = {}
        for i = 1, 5 do lamps[i] = l.phase == 'green' and '[ ]' or (i <= l.count and '[RED]' or '[ ]') end
        Text(table.concat(lamps, '  '), { color = l.phase == 'green' and c.SUCCESS or c.ERROR })
    end
end

--- true when something was drawn
S.draw = function()
    local c = BJI.Utils.Style.TEXT_COLORS
    local drawn = false
    local yellow = director.yellow()
    if yellow then
        Text(yellow, { color = c.HIGHLIGHT, wrap = true })
        drawn = true
    end
    local l = director.lights
    if l then
        drawLamps(l, c)
        Text(l.phase == 'green' and 'GREEN - GO!' or l.phase == 'formation' and 'FORMATION - hold position' or
            'Hold position until the lights go out', { color = l.phase == 'green' and c.SUCCESS or c.HIGHLIGHT })
        if director.falseStart then Text('FALSE START - tagged in your result', { color = c.ERROR }) end
        drawn = true
    end
    return drawn
end

return S
