-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Frame-spike report (2026-10-17, "spike every 15 s"): every add-on hook and
-- server-event handler adds its time to the current frame's buckets. When a
-- frame takes much longer than usual, the console says how long it took and
-- how much of it was BJR:ME, by name. A spike with little of ours in it comes
-- from BJR, BeamMP, another mod or the game. Costs two clock reads per call.
local P = { SPIKE_MS = 25, SPIKE_FACTOR = 2.5, LOG_EVERY_S = 2, FILE = '/raceprep_spikes.log', KEEP = 120 }
local fileLines = {}
local buckets, order, n = {}, {}, 0
local usual, clock, loggedAt = nil, 0, -1e9
P.last = nil -- last report, for tests
local function now()
    return Engine and Engine.Platform and Engine.Platform.getSystemTimeMS and Engine.Platform.getSystemTimeMS()
        or os.clock() * 1000
end
P.now = now
function P.add(name, ms)
    local b = buckets[name]
    if not b then n = n + 1; order[n] = name; b = 0 end
    buckets[name] = b + ms
end
--- the same function, timed into the frame's buckets under `name`
function P.wrap(name, fn)
    if type(fn) ~= 'function' then return fn end
    return function(...)
        local t = now()
        local a, b, c, d = fn(...)
        P.add(name, now() - t)
        return a, b, c, d
    end
end
--- once per frame, first thing: dtReal is the frame that just ended
function P.tick(dtReal, log)
    local ms = (tonumber(dtReal) or 0) * 1000
    clock = clock + (tonumber(dtReal) or 0)
    if ms > 0 then
        local limit = math.max(P.SPIKE_MS, (usual or ms) * P.SPIKE_FACTOR)
        if usual and ms > limit and clock - loggedAt >= P.LOG_EVERY_S then
            loggedAt = clock
            local total, parts = 0, {}
            -- BJR:ME's own buckets, then every extension (BeamNG's profiler hook), biggest first
            local others = {}
            for i = 1, n do
                local name, v = order[i], buckets[order[i]]
                if name:sub(1, 11) == 'extensions.' then others[#others + 1] = { name:sub(12), v }
                else total = total + v; if v >= 0.3 then parts[#parts + 1] = string.format('%s %.1f', name, v) end end
            end
            table.sort(others, function(x, y) return x[2] > y[2] end)
            local top = {}
            for i = 1, math.min(6, #others) do if others[i][2] >= 0.5 then top[#top + 1] = string.format('%s %.1f', others[i][1], others[i][2]) end end
            P.last = string.format('Frame spike %.0f ms (usual %.1f ms); BJR:ME %.1f ms%s%s', ms, usual, total,
                #parts > 0 and (': ' .. table.concat(parts, ', ')) or '',
                #top > 0 and (' | extensions: ' .. table.concat(top, ', ')) or '')
            if log then log('W', 'raceprepProf', P.last) end
            -- also to its own small file at once: BeamNG writes its log in batches
            fileLines[#fileLines + 1] = os.date('%H:%M:%S') .. ' ' .. P.last
            if #fileLines > P.KEEP then table.remove(fileLines, 1) end
            if writeFile then pcall(writeFile, P.FILE, table.concat(fileLines, '\n') .. '\n') end
        end
        -- slow average of normal frames (spikes do not pull it up)
        if not usual then usual = ms elseif ms < limit then usual = usual * 0.97 + ms * 0.03 end
    end
    for i = 1, n do buckets[order[i]] = nil; order[i] = nil end
    n = 0
end
--- time BJR:ME's own server-event handlers (source tag contains "raceprep");
--- other handlers pass through unchanged. Safe to call every frame.
function P.hook()
    local g = rawget(_G, 'AddEventHandler')
    if type(g) ~= 'function' or g == P.hooked then return end
    local original = g
    P.hooked = function(name, fn, src, ...)
        if type(src) == 'string' and src:lower():find('raceprep', 1, true) then fn = P.wrap('ev:' .. tostring(name), fn) end
        return original(name, fn, src, ...)
    end
    rawset(_G, 'AddEventHandler', P.hooked)
end
--- BeamNG's own per-extension profiler hook (extensions.setProfiler): times
--- every extension's hooks (BJR, BeamMP, KTS, the game's) into the buckets as
--- "extensions.<name>.<hook>". Measuring only; no extension is changed.
P.extProfiler = { start = function(self) self.t = now() end,
    add = function(self, name) P.add(name, now() - (self.t or now())) end }
function P.profileExtensions(on)
    if not (extensions and extensions.setProfiler) then return false end
    extensions.setProfiler(on ~= false and P.extProfiler or nil)
    return true
end
return P
