-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Practice / qualifying session window (RacePrep add-on): time left, my
-- current lap, my laps, and the standings by best valid lap. Shown while a
-- session runs on this map (and for a while after it ends) in free roam.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local session = require("ge/extensions/raceprep/session")
local results = require("ge/extensions/raceprep/results")

---@class BJIWindowRaceSession : BJIWindow
local W = {
    name = "RaceSession",
    minSize = ImVec2(760, 220),
    maxSize = ImVec2(1120, 900),
    flags = {
        BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE,
    },
}

local hiddenFor = nil -- session id the driver closed the window for
local SHOW_AFTER_END_S = 120
local endedSeen = {}

local function fmt(ms)
    return results.formatTime(ms)
end

local function clockText(ms)
    local s = math.max(0, math.floor((ms or 0) / 1000 + 0.999))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function classText(row)
    if row.class and row.pi then return string.format("%s %d", row.class, row.pi) end
    return ""
end

local function body(ctxt)
    local d = session.data
    local c = BJI.Utils.Style.TEXT_COLORS
    if not d or not d.rows then
        Text("No session.")
        return
    end
    local title = string.format("%s  -  %s", d.label or "Session", tostring(d.raceName or d.raceID))
    Text(title, { color = c.HIGHLIGHT })
    if d.state == "running" then
        SameLine()
        Text("   " .. clockText(session.remaining()) .. " left")
    elseif d.state == "overtime" then
        SameLine()
        Text("   time up - finish your lap", { color = c.ERROR })
    else
        SameLine()
        Text("   finished", { color = c.DISABLED })
    end

    if session.active() then
        local cur = session.currentLapTime()
        if cur then
            local cuts = session.currentLapCuts()
            Text("Current lap  " .. fmt(cur), { color = cuts > 0 and c.ERROR or c.DEFAULT })
            if cuts > 0 then
                SameLine()
                Text("  invalid (track limits)", { color = c.ERROR })
            end
        else
            Text("Out lap: cross the start/finish line to start timing.", { color = c.DISABLED })
        end
        if session.lastLap then
            local l = session.lastLap
            Text("Last lap  " .. fmt(l.time) .. (l.valid and "" or (l.void and "  (not counted)" or "  (invalid)")),
                { color = l.valid and c.DEFAULT or c.ERROR })
        end
        if Button("raceprep-session-gototrack", "Go to the track", { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO }) then
            session.goToTrack()
        end
        SameLine()
        Text("puts your car on the race's grid", { color = c.DISABLED })
    elseif d.state ~= "ended" and d.track and d.track.level then
        local here = getCurrentLevelIdentifier and getCurrentLevelIdentifier() == d.track.level
        Text(here and "Return to free roam to participate in this session." or
            ("This session is on another map (" .. tostring(d.track.level) .. ")."), { color = c.DISABLED })
    end

    Separator()
    if BeginTable("raceprep-session-standings", {
            { label = "Pos" },
            { label = "Driver" },
            { label = "Car" },
            { label = "Best lap" },
            { label = "S1" },
            { label = "S2" },
            { label = "S3" },
            { label = "Gap" },
            { label = "Laps" },
        }, { showHeader = true, flags = { TABLE_FLAGS.ALTERNATE_ROW_BG, TABLE_FLAGS.SIZING_STRETCH_PROP } }) then
        for _, row in ipairs(d.rows) do
            local color = session.isMine(row.playerID) and c.HIGHLIGHT or c.DEFAULT
            TableNewRow()
            Text(tostring(row.pos), { color = color })
            TableNextColumn()
            Text(tostring(row.name or "?"), { color = color })
            TableNextColumn()
            Text(classText(row), { color = c.DISABLED })
            TableNextColumn()
            Text(row.best and fmt(row.best) or "no valid lap", { color = row.best and color or c.DISABLED })
            TableNextColumn()
            for sector = 1, 3 do
                local value = row.bestSectors and row.bestSectors[sector]
                Text(value and string.format("%.3f", value / 1000) or "--",
                    { color = value and color or c.DISABLED })
                TableNextColumn()
            end
            Text(row.gap and string.format("+%.3f", row.gap / 1000) or "", { color = c.DISABLED })
            TableNextColumn()
            Text(tostring(row.laps or 0), { color = c.DISABLED })
        end
        EndTable()
    end
    Text("S1 / S2 / S3 are the sectors of each driver's best valid lap (seconds).",
        { color = c.DISABLED, wrap = true })
    local track = d.track
    local gates = track and require("ge/extensions/raceprep/lapTracker").new(track.steps)
    if gates and not gates:valid() then
        Text("Sector times unavailable: this track has no usable checkpoints.", { color = c.DISABLED })
    elseif gates and not gates.sectorBounds then
        Text("Sector times unavailable: add two intermediate timing checkpoints to this track in BeamJoy's race editor.",
            { color = c.DISABLED, wrap = true })
    end
    if #d.rows == 0 then
        Text("No laps yet.", { color = c.DISABLED })
    end
    if d.type == "qualifying" then
        local order = d.gridOrder
        local note
        if order == "qualifying" then
            note = "This qualifying sets the race grid."
        elseif order == "reverse" then
            note = "The race grid is this order with the top places reversed."
        else
            note = "The race grid does not use qualifying (rule: " .. tostring(order) .. ")."
        end
        if (order == "qualifying" or order == "reverse") and not d.gridPatch then
            note = note .. " Server: the BeamJoyCore grid order patch is not installed, so the grid stays in join order."
        end
        Text(note, { color = c.DISABLED, wrap = true })
    end
    if d.trackLimits ~= "off" then
    Text("Laps with all wheels off the track (grass, gravel, sand, dirt) do not count.", { color = c.DISABLED, wrap = true })

    end
    Separator()
    if #session.laps > 0 and BeginTree(string.format("My laps (%d)##raceprep-session-mylaps", #session.laps)) then
        for i, l in ipairs(session.laps) do
            Text(string.format("%d.  %s%s", #session.laps - i + 1, fmt(l.time),
                l.valid and "" or (l.void and "  not counted (reset)" or string.format("  invalid (%d cut%s)", l.cuts or 1, (l.cuts or 1) == 1 and "" or "s"))),
                { color = l.valid and c.DEFAULT or c.ERROR })
            if l.sectors then
                Text(string.format("    S1 %.3f   S2 %.3f   S3 %.3f", l.sectors[1] / 1000,
                    l.sectors[2] / 1000, l.sectors[3] / 1000),
                    { color = l.valid and c.DISABLED or c.ERROR })
            end
        end
        EndTree()
    end
    if Button("raceprep-session-hide", "Hide", { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING, width = 100 }) then
        hiddenFor = d.id
    end
    local prep = rawget(_G, "BJI_Win_RacePrep")
    if prep and prep.canEditRules and prep.canEditRules() and d.state ~= "ended" then
        SameLine()
        if Button("raceprep-session-stop", "End session now (admin)", { btnStyle = BJI.Utils.Style.BTN_PRESETS.ERROR }) then
            session.stop()
        end
    end
end

W.onClose = function()
    hiddenFor = session.data and session.data.id or hiddenFor
end

-- Race Prep menu: show it again after closing
W.reopen = function()
    hiddenFor = nil
end

W.getState = function()
    local d = session.data
    if not d or not d.id or hiddenFor == d.id then
        return false
    end
    local sc = rawget(_G, "BJI_Scenario")
    if sc and sc.isFreeroam and not sc.isFreeroam() then
        return false
    end
    if d.state == "ended" then
        local t = os.time()
        endedSeen[d.id] = endedSeen[d.id] or t
        return t - endedSeen[d.id] < SHOW_AFTER_END_S
    end
    return d.state == "running" or d.state == "overtime"
end

W.body = body

return W
