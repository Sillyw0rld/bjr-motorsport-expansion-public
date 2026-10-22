-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Platform=require("ge/extensions/raceprep/platform")
-- Spatial tyre-metres and per-wheel grip (Race Prep 1.9.0). Works on any
-- map: the whole road has hidden rubber, and it appears where tyres actually
-- run. Every car's wheel contact points are tracked; each metre a tyre rolls
-- over a cell (CELL m square) adds rubber there, more when the tyre slides.
-- The usage map is turned into smooth racing LINES (follow the most-used path
-- along the driving direction; usage-weighted centre and spread give position
-- and width), drawn as overlapping rubber patches along each line whose
-- opacity follows its use, so it darkens gradually. Converted static rubber
-- is restored when disabled through rubberSurface.
local L = {}
local marbles=require('ge/extensions/raceprep/rubberMarbles')

L.CELL = 1.0
L.PER_LAP = 1.401124923 -- Hirochi, ETK800 844_track_M, five laps, 2026-10-14; server authority
L.FULL = L.PER_LAP * 40
L.SLIDE_GAIN = 4
L.STEP, L.WINDOW, L.MIN_LEVEL, L.REBUILD_S = 2, 4, .04, 15
L.MAX_CELLS = 150000
local cells, tiles, pending = {}, {}, {}
local TILE = 16
local count, changed = 0, 0
local wheels, reports, gripSent = {}, {}, {}
-- per car: how readily its tyres shed rubber (softer compounds shed more),
-- refreshed only when the car's parts change (vdata identity)
local shedCache = {}
local function shedFor(id, vdata, wheelName)
 local e = shedCache[id]
 if not e or e.vdata ~= vdata then
  local ok, t = pcall(function() return require('ge/extensions/raceprep/upgrades').fittedTyres(id) end)
  t = ok and t or {}
  e = {vdata = vdata, F = marbles.shedFor(t.front and t.front.compound), R = marbles.shedFor(t.rear and t.rear.compound)}
  shedCache[id] = e
 end
 return tostring(wheelName):sub(1, 1):upper() == 'F' and e.F or e.R
end
local enabled, online, savedLevel = false, false, nil
L.peak=0
local settings={dryBonus=3,wetPenalty=5,lapsToFull=40}
local reportClock, sendClock, gripClock, requestClock = 0,0,0,-1e9
local function nowMS()
 return Engine and Engine.Platform and Engine.Platform.getSystemTimeMS and Engine.Platform.getSystemTimeMS()
  or os.clock()*1000
end
local function finite(v,lo,hi)
 v=tonumber(v);return v and v==v and v>=lo and v<=hi and v or nil
end
-- numeric tile/cell keys: string keys cost a concatenation per lookup (garbage
-- every frame in draw/deposit/levelAt, ~10 per march step in the rebuild); exact for |i| < 2^20
local function tileKey(ix,iy) return (ix+1048576)*2097152+(iy+1048576) end
local function keyOf(x,y) return tileKey(math.floor(x/L.CELL),math.floor(y/L.CELL)) end
L.cellKey=tileKey
local function own(veh)
 local BJI_Veh=Platform.get("BJI_Veh")
 if BJI_Veh and BJI_Veh.isVehicleOwn then return BJI_Veh.isVehicleOwn(veh:getID()) end
 if MPVehicleGE and MPVehicleGE.getVehicleByGameID then
  local v=MPVehicleGE.getVehicleByGameID(veh:getID());return v and v.isLocal==true or false
 end
 return not online
 end
local function object(id)
 return be and be.getObjectByID and be:getObjectByID(id)
end
local function ensure(x,y,z,fx,fy)
 local ix,iy=math.floor(x/L.CELL),math.floor(y/L.CELL)
 local key=tileKey(ix,iy);local c=cells[key]
 if not c and count<L.MAX_CELLS then
  c={ix=ix,iy=iy,x=(ix+.5)*L.CELL,y=(iy+.5)*L.CELL,z=z,amt=0,fx=fx or 0,fy=fy or 1}
  cells[key]=c;count=count+1
  local tk=tileKey(math.floor(c.x/TILE),math.floor(c.y/TILE))
  tiles[tk]=tiles[tk] or {};tiles[tk][#tiles[tk]+1]=c
 end
 return c,key
end
L.deposit=function(x,y,z,amount,fx,fy,localOnly)
 if not finite(x,-1e6,1e6) or not finite(y,-1e6,1e6) or not finite(z,-1e5,1e5) or not finite(amount,0,1e9) or amount<=0 then return end
 local c,key=ensure(x,y,z,fx,fy);if not c then return end
 c.amt=math.min(1e9,c.amt+amount);changed=changed+1
 L.peak=math.max(L.peak,c.amt)
 c.z=c.z+(z-c.z)*.2
 if fx and fy then
  if c.fx*fx+c.fy*fy<0 then fx,fy=-fx,-fy end
  c.fx,c.fy=c.fx*.9+fx*.1,c.fy*.9+fy*.1
 end
 if online and not localOnly then pending[key]=(pending[key] or 0)+amount end
end
L.count=function() return count end
L.cells=function() return cells end
L.pending=function() return pending end
L.onWheels=function(id,p)
 local veh=object(id)
 if veh and own(veh) and type(p)=='table' then
  p.at=reportClock;reports[id]=p
  if not gripSent[id] or gripSent[id].instance~=p.instance then gripSent[id]={instance=p.instance,values={}} end
 end
end
local function mergeRow(row)
 local ix,iy,z,a,fx,fy=row:match('^(%-?%d+),(%-?%d+),([^,]+),([^,]+),([^,]+),([^,]+)$')
 ix,iy,z,a,fx,fy=finite(ix,-1e6,1e6),finite(iy,-1e6,1e6),finite(z,-1e5,1e5),finite(a,0,1e9),finite(fx,-1.5,1.5),finite(fy,-1.5,1.5)
 if not (ix and iy and z and a and fx and fy) then return 0 end
 local c,k=ensure(ix*L.CELL,iy*L.CELL,z,fx,fy)
 if not c then return 0 end
 c.amt=a+(pending[k] or 0);L.peak=math.max(L.peak,c.amt);c.z,c.fx,c.fy=z,fx,fy;changed=changed+1
 return 1
end
L.merge=function(wire)
 if type(wire)~='string' or #wire>512000 then return 0 end
 local merged=0
 for row in wire:gmatch('[^;]+') do merged=merged+mergeRow(row) end
 return merged
end
-- A join or an admin Full/Clean sends the whole map at once (tens of
-- thousands of cells); merging it in one frame stuttered. Rows queue here
-- and L.update merges at most MERGE_ROWS per frame.
L.MERGE_ROWS=1500
-- Uploads stay small: BeamMP's server guesses 5x the compressed size when
-- decompressing and allocates 30 MB to retry when rows of similar numbers
-- compress better than that ("zlib uncompress() failed, trying with a larger
-- buffer"). 150 rows (~3.7x) every 1.25 s keeps the old 600 rows / 5 s rate.
L.UPLOAD_ROWS=150
L.SEND_S=1.25
local inbox,inboxAt,inboxN={},1,0
-- Network deltas are tagged with their map. A late packet from the old
-- level must never paint the new map, even when their coordinates overlap.
L.onDelta=function(payload)
 if type(payload)~='string' or #payload>512000 or not L.synced then return 0 end
 local level,wire=payload:match('^([^|]+)|(.+)$')
 if level~=(getCurrentLevelIdentifier and getCurrentLevelIdentifier()) then return 0 end
 local n=0
 for row in wire:gmatch('[^;]+') do inboxN=inboxN+1;inbox[inboxN]=row;n=n+1 end
 return n
end
-- Also bounded in time: 1500 rows took 3-4 ms in one frame on a full
-- Nordschleife map (127k cells), a visible hitch every server broadcast.
L.MERGE_MS=1
local clock, nextRebuild, lastChanged = 0, 0, -1
local function drainInbox()
 local stop=math.min(inboxN,inboxAt+L.MERGE_ROWS-1)
 local started=nowMS()
 local i=inboxAt
 while i<=stop do
  mergeRow(inbox[i]);inbox[i]=nil;i=i+1
  if i%64==0 and nowMS()-started>L.MERGE_MS then break end
 end
 inboxAt=i
 if inboxAt>inboxN then inbox,inboxAt,inboxN={},1,0;nextRebuild=0 end
end
L.queued=function() return inboxN-inboxAt+1 end
L.flush=function()
 if not online or not TriggerServerEvent then return 0 end
 local keys={};for k in pairs(pending) do keys[#keys+1]=k end;table.sort(keys)
 local rows,sent={},{}
 for _,key in ipairs(keys) do
  -- 600 cells per 5 s upload: batches of 3000 made packets the server's
  -- zlib rejected ("uncompress() failed" every 5 s); the rest waits
  if #rows>=L.UPLOAD_ROWS then break end
  local c=cells[key];local amount=math.min(500,pending[key])
  if c and amount>=.001 then
   rows[#rows+1]=string.format('%d,%d,%.2f,%.3f,%.3f,%.3f',c.ix,c.iy,c.z,amount,c.fx,c.fy);sent[key]=amount
  end
 end
 if #rows>0 then
  local ok,result=pcall(require('ge/extensions/raceprep/net').send,'RacePrepRubberAdd',tostring(savedLevel)..'|'..table.concat(rows,';'))
  if not ok or result==false then return 0 end
  for key,amount in pairs(sent) do pending[key]=pending[key]-amount;if pending[key]<.001 then pending[key]=nil end end
 end
 return #rows
end
L.levelAt=function(x,y,z)
 -- Mean of the 3x3 m around the wheel (empty cells count as 0), the same
 -- measure PER_LAP was calibrated on (the line corridor's mean). The max
 -- cell made grip reach full about twice as fast as the line darkened.
 local ix,iy=math.floor(x/L.CELL),math.floor(y/L.CELL);local sum=0
 for dx=-1,1 do for dy=-1,1 do
  local c=cells[tileKey(ix+dx,iy+dy)]
  if c and (not z or math.abs(c.z-z)<2) then sum=sum+c.amt end
 end end
 local level=sum/9/L.FULL
 return level<L.MIN_LEVEL and 0 or math.min(1,level)
end
L.factor=function(wet,level)
 return 1+(wet and -settings.wetPenalty or settings.dryBonus)/100*math.max(0,math.min(1,level))
end
local function contacts(veh,vdata)
 local out={};local vpos,up=veh:getPosition(),veh:getDirectionVectorUp()
 for i,w in pairs(vdata.wheels or {}) do
  if w.node1 and w.node2 and w.radius then
   local a,b=veh:getNodePosition(w.node1),veh:getNodePosition(w.node2)
   out[w.name or i]={x=(a.x+b.x)*.5+vpos.x-up.x*w.radius,y=(a.y+b.y)*.5+vpos.y-up.y*w.radius,z=(a.z+b.z)*.5+vpos.z-up.z*w.radius}
  end
 end
 return out
end
L.record=function(dt)
 if not (enabled and be and core_vehicle_manager) then return end
 for i=0,be:getObjectCount()-1 do
  local veh=be:getObject(i);local id=veh and veh:getID()
  local d=id and core_vehicle_manager.getVehicleData(id)
  if d and d.vdata and own(veh) then
   local r=reports[id]
   if not r or reportClock-r.at>.6 then
    veh:queueLuaCommand('extensions.load("raceprepRubberTelemetry") raceprepRubberTelemetry.enable()')
   end
   if r and reportClock-r.at<.6 then
    local vel=veh:getVelocity();local speed=vel:length();local fwd=veh:getDirectionVector()
    local slide=speed>2 and math.min(1,math.abs(1-math.abs(vel:dot(fwd))/speed)*6) or 0
    for name,p in pairs(contacts(veh,d.vdata)) do
     local info=r.wheels[name];local key=id..':'..name;local last=wheels[key]
     if info and info.road then
      local spin,side=math.abs((info.rollingSpeed or speed)-speed),math.abs(info.lateral or 0)
      marbles.emit(key,p,vel,fwd,math.max(spin,side),L.levelAt,shedFor(id,d.vdata,name),speed,side,spin)
      if last then
       local dx,dy=p.x-last.x,p.y-last.y;local dist=math.sqrt(dx*dx+dy*dy)
       if dist>.01 and dist<5 then
        marbles.wheelOver(id,p,dist,vel.x,vel.y)
        local steps=math.max(1,math.ceil(dist/.5));local amount=dist*(1+L.SLIDE_GAIN*slide)/steps
        for n=1,steps do local t=n/steps;L.deposit(last.x+dx*t,last.y+dy*t,p.z,amount,dx/dist,dy/dist) end
       elseif dist<=.01 and info.slip>3 then
        L.deposit(p.x,p.y,p.z,math.min(80,info.rollingSpeed)*(dt or 0)*.25,fwd.x,fwd.y)
       end
      end
      wheels[key]=p
     else wheels[key]=nil end
    end
   end
  end
 end
end
local function grip()
 local active=0
 for id,r in pairs(reports) do
  local veh=object(id);local d=veh and core_vehicle_manager.getVehicleData(id)
  if d and own(veh) and reportClock-r.at<.6 then
   if r.patched then
    active=active+1
    local values=gripSent[id] and gripSent[id].values or {};local rows={}
    for name,p in pairs(contacts(veh,d.vdata)) do
     local w=r.wheels[name]
     if w and type(w.id)=='number' then
      local wet=w.wet or require('ge/extensions/raceprep/rubberSurface').wet==true
      -- rubber picked up from marbles stays on the tyre, on and off the road
      local value=(w.road and L.factor(wet,L.levelAt(p.x,p.y,p.z))*marbles.factor(p.x,p.y,p.z) or 1)*marbles.pickupFactor(id)
      if not values[w.id] or math.abs(value-values[w.id])>.001 then rows[#rows+1]=string.format('[%d]=%.5f',w.id,value);values[w.id]=value end
     end
    end
    if #rows>0 then veh:queueLuaCommand('local e=extensions.'..(Platform.isBJR() and 'raceprepKTS' or 'luukstyrethermalsandwear')..' if e and e.setRubberGrip then e.setRubberGrip({'..table.concat(rows,',')..'}) end') end
   end
  end
 end
 L.ktsActive=active>0
end
L.vehicleChanged=function(id)
 reports[id],gripSent[id]=nil,nil
 local prefix=tostring(id)..':'
 for k in pairs(wheels) do if k:sub(1,#prefix)==prefix then wheels[k]=nil end end
end
L.restore=function()
 for id in pairs(reports) do
  local v=object(id)
  if v and own(v) then v:queueLuaCommand('local e=extensions.'..(Platform.isBJR() and 'raceprepKTS' or 'luukstyrethermalsandwear')..' if e and e.setRubberGrip then e.setRubberGrip({}) end if raceprepRubberTelemetry then raceprepRubberTelemetry.disable() end') end
 end
 reports,gripSent,wheels={},{},{}
 L.ktsActive=false
end
L.configure=function(rubber,clockValue)
 local BJI=Platform.get("BJI")
 local map=getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil
 local connected=BJI and BJI.CLIENT_READY==true or false
 if map~=savedLevel or connected~=online then
  L.restore();L.clear();savedLevel=map;online=connected;requestClock=-1e9
 end
 settings=rubber or settings
 L.FULL=(tonumber(settings.perLap) or L.PER_LAP)*math.max(10,math.min(400,tonumber(settings.lapsToFull) or 40))
 settings.dryBonus=math.max(0,math.min(10,tonumber(settings.dryBonus) or 3))
 settings.wetPenalty=math.max(0,math.min(20,tonumber(settings.wetPenalty) or 5))
 local nextEnabled=settings.enabled==true and (not settings.level or settings.level==map)
 if enabled and not nextEnabled then L.restore() end
 if not enabled and nextEnabled and online then L.synced=false;requestClock=-1e9 end
 enabled=nextEnabled
 marbles.configure(enabled,online,map);marbles.setScale(settings.marbleSize,settings.marbleSizeFar)
 require('ge/extensions/raceprep/rubberSurface').update(enabled)
 if online and clockValue-requestClock>=30 then
  -- Only request until a reset arrives. Later additions come as deltas.
  if not L.synced then TriggerServerEvent('RacePrepRubberGet','') end
  requestClock=clockValue
 end
end
L.onReset=function(level)
 if level~=(getCurrentLevelIdentifier and getCurrentLevelIdentifier()) then return end
 L.clear();L.synced=true
end
L.statusText=function()
 return string.format('%d cells, %d lines — %s',count,#(L.currentLines and L.currentLines() or {}),L.ktsActive and 'KTS per-wheel grip active' or (Platform.isBJR() and 'visual only; KTS runtime hook unavailable' or 'visual only; KTS rubber patch needed'))
end

---------------------------------------------------------------- lines

-- Rebuilding is spread over frames (a single-frame rebuild froze the game for
-- a moment every few seconds): inside the build job, work yields whenever its
-- slice of the frame (BUDGET_MS) is used up. Outside a job nothing yields.
L.BUDGET_MS = 1.5
local sliceStart = 0
-- The clock is read every YIELD_CHECK calls: reading it on every call (1.4
-- million native calls per Nordschleife rebuild) made the rebuild 7x slower
-- than the work itself, so it never finished within REBUILD_S.
local YIELD_CHECK = 64
local checks = 0
local function maybeYield()
    checks = checks + 1
    if checks < YIELD_CHECK then return end
    checks = 0
    if coroutine.running() and nowMS() - sliceStart > L.BUDGET_MS then coroutine.yield() end
end

-- cells within r of (x, y): fills one reused buffer (a new table per march
-- step was most of a rebuild's garbage); returns it and the count
local nearOut = {}
local function near(x, y, r)
    local out, n = nearOut, 0
    local r2 = r * r
    for ix = math.floor((x - r) / TILE), math.floor((x + r) / TILE) do
        for iy = math.floor((y - r) / TILE), math.floor((y + r) / TILE) do
            local tile = tiles[tileKey(ix, iy)]
            if tile then
                for t = 1, #tile do
                    local c = tile[t]
                    local dx, dy = c.x - x, c.y - y
                    if dx * dx + dy * dy <= r2 then n = n + 1; out[n] = c end
                end
            end
        end
    end
    return out, n
end

-- Road already covered by a line (1.9.3). Lines used to start again from
-- any cell outside the first line's 4 m corridor and then march onto the
-- same road: on VIR 9-10 lines lay on top of each other, so the stack drew
-- almost black, overflowed the decal cap (pieces popped in and out as the
-- camera moved) and the rebuild did ten times the work. Now every accepted
-- node is indexed; a march stops where another line (or its own earlier
-- part: the lap closed) already runs in the same direction.
local TAKEN_CELL = 3
local takenKey = tileKey
local function covered(taken, x, y, dx, dy, line, index)
    local ix, iy = math.floor(x / TAKEN_CELL), math.floor(y / TAKEN_CELL)
    for ox = -1, 1 do
        for oy = -1, 1 do
            local list = taken[takenKey(ix + ox, iy + oy)]
            if list then
                for i = 1, #list do
                    local t = list[i]
                    if (t.x - x) ^ 2 + (t.y - y) ^ 2 < 2.5 * 2.5 and t.dx * dx + t.dy * dy > 0.7
                        and (t.line ~= line or math.abs(t.index - index) > 40) then return true end
                end
            end
        end
    end
    return false
end
local function take(taken, x, y, dx, dy, line, index)
    local k = takenKey(math.floor(x / TAKEN_CELL), math.floor(y / TAKEN_CELL))
    taken[k] = taken[k] or {}
    table.insert(taken[k], { x = x, y = y, dx = dx, dy = dy, line = line, index = index })
end

-- march from a seed along the driving direction (sign 1) or against it (-1);
-- cells always point the way cars drove, so the filter uses the travel dir
local function march(seed, tx, ty, sign, used, minAmt, taken, line)
    local nodes = {}
    local px, py, pz = seed.x, seed.y, seed.z
    local dx, dy = tx, ty
    for _ = 1, 15000 do -- 30 km: a Nordschleife lap fits (stopped at 6 km before)
        maybeYield()
        local qx, qy = px + dx * L.STEP * sign, py + dy * L.STEP * sign
        local nx, ny = -dy, dx
        local sw, sl, sl2, sz, sa, fx, fy, n = 0, 0, 0, 0, 0, 0, 0, 0
        local around, count = near(qx, qy, L.WINDOW)
        for ci = 1, count do
            local c = around[ci]
            -- the whole corridor belongs to this line (no duplicate lines
            -- starting from cells next to it); other-direction cells excepted
            if (c.fx * dx + c.fy * dy) > 0 then c.used = used end
            local along = (c.x - qx) * dx + (c.y - qy) * dy
            if c.amt >= minAmt and math.abs(along) <= L.STEP and (c.fx * dx + c.fy * dy) > 0.5 then
                local lat = (c.x - qx) * nx + (c.y - qy) * ny
                local w = c.amt
                sw, sl, sl2, sz = sw + w, sl + w * lat, sl2 + w * lat * lat, sz + w * c.z
                sa, fx, fy, n = sa + w * c.amt, fx + c.fx * w, fy + c.fy * w, n + 1
                c.used = used
            end
        end
        if n == 0 then break end
        local lat = sl / sw
        local spread = math.sqrt(math.max(0, sl2 / sw - lat * lat))
        px, py, pz = qx + nx * lat, qy + ny * lat, sz / sw
        local l = math.sqrt(fx * fx + fy * fy)
        if l > 1e-6 then
            local ndx, ndy = dx * 0.7 + fx / l * 0.3, dy * 0.7 + fy / l * 0.3
            local nl = math.sqrt(ndx * ndx + ndy * ndy)
            dx, dy = ndx / nl, ndy / nl
        end
        -- index runs along the line: forward +1, +2...; backward -1, -2...
        local index = sign * (#nodes + 1)
        if covered(taken, px, py, dx, dy, line, index) then nodes.looped = sign > 0 and #nodes > 30; break end
        take(taken, px, py, dx, dy, line, index)
        nodes[#nodes + 1] = { x = px, y = py, z = pz, width = math.max(1.0, math.min(3.2, 2 * spread + 0.8)),
            -- usage-weighted mean (fringe cells weigh little); no peak floor:
            -- a single hot cell no longer makes the stretch look nearly full
            -- (2026-10-20, the line appeared in one go instead of building up)
            level = (sa / sw) / L.FULL }
        -- closed the loop
        if #nodes > 30 and (px - seed.x) ^ 2 + (py - seed.y) ^ 2 < (L.STEP * 1.5) ^ 2 then nodes.looped = true; break end
    end
    return nodes
end

local function smooth(nodes, k)
    local out = {}
    for i = 1, #nodes do
        maybeYield()
        local x, y, z, w, lv, n = 0, 0, 0, 0, 0, 0
        for j = math.max(1, i - k), math.min(#nodes, i + k) do
            local m = nodes[j]
            x, y, z, w, lv, n = x + m.x, y + m.y, z + m.z, w + m.width, lv + m.level, n + 1
        end
        out[i] = { x = x / n, y = y / n, z = z / n, width = w / n, level = lv / n }
    end
    return out
end

--- the racing lines: list of smoothed node lists {x, y, z, width, level}
-- A rebuild marks the cells it used with its generation number (a hash of
-- up to 150k cells per rebuild was garbage), and sorts in two reused arrays.
local generation, seedBuf, tempBuf = 0, {}, {}
L.lines = function()
    local minAmt = L.FULL * L.MIN_LEVEL
    generation = generation + 1
    local seeds, temp, n = seedBuf, tempBuf, 0
    for _, c in pairs(cells) do
        if c.amt >= minAmt * 2 then n = n + 1; seeds[n] = c end
        maybeYield()
    end
    for i = n + 1, #seeds do seeds[i] = nil end
    for i = n + 1, #temp do temp[i] = nil end
    -- Lua's table.sort cannot yield: at the 150k-cell cap it caused a
    -- single-frame spike. Bottom-up merge sort shares the rebuild budget.
    local width = 1
    while width < #seeds do
        for start = 1, #seeds, width * 2 do
            local middle = math.min(start + width, #seeds + 1)
            local finish = math.min(start + width * 2 - 1, #seeds)
            local a, b = start, middle
            for i = start, finish do
                if a < middle and (b > finish or seeds[a].amt >= seeds[b].amt) then
                    temp[i] = seeds[a]; a = a + 1
                else temp[i] = seeds[b]; b = b + 1 end
                maybeYield()
            end
        end
        seeds, temp = temp, seeds; width = width * 2
    end
    seedBuf, tempBuf = seeds, temp
    local used, lines, taken = generation, {}, {}
    for _, s in ipairs(seeds) do
        maybeYield()
        local l0 = math.sqrt(s.fx * s.fx + s.fy * s.fy)
        if s.used ~= used and #lines < 12 and l0 > 0.1 and not covered(taken, s.x, s.y, s.fx / l0, s.fy / l0, -1, 0) then
            local l = math.sqrt(s.fx * s.fx + s.fy * s.fy)
            if l > 0.1 then
                local tx, ty = s.fx / l, s.fy / l
                local id = #lines + 1
                take(taken, s.x, s.y, tx, ty, id, 0)
                local fwd = march(s, tx, ty, 1, used, minAmt, taken, id)
                local back = fwd.looped and {} or march(s, tx, ty, -1, used, minAmt, taken, id)
                local nodes = {}
                for i = #back, 1, -1 do nodes[#nodes + 1] = back[i] end
                nodes[#nodes + 1] = { x = s.x, y = s.y, z = s.z, width = 1.6, level = s.amt / L.FULL }
                for _, n in ipairs(fwd) do nodes[#nodes + 1] = n end
                if #nodes >= 25 then -- 50 m: shorter stubs came and went between rebuilds
                    local sm = smooth(nodes, 2)
                    sm.looped = fwd.looped
                    lines[#lines + 1] = sm
                end
            end
        end
    end
    return lines
end

---------------------------------------------------------------- drawing
-- The lines are drawn as overlapping rubber patches placed along them (every
-- STEP m, pointing along the line, twice as long as the spacing), submitted
-- each frame to the dynamic decal manager near the camera. No scene objects:
-- a version with DecalRoad strips froze the game whenever strips were
-- recreated (the engine re-projects them). Patch opacity follows how
-- rubbered that stretch is, so the line darkens gradually.
L.TEXTURE = 'art/raceprep/rubberstrip.png'
L.RANGE = 200         -- draw radius around the camera, m (same decal cap/cache)
L.ALPHA = 0.85        -- opacity of a fully rubbered stretch (single non-stacked line)
L.MAX_DECALS = 1500

local current = {}    -- published only after a complete budgeted rebuild
local patches = {}
local visible = {}
local PATCH_TILE = 64
local EMPTY = {}

--- Patches are plain numbers; their native vectors/colour are made the first
--- time a patch comes into view and kept until the next rebuild. Creating
--- them every frame caused GC/FFI spikes; creating them for every patch on
--- the map at each rebuild (Nordschleife: ~40k native objects every 15 s)
--- was the next biggest garbage source.
L.build = function()
    local lines, nextPatches = L.lines(), {}
    for _, nodes in ipairs(lines) do
        for i, a in ipairs(nodes) do
            maybeYield()
            local p, q = nodes[math.max(1,i-1)], nodes[math.min(#nodes,i+1)]
            local fx, fy = q.x-p.x, q.y-p.y
            local length = math.sqrt(fx*fx+fy*fy)
            if length > .01 and a.level >= L.MIN_LEVEL then
                -- Filter only the cached visual patches, not recorded cells,
                -- line extraction or grip. The small bounded correction
                -- softens 1 m cell-centroid zigzags without cutting an apex.
                -- No extra patches/native objects; this stays in the budget.
                local sx, sy = (p.x+2*a.x+q.x)*.25, (p.y+2*a.y+q.y)*.25
                local ox, oy = sx-a.x, sy-a.y
                local shift = math.sqrt(ox*ox+oy*oy)
                if shift > .2 then sx,sy=a.x+ox*.2/shift,a.y+oy*.2/shift end
                local k = tileKey(math.floor(sx/PATCH_TILE), math.floor(sy/PATCH_TILE))
                nextPatches[k] = nextPatches[k] or {}
                local bucket = nextPatches[k]
                bucket[#bucket+1] = {
                    x=sx, y=sy, z=a.z, fx=fx/length, fy=fy/length,
                    width=(p.width+2*a.width+q.width)*.25,
                    alpha=L.ALPHA*math.min(1,a.level), -- linear: the line darkens lap by lap
                }
            end
        end
    end
    current, patches = lines, nextPatches
    return #current
end

--- Submit only nearby cached patches. Call from onPreRender.
L.draw = function()
    if not enabled then return 0 end
    local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
    if not cam or not Engine.Render or not Engine.Render.DynamicDecalMgr then return 0 end
    local r2, n = L.RANGE*L.RANGE, 0
    for ix=math.floor((cam.x-L.RANGE)/PATCH_TILE),math.floor((cam.x+L.RANGE)/PATCH_TILE) do
        for iy=math.floor((cam.y-L.RANGE)/PATCH_TILE),math.floor((cam.y+L.RANGE)/PATCH_TILE) do
            for _,d in ipairs(patches[tileKey(ix,iy)] or EMPTY) do
                if (d.x-cam.x)^2+(d.y-cam.y)^2<r2 and n<L.MAX_DECALS then
                    if not d.position then
                        d.texture=L.TEXTURE;d.position=vec3(d.x,d.y,d.z)
                        d.forwardVec=vec3(d.fx,d.fy,0);d.scale=vec3(d.width,L.STEP*2,2)
                        d.color=ColorF(1,1,1,d.alpha);d.fadeStart=L.RANGE-30;d.fadeEnd=L.RANGE
                    end
                    n=n+1;visible[n]=d
                end
            end
        end
    end
    if n>0 then Engine.Render.DynamicDecalMgr.addDecals(visible,n) end
    return n
end

local job = nil
--- per frame: start a rebuild every REBUILD_S (if rubber was added) and run
--- the current one for at most BUDGET_MS
L.update = function(dt)
    dt=dt or 0
    clock = clock + dt
    reportClock=reportClock+dt
    if inboxAt<=inboxN then drainInbox() end
    marbles.update(dt)
    if enabled then
        L.record(dt)
        sendClock=sendClock+dt;gripClock=gripClock+dt
        if sendClock>=L.SEND_S then sendClock=0;L.flush() end
        if gripClock>=.2 then gripClock=0;grip() end
    end
    if enabled and not job and inboxAt>inboxN and clock >= nextRebuild then
        nextRebuild = clock + L.REBUILD_S
        if changed ~= lastChanged then
            lastChanged = changed
            job = coroutine.create(L.build)
        end
    end
    if job then
        sliceStart = nowMS()
        local ok, err = coroutine.resume(job)
        if not ok then log('E', 'rubberLine', tostring(err)); job = nil
        elseif coroutine.status(job) == 'dead' then job = nil end
    end
end
L.busy = function() return job ~= nil end

L.currentLines=function() return current end
L.clear = function()
    marbles.clear();shedCache={}
    job=nil;current={};patches={};visible={};nearOut={};seedBuf,tempBuf={},{};inbox,inboxAt,inboxN={},1,0;cells,tiles,pending,count,wheels,changed={},{},{},0,{},0
    lastChanged=-1;nextRebuild=0;L.synced=false;L.peak=0
end

return L
