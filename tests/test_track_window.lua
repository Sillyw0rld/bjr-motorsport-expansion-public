-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Track settings window draws with only the helpers BeamJoy defines (no global
-- Checkbox: 1.8.0 crashed in game on it, leaving ImGui child regions open).
local root='client/lua/'
package.path=root..'?.lua;'..package.path
ImVec2=function(x,y) return {x=x,y=y} end
BJI={Utils={Style={WINDOW_FLAGS={NO_COLLAPSE=1},TEXT_COLORS={HIGHLIGHT=1,DISABLED=2,DEFAULT=3,ERROR=4,SUCCESS=5},BTN_PRESETS={WARNING=1,INFO=2,SUCCESS=3}}}}
local sent={}
package.loaded['ge/extensions/raceprep/director']={data={track={level='mosport',amount=.4,
    rubber={enabled=true,initial=0,buildKm=100,dryBonus=2.5,wetPenalty=5},wind={enabled=true,speedKmh=10,direction=90,gustKmh=5,gustPeriod=20}}},
    setTrack=function(t) sent[#sent+1]=t end}
package.loaded['ge/extensions/raceprep/rubberLine']={peak=32,FULL=80,statusText=function() return 'rubber ok' end}
package.loaded['ge/extensions/raceprep/raceEnvironment']={status='wind ok'}
BJI_Win_RacePrep={canEditRules=function() return true end}
local clicks,slid={},{}
local texts={}
Text=function(s) texts[#texts+1]=s end;SameLine=function() end;Separator=function() end;EndTree=function() end
BeginTree=function() return true end
Button=function(id) return clicks[id]==true end
SliderFloat=function(id,value,min,max,data) assert(data.formatRender);return slid[id] end
BoolPtr=function(v) return {[0]=v} end
local toggled={}
ui_imgui={Checkbox=function(label,ptr) local id=label:match('##(.+)$');if toggled[id] then ptr[0]=not ptr[0];return true end;return false end}
assert(rawget(_G,'Checkbox')==nil)
local W=dofile(root..'ge/extensions/BJI/ui/windows/RaceTrack.lua')
W.body({})
local found=false
for _,s in ipairs(texts) do assert(not s:gsub('%%%%',''):find('%%',1,true),'unescaped % reaches ImGui: '..s);if s=='Peak recorded line: 40 %%' then found=true end end
assert(found,'rubber percentage shown, escaped for ImGui')
toggled['track-rubber-on']=true;W.body({});toggled={}
assert(sent[1] and sent[1].rubber.enabled==false,'rubber box applies at once')
slid['track-rubber-dry']=3.5;W.body({});slid={}
clicks['track-save']=true;W.body({});clicks={}
assert(sent[2].rubber.dryBonus==3.5,'one-decimal grip slider is kept')
-- a refused change: the reply is shown and the edit is dropped (back to the server's values)
local director=package.loaded['ge/extensions/raceprep/director']
slid['track-wind-speed']=55;W.body({});slid={}
director.adminStatus='Not saved: changing this needs an admin (BeamJoy SetConfig permission).';director.adminStatusSeq=1
texts={};W.body({})
local shown=false;for _,s in ipairs(texts) do if s:find('^Not saved') then shown=true end end
assert(shown,'refusal shown')
clicks['track-save']=true;W.body({});clicks={}
assert(sent[#sent].wind.speedKmh==10,'refused edit dropped, server values back')
W.show=true;clicks['track-close']=true;W.body({});assert(W.show==false,'Close button closes')
print('PASS: Track settings window: "%" escaped for ImGui, BeamJoy helpers only, rubber box applies at once, decimal grip slider, refusal shown and edit dropped, save and close')
