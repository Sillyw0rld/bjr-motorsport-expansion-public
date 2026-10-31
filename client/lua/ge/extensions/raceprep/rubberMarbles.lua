-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared off-line rubber debris. The server caps density and owns persistence;
-- clients fade between snapshots. Full density: -3% grip, linear 10-minute fade.
local M={LIFETIME=600,GRIP_LOSS=.03,MAX_CELLS=50000,MAX_PARTICLES=96,MERGE_ROWS=1500,MERGE_MS=1,UPLOAD_ROWS=150,SEND_S=2.5} -- small uploads: see rubberLine L.UPLOAD_ROWS (server limit: one per 2 s)
-- Wheels on marbles (2026-10-21, as in rFactor 2 / AMS2 / iRacing): a wheel
-- crossing a cell thins it a little (TAKE_PER_M of its density per metre, so a
-- busy spot thins over several passes, never in one) and the car's tyres pick
-- some up: up to PICKUP_LOSS grip, fading with PICKUP_TAU (gone in ~12 s).
-- Owner: mild, never a mystery (the HUD shows a "Marbles on tyres" pill).
M.TAKE_PER_M,M.PICKUP_GAIN,M.PICKUP_LOSS,M.PICKUP_TAU,M.PICKUP_SHOW=.06,2.5,.02,4,.15
local cells,pending,air,tiles={},{},{},{}
local taken,pickup={},{}
local EMPTY={}
local inbox,inboxAt,inboxN={},1,0
local TILE=32
local function nowMS()
 return Engine and Engine.Platform and Engine.Platform.getSystemTimeMS and Engine.Platform.getSystemTimeMS()
  or os.clock()*1000
end
local function tileIndexKey(ix,iy) return (ix+1048576)*2097152+(iy+1048576) end
local function tileKey(x,y) return tileIndexKey(math.floor(x/TILE),math.floor(y/TILE)) end
local clock,sendClock,count=0,0,0
local enabled,online,level,synced=false,false,nil,false
local nextEmit={}
local function finite(v,a,b) v=tonumber(v);return v and v==v and v>=a and v<=b and v end
local function key(x,y) return tileIndexKey(math.floor(x),math.floor(y)) end
M.cellKey=tileIndexKey
local function density(c) return math.max(0,c.a-(clock-c.at)*(c.fade or c.a/M.LIFETIME)) end
M.count=function() return count end
M.cells=function() return cells end
M.pending=function() return pending end
M.queued=function() return inboxN-inboxAt+1 end
M.clear=function() cells,pending,air,nextEmit,tiles,taken,pickup={},{},{},{},{},{},{};inbox,inboxAt,inboxN={},1,0;count=0;synced=false end
M.configure=function(on,connected,map)
 if map~=level or connected~=online then M.clear();level=map;online=connected end
 enabled=on==true
 if not enabled then air={} end
end
M.onReset=function(map)
 if map~=(getCurrentLevelIdentifier and getCurrentLevelIdentifier()) then return end
 M.clear();level=map;synced=true
end
M.deposit=function(x,y,z,amount,fx,fy,remote,remaining)
 if not finite(x,-1e6,1e6) or not finite(y,-1e6,1e6) or not finite(z,-1e5,1e5) or not finite(amount,0,1) then return end
 local ix,iy=math.floor(x),math.floor(y)
 local k=tileIndexKey(ix,iy);local c=cells[k]
 if not c and count>=M.MAX_CELLS then return end
 if not c then
  c={ix=ix,iy=iy,x=ix+.5,y=iy+.5};cells[k]=c;count=count+1
  local tk=tileKey(x,y);tiles[tk]=tiles[tk] or {};tiles[tk][k]=c
 end
 c.a=remote and amount or math.min(1,(c.a and density(c) or 0)+amount)
 c.z,c.at,c.fx,c.fy=z,clock,fx or 1,fy or 0
 c.fade=c.a/math.max(.1,remaining or M.LIFETIME)
 if online and not remote then pending[k]=(pending[k] or 0)+amount end
end
local function mergeRow(row)
 local x,y,z,a,fx,fy,remaining=row:match('^(%-?%d+),(%-?%d+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$')
 remaining=finite(remaining,0,600)
 x,y,z,a,fx,fy=finite(x,-1e6,1e6),finite(y,-1e6,1e6),finite(z,-1e5,1e5),finite(a,0,1),finite(fx,-1.5,1.5),finite(fy,-1.5,1.5)
 if x and y and z and a and fx and fy and remaining then
  local k=key(x,y)
  M.deposit(x,y,z,math.max(0,math.min(1,a+(pending[k] or 0)-(taken[k] or 0))),fx,fy,true,remaining)
  return 1
 end
 return 0
end
local function drainInbox()
 local stop=math.min(inboxN,inboxAt+M.MERGE_ROWS-1)
 local started=nowMS()
 local i=inboxAt
 while i<=stop do
  mergeRow(inbox[i]);inbox[i]=nil;i=i+1
  if i%64==0 and nowMS()-started>M.MERGE_MS then break end
 end
 inboxAt=i
 if inboxAt>inboxN then inbox,inboxAt,inboxN={},1,0 end
end
M.onDelta=function(payload)
 if type(payload)~='string' or #payload>512000 or not synced then return 0 end
 local map,wire=payload:match('^([^|]+)|(.+)$');if map~=level then return 0 end
 local n=0
 for row in wire:gmatch('[^;]+') do inboxN=inboxN+1;inbox[inboxN]=row;n=n+1 end
 return n
end
M.levelAt=function(x,y,z)
 if not enabled then return 0 end
 local c=cells[key(x,y)]
 return c and (not z or math.abs(c.z-z)<1) and density(c) or 0
end
M.factor=function(x,y,z) return 1-M.GRIP_LOSS*M.levelAt(x,y,z) end
M.flush=function()
 if not online or (not require('ge/extensions/raceprep/frontend').isCareer() and not TriggerServerEvent) then return 0 end
 local keys={};for k in pairs(pending) do keys[#keys+1]=k end;table.sort(keys)
 local rows,sent={},{}
 for _,k in ipairs(keys) do
  if #rows>=M.UPLOAD_ROWS then break end
  local c=cells[k];local a=math.min(1,pending[k])
  if c and a>=.001 then
   rows[#rows+1]=string.format('%d,%d,%.2f,%.3f,%.3f,%.3f',c.ix,c.iy,c.z,a,c.fx,c.fy);sent[k]=a
  end
 end
 if #rows>0 then
  local ok,result=pcall(require('ge/extensions/raceprep/net').send,'RacePrepMarbleAdd',tostring(level)..'|'..table.concat(rows,';'))
  if ok and result~=false then
   for k,a in pairs(sent) do pending[k]=pending[k]-a;if pending[k]<.001 then pending[k]=nil end end
  else return 0 end
 end
 return #rows
end
-- marbles wheels took off cells (server limit: one per 2 s, like additions)
M.flushTakes=function()
 if not online then return 0 end
 local keys={};for k in pairs(taken) do keys[#keys+1]=k end;table.sort(keys)
 local rows,sent={},{}
 for _,k in ipairs(keys) do
  if #rows>=M.UPLOAD_ROWS then break end
  local c=cells[k];local a=taken[k]
  if c and a>=.001 then rows[#rows+1]=string.format('%d,%d,%.3f',c.ix,c.iy,math.min(1,a)) end
  sent[k]=a
 end
 for k in pairs(sent) do taken[k]=nil end
 if #rows>0 then pcall(require('ge/extensions/raceprep/net').send,'RacePrepMarbleTake',tostring(level)..'|'..table.concat(rows,';')) end
 return #rows
end
-- Tyre debris as small 3D rubber pieces. Flight follows the damage-particle
-- technique (inherited velocity, ballistic flight, camera-facing flat-shaded
-- shapes drawn with debugDrawer); shapes, sizes and palette are Race Prep's own.
-- Real reference (Pirelli, 2011): pieces of 10-20 g ("toffee" strips, ~2-3 cm);
-- harder compounds shed small round marbles (~0.5-1.5 cm). Softer compounds
-- and harder slides shed more. Landed pieces ARE the marbles: one piece per
-- CHUNK of cell density, so every client draws the same marbles from the
-- synced cells (positions/shapes hashed from the cell), no per-piece traffic.
M.CHUNK=.035                -- density one landed piece adds
-- Drawn size over real size (sims exaggerate marbles to be seen): SCALE up to
-- NEAR, growing smoothly to SCALE_FAR at FAR, so far pieces read without
-- changing close ones. Both are Track settings sliders (owner 2026-10-21).
M.SCALE,M.SCALE_FAR=5,12
M.setScale=function(close,far)
 M.SCALE=math.max(1,math.min(10,tonumber(close) or 5))
 M.SCALE_FAR=math.max(1,math.min(25,tonumber(far) or 12))
end
M.MAX_PER_CELL=10           -- pieces drawn per 1 m cell at most
M.NEAR,M.FAR=6,80           -- full shape inside NEAR, single triangle to FAR (m): seen coming at speed (owner 2026-10-21)
M.MAX_DRAW=240              -- pieces drawn per frame (air + landed), nearest first; far cells draw fewer
M.MAX_TRIS=480              -- debugDrawer triangles per frame: ~1 us each + render-side cost (in-game 2026-10-17; raised with FAR 2026-10-21)
M.MIN_ANGLE=.0011           -- smallest drawn size/distance (~1 px at 1080p): smaller or farther pieces fade, never pop
M.FADE_STEPS=8              -- transparency steps for fading pieces (palette built once per step)
M.SLIP_MIN,M.SLIP_FULL=1.2,6  -- wheelspin / lock-up slip (m/s) where shedding starts / is certain
-- Cornering sheds by slip ANGLE, not slip speed (owner 2026-10-21; real tyres
-- wear by sliding in the contact patch and shed marbles every lap at the
-- limit, which is ~5-8 deg): nothing below ANGLE_START, a small LIMIT_CHANCE
-- per try at the limit, ramping to certain from ANGLE_SLIDE to ANGLE_FULL.
-- Before, side slip in m/s made fast corners at the limit shed ~60 % per try
-- and slow ones almost nothing.
M.ANGLE_START,M.ANGLE_LIMIT,M.ANGLE_SLIDE,M.ANGLE_FULL,M.LIMIT_CHANCE=3,6,10,20,.08
-- chance per try (every 0.2 s per wheel) for car speed, side slip and
-- wheelspin / lock-up slip (m/s) and the compound's shed factor
M.shedChance=function(speed,lateral,spin,shed)
 local deg=math.deg(math.atan((lateral or 0)/math.max(5,speed or 0)))
 local corner=0
 if deg>=M.ANGLE_SLIDE then corner=M.LIMIT_CHANCE+(1-M.LIMIT_CHANCE)*math.min(1,(deg-M.ANGLE_SLIDE)/(M.ANGLE_FULL-M.ANGLE_SLIDE))
 elseif deg>=M.ANGLE_START then corner=M.LIMIT_CHANCE*math.min(1,(deg-M.ANGLE_START)/(M.ANGLE_LIMIT-M.ANGLE_START)) end
 local wheel=math.max(0,math.min(1,((spin or 0)-M.SLIP_MIN)/(M.SLIP_FULL-M.SLIP_MIN)))
 return math.max(corner,wheel)*math.min(1,(shed or 1)*.75)
end
M.SHED={standard=.6,sport=.8,semi_slick=1,race_hard=1.1,race=1.3,race_medium=1.3,race_soft=1.6,race_supersoft=2}
M.shedFor=function(compound) return M.SHED[compound or ''] or .8 end
local band,bxor,rshift,tobit=bit and bit.band,bit and bit.bxor,bit and bit.rshift,bit and bit.tobit
local function hash01(ix,iy,j,salt)
 local n=tobit(ix*374761393+iy*668265263+j*362437+salt*1442695)
 n=bxor(n,rshift(n,13));n=tobit(n*1274126177);n=bxor(n,rshift(n,16))
 return band(n,65535)/65536
end
-- shape library: polygons in -0.5..0.5, centroid-fanned, faceted by a fixed
-- light so a flat shape reads as a 3D lump. {ax,ay,bx,by,cx,cy,shade}
local SHAPES={marble={},strip={}}
local function build(kind,variants,points,stretch,seed)
 local r=seed
 local function rnd() r=(r*1103515245+12345)%2147483648;return r/2147483648 end
 for v=1,variants do
  local verts={}
  for i=1,points do
   local a=(i-1)/points*2*math.pi+rnd()*.35
   local rad=.5*(.72+rnd()*.28)
   verts[i]={math.cos(a)*rad,math.sin(a)*rad*stretch+(stretch<1 and math.cos(a)*.12*(rnd()-.5) or 0)}
  end
  -- vertex ring (fan around the centre) and one facet tone per edge
  local ring={n=points}
  for i=1,points do
   local a,b=verts[i],verts[i%points+1]
   local d=(a[1]+b[1])/3*-.5+(a[2]+b[2])/3*.866
   ring[2*i-1],ring[2*i]=a[1],a[2]
   ring.shade=ring.shade or {};ring.shade[i]=d>.06 and 2 or d<-.06 and 3 or 1
  end
  SHAPES[kind][v]=ring
 end
end
build('marble',6,5,1,1301);build('strip',4,6,.38,2602)
local FAR_SHAPE={n=3,far=true,-.5,-.2,.5,-.2,0,.35,shade={1}}
-- dark rubber, three facet tones x three brightness levels (ColorI, built once)
local PAL,FADED
local function palette()
 if PAL or not color then return PAL end
 PAL,FADED={},{}
 for step=1,M.FADE_STEPS do FADED[step]={} end
 for l=1,3 do
  local f=.85+(l-1)*.15
  local function c(v) return math.floor(v*f+.5) end
  PAL[l]={color(c(27),c(27),c(29),255),color(c(64),c(63),c(66),255),color(c(11),c(11),c(12),255)}
  for step=1,M.FADE_STEPS-1 do
   local a=math.floor(255*step/M.FADE_STEPS+.5)
   FADED[step][l]={color(c(27),c(27),c(29),a),color(c(64),c(63),c(66),a),color(c(11),c(11),c(12),a)}
  end
 end
 return PAL
end
-- How opaque a piece of this size at this distance is drawn (0: not at all,
-- FADE_STEPS: solid) and the size to draw it at: under MIN_ANGLE a piece is
-- held at that size and fades with how much smaller it really is; past
-- 75 % of FAR it fades to nothing at FAR (Dynamic Damage Particles 2.0 idea).
M.fade=function(size,l)
 local minS=l*M.MIN_ANGLE;local f=1
 if size<minS then f=size/minS;size=minS end
 local edge=M.FAR*.75
 if l>edge then f=f*math.max(0,(M.FAR-l)/(M.FAR-edge)) end
 return math.min(M.FADE_STEPS,math.floor(f*M.FADE_STEPS+.5)),size
end
local t1,t2,t3
local tris=0
local fwx,fwy,fwz=0,0,0
-- 1 drawn, 0 culled (behind the camera / too small to see), -1 budget spent
local function drawPiece(px,py,pz,size,tri,shade,c,s,cx,cy,cz)
 local dx,dy,dz=cx-px,cy-py,cz-pz
 if dx*fwx+dy*fwy+dz*fwz>0 then return 0 end
 local l=math.sqrt(dx*dx+dy*dy+dz*dz);if l<1e-4 then return 0 end
 if l>M.NEAR then size=size*(1+(M.SCALE_FAR/M.SCALE-1)*math.min(1,(l-M.NEAR)/(M.FAR-M.NEAR))) end
 local step;step,size=M.fade(size,l);if step<1 then return 0 end
 local nt=tri.far and 1 or tri.n
 if tris+nt>M.MAX_TRIS then return -1 end
 dx,dy,dz=dx/l,dy/l,dz/l
 local rx,ry=dy,-dx;local rl=math.sqrt(rx*rx+ry*ry)
 if rl<1e-6 then rx,ry,rl=1,0,1 end
 rx,ry=rx/rl,ry/rl
 -- up = right x dir (right is horizontal)
 local ux,uy,uz=ry*dz,-rx*dz,rx*dy-ry*dx
 local Rx,Ry,Rz=(rx*c+ux*s)*size,(ry*c+uy*s)*size,uz*s*size
 local Ux,Uy,Uz=(ux*c-rx*s)*size,(uy*c-ry*s)*size,uz*c*size
 local pal=step<M.FADE_STEPS and FADED[step][shade] or PAL[shade]
 if tri.far then
  t1:set(px+Rx*tri[1]+Ux*tri[2],py+Ry*tri[1]+Uy*tri[2],pz+Rz*tri[1]+Uz*tri[2])
  t2:set(px+Rx*tri[3]+Ux*tri[4],py+Ry*tri[3]+Uy*tri[4],pz+Rz*tri[3]+Uz*tri[4])
  t3:set(px+Rx*tri[5]+Ux*tri[6],py+Ry*tri[5]+Uy*tri[6],pz+Rz*tri[5]+Uz*tri[6])
  debugDrawer:drawTriSolid(t1,t2,t3,pal[1],true)
  tris=tris+1;return 1
 end
 -- fan: the centre once, every ring vertex once (shared by neighbouring facets)
 t1:set(px,py,pz)
 local a,b=t2,t3
 a:set(px+Rx*tri[1]+Ux*tri[2],py+Ry*tri[1]+Uy*tri[2],pz+Rz*tri[1]+Uz*tri[2])
 local n=tri.n
 for i=1,n do
  local k=(i%n)*2
  b:set(px+Rx*tri[k+1]+Ux*tri[k+2],py+Ry*tri[k+1]+Uy*tri[k+2],pz+Rz*tri[k+1]+Uz*tri[k+2])
  debugDrawer:drawTriSolid(t1,a,b,pal[tri.shade[i]],true)
  a,b=b,a
 end
 tris=tris+n
 return 1
end
-- a landed or remote piece j of cell c: deterministic for every client
local function cellPiece(c,j)
 local pc=c.pc;if not pc then pc={};c.pc=pc end
 local q=pc[j]
 if not q then
  local h1,h2,h3,h4=hash01(c.ix,c.iy,j,1),hash01(c.ix,c.iy,j,2),hash01(c.ix,c.iy,j,3),hash01(c.ix,c.iy,j,4)
  local strip=h3<.12
  q={x=c.ix+.08+h1*.84,y=c.iy+.08+h2*.84,size=strip and .02+h4*.01 or .005+h4*.01,strip=strip,
   shape=1+math.floor(h4*1000)%(strip and 4 or 6),shade=1+math.floor(h3*1000)%3,cr=math.cos(h1*6.283),sr=math.sin(h1*6.283)}
  pc[j]=q
 end
 return q
end
M.piecesIn=function(c)
 local a=density(c);if a<=.002 then return 0,a end
 return math.min(M.MAX_PER_CELL,math.ceil(a/M.CHUNK-.01)),a
end
M.emit=function(id,p,vel,forward,slip,lineLevel,shed,speed,lateral,spin)
 if not enabled or not finite(slip,0,5000) or not finite(p.x,-1e6,1e6) or not finite(p.y,-1e6,1e6) or not finite(p.z,-1e5,1e5)
  or not finite(vel.x,-5000,5000) or not finite(vel.y,-5000,5000) or not finite(forward.x,-1.5,1.5) or not finite(forward.y,-1.5,1.5) or #air>=M.MAX_PARTICLES or clock<(nextEmit[id] or 0) then return end
 nextEmit[id]=clock+.2
 shed=finite(shed,0,3) or 1
 -- callers without the split (older tests) count all slip as wheelspin
 local chance=M.shedChance(finite(speed,0,5000) or 0,finite(lateral,0,5000) or 0,finite(spin,0,5000) or (lateral==nil and slip) or 0,shed)
 if math.random()>chance then return end
 local side=(math.random()<.5 and -1 or 1)
 local strip=math.random()<math.min(.5,.05+.12*math.max(0,shed-1)+(slip>8 and .1 or 0))
 local size=strip and .02+math.random()*.01 or .005+math.random()*.01
 air[#air+1]={x=p.x,y=p.y,z=p.z+.08,ground=p.z,age=0,
  vx=vel.x*.12-forward.y*side*6,vy=vel.y*.12+forward.x*side*6,vz=2+math.random(),
  fx=forward.x,fy=forward.y,side=side,lineLevel=lineLevel,size=size,strip=strip,
  shape=math.random(strip and 4 or 6),shade=math.random(3),roll=math.random()*6.283,spin=(math.random()-.5)*24}
end
M.update=function(dt)
 if inboxAt<=inboxN then drainInbox() end
 dt=math.max(0,dt or 0);clock=clock+dt
 if not enabled then return end
 for i=#air,1,-1 do
  local p=air[i];p.age=p.age+dt;p.vz=p.vz-9.81*dt
  p.x,p.y,p.z=p.x+p.vx*dt,p.y+p.vy*dt,p.z+p.vz*dt;p.roll=p.roll+p.spin*dt
  if p.z<=p.ground or p.age>1.2 then
   -- Do not settle on the established racing-line corridor; a piece a wheel
   -- flicked off a cell was already taken from it and does not land again.
   if p.settle~=false and (not p.lineLevel or p.lineLevel(p.x,p.y,p.ground)==0) then
    local z=p.ground
    if castRayStatic and vec3 then
     local distance=castRayStatic(vec3(p.x,p.y,z+1),vec3(0,0,-1),3)
     z=distance and distance<3 and z+1-distance or nil
    end
    if z then
     M.deposit(p.x,p.y,z,M.CHUNK,p.fx,p.fy)
     -- this client keeps its own piece exactly where it landed
     local c=cells[key(p.x,p.y)]
     if c then
      c.loc=c.loc or {}
      if #c.loc>=M.MAX_PER_CELL then table.remove(c.loc,1) end
      c.loc[#c.loc+1]={x=p.x,y=p.y,size=p.size,strip=p.strip,shape=p.shape,shade=p.shade,cr=math.cos(p.roll),sr=math.sin(p.roll)}
     end
    end
   end
   table.remove(air,i)
  end
 end
 for id,v in pairs(pickup) do
  v=v*math.exp(-dt/M.PICKUP_TAU);pickup[id]=v>=.01 and v or nil
 end
 sendClock=sendClock+dt
 if sendClock>=M.SEND_S then
  sendClock=0;M.flush();M.flushTakes()
  for k,c in pairs(cells) do
   if density(c)<=0 and not pending[k] and not taken[k] then cells[k]=nil;local tk=tileKey(c.x,c.y);if tiles[tk] then tiles[tk][k]=nil;if not next(tiles[tk]) then tiles[tk]=nil end end;count=count-1 end
  end
 end
end
-- A wheel of vehicle `id` crossed `dist` metres at p: thin the cell a little,
-- the tyres pick some up, and the pieces that no longer fit the cell flick off
-- the wheel (this client only; the cell change is what syncs).
M.wheelOver=function(id,p,dist,vx,vy)
 if not enabled or not finite(dist,.01,5) or not finite(p.x,-1e6,1e6) or not finite(p.y,-1e6,1e6) then return 0 end
 local k=key(p.x,p.y);local c=cells[k]
 if not c or (p.z and math.abs(c.z-p.z)>=1) then return 0 end
 local d=density(c);if d<=.002 then return 0 end
 local take=math.min(d,d*M.TAKE_PER_M*dist)
 local before=M.piecesIn(c)
 local loc=c.loc;local L=loc and math.min(#loc,before) or 0
 local flicked={}
 local remaining=c.fade and c.fade>0 and d/c.fade or M.LIFETIME
 c.a,c.at=d-take,clock;c.fade=c.a/math.max(.1,remaining)
 if online then taken[k]=(taken[k] or 0)+take end
 pickup[id]=math.min(1,(pickup[id] or 0)+take*M.PICKUP_GAIN)
 local after=M.piecesIn(c)
 for j=after+1,before do flicked[#flicked+1]=j<=L and loc[#loc-L+j] or cellPiece(c,j) end
 if loc then for _=1,math.max(0,L-after) do table.remove(loc) end end
 vx,vy=finite(vx,-5000,5000) or 0,finite(vy,-5000,5000) or 0
 for _,q in ipairs(flicked) do
  if #air>=M.MAX_PARTICLES then break end
  air[#air+1]={x=q.x,y=q.y,z=c.z+.03,ground=c.z,age=0,settle=false,
   vx=vx*.35+(math.random()-.5)*3,vy=vy*.35+(math.random()-.5)*3,vz=1+math.random()*1.5,
   size=q.size,strip=q.strip,shape=q.shape,shade=q.shade,roll=math.random()*6.283,spin=(math.random()-.5)*20}
 end
 return take
end
-- picked-up rubber on vehicle `id`'s tyres: 0..1, and its grip multiplier
M.pickup=function(id) return pickup[id] or 0 end
M.pickupFactor=function(id) return 1-M.PICKUP_LOSS*(pickup[id] or 0) end
-- Draw at render time, nearest first (NEAR pass then FAR pass), within fixed
-- piece and triangle budgets. No allocation per frame after the first.
local function drawCell(c,cx,cy,cz,far2,near2,full,n0)
 local d2=(c.x-cx)^2+(c.y-cy)^2
 if d2>far2 or (full and d2>near2) or (not full and d2<=near2) then return n0 end
 local n,a=M.piecesIn(c);if n==0 then return n0 end
 -- all pieces up close, fewer per cell further out (1 by ~20 m), so the
 -- budget covers a band instead of its first metres (in-game 2026-10-21)
 if d2>near2 then n=math.min(n,math.max(1,math.floor(M.MAX_PER_CELL*(near2/d2)^.75))) end
 local shrink=a<M.CHUNK and math.max(.4,a/M.CHUNK) or 1
 local loc=c.loc;local L=loc and math.min(#loc,n) or 0
 local drawn=n0
 for j=1,n do
  if drawn>=M.MAX_DRAW then return drawn end
  local q=j<=L and loc[#loc-L+j] or cellPiece(c,j)
  local size=q.size*shrink*M.SCALE
  local tri=full and SHAPES[q.strip and 'strip' or 'marble'][q.shape] or FAR_SHAPE
  local r=drawPiece(q.x,q.y,c.z+size*.3,size,tri,q.shade,q.cr,q.sr,cx,cy,cz)
  if r<0 then return M.MAX_DRAW end
  drawn=drawn+r
 end
 return drawn
end
M.draw=function()
 if not enabled or not debugDrawer or not debugDrawer.drawTriSolid or not palette() then return 0 end
 local cam=core_camera and core_camera.getPosition and core_camera.getPosition()
 if not cam then return 0 end
 if not t1 then t1,t2,t3=vec3(0,0,0),vec3(0,0,0),vec3(0,0,0) end
 if debugDrawer.setSolidTriCulling then debugDrawer:setSolidTriCulling(false) end
 tris=0
 local cx,cy,cz=cam.x,cam.y,cam.z
 local f=core_camera.getForward and core_camera.getForward()
 fwx,fwy,fwz=f and f.x or 0,f and f.y or 0,f and f.z or 0
 local n=0
 for i=1,#air do
  local p=air[i]
  if n>=M.MAX_DRAW then break end
  if (p.x-cx)^2+(p.y-cy)^2<=M.FAR^2 then
   local r=drawPiece(p.x,p.y,p.z,p.size*M.SCALE,SHAPES[p.strip and 'strip' or 'marble'][p.shape],p.shade,math.cos(p.roll),math.sin(p.roll),cx,cy,cz)
   if r<0 then break end;n=n+r
  end
 end
 local far2,near2=M.FAR^2,M.NEAR^2
 local t0x,t1x=math.floor((cx-M.FAR)/TILE),math.floor((cx+M.FAR)/TILE)
 local t0y,t1y=math.floor((cy-M.FAR)/TILE),math.floor((cy+M.FAR)/TILE)
 for pass=1,2 do
  for ix=t0x,t1x do for iy=t0y,t1y do
   for _,c in pairs(tiles[tileIndexKey(ix,iy)] or EMPTY) do
    if n>=M.MAX_DRAW then return n end
    n=drawCell(c,cx,cy,cz,far2,near2,pass==1,n)
   end
  end end
 end
 return n
end
M.trianglesDrawn=function() return tris end
M.airCount=function() return #air end
return M
