-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local hostReady=false
package.loaded['ge/extensions/raceprep/bjr/host']={ready=function() return hostReady end}
local S=require('ge/extensions/raceprep/bjr/sidebar')
local function api()
 local a={handlers={},calls=0,serial=0}
 a.addHandler=function(key,callback)
  a.serial=a.serial+1;a.handlers[a.serial]={key=key,callback=callback};return a.serial
 end
 a.onBJUpdateSelf=function() a.calls=a.calls+1 end
 a.dispatch=function(key)
  for _,row in pairs(a.handlers) do if row.key==key then row.callback() end end
 end
 return a
end
S.update() -- expansion can load before BJR
local a=api();beamjoy_communications_ui=a
local original=a.onBJUpdateSelf
local nativeCalls=0
local native=a.addHandler('BJMainPadRequest',function() nativeCalls=nativeCalls+1 end)
S.update();a.dispatch('BJMainPadRequest')
assert(a.calls==0 and nativeCalls==1,'mount before host readiness is safe')
hostReady=true;S.update()
assert(a.calls==1,'ready transition restores a sidebar already mounted')
for i=1,100 do S.update() end
assert(a.calls==1,'no periodic visibility traffic')
a.dispatch('BJMainPadRequest')
assert(a.calls==2 and nativeCalls==2,'ready before mount and UI reload both replay visibility')
assert(a.onBJUpdateSelf==original,'never replaces BJR functions')
a.loginChecking=true;S.update();a.dispatch('BJMainPadRequest');assert(a.calls==2)
a.loginChecking=false;a.loginPending=true;S.update();assert(a.calls==2)
a.loginPending=false;S.update();assert(a.calls==3,'wait for guest login to finish')
S.stop();assert(a.handlers[native],'keeps native handlers on unload')
a.dispatch('BJMainPadRequest');S.update();assert(a.calls==3 and nativeCalls==4)
S.start();S.update();assert(a.calls==4,'late expansion reload')
local b=api();beamjoy_communications_ui=b;S.update()
assert(b.calls==1 and a.handlers[native] and not a.handlers[3],'host replacement cleans its own old callback')
-- A BJR UI registry reset must not leave us bound to a dead registration.
b.handlers={};S.update();b.dispatch('BJMainPadRequest');assert(b.calls==3)
S.reset();assert(next(b.handlers)==nil,'disconnect cleans expansion callback')
S.update();assert(b.calls==4,'reconnect can register again')
b.onBJUpdateSelf=function() error('not ready internally') end
assert(not S.replay() and S.lastError,'host errors do not escape into the game loop')
S.stop()
print('PASS: BJR sidebar mount/readiness, login, reload and cleanup; no host function replacement or periodic replay')
