-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Expansion-owned compatibility for a missed BJR sidebar visibility push.
-- bjMain already sends BJMainPadRequest when it mounts. Listen through BJR's
-- handler API and replay its current window state; do not patch its files or
-- replace its functions. No timers, polling messages or forced window opening.
local H=require('ge/extensions/raceprep/frontend').host()
local S={replays=0}
local bound,token,callback
local enabled,wasReady=true,false

local function detach()
 if bound and token and bound.handlers then
  local row=bound.handlers[token]
  -- BJR exposes the registration ID but no removal method in build 2702.
  -- Remove only our own registration, never another handler for this event.
  if row and row.callback==callback then bound.handlers[token]=nil end
 end
 bound,token,callback=nil,nil,nil
 wasReady=false
end

local function ready(api)
 return api and H.ready() and not api.loginChecking and not api.loginPending
end

function S.replay()
 local api=rawget(_G,'beamjoy_communications_ui')
 if not enabled or api~=bound or not ready(api) then return false end
 local ok,err=pcall(api.onBJUpdateSelf)
 if ok then S.replays=S.replays+1;S.lastError=nil
 else S.lastError=tostring(err) end
 return ok
end

function S.update()
 if not enabled then return end
 local api=rawget(_G,'beamjoy_communications_ui')
 if api~=bound or (bound and (not bound.handlers or not bound.handlers[token] or
  bound.handlers[token].callback~=callback)) then
  detach()
  if api and type(api.addHandler)=='function' and type(api.onBJUpdateSelf)=='function' and type(api.handlers)=='table' then
   bound=api
   callback=function() S.replay() end
   token=api.addHandler('BJMainPadRequest',callback)
  end
 end
 local nowReady=ready(bound) and true or false
 -- Also cover an expansion loaded after the BJR component already mounted.
 -- If this happens before the mount, its existing request replays again then.
 if nowReady and not wasReady then S.replay() end
 wasReady=nowReady
end

function S.start() enabled=true;wasReady=false end
function S.reset() detach() end
function S.stop() enabled=false;detach() end
return S
