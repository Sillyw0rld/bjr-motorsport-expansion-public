-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local L=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
getCurrentLevelIdentifier=function() return 'hirochi' end
BJI={CLIENT_READY=true};local sent={}
TriggerServerEvent=function(event,wire) sent[#sent+1]={event,wire} end
package.loaded['ge/extensions/raceprep/net']={send=function(...) return TriggerServerEvent(...) end} -- chunking: test_net_chunks.lua
L.configure({enabled=true,level='hirochi',lapsToFull=40,perLap=2,dryBonus=3,wetPenalty=5},0)
assert(L.FULL==80 and sent[1][1]=='RacePrepRubberGet')
local k12,k66=L.cellKey(1,2),L.cellKey(6,6)
L.deposit(1.2,2.5,3,2,1,0)
assert(type(next(L.cells()))=='number','rubberLine cells use numeric keys')
assert(L.count()==1 and L.pending()[k12]==2)
assert(L.merge('1,2,3,10,1,0')==1 and L.cells()[k12].amt==12)
L.merge('1,2,3,10,1,0');assert(L.cells()[k12].amt==12,'absolute deltas idempotent')
assert(L.flush()==1 and not next(L.pending()))
L.merge('1,2,3,12,1,0');assert(L.cells()[k12].amt==12)
assert(L.levelAt(2.5,3.5,3)==0,'3x3 mean below MIN_LEVEL is no grip')
L.merge('1,2,3,48,1,0');assert(math.abs(L.levelAt(2.5,3.5,3)-48/9/80)<1e-12,'3x3 mean grip lookup')
assert(L.levelAt(2.5,3.5,30)==0,'no grip transfer between bridge decks')
assert(math.abs(L.factor(false,1)-1.03)<1e-9 and math.abs(L.factor(true,1)-.95)<1e-9)
L.deposit(1,2,3,600,1,0);assert(L.flush()==1 and L.pending()[k12]==100,'bound each outgoing amount')
assert(L.merge('x;1,2,3,nan,1,0;10000000,2,3,1,1,0')==0)
L.onReset('other');assert(L.count()==1)
L.onReset('hirochi');assert(L.count()==0 and not next(L.pending()) and L.synced)
assert(L.onDelta('other|1,2,3,80,1,0')==0)
assert(L.onDelta('hirochi|1,2,3,80,1,0')==1 and L.queued()==1)
L.MERGE_ROWS=1;assert(L.onDelta('hirochi|5,5,3,80,1,0;6,6,3,80,1,0')==2)
L.update(0);assert(L.queued()==2 and L.cells()[k12].amt==80,'merged one row per frame')
L.update(0);L.update(0);assert(L.queued()==0 and L.cells()[k66].amt==80);L.MERGE_ROWS=1500
L.clear();assert(L.onDelta('hirochi|1,2,3,80,1,0')==0,'wait for reset before deltas')
L.deposit(0,0,0,1,1,0);L.update(.1);L.clear();assert(not L.busy(),'clear cancels a running rebuild')
L.configure({enabled=false,lapsToFull=400,dryBonus=3,wetPenalty=5},1)
assert(L.FULL==L.PER_LAP*400)
print('PASS: rubber absolute sync + pending, bounded batches, grip, height isolation, map reset and coroutine cancellation')
-- 1.9.3: a wide, well-used road gives ONE line, not a stack of copies
local W=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
W.configure({enabled=true,level='hirochi',lapsToFull=10,perLap=1.4,dryBonus=3,wetPenalty=5},0)
for x=0,300 do for y=-6,6 do W.deposit(x+.5,y+.5,0,20-math.abs(y),1,0,true) end end
local lines=W.lines();assert(#lines==1,'one line on a wide road, got '..#lines)
assert(#lines[1]>=140,'line covers the road')
assert(lines[1][70].level>1 and W.ALPHA>=0.8,'core line level is not diluted to faint opacity by fringe cells')
-- Join inbox drains completely before starting a line rebuild, then rebuilds immediately
do
 local J=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
 J.configure({enabled=true,level='hirochi',lapsToFull=10,perLap=1.4,dryBonus=3,wetPenalty=5},0)
 J.onReset('hirochi')
 J.MERGE_ROWS=50
 local rows={}
 for x=0,120 do rows[#rows+1]=string.format('%d,0,0,14,1,0',x) end
 assert(J.onDelta('hirochi|'..table.concat(rows,';'))==121)
 J.update(.01);assert(#J.currentLines()==0 and not J.busy(),'does not start partial rebuild while inbox is still draining')
 J.update(.01);J.update(.01) -- finishes draining 121 rows and starts rebuild immediately (no 15 s wait)
 while J.busy() do J.update(.01) end
 assert(#J.currentLines()==1,'rebuilds complete line immediately after inbox finishes draining')
end
print('PASS: wide road builds a single rubber line')
-- uploads are small and frequent (150 cells per 1.25 s): BeamMP retries big-ratio packets with a 30 MB buffer
do
 local C=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
 C.configure({enabled=true,level='hirochi',lapsToFull=40,perLap=2,dryBonus=3,wetPenalty=5},0)
 for x=0,699 do C.deposit(x+.5,.5,0,1,1,0) end
 local n=0 for _ in pairs(C.pending()) do n=n+1 end
 assert(n==700)
 assert(C.UPLOAD_ROWS<=150 and C.SEND_S<=1.25,'small, frequent uploads (BeamMP zlib guess)')
 assert(C.flush()==C.UPLOAD_ROWS,'first upload capped')
 local left=0 for _ in pairs(C.pending()) do left=left+1 end
 assert(left==700-C.UPLOAD_ROWS,'the rest waits for the next upload')
 while left>0 do local n=C.flush();assert(n==math.min(left,C.UPLOAD_ROWS));left=left-n end
 print('PASS: rubber uploads capped at '..C.UPLOAD_ROWS..' cells per flush, every '..C.SEND_S..' s')
end
-- 2026-10-20: the line builds up lap by lap (no peak floor, linear opacity)
do
 local P=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
 P.configure({enabled=true,level='hirochi',lapsToFull=10,perLap=1.4,dryBonus=3,wetPenalty=5},0)
 for x=0,300 do for y=-1,1 do P.deposit(x+.5,y+.5,0,1.4,1,0,true) end end -- one lap of rubber
 P.deposit(150.5,1.5,0,12.6,1,0,true) -- one hot cell at the edge of that stretch
 local lines=P.lines();assert(#lines==1)
 local lv=lines[1][40].level
 assert(lv>0.05 and lv<0.2,'one lap = about a tenth of full rubber, got '..lv)
 for _,n in ipairs(lines[1]) do assert(n.level<0.5,'a single hot edge cell does not make the stretch look nearly full: '..n.level) end
 print('PASS: rubber line level builds up lap by lap (no peak floor)')
end
