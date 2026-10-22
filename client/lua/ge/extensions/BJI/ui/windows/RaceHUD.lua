-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Driver timing HUD for BeamJoy multiplayer races (RacePrep add-on):
-- position, lap, current lap time with live delta to personal best, last and
-- best lap, and the gaps to the cars ahead and behind (time and distance).
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local timing = require("ge/extensions/raceprep/timing")

---@class BJIWindowRaceHUD : BJIWindow
local W = {
    name = "RaceHUD",
    flags = {
        BJI.Utils.Style.WINDOW_FLAGS.NO_TITLE_BAR,
        BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE,
        BJI.Utils.Style.WINDOW_FLAGS.ALWAYS_AUTO_RESIZE,
    },
}

local placed = false

local function colors()
    local c = BJI.Utils.Style.TEXT_COLORS
    return c.SUCCESS, c.ERROR, c.HIGHLIGHT, c.DISABLED, c.DEFAULT
end

local function deltaColor(ms)
    local good, bad, _, muted = colors()
    if not ms then
        return muted
    end
    return ms <= 0 and good or bad
end

local function bigText(text, color, factor)
    local scale = BJI_LocalStorage.get(BJI_LocalStorage.GLOBAL_VALUES.UI_SCALE) or 1
    SetWindowFontScale(scale * factor)
    Text(text, { color = color })
    SetWindowFontScale(scale)
end

local function drawGap(label, gap, arrow)
    local _, _, highlight, muted = colors()
    if not gap then
        Text(arrow .. " " .. label .. ": --", { color = muted })
        return
    end
    Text(arrow .. " " .. gap.name, { color = highlight })
    SameLine()
    local timeText
    if gap.laps then
        timeText = string.format("+%d lap%s", gap.laps, gap.laps > 1 and "s" or "")
    else
        timeText = gap.interval and string.format("%.3f s", math.abs(gap.interval) / 1000) or "--"
    end
    Text(timeText)
    SameLine()
    if gap.distance then
        Text(string.format("%.0f m  (~%.1f s)", math.abs(gap.distance), (gap.live or 0) / 1000),
            { color = muted })
    else
        Text("-- m", { color = muted })
    end
end

local function body(ctxt)
    if W.position then
        W.position = nil -- only place the window on its first frame
    end
    -- yellow flag, start lights, false start (Race control no longer pops up)
    require("ge/extensions/raceprep/raceSignals").draw()
    local snap = timing.get(ctxt)
    if not snap or not snap.self then
        Text("Waiting for timing...", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
        return
    end
    local me = snap.self
    local _, _, highlight, muted = colors()
    local rt = rawget(_G, "bjiRacePrep")
    local rolling = rt and rt.rolling
    if rolling and rolling.phase == "formation" then
        Text(string.format("FORMATION - pace %d km/h - hold position", rolling.pace or 80),
            { color = BJI.Utils.Style.TEXT_COLORS.ERROR })
    end

    Text(string.format("P%d / %d", me.position, #snap.entries), { color = highlight })
    if snap.laps and snap.laps > 1 then
        SameLine()
        Text(string.format("   Lap %d / %d", math.min(me.lap, snap.laps), snap.laps))
    end

    bigText(timing.formatLap(snap.lapTime), nil, 1.8)
    if snap.liveDelta then
        SameLine()
        bigText(timing.formatGap(snap.liveDelta), deltaColor(snap.liveDelta), 1.4)
    end

    Text("Last " .. timing.formatLap(me.lastLap), { color = muted })
    SameLine()
    Text("   Best " .. timing.formatLap(snap.bestLap), { color = muted })
    if snap.sectorDelta then
        SameLine()
        Text("   Split " .. timing.formatGap(snap.sectorDelta), { color = deltaColor(snap.sectorDelta) })
    end

    local rt = rawget(_G, "bjiRacePrep")
    local temps = rt and rt.trackTemp
    if temps then
        Text(string.format("Air %.0f\194\176C   Track %.0f\194\176C%s", temps.air, temps.track, temps.wet and "  wet" or ""),
            { color = muted })
    end
    Separator()
    drawGap("Ahead", snap.gapAhead, "^")
    drawGap("Behind", snap.gapBehind, "v")
end

W.getState = function()
    local race = timing.getRace()
    return race ~= nil and race.isParticipant() and not race.isFinished() and not race.isEliminated() and
        race.race.startTime ~= nil
end

W.onLoad = function()
    if not placed then
        placed = true
        local size = ui_imgui.GetMainViewport().Size
        W.position = ImVec2(size.x * 0.5 - 180, 40)
    end
end

W.body = body

return W
