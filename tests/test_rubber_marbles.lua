-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local M=dofile('client/lua/ge/extensions/raceprep/rubberMarbles.lua')
getCurrentLevelIdentifier=function() return 'test' end
M.configure(true,false,'test')
M.deposit(1.5,2.5,3,1,1,0)
assert(M.factor(1.5,2.5,3)==.97)
assert(M.factor(1.5,2.5,10)==1)
M.update(300);assert(math.abs(M.levelAt(1.5,2.5,3)-.5)<1e-9)
M.update(300);assert(M.levelAt(1.5,2.5,3)==0 and M.count()==0)
M.deposit(1.5,2.5,3,.1,1,0)
M.update(300);assert(math.abs(M.levelAt(1.5,2.5,3)-.05)<1e-9,'low density fades over ten minutes too')
M.clear();M.configure(true,true,'test');M.onReset('test')
assert(M.onDelta('wrong|1,2,3,1,1,0,600')==0)
assert(M.onDelta('test|1,2,3,1,1,0,300')==1)
M.update(150);assert(math.abs(M.levelAt(1.5,2.5,3)-.5)<1e-9,'remaining lifetime preserved for joiners')
M.update(150);assert(M.levelAt(1.5,2.5,3)==0)
local sent={};TriggerServerEvent=function(e,p) sent[#sent+1]={e,p} end
package.loaded['ge/extensions/raceprep/net']={send=function(...) return TriggerServerEvent(...) end} -- chunking: test_net_chunks.lua
M.deposit(1.5,2.5,3,.2,1,0);M.flush()
assert(sent[1][1]=='RacePrepMarbleAdd' and sent[1][2]:match('^test|'))
M.configure(false,true,'test');assert(M.factor(1.5,2.5,3)==1)
M.clear();M.configure(true,false,'test')
math.randomseed(7)
local landed=0
for i=1,40 do M.emit('wheel'..i,{x=0,y=0,z=0},{x=10,y=0},{x=1,y=0},8,function() return 0 end,1);M.update(.5);landed=M.count() end
assert(landed>=1,'a hard slide sheds pieces that land outside the wheel path')
-- shedding: below SLIP_MIN nothing; soft compounds shed more than hard
M.clear();M.configure(true,false,'test')
M.emit('slow',{x=0,y=0,z=0},{x=10,y=0},{x=1,y=0},1,nil,2);M.update(1.3);assert(M.count()==0,'grip-limit driving below 1.2 m/s slip sheds nothing')
local function shedCount(shed)
 math.randomseed(11);local hits=0
 for i=1,400 do M.clear();M.configure(true,false,'test');M.emit('w',{x=0,y=0,z=0},{x=10,y=0},{x=1,y=0},3,nil,shed);M.update(1.3);hits=hits+M.count() end
 return hits
end
assert(shedCount(M.shedFor('race_supersoft'))>shedCount(M.shedFor('standard'))*1.5,'super soft sheds clearly more than a road tyre')
-- landed pieces ARE the marbles: one piece per CHUNK of density, deterministic per cell
M.clear();M.configure(true,false,'test')
M.deposit(5.5,5.5,0,M.CHUNK*3,1,0)
local c=M.cells()[M.cellKey(5,5)];assert(M.piecesIn(c)==3,'three chunks -> three pieces')
M.deposit(6.5,5.5,0,1,1,0);assert(M.piecesIn(M.cells()[M.cellKey(6,5)])==M.MAX_PER_CELL,'pieces per cell capped')
-- drawing: debugDrawer triangles, camera-facing, budgets, no per-frame allocation
local created,triCalls=0,0
vec3=function(x,y,z) created=created+1;return {x=x,y=y,z=z,set=function(self,a,b,c2) self.x,self.y,self.z=a,b,c2 end} end
color=function(r,g,b,a) created=created+1;return {r,g,b,a} end
debugDrawer={drawTriSolid=function() triCalls=triCalls+1 end}
core_camera={getPosition=function() return {x=0,y=0,z=1.5} end}
M.clear();M.configure(true,false,'test')
M.deposit(2.5,.5,0,M.CHUNK*2,1,0)
assert(M.draw()==2 and triCalls>0)
local before=created;triCalls=0;M.draw();assert(created==before,'no allocation per frame after the first')
-- worst case: a dense marble field around the camera stays inside the budgets
M.clear();M.configure(true,false,'test')
for x=-40,40 do for y=-40,40 do M.deposit(x+.5,y+.5,0,1,1,0) end end
triCalls=0;local n=M.draw()
assert(n<=M.MAX_DRAW and triCalls<=M.MAX_TRIS,'piece and triangle budgets hold: '..n..' pieces, '..triCalls..' tris')
local t0=os.clock();for _=1,200 do triCalls=0;M.draw() end
local ms=(os.clock()-t0)/200*1000
print(string.format('marbles worst-case draw (Lua side): %.3f ms/frame, %d pieces, %d tris',ms,n,triCalls))
assert(ms<2,'worst-case marble draw must stay cheap on the Lua side')
-- nearest first: with a far field beyond FAR nothing is drawn
M.clear();M.configure(true,false,'test');M.deposit(M.FAR+10.5,.5,0,1,1,0);assert(M.draw()==0,'nothing beyond FAR')
M.clear();assert(M.draw()==0)
-- F12: numeric cell/tile keys, budgeted inbox, and 600-row upload cap
do
 M.configure(true,true,'test');M.onReset('test')
 M.MERGE_ROWS=1
 assert(M.onDelta('test|1,2,3,1,1,0,600;2,2,3,1,1,0,600')==2 and M.queued()==2)
 M.update(0);assert(M.queued()==1 and M.count()==1 and type(next(M.cells()))=='number')
 M.update(0);assert(M.queued()==0 and M.count()==2)
 M.MERGE_ROWS=1500
 M.clear();M.configure(true,true,'test');M.onReset('test')
 for x=0,699 do M.deposit(x+.5,.5,0,.1,1,0) end
 assert(M.flush()==M.UPLOAD_ROWS and M.UPLOAD_ROWS<=150,'marble uploads capped at UPLOAD_ROWS (small: BeamMP zlib guess)')
 local left=700-M.UPLOAD_ROWS;while left>0 do local n=M.flush();assert(n==math.min(left,M.UPLOAD_ROWS));left=left-n end
end
print('PASS: 3D rubber pieces (shedding by slip+compound, deterministic landed pieces, budgets), marbles 3% cap, height isolation, full/low-density 10-minute fade, late-join lifetime, map sync, disable')
