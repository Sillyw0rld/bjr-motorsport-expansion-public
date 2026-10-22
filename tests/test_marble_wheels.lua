-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Marbles and wheels (2026-10-21): far / small pieces fade instead of popping;
-- admin marble size; a wheel crossing a cell thins it a little, flicks the
-- pieces that no longer fit (local only), and the tyres pick some up: mild
-- (at most 2 % grip), gone in ~12 s; the server applies the same thinning.
getCurrentLevelIdentifier=function() return 'test' end
local M=dofile('client/lua/ge/extensions/raceprep/rubberMarbles.lua')
-- fade: solid up close, held at ~1 px and translucent far away, gone at FAR
local step,size=M.fade(.05,5);assert(step==M.FADE_STEPS and size==.05,'a 5 cm piece at 5 m is solid')
step,size=M.fade(.015,20);assert(step>=1 and step<M.FADE_STEPS and math.abs(size-20*M.MIN_ANGLE)<1e-9,'a small far piece fades, held at the minimum size')
assert(M.fade(.002,60)==0,'far below a pixel: not drawn')
assert(M.fade(.05,M.FAR)==0,'nothing at FAR: it faded out on the way')
assert(select(1,M.fade(.05,M.FAR*.9))<M.FADE_STEPS,'fading in the last quarter before FAR')
-- shedding by slip angle: nothing in normal driving, a little at the limit
-- (the same at 60 and 150 km/h), heavy when sliding, wheelspin as before
do
 local race=M.shedFor('race')
 local function side(v,deg) return v*math.tan(math.rad(deg)) end
 assert(M.shedChance(40,side(40,2),0,race)==0,'2 deg: normal driving sheds nothing')
 local fast,slow=M.shedChance(42,side(42,7),0,race),M.shedChance(17,side(17,7),0,race)
 assert(fast>0 and fast<=M.LIMIT_CHANCE and math.abs(fast-slow)<1e-9,'at the limit: a little, the same in fast and slow corners')
 assert(M.shedChance(30,side(30,15),0,race)>.4 and M.shedChance(30,side(30,25),0,race)>.95,'sliding past the limit sheds heavily')
 assert(M.shedChance(20,0,6,race)>.95 and M.shedChance(20,0,1,race)==0,'wheelspin / lock-up as before')
 assert(M.shedChance(42,side(42,7),0,M.shedFor('standard'))<fast,'road tyres shed less than race tyres at the limit')
end
-- size setting
M.setScale(99,99);assert(M.SCALE==10 and M.SCALE_FAR==25);M.setScale(nil);assert(M.SCALE==5 and M.SCALE_FAR==12);M.setScale(7.5,15);assert(M.SCALE==7.5 and M.SCALE_FAR==15);M.setScale(5,12)
-- a wheel crossing a full cell: thins it, picks some up, flicks the extra pieces
M.configure(true,false,'test')
M.deposit(1.5,2.5,3,M.CHUNK*8,1,0)
local c=M.cells()[M.cellKey(1,2)];local before=M.piecesIn(c);local d0=M.levelAt(1.5,2.5,3)
local air0=M.airCount()
local take=M.wheelOver('car',{x=1.5,y=2.5,z=3},1,20,0)
assert(math.abs(take-d0*M.TAKE_PER_M)<1e-9,'one metre takes TAKE_PER_M of the density')
assert(M.levelAt(1.5,2.5,3)<d0 and M.levelAt(1.5,2.5,3)>d0*.9,'one pass thins, never clears')
assert(M.piecesIn(c)==before,'one light pass does not remove a whole piece')
local passes=1
while M.piecesIn(c)==before and passes<20 do M.wheelOver('car',{x=1.5,y=2.5,z=3},1,20,0);passes=passes+1 end
assert(passes<=4 and M.piecesIn(c)==before-1 and M.airCount()-air0==1,'a few passes: the piece that no longer fits flies off the wheel')
assert(M.pickup('car')>0 and M.pickupFactor('car')<1 and M.pickupFactor('car')>=1-M.PICKUP_LOSS,'tyres pick some up, capped')
assert(M.wheelOver('car',{x=1.5,y=2.5,z=9},1,20,0)==0,'another height (bridge) is not touched')
assert(M.wheelOver('car',{x=40.5,y=40.5,z=3},1,20,0)==0,'no marbles, nothing happens')
-- flicked pieces do not land again
local count=M.count();for _=1,10 do M.update(.2) end
assert(M.count()==count and M.levelAt(1.5,2.5,3)<d0,'a flicked piece is gone, not a new marble')
-- worst case: through dense marbles the loss saturates at PICKUP_LOSS, then wears off
for i=1,60 do M.deposit(i+.5,2.5,3,1,1,0) end
for i=1,60 do M.wheelOver('car',{x=i+.5,y=2.5,z=3},1,30,0) end
assert(M.pickup('car')==1 and math.abs(M.pickupFactor('car')-(1-M.PICKUP_LOSS))<1e-9,'never more than PICKUP_LOSS')
M.update(4);assert(M.pickup('car')<.4,'about a third left after 4 s')
M.update(9);assert(M.pickupFactor('car')>.999,'under 0.1 % grip after 13 s')
M.update(7);assert(M.pickup('car')==0,'fully gone by 20 s')
-- online: the thinning is uploaded in one batch; pending takes survive a delta
local sent={};package.loaded['ge/extensions/raceprep/net']={send=function(e,p) sent[#sent+1]={e,p};return true end}
M.clear();M.configure(true,true,'test');M.onReset('test')
M.onDelta('test|1,2,3.00,0.300,1,0,600');M.update(.1)
local d1=M.levelAt(1.5,2.5,3);M.wheelOver('car',{x=1.5,y=2.5,z=3},2,20,0)
M.onDelta('test|1,2,3.00,0.300,1,0,600');M.update(.1)
assert(math.abs(M.levelAt(1.5,2.5,3)-(d1-d1*M.TAKE_PER_M*2))<.002,'a server row does not undo a take not sent yet')
assert(M.flushTakes()==1 and sent[#sent][1]=='RacePrepMarbleTake' and sent[#sent][2]:match('^test|1,2,0%.0%d%d$'),'take rows: x,y,amount')
assert(M.flushTakes()==0,'sent once')
-- server: the same thinning, expiry kept, zero sent once
local at=100
local S=dofile('server/RacePrep/MarbleMap.lua')
local m=S.new{path='server/RacePrep',now=function() return at end,read=function() return nil end,write=function() return true end}
m.add('test','1,2,3,0.5,1,0');m.takeChanged('test')
assert(m.take('test','1,2,0.1')==1 and math.abs(m.store.map('test')['1:2'].a-.4)<1e-9,'server cell thinned')
assert(m.takeChanged('test'):find('^1,2,'),'thinned cell goes out in the next delta')
at=400;m.decay('test');assert(math.abs(m.store.map('test')['1:2'].a-.2)<1e-6,'expiry unchanged: still gone at 10 minutes')
assert(m.take('test','1,2,5')==1 and m.store.map('test')['1:2'].a==0,'taking more than is there empties the cell')
assert(m.takeChanged('test'):find(',0.000,',1,true) and m.store.count('test')==0,'emptied cell: explicit zero, then removed')
assert(m.take('test','9,9,0.1;bad;1,2,-1')==0,'unknown cells and junk rows ignored')
-- far pieces: seen coming out to FAR (80 m), one per cell further out
do
 local P=dofile('client/lua/ge/extensions/raceprep/rubberMarbles.lua')
 vec3=function(x,y,z) return {x=x,y=y,z=z,set=function(self,a,b,c2) self.x,self.y,self.z=a,b,c2 end} end
 color=function(r,g,b,a) return {r,g,b,a} end
 local tris={};debugDrawer={drawTriSolid=function(_,a,b,c2,col) tris[#tris+1]={x=(a.x+b.x+c2.x)/3,alpha=col[4]} end}
 core_camera={getPosition=function() return {x=0,y=0,z=1.2} end,getForward=function() return {x=1,y=0,z=0} end}
 P.configure(true,false,'test')
 for _,x in ipairs({5,25,60,90,-30}) do P.deposit(x+.5,.5,0,.3,1,0) end
 P.draw()
 local seen={}
 for _,t in ipairs(tris) do seen[math.floor(t.x+.5)]=true end
 assert(seen[5] and seen[25] and seen[60],'pieces at 5, 25 and 60 m ahead')
 assert(not seen[90] and not seen[-30],'none past FAR or behind the camera')
 -- a long 3 m band: pieces all the way out, inside the budgets
 P.clear();P.configure(true,false,'test')
 for x=5,200 do for y=2,4 do P.deposit(x+.5,y+.5,0,.3,1,0) end end
 tris={};P.draw();local far=0
 for _,t in ipairs(tris) do if t.x>60 then far=far+1 end end
 assert(far>0,'a band is drawn beyond 60 m, not just its first metres')
 assert(P.trianglesDrawn()<=P.MAX_TRIS,'triangle budget holds')
 -- worst case: a full map (50k cells) around the camera
 P.clear();P.configure(true,false,'test')
 for i=0,49999 do P.deposit((i%224)-111.5,math.floor(i/224)-111.5,0,.5,1,0) end
 local t0=os.clock();for _=1,20 do P.draw() end
 local ms=(os.clock()-t0)/20*1000
 print(string.format('marble pieces worst case (Lua side, 50k cells): %.2f ms/frame, %d tris',ms,P.trianglesDrawn()))
 assert(ms<2,'piece pass stays cheap even with a full map')
end
print('PASS: marbles fade (no pop), pieces seen to 80 m, admin size, wheels thin cells and flick pieces, mild picked-up grip that wears off, server thinning')
