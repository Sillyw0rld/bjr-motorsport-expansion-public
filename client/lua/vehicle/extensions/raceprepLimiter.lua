-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Rolling-start pace limiter (vehicle side, RacePrep add-on).
-- While active, the add-on owns the throttle channel: the driver's own
-- throttle is passed through, but capped so the car cannot exceed the pace
-- speed (fading out over the last 2 km/h). Brake and steering are untouched.

local M = {}

local SOURCE = "raceprep"
local FADE_MS = 0.6 -- m/s below the pace speed where the throttle fades out

local pace = nil -- m/s, nil = inactive

local function driverThrottle()
  local li = input.lastInputs and input.lastInputs["local"]
  return li and tonumber(li.throttle) or 0
end

local function updateGFX(dt)
  if not pace then
    return
  end
  local want = math.max(0, math.min(1, driverThrottle()))
  local speed = obj:getVelocity():length()
  local over = speed - pace
  local throttle = want
  if over >= 0 then
    throttle = 0
  elseif over > -FADE_MS then
    throttle = want * (-over / FADE_MS)
  end
  input.event("throttle", throttle, 2, nil, nil, nil, SOURCE)
end

M.setPace = function(kmh)
  pace = math.max(10, tonumber(kmh) or 80) / 3.6
  input.setAllowedInputSource("throttle", SOURCE, true)
end

M.release = function()
  if pace then
    pace = nil
    input.setAllowedInputSource("throttle", nil)
    input.event("throttle", driverThrottle(), 2, nil, nil, nil, "local")
  end
end

M.isActive = function()
  return pace ~= nil
end

M.updateGFX = updateGFX
M.onReset = function() end -- keep the limit across resets during formation

return M
