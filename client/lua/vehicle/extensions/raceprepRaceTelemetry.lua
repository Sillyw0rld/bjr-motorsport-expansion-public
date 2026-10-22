-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Opt-in race telemetry only; no changes to wheel forces or vehicle controls.
local M={}
local active,timer,maxThrottle=false,0,0
M.enable=function() active=true end
M.disable=function() active=false;timer=0;maxThrottle=0 end
M.updateGFX=function(dt)
 if not active then return end
 maxThrottle=math.max(maxThrottle,tonumber(electrics.values.throttle) or 0)
 timer=timer+dt;if timer<.5 then return end;timer=0
 local road=false
 for _,w in pairs(wheels.wheels or {}) do
  if (w.downForceRaw or 0)>0 then
   for _,id in ipairs({w.contactMaterialID1 or -1,w.contactMaterialID2 or -1}) do
    if id==10 or id==11 or id==29 then road=true end
   end
  end
 end
 local p={onTrack=road,damage=beamstate and beamstate.damage or 0,throttle=maxThrottle}
 maxThrottle=0
 obj:queueGameEngineLua('if bjiRacePrep then bjiRacePrep.onRaceTelemetry('..obj:getId()..','..serialize(p)..') end')
end
return M
