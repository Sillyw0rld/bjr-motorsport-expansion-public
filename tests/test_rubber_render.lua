-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
getCurrentLevelIdentifier=function() return 'test' end
local created,submitted=0
vec3=function(x,y,z) created=created+1;return {x=x,y=y,z=z} end
ColorF=function(r,g,b,a) created=created+1;return {r=r,g=g,b=b,a=a} end
local ms=0
Engine={Platform={getSystemTimeMS=function() ms=ms+.05;return ms end},Render={DynamicDecalMgr={addDecals=function(t,n) submitted=n;assert(t[1].position.x) end}}}
core_camera={getPosition=function() return {x=50,y=0,z=3} end}
local L=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
L.configure({enabled=true,perLap=2,lapsToFull=40},0)
for x=0,300 do for y=-1,1 do L.deposit(x,y,0,20,1,0) end end
local co=coroutine.create(L.build);local resumes=0
while coroutine.status(co)~='dead' do ms=0;assert(coroutine.resume(co));resumes=resumes+1;assert(resumes<10000) end
assert(resumes>1,'sorting, marching and decal construction yield to the budget')
assert(#L.currentLines()>0)
assert(created==0,'a rebuild creates no native objects (made when a patch first comes into view)')
assert(L.draw()>0 and submitted>0 and created>0);local before=created;L.draw()
assert(created==before,'render reuses cached native vectors and colours')
L.clear();assert(L.draw()==0,'reset removes cached decals too')
print('PASS: budgeted line/decal rebuild, native objects on first view then cached, reset')

-- Visual smoothing is bounded and never changes the recorded/extracted
-- nodes, level or height. Same number of cached decals, same submission API.
do
 local V=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
 V.configure({enabled=true,perLap=2,lapsToFull=40},0)
 local nodes={}
 for i=-130,130 do nodes[#nodes+1]={x=i*2,y=i%2==0 and .3 or -.3,z=2+i*.01,width=i%2==0 and 2.4 or 1.6,level=.7} end
 V.lines=function() return {nodes} end
 local before=created;V.build();assert(created==before,'smoothing allocates no native objects')
 local seen,number
 Engine.Render.DynamicDecalMgr.addDecals=function(t,n) seen,number=t,n end
 core_camera.getPosition=function() return {x=0,y=0,z=3} end
 assert(V.RANGE==200 and V.MAX_DECALS==1500)
 assert(V.draw()>0)
 local distant=false
 for i=1,number do
  local d=seen[i];local node=nodes[d.x/2+131]
  assert(node and node.y==(d.x/2%2==0 and .3 or -.3),'source nodes untouched')
  assert(math.abs(d.y-node.y)<=.20000001 and d.z==node.z,'bounded visual movement, height kept')
  assert(d.width>=1.6 and d.width<=2.4 and d.width~=node.width,'width softened within source bounds')
  assert(math.abs(d.alpha-V.ALPHA*.7)<1e-9,'opacity linear in rubber level (builds up lap by lap)')
  assert(d.scale.y==V.STEP*2 and d.scale.z==2 and d.texture==V.TEXTURE,'same decal method and size')
  assert(d.fadeStart==170 and d.fadeEnd==200,'same 30 m fade at longer range')
  if d.x>175 then distant=true end
 end
 assert(distant,'rubber beyond the old 150 m radius is submitted')
 before=created;V.draw();assert(created==before,'longer-range objects cached too')
 V.MAX_DECALS=2;assert(V.draw()==2 and number==2,'hard decal cap still enforced')
 V.clear();assert(V.draw()==0)
 print('PASS: bounded visual-only smoothing, 200 m range, unchanged cached submission and cap')
end
