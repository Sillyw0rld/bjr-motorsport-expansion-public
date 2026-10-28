-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Points/countback series layered on BeamJoy tournament races; no BeamJoy data writes.
local C={POINTS={25,18,15,12,10,8,6,4,2,1}}
C.new=function() return {schema=1,series={}} end
C.create=function(store,name,now,link)
 local id=tostring(now)..'-'..tostring(#store.series+1)
 local s={id=id,name=tostring(name or 'Race Prep Championship'):sub(1,80),status='draft',rounds={},results={},drivers={},
  round=1,linkTournament=link==true,fastestLapBonus=true,seen={}}
 store.series[#store.series+1]=s;store.active=id;return s
end
C.active=function(store) for _,s in ipairs(store.series) do if s.id==store.active then return s end end end
C.standings=function(s)
 local rows={};for _,d in pairs(s.drivers) do rows[#rows+1]=d end
 table.sort(rows,function(a,b)
  if a.points~=b.points then return a.points>b.points end
  for pos=1,100 do local aa,bb=a.finishes[pos] or 0,b.finishes[pos] or 0;if aa~=bb then return aa>bb end end
  return tostring(a.name)<tostring(b.name)
 end)
 local out={};for i,d in ipairs(rows) do out[i]={position=i,name=d.name,points=d.points,wins=d.finishes[1] or 0,races=d.races} end
 return out
end
C.record=function(store,res,identity,tournament)
 local s=C.active(store)
 if not s or s.status~='running' or (s.linkTournament and not tournament) then return false end
 -- the first listed round not yet raced on this map + race (any order)
 s.done=s.done or {}
 local round,roundIndex
 for i,r in ipairs(s.rounds) do
  if not s.done[tostring(i)] and tostring(r.raceID)==tostring(res.raceID) and
   tostring(r.level or ''):lower()==tostring(res.level or ''):lower() then round,roundIndex=r,i;break end
 end
 if not round then return false end
 local key=res.runID or res.key
 if not key or s.seen[key] then return false end
 s.seen[key]=true
 local roundRows,seen={},{}
 for _,row in ipairs(res.rows or {}) do
  local id=identity(row.playerID,row)
  if id and not seen[id] then
   seen[id]=true
   local d=s.drivers[id] or {name=row.name,points=0,races=0,finishes={}}
   d.name=row.name or d.name;d.races=d.races+1
   local points=row.status=='FIN' and (C.POINTS[row.position] or 0) or 0
   if row.status=='FIN' then
    d.finishes[row.position]=(d.finishes[row.position] or 0)+1
    if s.fastestLapBonus and row.fastestLap and row.position<=10 then points=points+1 end
   end
   d.points=d.points+points;s.drivers[id]=d
   roundRows[#roundRows+1]={name=d.name,position=row.position,points=points,total=row.total,status=row.status}
  end
 end
 s.results[#s.results+1]={name=round.name,level=round.level,raceID=round.raceID,runID=key,rows=roundRows}
 s.done[tostring(roundIndex)]=true
 local count=0;for _ in pairs(s.done) do count=count+1 end
 s.round=count+1;if count>=#s.rounds then s.status='completed' end
 return true
end
C.view=function(store)
 local s=C.active(store);if not s then return nil end
 return {id=s.id,name=s.name,status=s.status,round=s.round,totalRounds=#s.rounds,rounds=s.rounds,
  rows=C.standings(s),linkTournament=s.linkTournament}
end
return C
