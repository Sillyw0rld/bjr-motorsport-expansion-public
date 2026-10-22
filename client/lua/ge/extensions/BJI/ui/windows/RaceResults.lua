-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race results window (RacePrep add-on): shown when a BeamJoy multiplayer
-- race finishes, kept after BeamJoy clears the race, reopened from the Race
-- Prep window. Click a driver to see every lap with its sectors.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local results = require("ge/extensions/raceprep/results")

---@class BJIWindowRaceResults : BJIWindow
local W = {
    name = "RaceResults",
    minSize = ImVec2(620, 260),
    maxSize = ImVec2(1100, 900),
    flags = {
        BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE,
    },
}

local selected = nil -- playerID whose laps are shown

local function fmt(ms)
    return results.formatTime(ms)
end

local function gapText(row)
    if row.position == 1 then
        return row.status == "FIN" and "Winner" or "-"
    end
    if row.gap then
        return string.format("+%.3f", row.gap / 1000)
    end
    if row.lapsDown and row.lapsDown > 0 then
        return string.format("+%d lap%s", row.lapsDown, row.lapsDown == 1 and "" or "s")
    end
    return "-"
end

local function sectorsText(sectors)
    if not sectors then
        return "--"
    end
    return string.format("%s / %s / %s", fmt(sectors[1]), fmt(sectors[2]), fmt(sectors[3]))
end

local function body(ctxt)
    local res = results.last
    if not res then
        Text("No race results yet.")
        return
    end
    local c = BJI.Utils.Style.TEXT_COLORS
    Text(string.format("%s   -   %d lap%s   -   %s", tostring(res.raceName or res.raceID), res.laps or 1,
        (res.laps or 1) == 1 and "" or "s", tostring(res.date or "")), { color = c.HIGHLIGHT })
    if not res.sectorBounds then
        Text("This race has too few checkpoints for sector times.", { color = c.DISABLED })
    end

    if BeginTable("raceprep-results", {
            { label = "Pos" },
            { label = "Driver" },
            { label = "Car" },
            { label = "Status" },
            { label = "Laps" },
            { label = "Total" },
            { label = "Gap" },
            { label = "Best lap" },
            { label = "Best lap sectors" },
        }, {
            showHeader = true,
            flags = { TABLE_FLAGS.ALTERNATE_ROW_BG, TABLE_FLAGS.SIZING_STRETCH_PROP },
        }) then
        for _, row in ipairs(res.rows) do
            local isSelf = BJI_Context and BJI_Context.User and row.playerID == BJI_Context.User.playerID
            local color = isSelf and c.HIGHLIGHT or c.DEFAULT
            TableNewRow()
            Text(string.format("P%d", row.position), { color = color })
            TableNextColumn()
            if Button("raceprep-results-row-" .. tostring(row.playerID), row.name or "?",
                    { btnStyle = selected == row.playerID and BJI.Utils.Style.BTN_PRESETS.SUCCESS or
                        BJI.Utils.Style.BTN_PRESETS.INFO, noSound = true }) then
                selected = selected ~= row.playerID and row.playerID or nil
            end
            TableNextColumn()
            local rt = rawget(_G, "bjiRacePrep")
            local skill = rt and rt.skillText and rt.skillText(row.playerID, true)
            Text((row.car or "?") .. (skill and ("   skill " .. skill) or ""), { color = c.DISABLED })
            TableNextColumn()
            local status = row.status
            if row.falseStart then status=status .. "  FALSE START" end
            if row.cuts and row.cuts > 0 then status = status .. string.format("  %d cut%s", row.cuts, row.cuts == 1 and "" or "s") end
            if row.penalty then status = status .. string.format("  +%gs", row.penalty / 1000) end
            Text(status, { color = row.status == "FIN" and (row.penalty and c.HIGHLIGHT or c.SUCCESS) or c.ERROR })
            TableNextColumn()
            Text(tostring(row.laps or 0))
            TableNextColumn()
            Text(fmt(row.total), { color = color })
            TableNextColumn()
            Text(gapText(row), { color = color })
            TableNextColumn()
            -- fastest lap, cut or not: green = valid, red = had a track-limits cut
            local lap = row.bestAny or row.best
            Text(lap and (fmt(lap.time) .. (row.fastestLap and lap == row.best and "  fastest" or "")) or "--",
                { color = lap and (lap.invalid and c.ERROR or c.SUCCESS) or color })
            TableNextColumn()
            Text(lap and sectorsText(lap.sectors) or "--", { color = c.DISABLED })
        end
        EndTable()
    end
    Text("Click a driver for every lap. Best lap: green = valid lap, red = it had a track-limits cut (not counted as a best lap); \"fastest\" = fastest valid lap of the race. Penalties are included in Total.",
        { color = c.DISABLED, wrap = true })

    if selected then
        for _, row in ipairs(res.rows) do
            if row.playerID == selected then
                Separator()
                Text(string.format("%s - %s", row.name or "?", row.car or "?"), { color = c.HIGHLIGHT })
                if BeginTable("raceprep-results-laps", {
                        { label = "Lap" },
                        { label = "Time" },
                        { label = "S1" },
                        { label = "S2" },
                        { label = "S3" },
                    }, {
                        showHeader = true,
                        flags = { TABLE_FLAGS.ALTERNATE_ROW_BG },
                    }) then
                    for _, l in ipairs(row.lapList or {}) do
                        local isBest = row.best and row.best.lap == l.lap
                        TableNewRow()
                        Text(tostring(l.lap))
                        TableNextColumn()
                        Text(fmt(l.time) .. (l.invalid and string.format("  invalid (%d cut%s)", l.cuts or 1, (l.cuts or 1) == 1 and "" or "s") or ""),
                            { color = isBest and c.SUCCESS or (l.invalid and c.ERROR or c.DEFAULT) })
                        for i = 1, 3 do
                            TableNextColumn()
                            local s = l.sectors and l.sectors[i]
                            local best = row.bestSectors and row.bestSectors[i]
                            Text(fmt(s), { color = (s and best and s == best) and c.SUCCESS or c.DEFAULT })
                        end
                    end
                    EndTable()
                end
                if row.theoretical then
                    Text("Best sectors combined (not one lap): " .. fmt(row.theoretical), { color = c.DISABLED })
                end
                if #(row.lapList or {}) == 0 then
                    Text("No complete laps recorded.", { color = c.DISABLED })
                end
            end
        end
    end

    Separator()
    if Button("raceprep-results-close", "Close", { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING, width = 120 }) then
        results.visible = false
    end
    SameLine()
    Text("Saved on the server in the race history.", { color = c.DISABLED })
end

W.getState = function()
    return results.visible and results.last ~= nil
end

W.onClose = function()
    results.visible = false
end

W.body = body

return W
