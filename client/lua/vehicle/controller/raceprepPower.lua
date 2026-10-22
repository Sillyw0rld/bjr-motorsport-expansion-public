-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- A part-installed controller loads the vehicle extension after powertrain init.
local M={type='auxiliary',init=function() end}
local function apply()
    extensions.load('raceprepPower')
    if extensions.raceprepPower then extensions.raceprepPower.apply() end
end
M.initLastStage=apply
M.reset=apply
return M
