-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Read-only native BJR lobby projection. Never changes grid assignment/Ready.
local G={}
local fields={'class','pi','pi_speed','pi_technical','source','method','anchored','assumptions','flag','performancePI','tuningPotentialPI','weightBonusPI'}
G.RATING_FIELDS=fields
function G.snapshot(session,selfID,ratings)
 local out={active=false,rows={},readyCount=0,total=0}
 if not session or (session.state~='GRID' and session.state~='COUNTDOWN') then return out end
 out.active=true;out.mode=(session.settings or {}).placementMode or 'random'
 for _,p in pairs(session.participants or {}) do
  local id=tonumber(p.playerID)
  if id then
   local row={playerID=id,name=p.displayName or p.playerName or ('Player '..id),model=p.vehicleModel,
    ready=p.ready==true,isSelf=id==tonumber(selfID),joinIndex=tonumber(p.joinIndex),slot=tonumber(p.gridSlot)}
   if ratings and ratings.getPlayer then
    local ok,entry=pcall(ratings.getPlayer,id)
    if ok and type(entry)=='table' and tonumber(entry.pi) then
     row.rating={};for _,key in ipairs(fields) do row.rating[key]=entry[key] end
    end
   end
   out.rows[#out.rows+1]=row
   if row.ready then out.readyCount=out.readyCount+1 end
  end
 end
 table.sort(out.rows,function(a,b)
  local x=out.mode=='manual' and a.slot or a.joinIndex
  local y=out.mode=='manual' and b.slot or b.joinIndex
  x,y=x or math.huge,y or math.huge
  if x~=y then return x<y end
  return a.playerID<b.playerID
 end)
 for i,row in ipairs(out.rows) do
  row.position=out.mode=='manual' and row.slot or out.mode=='deterministic' and i or nil
 end
 out.total=#out.rows
 out.note=out.mode=='random' and 'BJR assigns random grid positions when the countdown starts.' or
  out.mode=='manual' and 'Grid slots are assigned by the BJR host.' or 'Grid positions follow BJR join order.'
 return out
end
return G
