-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Opt-in contact/slide telemetry. Never writes tyre friction itself: KTS owns it.
local M={}
local enabled,clock=false,0
function M.enable() enabled=true end
function M.disable() enabled=false;clock=0 end
function M.updateGFX(dt)
 if not enabled then return end
 clock=clock+(dt or 0);if clock<.1 then return end;clock=0
 local rows={}
 for _,w in pairs(wheels.wheels or {}) do
  local road,wet=false,false
  if (w.downForceRaw or 0)>1 and not w.isBroken then
   for _,id in ipairs({w.contactMaterialID1 or -1,w.contactMaterialID2 or -1}) do
    road=road or id==10 or id==11 or id==29
    wet=wet or id==11
   end
  end
  rows[w.name]={id=w.wheelID,road=road,wet=wet,slip=math.abs(w.lastSlip or 0),
   lateral=math.abs(w.lastSideSlip or 0),rollingSpeed=math.abs((w.angularVelocity or 0)*(w.radius or 0))}
 end
 local e=extensions.luukstyrethermalsandwear
 local p={wheels=rows,kts=e~=nil,patched=e and (type(e.setRubberGrip)=='function' or (extensions.raceprepKTS and extensions.raceprepKTS.status.grip~=nil)) or false,instance=e and tostring(e)..tostring(extensions.raceprepKTS)}
 obj:queueGameEngineLua('local m=package.loaded["ge/extensions/raceprep/rubberLine"] if m then m.onWheels('..obj:getID()..','..serialize(p)..') end')
end
return M
