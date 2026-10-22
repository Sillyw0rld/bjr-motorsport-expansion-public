-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Vehicle-side half of the RacePrep differential setup.
--
-- Differential behaviour in BeamNG is runtime state on the powertrain device
-- (lua/vehicle/powertrain/differential.lua): a mode (open/lsd/locked/...), the
-- LSD preload and lock coefficients, and the torque split. Changing those
-- here turns any car's diff into a tunable race diff without new parts. The
-- driver's own client simulates their car, so this only affects that driver.
--
-- The GE side (bjiRacePrep) sends settings with applyAll() and asks for the
-- current state with report(). A respawn reloads this VM; GE re-sends then.

local M = {}

-- settings applied by the driver, per device name
local applied = {}
-- the device values from the car's own parts, per device name
local stock = {}
local reapplyPending = false

local function shallowCopyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do
        out[i] = v
    end
    return out
end

-- breadth-first search below a device
local function subtreeAny(device, predicate)
    local queue = {}
    for _, child in ipairs(device.children or {}) do
        queue[#queue + 1] = child
    end
    local i = 1
    while queue[i] do
        local d = queue[i]
        if predicate(d) then
            return true
        end
        for _, child in ipairs(d.children or {}) do
            queue[#queue + 1] = child
        end
        i = i + 1
    end
    return false
end

local function isCentre(device)
    if device.name:match("_C$") then
        return true
    end
    return subtreeAny(device, function(d) return d.type == "differential" end)
end

local function position(device)
    local name = device.name
    if isCentre(device) then
        return "centre"
    elseif name:match("_F$") or name:lower():find("front") then
        return "front"
    elseif name:match("_R$") or name:lower():find("rear") then
        return "rear"
    end
    return "other"
end

-- which output of a centre diff drives the front axle (1, 2 or nil)
local function frontOutput(device)
    for index, child in ipairs(device.children or {}) do
        local check = function(d) return d.name:match("_F$") or d.name:lower():find("front") end
        if check(child) or subtreeAny(child, check) then
            return index
        end
    end
end

local function captureStock(device)
    if not stock[device.name] then
        stock[device.name] = {
            mode = device.mode,
            availableModes = shallowCopyList(device.availableModes),
            lsdPreload = device.lsdPreload,
            lsdLockCoef = device.lsdLockCoef,
            lsdRevLockCoef = device.lsdRevLockCoef,
            splitA = device.diffTorqueSplitA,
        }
    end
    return stock[device.name]
end

local function applyDevice(device, s)
    local base = captureStock(device)
    local splitChanged = false
    if not s or s.mode == "stock" then
        device.availableModes = shallowCopyList(base.availableModes)
        device.lsdPreload = base.lsdPreload
        device.lsdLockCoef = base.lsdLockCoef
        device.lsdRevLockCoef = base.lsdRevLockCoef
        splitChanged = device.diffTorqueSplitA ~= base.splitA
        device.diffTorqueSplitA = base.splitA
        device.diffTorqueSplitB = 1 - base.splitA
        device:setMode(base.mode)
    else
        -- a single available mode, so no in-car toggle can switch it back
        device.availableModes = { s.mode }
        if s.mode == "lsd" then
            device.lsdPreload = tonumber(s.preload) or base.lsdPreload
            device.lsdLockCoef = tonumber(s.lock) or base.lsdLockCoef
            device.lsdRevLockCoef = tonumber(s.coast) or base.lsdRevLockCoef
        end
        device:setMode(s.mode)
    end
    if s and tonumber(s.split) then
        local split = math.min(math.max(tonumber(s.split), 0), 1)
        splitChanged = splitChanged or device.diffTorqueSplitA ~= split
        device.diffTorqueSplitA = split
        device.diffTorqueSplitB = 1 - split
    end
    return splitChanged
end

local function applyStored()
    local splitChanged = false
    for _, device in ipairs(powertrain.getDevicesByType("differential") or {}) do
        local s = applied[device.name]
        if s or stock[device.name] then
            splitChanged = applyDevice(device, s) or splitChanged
        end
    end
    if splitChanged and powertrain.calculateTreeInertia then
        powertrain.calculateTreeInertia()
    end
end

M.report = function()
    local devices = {}
    for _, device in ipairs(powertrain.getDevicesByType("differential") or {}) do
        local base = captureStock(device)
        local front = isCentre(device) and frontOutput(device) or nil
        devices[#devices + 1] = {
            name = device.name,
            uiName = device.uiName,
            position = position(device),
            mode = device.mode,
            stockMode = base.mode,
            preload = device.lsdPreload,
            lock = device.lsdLockCoef,
            coast = device.lsdRevLockCoef,
            split = device.diffTorqueSplitA,
            stockSplit = base.splitA,
            frontOutput = front,
            applied = applied[device.name] ~= nil,
        }
    end
    obj:queueGameEngineLua(string.format(
        "if bjiRacePrep then bjiRacePrep.onDiffReport(%d, %s) end", obj:getId(), serialize(devices)))
end

-- settings: table<deviceName, {mode, preload, lock, coast, split}> ;
-- devices missing from it go back to stock
M.applyAll = function(settings)
    applied = type(settings) == "table" and settings or {}
    applyStored()
    M.report()
end

M.onReset = function()
    reapplyPending = true
end

M.updateGFX = function()
    if reapplyPending then
        reapplyPending = false
        if next(applied) then
            applyStored()
        end
    end
end

return M
