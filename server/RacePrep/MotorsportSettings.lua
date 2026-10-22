-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Server-wide Motorsport settings (motorsport.json; Motorsport settings tab):
-- who may do what, by BeamJoy group, and the race weekend defaults.
--
-- permissions: the lowest BeamJoy group allowed, or "everyone":
--   weekend      start, advance and end a race weekend (default mod and up)
--   rules        edit race rules and track settings (default admin and up)
--   raceControl  full-course yellow and other race control (default mod and up)
-- Groups rank in BeamJoy's own order (groups.json: default, player, vip, mod,
-- admin, owner); the last group (the owner) is always allowed.
-- weekend: default practice / qualifying minutes, grid order, and where the
-- grid order comes from ("rules": the race's rules; "weekend": chosen when the
-- weekend starts, the race's rule preselected).
-- Plain Lua 5.1 (no BeamMP API), so it runs in tests too.
local M = {}

M.ACTIONS = { "weekend", "rules", "raceControl" }
M.GRID_ORDERS = { "join", "qualifying", "reverse", "handicap" }
M.DEFAULTS = {
    permissions = { weekend = "mod", rules = "admin", raceControl = "mod" },
    weekend = { practiceMinutes = 10, qualifyingMinutes = 10, gridOrder = "qualifying", gridSource = "rules" },
}

local function oneOf(value, list, fallback)
    for _, v in ipairs(list) do if v == value then return value end end
    return fallback
end

--- group names in rank order, from groups.json's list (BeamJoy's own order)
function M.groupNames(groups)
    local out = {}
    for _, g in ipairs(type(groups) == "table" and groups or {}) do
        if type(g) == "table" and type(g.name) == "string" and g.name ~= "" then out[#out + 1] = g.name end
    end
    if #out == 0 then out = { "default", "player", "vip", "mod", "admin", "owner" } end
    return out
end

--- keeps known keys with valid values (group names checked against groups)
function M.sanitize(input, groups)
    input = type(input) == "table" and input or {}
    local names = M.groupNames(groups)
    local allowedNames = { "everyone" }
    for _, n in ipairs(names) do allowedNames[#allowedNames + 1] = n end
    local p = type(input.permissions) == "table" and input.permissions or {}
    local w = type(input.weekend) == "table" and input.weekend or {}
    local out = { schema = 1, permissions = {}, weekend = {} }
    for _, action in ipairs(M.ACTIONS) do
        out.permissions[action] = oneOf(p[action], allowedNames, M.DEFAULTS.permissions[action])
    end
    local function minutes(v, d)
        v = tonumber(v)
        if not v or v ~= v then return d end
        return math.floor(math.max(0, math.min(120, v)))
    end
    out.weekend.practiceMinutes = minutes(w.practiceMinutes, M.DEFAULTS.weekend.practiceMinutes)
    out.weekend.qualifyingMinutes = minutes(w.qualifyingMinutes, M.DEFAULTS.weekend.qualifyingMinutes)
    out.weekend.gridOrder = oneOf(w.gridOrder, M.GRID_ORDERS, M.DEFAULTS.weekend.gridOrder)
    out.weekend.gridSource = oneOf(w.gridSource, { "rules", "weekend" }, M.DEFAULTS.weekend.gridSource)
    return out
end

--- a group's rank (1 = lowest); unknown or missing = 0
function M.rank(groups, name)
    for i, n in ipairs(M.groupNames(groups)) do if n == name then return i end end
    return 0
end

--- may a player of this BeamJoy group do this action?
function M.allowed(settings, action, playerGroup, groups)
    local need = settings and settings.permissions and settings.permissions[action] or M.DEFAULTS.permissions[action]
    if need == "everyone" then return true end
    local names = M.groupNames(groups)
    local mine = M.rank(groups, playerGroup)
    if mine == 0 then return false end
    if mine == #names then return true end -- the owner group
    return mine >= M.rank(groups, need)
end

return M
