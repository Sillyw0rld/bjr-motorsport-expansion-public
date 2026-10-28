-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local C={}
C.COLOURS={'#ff8a1f','#ef4b4b','#f2d23c','#7fd89a','#4fd1c5','#4fb4ff','#c46cf0','#ff5fa2','#e8eaed'}
function C.colour(value)
 for _,v in ipairs(C.COLOURS) do if value==v then return true end end
 return false
end
C.STAFF={rename=true,retag=true,recolour=true,makeLeader=true,removeMember=true,remove=true}

function C.new() return {schema=1,serial=0,crews={},members={},history={}} end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function text(s,max) return type(s)=='string' and #s>=2 and #s<=max and not s:find('[%c]') and s:match('%S') end
function C.valid(s)
 if type(s)~='table' or s.schema~=1 or type(s.serial)~='number' or type(s.crews)~='table' or type(s.members)~='table' or type(s.history)~='table' then return false end
 for id,c in pairs(s.crews) do
  if type(c)~='table' or type(c.members)~='table' or type(c.invites)~='table' or type(c.requests)~='table' or type(c.name)~='string' or type(c.tag)~='string' or type(c.colour)~='string' or type(c.leader)~='string' or not c.members[c.leader] then return false end
  for d,m in pairs(c.members) do if s.members[d]~=id or type(m)~='table' or type(m.order)~='number' then return false end end
 end
 for d,id in pairs(s.members) do if not s.crews[id] or not s.crews[id].members[d] then return false end end;return true
end
function C.apply(s,actor,p,max,now,staff,known)
 local id=p.crew or s.members[actor];local c=id and s.crews[id]
 if C.STAFF[p.action] and not staff then return false,'Manage crews permission required.' end
 local function joined(driver,cid) s.history[driver]=s.history[driver] or {};table.insert(s.history[driver],{crew=cid,joined=now}) end
 local function left(driver,cid) for i=#(s.history[driver] or {}),1,-1 do local m=s.history[driver][i];if m.crew==cid and not m.left then m.left=now;break end end end
 local function join(target)
  if s.members[target] or not known(target) or count(c.members)>=max then return false,'Crew full or driver already belongs to a crew.' end
  s.serial=s.serial+1;c.members[target]={joined=now,order=s.serial};s.members[target]=id;joined(target,id)
  for _,crew in pairs(s.crews) do crew.invites[target]=nil;crew.requests[target]=nil end;return true
 end
 if p.action=='create' then
  if s.members[actor] or not text(p.name,40) or not text(p.tag,4) or not p.tag:match('^[a-zA-Z0-9]+$') or not C.colour(p.colour) then return false,'Choose a name, a 2–4 letter or number tag and one of the nine crew colours; one crew per driver.' end
  for _,crew in pairs(s.crews) do if crew.tag:lower()==p.tag:lower() then return false,'That crew tag is already taken.' end end
  s.serial=s.serial+1;id='crew-'..s.serial
  s.crews[id]={id=id,name=p.name,tag=p.tag:upper(),colour=p.colour,leader=actor,members={[actor]={joined=now,order=s.serial}},invites={},requests={}}
  s.members[actor]=id;joined(actor,id);return true
 end
 if not c then return false,'Crew no longer exists.' end
 if p.action=='request' and not s.members[actor] then if count(c.members)>=max then return false,'Crew full.' end;c.requests[actor]=now;return true end
 if p.action=='accept' and c.invites[actor] then return join(actor) end
 if p.action=='decline' then c.invites[actor]=nil;c.requests[actor]=nil;return true end
 if p.action=='retag' and staff then
  if not text(p.tag,4) or not p.tag:match('^[a-zA-Z0-9]+$') then return false,'Use 2–4 letters or numbers.' end
  for other,crew in pairs(s.crews) do if other~=id and crew.tag:lower()==p.tag:lower() then return false,'That crew tag is already taken.' end end
  c.tag=p.tag:upper();return true
 end
 if p.action=='recolour' and staff then if not C.colour(p.colour) then return false,'Choose one of the nine crew colours.' end;c.colour=p.colour;return true end
 if p.action=='makeLeader' and staff and c.members[p.driver] then c.leader=p.driver;return true end
 if p.action=='removeMember' and staff and c.members[p.driver] then
  left(p.driver,id);c.members[p.driver]=nil;s.members[p.driver]=nil
  if not next(c.members) then s.crews[id]=nil
  elseif c.leader==p.driver then local oldest,order;for d,m in pairs(c.members) do if not order or m.order<order then oldest,order=d,m.order end end;c.leader=oldest end
  return true
 end
 if p.action=='rename' and staff and text(p.name,40) then c.name=p.name;return true end
 if p.action=='remove' and staff then for d in pairs(c.members) do left(d,id);s.members[d]=nil end;s.crews[id]=nil;return true end
 if p.action=='leave' and s.members[actor]==id then
  left(actor,id);c.members[actor]=nil;s.members[actor]=nil
  if next(c.members)==nil then s.crews[id]=nil
  elseif c.leader==actor then
   local oldest,order
   for d,m in pairs(c.members) do if not order or m.order<order then oldest,order=d,m.order end end;c.leader=oldest
  end
  return true
 end
 if p.action=='declineRequest' and c.leader==actor and c.requests[p.driver] then c.requests[p.driver]=nil;return true end
 if c.leader~=actor then return false,'Only the crew leader can do that.' end
 if p.action=='invite' and type(p.driver)=='string' and known(p.driver) and not s.members[p.driver] and count(c.members)<max then c.invites[p.driver]=now;return true end
 if p.action=='approve' and c.requests[p.driver] then return join(p.driver) end
 if p.action=='handover' and c.members[p.driver] then c.leader=p.driver;return true end
 return false,'Crew action refused.'
end
function C.view(s,actor,drivers)
 local rows={};local own=s.members[actor]
 for id,c in pairs(s.crews) do
  local v={id=id,name=c.name,tag=c.tag,colour=c.colour,leader=c.leader,members={},invited=c.invites[actor]~=nil,requested=c.requests[actor]~=nil,requests={}}
  for d,m in pairs(c.members) do v.members[#v.members+1]={id=d,name=(drivers[d] or {}).name or 'Driver',joined=m.joined,leader=c.leader==d} end
  table.sort(v.members,function(a,b) return a.joined<b.joined or a.joined==b.joined and a.id<b.id end)
  if c.leader==actor then for d in pairs(c.requests) do v.requests[#v.requests+1]={id=d,name=(drivers[d] or {}).name or 'Driver'} end end
  rows[#rows+1]=v
 end
 table.sort(rows,function(a,b) return a.name<b.name end);return {items=rows,own=own}
end
return C
