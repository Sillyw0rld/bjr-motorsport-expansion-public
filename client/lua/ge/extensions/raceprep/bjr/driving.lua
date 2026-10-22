-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- BJR/game objects -> compact HTML driving packet, sampled independently of
-- the setup window. Race timing (positions, gaps, sectors, penalties) is
-- BJR's own: BJR 2.0 sends every player its race HUD data (BJRaceHud), which
-- BJR:ME's HUD reads directly in the UI. This packet adds what BJR does not
-- have: race signals (start lights, flags, false start, formation), the
-- track-limits pill, the race weekend announcement, each driver's class / PI
-- badge, and the practice / qualifying session HUD.
local H=require('ge/extensions/raceprep/bjr/host')
local D={}
local nextBadges,badges=0,{}
local lastRun
D.LIMITS_SHOW_S=5
local function vehicles()
 local out,choices={},{}
 for _,v in pairs(MPVehicleGE and MPVehicleGE.getVehicles and MPVehicleGE.getVehicles() or {}) do
  local pid=tonumber(v.ownerID);local id=v.gameVehicleID
  local object=id and be:getObjectByID(id)
  if pid and object and not v.isDeleted then
   local player
   for _,p in pairs(beamjoy_players and beamjoy_players.players or {}) do if tonumber(p.playerID)==pid then player=p;break end end
   local current=player and player.currentVehicle
   local data={pos=object:getPosition(),dir=object.getDirectionVector and object:getDirectionVector()}
   if current and (current==id or current==v.remoteVehID or current==v.remoteVID) then out[pid]=data end
   local c=choices[pid] or {};choices[pid]=c;c[#c+1]=data
  end
 end
 for pid,c in pairs(choices) do if not out[pid] and #c==1 then out[pid]=c[1] end end
 local own=H.vehicle();if own then out[H.playerID()]={pos=own:getPosition(),dir=own.getDirectionVector and own:getDirectionVector()} end
 return out
end
D.positions=vehicles
function D.reset() lastRun=nil;badges={};nextBadges=0 end
--- class / PI per racer, keyed by BJR's playerName (BJRaceHud rows carry it)
local function raceBadges(s,now)
 if now<nextBadges then return badges end
 nextBadges=now+1000;badges={}
 for _,p in pairs(s and s.participants or {}) do
  local e=raceprepRatings and raceprepRatings.getPlayer and raceprepRatings.getPlayer(p.playerID)
  if p.playerName and type(e)=='table' and e.class and e.pi then badges[p.playerName]={class=e.class,pi=e.pi} end
 end
 return badges
end
function D.packet(now,clock)
 local runner=beamjoy_raceRunner
 local s=runner and (runner.session or runner.spectatingSession)
 local rt=rawget(_G,'bjiRacePrep')
 local director=require('ge/extensions/raceprep/director')
 local session=require('ge/extensions/raceprep/session')
 local live=s and (s.state=='COUNTDOWN' or s.state=='RACE')
 local signals={}
 if live then
  signals.lights=director.lights;local ok,yellow=pcall(director.yellow);if ok then signals.yellow=yellow end
  local flags=director.data and director.data.runID==s.id and director.data.falseStarts
  signals.falseStart=director.falseStart==true or (flags and flags[tostring(H.playerID())]~=nil) or false
  if rt and rt.rolling and rt.rolling.phase=='formation' then signals.formation=rt.rolling.pace or 80;signals.noPassing=rt.rolling.warning end
 end
 -- a new BJR race run: my track-limit cut count starts again
 if s and s.id~=lastRun then lastRun=s.id;session.raceCut=nil elseif not s then lastRun=nil end
 local cut=session.raceCut
 if live and cut and clock and clock-(cut.at or -1e9)<=D.LIMITS_SHOW_S then
  local rules=rt and rt.getRules and rt.getRules(s.raceId) or {}
  signals.limits={cuts=cut.count,mode=rules.trackLimits or 'invalid',after=tonumber(rules.cutPenaltyAfter),seconds=tonumber(rules.cutPenaltySeconds)}
 end
 -- rubber picked up from marbles: a pill, so a loose car is never a mystery
 local okV,vid=pcall(function() return be and be:getPlayerVehicleID(0) end)
 local marbles=package.loaded['ge/extensions/raceprep/rubberMarbles']
 local picked=okV and vid and vid>=0 and marbles and marbles.pickup(vid) or 0
 if picked>=(marbles and marbles.PICKUP_SHOW or 1) then signals.marbles={gripPercent=math.floor(picked*marbles.PICKUP_LOSS*1000+.5)/10} end
 local out={active=H.ready()==true,signals=signals,trackTemp=rt and rt.trackTemp}
 if s then out.race={runID=s.id,state=s.state,raceName=(function() for _,r in pairs(beamjoy_races and beamjoy_races.data or {}) do if r.id==s.raceId then return r.name end end end)(),
  badges=raceBadges(s,now)} end
 local okA,announcement=pcall(function() return session.currentAnnouncement and session.currentAnnouncement() end)
 if okA and announcement then out.announcement=announcement end
 local p=session.data
 if p and p.id then
  if p.state=='running' or p.state=='overtime' or p.state=='ended' then
   local status={}
   if session.status then
    local ok,value=pcall(session.status)
    status=ok and type(value)=='table' and value or {timing=false,message='Session timing status unavailable; refresh or rejoin.'}
   end
   local okLive,liveSectors=pcall(function() return session.liveSectors and session.liveSectors() end)
   out.practice={blocked=status.timing==false and p.state~='ended',reason=status.message,sectorMessage=status.sectorMessage,id=p.id,state=p.state,label=p.label,raceName=p.raceName,remaining=session.remaining(),currentLap=session.currentLapTime(),
    cuts=session.currentLapCuts(),lastLap=session.lastLap,rows=p.rows,laps=session.laps,canEdit=H.canEdit(),active=session.active(),
    live=okLive and liveSectors or nil,playerID=H.playerID()}
  end
 end
 return out
end
return D
