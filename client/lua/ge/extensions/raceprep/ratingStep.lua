-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- The rating step: one config per call or a quiet background queue. The helper
-- car is spawned out of sight and removed afterwards; the rating itself runs
-- through the stock collection pipeline (no second method, no rig).
local Frontend=require('ge/extensions/raceprep/frontend')
local function host() return Frontend.host() end
local M={}
local IDLE_SECONDS=15
local COLLECT_TIMEOUT=25
local RETRY_SECONDS=5
local PUSH_INTERVAL=0.5
local backgroundAllowed=false
local queue,seen,failures,current,clock,idleFor,done,total,script,pushClock,retryAt,scanAt
local function reset()
 queue,seen,failures,current,clock,idleFor,done,total,pushClock,retryAt,scanAt={},{},{},nil,0,0,0,0,0,0,0
end
local function resolve(item,result) for _,h in ipairs(item.handles or {}) do h.done=true;h.result=result end end
reset()
local function keyOf(model,config) return tostring(model)..'/'..tostring(config) end
local function helperDelete(id)
 local v=id and be and be.getObjectByID and be:getObjectByID(id)
 if v then
  local H=host();if H.unhelper then H.unhelper(id) end
  v:delete()
 end
end
local function finish(result)
 local item=current;current=nil
 helperDelete(item.helper)
 done=done+1
 for _,h in ipairs(item.handles or {}) do h.done=true;h.result=result end
 if result.skip and not result.transient and not failures[item.key] then
  failures[item.key]=result.skip
  log('W','ratingStep',item.key..': '..tostring(result.skip))
 end
 if result.transient then seen[item.key]=nil end
end
local function helperPosition()
 local v=be and be.getPlayerVehicle and be:getPlayerVehicle(0)
 local pos=v and v.getPosition and v:getPosition() or vec3(0,0,500)
 return pos+vec3(0,0,-400)
end
local function worldReady()
 if not host().ready() then return false,'career inactive' end
 if not (getCurrentLevelIdentifier and getCurrentLevelIdentifier()) then return false,'no level loaded' end
 if not (core_vehicles and core_vehicles.spawnNewVehicle) then return false,'spawn unavailable' end
 return true
end
-- Background (queued) work runs while the player is idle only.
local function busy(dt)
 local mm=gameplay_missions_missionManager
 if mm and mm.getForegroundMissionId and mm.getForegroundMissionId() then return 'mission' end
 local r=ui_router and ui_router.getCurrent and ui_router.getCurrent()
 local name=r and (r.name or r.request and r.request.name) or ''
 if name:find('computer') or name:find('loading') then return 'ui' end
 local v=be and be.getPlayerVehicle and be:getPlayerVehicle(0)
 local speed=v and v.getVelocity and v:getVelocity():length() or 0
 if speed<0.5 then idleFor=idleFor+dt else idleFor=0 end
 if idleFor<IDLE_SECONDS then return 'player active' end
end
local function enqueue(item)
 item.key=keyOf(item.model,item.config)
 if failures[item.key] then
  for _,h in ipairs(item.handles or {}) do h.done=true;h.result={skip=failures[item.key]} end
  if item.handle then item.handle.done=true;item.handle.result={skip=failures[item.key]} end
  return false
 end
 local existing=seen[item.key]
 if existing then
  for _,h in ipairs(item.handles or {}) do
   existing.handles=existing.handles or {};existing.handles[#existing.handles+1]=h
  end
  if item.handle then
   existing.handles=existing.handles or {};existing.handles[#existing.handles+1]=item.handle
  end
  return false
 end
 seen[item.key]=item;total=total+1
 if item.manual then
  -- Explicit calls (e.g. parts generation) run ahead of the background queue.
  local at=#queue+1
  for i,q in ipairs(queue) do if not q.manual then at=i break end end
  table.insert(queue,at,item)
 else
  queue[#queue+1]=item
 end
 return true
end
local function pushIndicator()
 if not be or not be.queueJS then return end
 script=script or (readFile and readFile('/ui/modules/ascension/rating-progress.js'))
 if not script then return end
 local n=0;for _ in pairs(failures)do n=n+1 end
 be:queueJS(script..'\nwindow.ascensionRating && window.ascensionRating.show('..jsonEncode{
  text='Rating new cars: '..done..' / '..total,model=current and current.model,
  done=done,total=total,failures=n}..');')
end
local function hideIndicator()
 if be and be.queueJS then be:queueJS('window.ascensionRating && window.ascensionRating.hide();') end
end
-- One call per car (documented in docs/ascension/RATING-STEP.md). Returns a
-- handle; inside a jobsystem job: local h=rateConfig(m,c) while not h.done do
-- job.yield() end -> h.result.entry or h.result.skip.
function M.rateConfig(model,config)
 local h={model=model,config=config,done=false}
 if not backgroundAllowed then h.done=true;h.result={skip='rating phase inactive',transient=true};return h end
 enqueue{model=model,config=config,handles={h},manual=true}
 return h
end
function M.setBackgroundAllowed(on)
 backgroundAllowed=on==true
 if not backgroundAllowed and current then finish{skip='rating phase ended',transient=true} end
end
-- Queue unrated work: configs on sale at dealers first, then each unrated
-- model's default config. Returns the newly queued count.
function M.scan()
 if not backgroundAllowed or not Frontend.isCareer() or not host().ready() then return 0 end
 local n=0
 local shopping=career_modules_vehicleShopping
 if shopping and shopping.getVehiclesInShop then
  for _,o in ipairs(shopping.getVehiclesInShop() or {}) do
   if (o.AscensionRatingStatus=='pending' or o.Class=='Unrated') and o.model_key and o.key then
    if enqueue{model=o.model_key,config=o.key,source='dealer'} then n=n+1 end
   end
  end
 end
 local list=core_vehicles.getConfigList and core_vehicles.getConfigList() or {}
 for _,c in pairs(list.configs or {}) do
  -- Only cars: props/trailers have no engine to rate and would stall the
  -- collector; native cars are seeded anyway, this catches modded cars.
  if (c.AscensionRatingStatus=='pending' or c.Class=='Unrated') and c.is_default_config and c.Type=='Car'
   and c.model_key and c.key then
   if enqueue{model=c.model_key,config=c.key,source='default'} then n=n+1 end
  end
 end
 if n>0 then log('I','ratingStep','Queued '..n..' unrated configs') end
 return n
end
function M.tick(dt)
 clock=clock+(dt or 0);pushClock=pushClock+(dt or 0)
 if current then
  local entry,status
  if raceprepRatings and raceprepRatings.getVehicle then
   entry,status=raceprepRatings.getVehicle(current.helper)
  end
  if not (be and be.getObjectByID and be:getObjectByID(current.helper)) then
   finish{skip='helper car removed'}
  elseif entry then
   finish{entry=entry}
  elseif type(status)=='string' and status:find('unavailable') then
   finish{skip=status}
  elseif clock-current.at>COLLECT_TIMEOUT then
   finish{skip='collection timed out'}
  end
 elseif queue[1] and clock>=retryAt then
  local item=queue[1]
  local ok,why=worldReady()
  if not ok then
   table.remove(queue,1)
   if item.manual then
    -- A caller inside a job waits on the handle: answer instead of stalling
    -- its job. A later background scan rates the car when a level is loaded.
    item.at=clock;current=item;finish{skip=why,transient=true}
   else
    item.when=clock+RETRY_SECONDS;queue[#queue+1]=item;retryAt=clock+1
   end
  elseif item.when and clock<item.when then
   retryAt=item.when
  elseif not item.manual and busy(dt) then
   -- Idle gating holds the background queue only; explicit callers keep going.
  else
   table.remove(queue,1);current=item
   local path='vehicles/'..item.model..'/'..tostring(item.config):gsub('%.pc$','')..'.pc'
   local ok,v=pcall(core_vehicles.spawnNewVehicle,item.model,
    {config=path,autoEnterVehicle=false,pos=helperPosition(),vehicleName='ascension-rating-helper'})
   item.at=clock
   if not ok or not v then finish{skip='Could not spawn default configuration'}
   else
    item.helper=v:getID()
    local H=host();if H.helper then H.helper(item.helper) end
   end
  end
 end
 if current or queue[1] then
  if pushClock>=PUSH_INTERVAL then pushClock=0;pushIndicator() end
 elseif total>0 then
  total,done,seen=0,0,{};hideIndicator()
 end
 -- Cars that appear outside generation (installed mid-session, newly offered
 -- at dealers) are picked up by a quiet rescan; nothing queued stays silent.
 if not current and not queue[1] and clock>=scanAt then
  scanAt=clock+30;M.scan()
 end
end
function M.status()
 local n=0;for _ in pairs(failures)do n=n+1 end
 return {active=current~=nil,queued=#queue,done=done,total=total,failures=n,
  text=total>0 and ('Rating new cars: '..done..' / '..total) or nil,
  model=current and current.model}
end
function M.failures() local out={};for k,v in pairs(failures)do out[k]=v end return out end
function M.reset()
 backgroundAllowed=false
 if current then resolve(current,{skip='reset'});helperDelete(current.helper) end
 for _,q in ipairs(queue or {}) do resolve(q,{skip='reset'}) end
 reset();hideIndicator()
end
return M
