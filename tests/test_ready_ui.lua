-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local root='client/lua/'
package.path=root..'?.lua;'..package.path
table.includes=function(t,v) for _,x in pairs(t or {}) do if x==v then return true end end;return false end
math.clamp=function(n,a,b) return math.max(a,math.min(b,n)) end
string.var=function(s) return s end
ImVec2=function(x,y) return {x=x,y=y} end
local style={WINDOW_FLAGS={NO_COLLAPSE=1,NO_SCROLL_WITH_MOUSE=2},TEXT_COLORS={HIGHLIGHT=1,ERROR=2,DISABLED=3,SUCCESS=4,DEFAULT=5},BTN_PRESETS={SUCCESS=1,INFO=2,WARNING=3}}
BJI={Utils={Style=style,UI={PrettyDelay=tostring}}}
local race={state=1,STATES={GRID=1},raceID=1,raceName='Test Race',settings={laps=1},grid={timeout=120000,participants={1},ready={},startPositions={{}},readyTime=0},isParticipant=function() return true end,isReady=function() return false end}
BJI_Scenario={TYPES={RACE_MULTI=1},get=function() return race end,canReplaceVehicle=function() return true end}
local car={getID=function() return 1 end}
BJI_Veh={getCurrentVehicleOwn=function() return car end,isCurrentVehicleOwn=function() return true end,getCurrentModel=function() return 'test' end,getModelLabel=function() return 'Test Car' end}
BJI_Context={User={playerID=1},BJC={Race={GridTimeout=120}}}
BJI_Perm={canSpawnVehicle=function() return true end,hasPermission=function() return false end,PERMISSIONS={SET_CONFIG=1}}
BJI_Tournament={canJoinActivity=function() return true end}
extensions={core_vehicle_manager={getVehicleData=function() return {vdata={variables={}},config={vars={}}} end}}
local base={fuel=true,aero=true,diff=true,diffModes={open=true,lsd=true,locked=true},centreSplit=true}
local rules=base
bjiRacePrep={getRules=function() return rules end,diffReports={[1]={}},diffSettings={}}
local entry={pi=497,pi_speed=500,pi_technical=494,class='C',source='measured'}
raceprepRatings={getVehicle=function() return entry end,badge=function(e) return e.class..' '..e.pi end}
TABLE_COLUMNS_FLAGS={WIDTH_FIXED=1,WIDTH_STRETCH=2};TABLE_FLAGS={SIZING_STRETCH_PROP=1,ALTERNATE_ROW_BG=2}
local captured
Button=function(id,label,options) if id=='raceprep-ready' then captured={label=label,disabled=options.disabled} end;return false end
Text=function() end;SameLine=function() end;TooltipText=function() end;Separator=function() end;ProgressBar=function() end
BeginTable=function() return false end;BeginTabBar=function() return true end;EndTabBar=function() end
BeginTabItem=function(name) return name=='Race' end;EndTabItem=function() end
local window=dofile(root..'ge/extensions/BJI/ui/windows/RacePrep.lua')
local stamp=0
local function draw()
 stamp=stamp+10;captured=nil;window.body({now=stamp,players={[1]={playerName='Driver'}}});assert(captured);return captured
end
rules={allowedClasses={C=false,B=true},aero=true,diff=true};local r=draw();assert(r.disabled and r.label:find('Class C is not allowed',1,true))
entry={pi=550,pi_speed=555,pi_technical=545,class='B'};r=draw();assert(not r.disabled)
rules={piMin=560,aero=true,diff=true};r=draw();assert(r.disabled and r.label:find('below minimum',1,true))
rules={piMax=540,aero=true,diff=true};r=draw();assert(r.disabled and r.label:find('exceeds maximum',1,true))
rules={piMin=501,piMax=600,aero=true,diff=true};r=draw();assert(not r.disabled)
entry=nil;r=draw();assert(r.disabled and r.label:find('Waiting for car rating',1,true))
print('PASS: actual RacePrep Race-tab drawing code: C blocked / B allowed, minimum and maximum PI, eligible range and pending rating Ready state')
