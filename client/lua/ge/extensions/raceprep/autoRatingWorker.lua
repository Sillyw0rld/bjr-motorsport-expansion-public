-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- One disposable vehicle; never replaces the player's car or changes its parts.
local W={}
function W.new(api)
 local self={};local clock,idle,heartbeat=0,0,-10;local job;local primary
 local function stop(reason,action)
  if not job then return end
  local old=job;job=nil
  if old.vehicle then api.delete(old.vehicle)end
  if primary then api.enter(primary)end
  if action then api.send({action=action,id=old.id,reason=reason})end
 end
 function self.receive(p)
  if p.action=='stop'then if job and p.id==job.id then stop(p.reason)end;return end
  if p.action~='start'or job then return end
  local c=api.current();if not api.free()or idle<30 then api.send({action='abort',id=p.id,reason='Player is active or in a session.'});return end
  if p.localOnly then api.send({action='failed',id=p.id,reason='This client has no verified local-only spawn implementation.'});return end
  primary=c and c.id;job={id=p.id,model=p.model,at=clock,label='Rating new cars ('..p.index..'/'..p.total..')…',primary=primary}
  local ok,id=pcall(api.spawn,p.model,p.config)
  if not ok or not id then stop('Could not spawn default configuration.','failed');return end
  job.vehicle=id
  -- BeamMP may move the camera despite autoEnterVehicle=false.
  if primary then api.enter(primary)else api.freeCamera()end
 end
 function self.update(dt)
  clock=clock+dt;local c=api.current();local active=c and(c.speed>.5 or c.input or job and c.id~=primary)
  if active or not api.free()then idle=0 else idle=idle+dt end
  if job then
   if active or not api.free()then stop('Stopped: driving or activity changed.','abort')
   elseif clock-job.at>25 then stop('Could not rate: collection timed out.','failed')
   elseif job.vehicle and api.rated(job.vehicle)then
    -- Normal rating collection/publishing runs independently. Keep the vehicle
    -- alive until the server acknowledges that the validated entry was saved.
    if not job.sent then job.sent=true;api.send({action='done',id=job.id})end
   end
  end
  if clock-heartbeat>=2 then heartbeat=clock;api.send({action='heartbeat',idle=idle,vehicle=c and c.id})end
 end
 function self.view()return job and {active=true,text=job.label,model=job.model}or {active=false}end
 function self.disconnect()stop('Disconnected');idle=0 end
 return self
end
return W
