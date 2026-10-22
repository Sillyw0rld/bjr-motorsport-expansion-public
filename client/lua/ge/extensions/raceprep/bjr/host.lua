-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR boundary: use the fork's public services, never create legacy BJI globals.
local H={id='beamjoy-revived'}
function H.ready() return beamjoy_main and beamjoy_main.client_ready==true and beamjoy_cache and beamjoy_cache.loaded==true and MPCoreNetwork and MPCoreNetwork.isMPSession() and MPGameNetwork and MPGameNetwork.launcherConnected() end
function H.playerID() return MPConfig and MPConfig.getPlayerServerID and tonumber(MPConfig.getPlayerServerID()) end
function H.vehicle()
 local v=be and be:getPlayerVehicle(0)
 if v and H.own(v:getID()) then return v end
end
function H.own(id)
 if MPVehicleGE and MPVehicleGE.isOwn then return MPVehicleGE.isOwn(id)==true end
 local v=MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(id)
 return v and v.isLocal==true or false
end
function H.canEdit()
 return beamjoy_permissions and BJ_PERMISSIONS and beamjoy_permissions.hasAllPermissions(nil,BJ_PERMISSIONS.SetConfig)==true or false
end
function H.session() return beamjoy_raceRunner and beamjoy_raceRunner.session end
--- the race's green-light time on GetCurrentTimeMillis()'s clock, or nil.
--- BJR main: raceStartTimeMs (that clock). BJR development: raceStartLocalMs on
--- its synchronised clock (beamjoy_clockSync.localMs), converted here so race
--- times and false starts are not off by each player's network delay.
function H.raceStartMs(runner)
 runner=runner or beamjoy_raceRunner
 if not runner then return nil end
 if tonumber(runner.raceStartTimeMs) then return tonumber(runner.raceStartTimeMs) end
 local sync=rawget(_G,'beamjoy_clockSync')
 if tonumber(runner.raceStartLocalMs) and sync and type(sync.localMs)=='function' and GetCurrentTimeMillis then
  local ok,nowSync=pcall(sync.localMs)
  if ok and tonumber(nowSync) then return GetCurrentTimeMillis()-(nowSync-runner.raceStartLocalMs) end
 end
 return nil
end
function H.race()
 local s=H.session();if not s then return end
 for _,r in pairs(beamjoy_races and beamjoy_races.data or {}) do if tostring(r.id)==tostring(s.raceId) then return r,s end end
end
function H.send(event,payload) require('ge/extensions/raceprep/net').send(event,jsonEncode(payload or {})) end
function H.notice(text) if toast and toast.warn then toast.warn(text) elseif guihooks then guihooks.trigger('toastrMsg',{type='warning',msg=text,title='Motorsport Expansion'}) end end
function H.participant()
 local s=H.session();local id=H.playerID()
 for _,p in pairs(s and s.participants or {}) do if tonumber(p.playerID)==id then return p end end
end
function H.onGrid() local s=H.session();return s and s.state=='GRID' or false end
function H.editable() return not H.session() or H.onGrid() and not (H.participant() or {}).ready end
function H.restricted()
 local s=H.session();if not s then return false end
 local settings=s.settings or {};local mode=settings.vehicleRestrictionStartMode
 if mode=='single' then return settings.vehicleRestrictionModel~=nil end
 if mode=='pool' then return type(settings.vehicleRestrictionPool)=='table' and #settings.vehicleRestrictionPool>0 end
 if mode=='raceDefined' then local r=H.race();return r and r.vehicleRestrictionMode and r.vehicleRestrictionMode~='free' or false end
 return false
end
function H.partsEditable() return H.editable() and not H.restricted() end
function H.tuningEditable() local s=H.session();return H.editable() and not (H.restricted() and s.settings.allowTuning==false) end
return H
