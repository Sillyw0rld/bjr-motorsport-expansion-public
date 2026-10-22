-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local T=require('ge/extensions/raceprep/bjr/lapTracker')
local function gate(x,y,dx,dy,parents,step,finish) return {pos={x=x,y=y,z=0},dir={x=dx,y=dy,z=0},width=12,height=8,parents=parents,step=step,isFinish=finish} end
local race={loopable=true,branchingEnabled=true,gates={gate(0,0,0,1,{0},1),gate(40,40,1,0,{1},2),gate(80,40,1,0,{1},2),gate(0,80,0,-1,{2},3),gate(80,80,0,1,{3},3)}}
local t,time,position
local function reset() t=T.new(race);time=0;position={x=0,y=-10,z=0};t:update(time,position) end
local function go(x,y)
 local start=position;local dx,dy=x-start.x,y-start.y;local n=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/5));local result
 for i=1,n do time=time+1000;local p={x=start.x+dx*i/n,y=start.y+dy*i/n,z=0};result=t:update(time,p) or result;position=p end
 return result
end
reset();go(0,10);assert(t.state=='lap');go(20,40);go(50,40);go(20,100);go(0,90);go(0,70);go(-30,50);go(-30,-10);go(0,-10)
local lap=go(0,10);assert(lap and lap.valid and not lap.incomplete,'branch 1 valid')
reset();go(0,10);go(60,20);go(70,40);go(90,40);go(80,70);go(80,90);go(110,100);go(110,-10);go(0,-10);lap=go(0,10)
assert(lap and lap.valid,'branch 2 valid')
reset();go(0,10);t:cut();go(20,40);go(50,40);go(20,100);go(0,90);go(0,70);go(-30,50);go(-30,-10);go(0,-10);lap=go(0,10)
assert(lap and not lap.valid and lap.cuts==1,'cut invalidates lap')
reset();go(0,10);go(20,40);go(50,40);go(50,-10);go(0,-10);lap=go(0,10)
assert(lap and lap.incomplete,'shortcut to finish cannot count')
reset();go(0,10);time=time+1000;t:update(time,{x=500,y=500,z=0});assert(t.state=='out','teleport starts new outlap')
print('PASS: BJR alternate parent routes, complete lap, shortcut, cuts and teleport')
