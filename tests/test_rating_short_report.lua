-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- short rating reports (2026-10-21): a car whose rating is the server's own
-- copy is reported by key; the full parts list (which compresses past BeamMP's
-- 5:1 unpack buffer, a 30 MB retry per packet) only for a rating the server
-- lacks, or when the server answers that the key is missing
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
jsonReadFile=function(path)
 if path:find('ratings%-seed') then return {entries={},baselines={},constants={}} end
 return {models={},parts={}}
end
readFile=function() return '{}' end
local decoded
jsonDecode=function(s) return decoded and decoded[s] or {models={}} end
jsonEncode=function(t) return t end
local reports={}
TriggerServerEvent=function() end
package.loaded['ge/extensions/raceprep/net']={send=function(event,p) if event=='RacePrepComputedRating' then reports[#reports+1]=p end end}
local parts={['/main']='m_body',['/main/engine']='rp_engine'}
local vdata={model='m',activeParts=parts}
core_vehicle_manager={getVehicleData=function() return {vdata=vdata,config={partConfigFilename='vehicles/m/x.pc'}} end}
MPVehicleGE={getVehicleByGameID=function() return {isLocal=true,serverVehicleString='0-11',ownerID=0} end}
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local K=require('ge/extensions/raceprep/ratingIdentity').key('m','x',parts)
R.vehicles[11]=K
decoded={full={entries={[K]={model='m',config='x',pi=600,pi_speed=610,pi_technical=590,class='B',source='computed',enginePotential=require('ge/extensions/raceprep/ratingIdentity').hash({enginePotential='2.33.0:'..require('ge/extensions/raceprep/bjr/setupLibrary').signature(require('common/raceprep/engineSelection').settings())}),parts=parts}},constants={v=1},vehicles={}},
 again={delta=true,entries={},vehicles={}}}
R.onRatings('full')
local r=reports[#reports]
assert(r and r.key==K and r.parts==nil and r.serverVehicleID=='0-11' and r.model=='m','server-held rating: short report by key, no parts list')
R.onRatingMissing('0-11')
R.onRatings('again')
r=reports[#reports]
assert(r and r.parts and r.parts['/main/engine']=='rp_engine' and r.key==nil,'server lacks the key: full report next pass')
print('PASS: rating reports: server-held ratings by key, full parts list only when the server lacks it')
