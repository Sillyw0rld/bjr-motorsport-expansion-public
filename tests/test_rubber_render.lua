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
  assert(d.fadeStart==140 and d.fadeEnd==200,'gentler native distance fade, unchanged draw radius')
  if d.x>175 then distant=true end
 end
 assert(distant,'rubber beyond the old 150 m radius is submitted')
 before=created;V.draw();assert(created==before,'longer-range objects cached too')
 V.MAX_DECALS=2;assert(V.draw()==2 and number==2,'hard decal cap still enforced')
 V.clear();assert(V.draw()==0)
 print('PASS: bounded visual-only smoothing, 200 m range, unchanged cached submission and cap')
end

-- 0.40 compatibility remaps only cached visual alpha. Accumulation values,
-- geometry, render batching and object reuse retain the existing contracts.
do
 local previous=rawget(_G,'beamng_version')
 beamng_version='0.39.4.0'
 local old=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
 assert(old.visualAlpha(.3)==.3 and old.visualAlpha(0)==0)
 assert(old.VISUAL_TINT==1,'older versions retain their original tint')
 assert(old.VISUAL_WIDTH_SCALE==1,'older versions retain their original displayed width')
 beamng_version='0.40.0.0'
 local new=dofile('client/lua/ge/extensions/raceprep/rubberLine.lua')
 assert(new.visualAlpha(0)==0 and new.visualAlpha(new.ALPHA)==1)
 assert(new.visualAlpha(.1)>.9 and new.visualAlpha(.1)<new.visualAlpha(.4))
 assert(new.visualAlpha(.4)<new.visualAlpha(new.ALPHA))
 new.configure({enabled=true,perLap=2,lapsToFull=40},0)
 new.lines=function() return {{{x=0,y=0,z=0,width=2,level=.2},{x=2,y=0,z=0,width=2,level=.8}}} end
 new.build()
 local data,count
 Engine.Render.DynamicDecalMgr.addDecals=function(t,n) data,count=t,n end
 assert(new.draw()==2 and count==2)
 assert(data[1].color.a==new.visualAlpha(data[1].alpha))
 assert(data[2].color.a==new.visualAlpha(data[2].alpha))
 assert(data[1].color.r==new.VISUAL_TINT and data[1].color.g==new.VISUAL_TINT and data[1].color.b==new.VISUAL_TINT)
 assert(new.VISUAL_TINT>0 and new.VISUAL_TINT<1,'charcoal modulation retains texture detail')
 assert(data[1].scale.x==data[1].width*1.35,'wider visual footprint retains measured width variation')
 assert(data[1].width==2 and data[2].width==2,'recorded and extracted widths are unchanged')
 assert(data[1].color.a<data[2].color.a and data[2].color.a<=1)
 assert(data[1].texture==new.TEXTURE and data[2].texture==new.TEXTURE)
 local n=created;new.draw();assert(created==n,'0.40 correction creates no objects per frame')
 beamng_version=previous
 print('PASS: 0.40 visual alpha remap, monotonic buildup, unchanged older versions and cache')
end
