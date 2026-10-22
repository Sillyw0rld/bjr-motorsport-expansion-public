-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Standings tower for BeamJoy multiplayer races (RacePrep add-on): position,
-- driver, interval to the car ahead (or gap to the leader), lap, best lap.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local timing = require("ge/extensions/raceprep/timing")
local classStyle = require("ge/extensions/raceprep/classStyle")

---@class BJIWindowRaceTower : BJIWindow
local W = {
    name = "RaceTower",
    flags = {
        BJI.Utils.Style.WINDOW_FLAGS.NO_TITLE_BAR,
        BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE,
        BJI.Utils.Style.WINDOW_FLAGS.ALWAYS_AUTO_RESIZE,
    },
}

local placed = false
local showLeaderGap = false

local function body(ctxt)
    if W.position then
        W.position = nil -- only place the window on its first frame
    end
    local snap = timing.get(ctxt)
    if not snap then
        return
    end
    local c = BJI.Utils.Style.TEXT_COLORS

    if Button("raceprep-tower-mode", showLeaderGap and "Gap to leader" or "Interval",
            { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO, noSound = true }) then
        showLeaderGap = not showLeaderGap
    end
    TooltipText("Switch between the interval to the car ahead and the gap to the leader.")

    if BeginTable("raceprep-tower", {
            { label = "Pos" },
            { label = "Driver" },
            { label = "PI" },
            { label = showLeaderGap and "Gap" or "Int." },
            { label = "Lap" },
            { label = "Best" },
        }, {
            showHeader = true,
            flags = { TABLE_FLAGS.ALTERNATE_ROW_BG },
        }) then
        for _, e in ipairs(snap.entries) do
            local color = e.isSelf and c.HIGHLIGHT or c.DEFAULT
            TableNewRow()
            Text(string.format("P%d", e.position), { color = color })
            TableNextColumn()
            Text(e.name, { color = color })
            TableNextColumn()
            local ratings = rawget(_G, "raceprepRatings")
            local entry = ratings and ratings.getPlayer(e.playerID)
            classStyle.drawBadge(entry, c.DISABLED)
            TableNextColumn()
            if e.eliminated then
                Text("DNF", { color = c.ERROR })
            elseif e.position == 1 then
                Text(e.finished and "FIN" or "Leader", { color = e.finished and c.SUCCESS or c.DISABLED })
            elseif showLeaderGap then
                Text(timing.formatGap(e.diff), { color = color })
            elseif e.intervalLaps then
                Text(string.format("+%d L", e.intervalLaps), { color = color })
            else
                Text(timing.formatGap(e.interval), { color = color })
            end
            TableNextColumn()
            Text(e.finished and "FIN" or (snap.laps > 1 and string.format("%d/%d", math.min(e.lap, snap.laps), snap.laps) or "-"),
                { color = e.finished and c.SUCCESS or color })
            TableNextColumn()
            Text(e.bestLap and timing.formatLap(e.bestLap) or "--", { color = c.DISABLED })
        end
        EndTable()
    end
end

W.getState = function()
    local race = timing.getRace()
    return race ~= nil and race.race.startTime ~= nil and #(race.race.leaderboard or {}) > 0
end

W.onLoad = function()
    if not placed then
        placed = true
        local size = ui_imgui.GetMainViewport().Size
        W.position = ImVec2(20, size.y * 0.25)
    end
end

W.body = body

return W
