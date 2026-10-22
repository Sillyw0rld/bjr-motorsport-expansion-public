-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Track settings for the current map (RacePrep add-on, admins with
-- SetConfig): rubber (on/off, level, build-up, grip) and wind. They apply on
-- this map everywhere (free roam, practice/qualifying, races) and are saved
-- on the server (track.json). Opened from the "Race Prep" menu.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local director = require("ge/extensions/raceprep/director")

---@class BJIWindowRaceTrack : BJIWindow
local W = {
    name = "RaceTrack",
    minSize = ImVec2(460, 360),
    maxSize = ImVec2(900, 1200),
    flags = { BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE },
    show = false,
}

local draft, draftLevel = nil, nil
local levelTarget = nil -- rubber level slider (0-100)
local statusSeen = nil -- last server reply handled (a refusal drops the edit)

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end

-- BeamJoy has no checkbox builder (same helper as the RacePrep window).
local function Checkbox(id, label, value)
    local ptr = BoolPtr(value == true)
    if ui_imgui.Checkbox(label .. "##" .. id, ptr) then
        return ptr[0]
    end
    return nil
end

local function slider(id, label, value, min, max, fmt)
    Text(label)
    SameLine()
    local v = SliderFloat(id, tonumber(value) or min, min, max,
        { precision = fmt:find("%.1f", 1, true) and 1 or 0, formatRender = fmt })
    return v
end

local function body()
    local c = BJI.Utils.Style.TEXT_COLORS
    local prep = rawget(_G, "BJI_Win_RacePrep")
    if not (prep and prep.canEditRules and prep.canEditRules()) then
        Text("Track settings need the SetConfig permission.", { color = c.DISABLED })
        return
    end
    local track = director.data and director.data.track
    if not track or not track.level then
        Text("Waiting for the server...", { color = c.DISABLED })
        return
    end
    if director.adminStatusSeq ~= statusSeen then
        statusSeen = director.adminStatusSeq
        if tostring(director.adminStatus):find("^Not saved") then draft = nil end
    end
    if draftLevel ~= track.level or not draft then
        draftLevel = track.level
        draft = { rubber = copy(track.rubber), wind = copy(track.wind) }
        levelTarget = nil
    end
    Text("Track: " .. tostring(track.level), { color = c.HIGHLIGHT })
    Text("These settings apply on this map everywhere: free roam, practice, qualifying and races.",
        { color = c.DISABLED, wrap = true })

    Separator()
    Text("Rubber", { color = c.HIGHLIGHT })
    local r = draft.rubber
    local changed = Checkbox("track-rubber-on", "Rubber on the racing line (grip and look)", r.enabled == true)
    if changed ~= nil then
        r.enabled = changed
        director.setTrack({ rubber = { enabled = changed } }) -- immediate
    end
    local line=require('ge/extensions/raceprep/rubberLine')
    local marbles=require('ge/extensions/raceprep/rubberMarbles')
    Text(string.format('Marbles: %d cells; up to 3 %% grip loss, fade over 10 minutes.',marbles.count()),{color=c.DISABLED,wrap=true})
    local amount=math.floor(math.min(1,(line.peak or 0)/line.FULL)*100+.5)
    Text(string.format("Peak recorded line: %d %%", amount), { color = r.enabled and c.DEFAULT or c.DISABLED })
    if not r.enabled then
        Text("Off: the track shows the map's own rubber line and grip.", { color = c.DISABLED, wrap = true })
    end
    if Button("track-rubber-clean", "Clean track", { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING }) then
        director.setTrack({ amount = "clean" })
    end
    SameLine()
    if Button("track-rubber-full", "Full rubber", { btnStyle = BJI.Utils.Style.BTN_PRESETS.INFO }) then
        director.setTrack({ amount = 1 })
    end
    TooltipText('Sets the recorded driven line to full rubber. Drive first on an empty map; this does not invent a racing line.')
    levelTarget = levelTarget or amount
    local v = slider("track-rubber-level", "Set level", levelTarget, 0, 100, "%.0f %%")
    if v then levelTarget = math.floor(v + 0.5) end
    SameLine()
    if Button("track-rubber-set", "Set", { btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS }) then
        director.setTrack({ amount = levelTarget / 100 })
    end
    if BeginTree("Build-up and grip##track-rubber-advanced") then
        v = slider("track-rubber-laps", "Car-laps to fully rubbered (all cars)", r.lapsToFull or 40, 10, 400, "%.0f laps")
        if v then r.lapsToFull = math.floor(v + 0.5) end
        v = slider("track-rubber-dry", "Dry grip bonus at full rubber", r.dryBonus, 0, 10, "%.1f %%")
        if v then r.dryBonus = v end
        v = slider("track-rubber-wet", "Wet grip loss at full rubber", r.wetPenalty, 0, 20, "%.1f %%")
        if v then r.wetPenalty = v end
        v = slider("track-rubber-marbles", "Marble size up close (x real)", r.marbleSize or 5, 1, 10, "%.1fx")
        if v then r.marbleSize = v end
        v = slider("track-rubber-marbles-far", "Marble size at 80 m (x real)", r.marbleSizeFar or 12, 1, 25, "%.1fx")
        if v then r.marbleSizeFar = v end
        Text("Grip follows each wheel through KTS. Without the rubber grip patch, the line is visual only.",
            { color = c.DISABLED, wrap = true })
        EndTree()
    end
    local rubberStatus = line.statusText()
    if rubberStatus then Text(rubberStatus, { color = c.DISABLED, wrap = true }) end

    Separator()
    Text("Wind", { color = c.HIGHLIGHT })
    local w = draft.wind
    changed = Checkbox("track-wind-on", "Physical wind on this map", w.enabled == true)
    if changed ~= nil then w.enabled = changed end
    if w.enabled then
        v = slider("track-wind-speed", "Base wind", w.speedKmh, 0, 120, "%.0f km/h")
        if v then w.speedKmh = math.floor(v + 0.5) end
        v = slider("track-wind-dir", "Blowing towards", w.direction, 0, 360, "%.0f deg (0 east, 90 north)")
        if v then w.direction = math.floor(v + 0.5) end
        v = slider("track-wind-gust", "Gusts", w.gustKmh, 0, 60, "+/- %.0f km/h")
        if v then w.gustKmh = math.floor(v + 0.5) end
        v = slider("track-wind-period", "Gust period", w.gustPeriod, 2, 120, "%.0f s")
        if v then w.gustPeriod = math.floor(v + 0.5) end
    end
    local windStatus = require("ge/extensions/raceprep/raceEnvironment").status
    if windStatus then Text(windStatus, { color = c.DISABLED, wrap = true }) end

    Separator()
    if Button("track-save", "Save track settings", { btnStyle = BJI.Utils.Style.BTN_PRESETS.SUCCESS }) then
        director.setTrack({ rubber = draft.rubber, wind = draft.wind })
        draft = nil
    end
    SameLine()
    if Button("track-close", "Close", { btnStyle = BJI.Utils.Style.BTN_PRESETS.WARNING }) then
        W.show = false
    end
    Text("The rubber on/off box and the level buttons apply at once; the rest needs Save.",
        { color = c.DISABLED, wrap = true })
    if director.adminStatus then
        Text(director.adminStatus, { color = director.adminStatus:find("^Not saved") and c.ERROR or c.SUCCESS, wrap = true })
    end
end

W.getState = function()
    return W.show == true
end

W.onClose = function()
    W.show = false
    draft = nil
end

W.body = body

return W
