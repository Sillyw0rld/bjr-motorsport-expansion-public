-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race weekend (Race weekend tab): practice, then qualifying, then the race,
-- on one BeamJoy race. Sessions.lua times each session; this module only
-- decides what comes next.
--
-- stage: practice | qualifying | grid | race | ended
--   practice ends    -> qualifying starts at once (or the grid, with no qualifying)
--   qualifying ends  -> grid: drivers on a lap finish it (Sessions' grace), then
--                       everyone sees the grid; staff open the race lobby (BJR's
--                       API cannot open one for a plugin)
--   the race starts  -> race (BJR's countdown on this race)
--   the race ends    -> ended; its qualifying result no longer sets grids
-- Plain Lua 5.1 (no BeamMP API), so it runs in tests too.
local W = {}

W.STAGES = { practice = "Practice", qualifying = "Qualifying", grid = "Grid", race = "Race", ended = "Ended" }

--- o = {raceID, level, raceName, practiceMinutes, qualifyingMinutes,
---      gridOrder (nil = the race's rules), by (player name)}
function W.new(o, now)
    local function minutes(v) v = tonumber(v) or 0; return math.floor(math.max(0, math.min(120, v))) end
    return {
        raceID = tostring(o.raceID), level = o.level, raceName = o.raceName,
        practiceMinutes = minutes(o.practiceMinutes), qualifyingMinutes = minutes(o.qualifyingMinutes),
        gridOrder = o.gridOrder, by = o.by, startedAt = now, stage = nil, grid = nil,
    }
end

--- the first stage: "practice" / "qualifying" with minutes, else "grid"
function W.first(w)
    if w.practiceMinutes > 0 then return "practice", w.practiceMinutes end
    if w.qualifyingMinutes > 0 then return "qualifying", w.qualifyingMinutes end
    return "grid"
end

--- the stage after a session of this kind ended (or was skipped)
function W.after(w, kind)
    if kind == "practice" and w.qualifyingMinutes > 0 then return "qualifying", w.qualifyingMinutes end
    return "grid"
end

--- BJR started this race's countdown / finished it
function W.raceStarted(w, raceID)
    if w and w.stage == "grid" and tostring(raceID) == w.raceID then w.stage = "race"; return true end
    return false
end
function W.raceFinished(w, raceID)
    if w and (w.stage == "race" or w.stage == "grid") and tostring(raceID) == w.raceID then w.stage = "ended"; return true end
    return false
end

--- what clients get; grid = {{pos, playerID, name}} once qualifying is over
function W.view(w)
    if not w then return nil end
    return {
        raceID = w.raceID, level = w.level, raceName = w.raceName, stage = w.stage, label = W.STAGES[w.stage],
        practiceMinutes = w.practiceMinutes, qualifyingMinutes = w.qualifyingMinutes,
        gridOrder = w.gridOrder, by = w.by, grid = w.grid,
    }
end

--- the grid list for clients from Sessions.gridOrder's entries
function W.gridList(order)
    local out = {}
    for i, e in ipairs(order or {}) do out[i] = { pos = i, playerID = e.playerID, name = e.name } end
    return out
end

return W
