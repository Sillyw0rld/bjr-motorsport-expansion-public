-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Native start/finish release and spatial formation-order warnings. No
-- penalties: ambiguous/missing positions fail open, not invented gate metres.
local R={}
local function dot(a,b) return a.x*b.x+a.y*b.y end
local function normal(v)
 if not v then return end
 local len=math.sqrt(v.x*v.x+v.y*v.y)
 if len<.01 then return end
 return {x=v.x/len,y=v.y/len}
end
function R.released(session)
 for _,p in pairs(session and session.participants or {}) do
  if (p.currentLap or 1)>1 or (p.currentGate or 0)>=1 then return true end
 end
 return false
end
function R.order(session,race)
 local out={};local mode=(session.settings or {}).placementMode
 for _,p in pairs(session.participants or {}) do
  local slot
  local pos=p.startPosition and p.startPosition.pos
  if pos then
   for i,s in ipairs(race.startPositions or {}) do
    if math.abs(pos.x-s.pos.x)<.05 and math.abs(pos.y-s.pos.y)<.05 and math.abs(pos.z-s.pos.z)<.1 then slot=i;break end
   end
  end
  slot=slot or (mode=='manual' and p.gridSlot) or (mode=='deterministic' and p.joinIndex)
  if not slot then return nil end -- random assignment is not join order
  out[#out+1]={player=p,slot=slot}
 end
 table.sort(out,function(a,b) if a.slot~=b.slot then return a.slot<b.slot end;return a.player.playerID<b.player.playerID end)
 return out
end
function R.check(session,race,selfID,positions)
 if not session or not race then return end
 local order=R.order(session,race);if not order then return end
 local mine,ahead
 for i,row in ipairs(order) do if tonumber(row.player.playerID)==tonumber(selfID) then mine=row.player;ahead=order[i-1] and order[i-1].player;break end end
 if not ahead then return end
 if (mine.currentGate or 0)~=(ahead.currentGate or 0) or (mine.currentLap or 1)~=(ahead.currentLap or 1) then return end
 local a,b=positions[tonumber(mine.playerID)],positions[tonumber(ahead.playerID)]
 if not a or not b or not a.pos or not b.pos then return end
 local da,db=normal(a.dir),normal(b.dir);if not da or not db or dot(da,db)<.5 then return end
 local direction=normal{x=da.x+db.x,y=da.y+db.y};if not direction then return end
 local dx,dy,dz=a.pos.x-b.pos.x,a.pos.y-b.pos.y,a.pos.z-b.pos.z
 if dx*dx+dy*dy>75*75 or math.abs(dz)>3 then return end
 local metres=dx*direction.x+dy*direction.y
 local lateral=math.abs(dx*direction.y-dy*direction.x)
 if metres>2 and lateral<12 then return {name=ahead.displayName or ahead.playerName or 'the car ahead',metres=metres,playerID=ahead.playerID} end
end
return R
