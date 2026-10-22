-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Road Temperature (built in since 2.12.0): KTS mailbox feed, resend timing, air restored on end
local sent={}
be={sendToMailbox=function(_,k,v) sent[#sent+1]={k,v} end}
core_environment={getTemperatureK=function() return 273.15+20 end,getTimeOfDay=function() return {time=0} end,
  getCloudCover=function() return 0 end,getPrecipitation=function() return 0 end}
log=function() end;jsonReadFile=function() return nil end;jsonWriteFile=function() end
local M=dofile('client/lua/ge/extensions/roadTemperature.lua')
M.onExtensionLoaded();M.onUpdate(0.1)
local st=M.get();assert(st and st.track>st.air,'noon clear: track hotter than air ('..st.track..')')
local function last(k) for i=#sent,1,-1 do if sent[i][1]==k then return sent[i][2] end end end
assert(math.abs(last('tyreWearMailboxEnvTemp')-(st.track+3))<1e-9,'stock KTS gets track + 3')
assert(last('ktsRoadTempC')==string.format('%.2f',st.track),'old mailbox still sent')
local n=#sent;M.onUpdate(0.1);assert(#sent==n,'not every frame (0.25 s)');M.onUpdate(0.2);assert(#sent>n,'resent within 0.25 s')
M.onVehicleSpawned();n=#sent;M.onUpdate(0.01);assert(last('tyreWearMailboxEnvTemp') and #sent>n,'resent at once after a spawn')
M.onClientEndMission();assert(math.abs(last('tyreWearMailboxEnvTemp')-20)<1e-9 and last('ktsRoadTempC')=='off','real air handed back at mission end')
print(string.format('PASS: track %.1f C -> stock KTS mailbox %.1f (road %.1f); 0.25 s resend; spawn resend; air restored on end',st.track,st.track+3,st.track))
