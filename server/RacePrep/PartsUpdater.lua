-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Upgrade parts for newly added cars, at server start (2026-10-19). Runs the
-- bundled updater (updater/tools/parts_updater.py) in the background: it adds
-- parts for Automation cars in Resources/Client that have none (existing cars
-- are never touched), then the new zip is delivered with `reloadmods`:
-- typed automatically when the server runs inside tmux (the sandboxed service
-- or the launcher), otherwise the console tells the admin to type it.
-- Players already connected keep the old zip until they rejoin, which is why
-- this only runs at startup.
local U = {}

function U.start(o)
    local windows = o.osName == 'Windows'
    -- Public installs: the launcher (start-bjrme-server) builds parts before
    -- BeamMP starts and holds the session lock while the server runs. Started
    -- without it (hosted panels), the bundled compiled generator runs here in
    -- the background instead, like the developer path below (2026-10-22).
    if o.exists(o.path .. '/updater/preflight-required.json') then
        if o.exists(o.path .. '/updater/server-session.lock') then
            o.log('Upgrade parts: built by start-bjrme-server before the server started')
            return false
        end
        local exe = windows and 'bjrme-generator\\bjrme-generator.exe' or './bjrme-generator/bjrme-generator'
        if not o.exists(windows and 'bjrme-generator/bjrme-generator.exe' or exe) then
            o.logWarn('Upgrade parts: bjrme-generator is missing; start the server with start-bjrme-server to build parts for new cars')
            return false
        end
        local result = o.path .. '/updater/last-run.json'
        local cmd = string.format('"%s" --beammp . --result "%s" > "%s/updater/last-run.log" 2>&1', exe, result, o.path)
        o.execute(windows and ('start "" /B ' .. cmd) or (cmd .. ' &'))
        U.pending = { result = result, started = o.now(), o = o, windows = windows, log = o.path .. '/updater/last-run.log' }
        o.log('Upgrade parts: server started without start-bjrme-server; checking for new cars in the background')
        return true
    end
    local dir = o.path .. '/updater/tools'
    if not o.exists(dir .. '/parts_updater.py') then return false end
    -- the previous result stays in place (deleting it makes BeamMP's plugin
    -- file monitor warn); results older than this start are ignored
    local result = dir .. '/last-run.json'
    local cmd = string.format('%s -I "%s/parts_updater.py" --beammp . > "%s/last-run.log" 2>&1',
        windows and 'python' or 'python3', dir, dir)
    cmd = windows and ('start "" /B ' .. cmd) or (cmd .. ' &')
    o.execute(cmd)
    U.pending = { result = result, started = o.now(), o = o, windows = windows, log = dir .. '/last-run.log' }
    o.log('Upgrade parts: checking for new cars (background)')
    return true
end

--- once a second until the updater reports; true when it has finished
function U.poll()
    local p = U.pending
    if not p then return true end
    local o = p.o
    local r = o.read(p.result)
    if type(r) == 'table' and (tonumber(r.finishedAt) or 0) < p.started - 1 then r = nil end -- the previous start's result
    if type(r) ~= 'table' then
        if o.now() - p.started > 600 then
            U.pending = nil
            o.logWarn('Upgrade parts: no result after 10 minutes; the server runs with the previous parts')
            return true
        end
        return false
    end
    U.pending = nil
    local cars = type(r.newCars) == 'table' and r.newCars or {}
    if r.status == 'up-to-date' then
        o.log('Upgrade parts: every car has its parts')
    elseif r.status == 'updated' then
        o.log(string.format('Upgrade parts generated for %d new car(s) in %s s: %s', #cars, tostring(r.seconds), table.concat(cars, ', ')))
        local tmux, pane = o.getenv('TMUX'), o.getenv('TMUX_PANE')
        local sock = type(tmux) == 'string' and tmux:match('^([^,]+)')
        if not p.windows and sock and type(pane) == 'string' and pane:match('^%%%d+$') then
            o.execute(string.format('tmux -S "%s" send-keys -t "%s" reloadmods Enter', sock, pane))
            o.log('Upgrade parts: reloadmods sent; players who join from now on get the new parts')
            U.delivered = 'auto'
        else
            o.logWarn('Upgrade parts: type  reloadmods  in this console to deliver them (players who join afterwards get them)')
            U.delivered = 'manual'
        end
    else
        o.logWarn('Upgrade parts: updater failed: ' .. tostring(r.error) .. ' (server runs with the previous parts; details in ' .. tostring(p.log) .. ')')
    end
    U.last = r
    return true
end

return U
