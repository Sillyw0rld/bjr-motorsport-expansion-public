-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local M={type='auxiliary',init=function() end}
local function apply()
    extensions.load('raceprepWeight')
    if extensions.raceprepWeight then extensions.raceprepWeight.apply() end
end
M.initLastStage=apply
M.resetLastStage=apply
return M
