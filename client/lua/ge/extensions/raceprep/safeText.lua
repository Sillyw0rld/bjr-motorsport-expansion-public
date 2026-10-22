-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BeamJoy's Text/TooltipText pass the string to ImGui as a printf format, so
-- a "%" in Race Prep text ("20 %", "+8 % downforce") printed garbage from
-- memory. Race Prep windows use these wrappers: "%" is escaped to "%%".
local M = {}

local function escape(text)
    return (tostring(text):gsub("%%", "%%%%"))
end
M.escape = escape

M.Text = function(text, data)
    return Text(escape(text), data)
end

M.TooltipText = function(text)
    if TooltipText then
        return TooltipText(text ~= nil and escape(text) or nil)
    end
end

return M
