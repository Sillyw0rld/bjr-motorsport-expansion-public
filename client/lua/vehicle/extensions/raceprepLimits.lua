-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Track limits (vehicle side, RacePrep add-on).
-- A "cut" is the car with every wheel that touches the ground on an
-- off-track surface (grass, gravel, sand, dirt...) and none on the track,
-- for OFF_S in a row. Kerbs, asphalt run-off and airborne wheels do not
-- count. Each cut is reported once to the game engine side
-- (bjiRacePrep.onCut); the car must be back on track for ON_S before the
-- next one counts.
--
-- Surface ids: the ground model's collision type (lua/common/particles.json):
-- 7 FOLIAGE, 14 DIRT_DUSTY, 15 DIRT, 16 SAND, 17 SANDY_ROAD, 18 MUD,
-- 19 GRAVEL, 20 GRASS, 22 SNOW, 31 FOLIAGE_THIN.

local M = {}

local OFF = { [7] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true,
  [19] = true, [20] = true, [22] = true, [31] = true }
local OFF_S = 0.25
local ON_S = 0.5

local active = false
local offTime, onTime = 0, 0
local cutOpen = false

local function surfaceState()
  local onTrack, offTrack, total = 0, 0, 0
  for _, wd in pairs(wheels.wheels or {}) do
    total = total + 1
    local mat = wd.contactMaterialID1
    if mat and mat >= 0 and (wd.downForceRaw or 1) > 0 then
      if OFF[mat] or OFF[wd.contactMaterialID2 or -1] then
        offTrack = offTrack + 1
      else
        onTrack = onTrack + 1
      end
    end
  end
  return onTrack, offTrack, total
end

local function updateGFX(dt)
  if not active then
    return
  end
  local onTrack, offTrack, total = surfaceState()
  if total > 0 and offTrack == total then
    offTime, onTime = offTime + dt, 0
    if not cutOpen and offTime >= OFF_S then
      cutOpen = true
      obj:queueGameEngineLua("if bjiRacePrep and bjiRacePrep.onCut then bjiRacePrep.onCut(" .. obj:getId() .. ") end")
    end
  elseif onTrack > 0 then
    onTime, offTime = onTime + dt, 0
    if onTime >= ON_S then
      cutOpen = false
    end
  else
    offTime, onTime = 0, 0 -- airborne/unknown contact breaks continuous debounce
  end
end

M.enable = function()
  active = true
end

M.disable = function()
  active = false
  offTime, onTime, cutOpen = 0, 0, false
end

M.isActive = function()
  return active
end

M.updateGFX = updateGFX

return M
