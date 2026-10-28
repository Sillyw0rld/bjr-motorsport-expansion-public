-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local G=dofile('client/lua/ge/extensions/raceprep/bjr/rivalsGhost.lua')
local function near(a,b) return math.abs(a-b)<1e-6 end
-- a straight lap east at 20 m/s, one sample every 200 ms, then a turn north
local trace={}
for i=0,50 do trace[#trace+1]={t=i*200,x=i*4,y=0,z=1} end
for i=1,20 do trace[#trace+1]={t=10000+i*200,x=200,y=i*4,z=1} end

local p=assert(G.at(trace,1100))
assert(near(p.x,22) and near(p.y,0) and near(p.z,1),'interpolates between samples')
assert(near(p.dx,1) and near(p.dy,0),'heads along the line')
p=assert(G.at(trace,12000));assert(near(p.x,200) and near(p.y,40) and near(p.dx,0) and near(p.dy,1),'after the turn')
assert(G.at(trace,-1)==nil and G.at(trace,99999)==nil,'nothing before or after the lap')
assert(G.at({},100)==nil and G.at(nil,100)==nil and G.at(trace,0/0)==nil)
local still={{t=0,x=5,y=5,z=0},{t=200,x=5,y=5,z=0}}
assert(G.at(still,100).dx==nil,'no heading while stopped')

assert(G.alpha(.4,20)==.4 and G.alpha(.4,G.FADE_NEAR)==0 and G.alpha(.4,1)==0)
assert(near(G.alpha(.4,(G.FADE_NEAR+G.FADE_FAR)/2),.2),'fades in between')

-- drawing: a box and a label per visible ghost; none when it's on top of you
local calls={prism=0,text=0}
debugDrawer={drawSquarePrism=function() calls.prism=calls.prism+1 end,drawTextAdvanced=function(_,_,_,_,_,_) calls.text=calls.text+1 end}
vec3=function(x,y,z) return {x=x,y=y,z=z} end;Point2F=function(a,b) return {a,b} end
ColorF=function(...) return {...} end;ColorI=ColorF;String=function(s) return s end
local ghosts={{trace=trace,t=1100,label='Ana · target',color={1,.55,.15},alpha=.35},{trace=trace,t=5000,label='Your best',color={.45,.75,1},alpha=.22}}
G.draw(ghosts,{x=-50,y=0,z=1})
assert(calls.prism==2 and calls.text==2,'both ghosts drawn')
calls={prism=0,text=0};G.draw({ghosts[1]},{x=22,y=0,z=1})
assert(calls.prism==0,'inside your car: invisible')
debugDrawer=nil;G.draw(ghosts,{x=0,y=0,z=0})
print('PASS: Rivals ghost position, heading, fade and drawing')
