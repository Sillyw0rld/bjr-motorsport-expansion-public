-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Rivals ghosts: the target lap and your best lap this run, drawn where each
-- car was at the same moment of its lap. Drawn in your game only: no car is
-- spawned (BeamMP would sync it to everyone) and nothing is sent.
local G={}
G.LENGTH,G.WIDTH,G.HEIGHT=4.4,1.9,1.4
G.FADE_NEAR,G.FADE_FAR=3,8 -- metres: invisible inside FADE_NEAR, full from FADE_FAR
--- position and heading at lap time t (ms) on a trace of {t,x,y,z} samples;
--- nil outside the trace. The heading spans about half a second either side,
--- steadier than one 0.2 s step.
function G.at(trace,t)
 local n=type(trace)=='table' and #trace or 0
 if n<2 or type(t)~='number' or t~=t or t<trace[1].t or t>trace[n].t then return end
 local lo,hi=1,n
 while hi-lo>1 do local mid=math.floor((lo+hi)/2);if trace[mid].t<=t then lo=mid else hi=mid end end
 local a,b=trace[lo],trace[hi];local f=b.t>a.t and (t-a.t)/(b.t-a.t) or 0
 local p={x=a.x+(b.x-a.x)*f,y=a.y+(b.y-a.y)*f,z=a.z+(b.z-a.z)*f}
 local s,e=trace[math.max(1,lo-2)],trace[math.min(n,hi+2)]
 local dx,dy=e.x-s.x,e.y-s.y;local len=math.sqrt(dx*dx+dy*dy)
 if len>=.05 then p.dx,p.dy=dx/len,dy/len end
 return p
end
--- the ghost's opacity at a distance from your car
function G.alpha(base,dist)
 if dist>=G.FADE_FAR then return base end
 if dist<=G.FADE_NEAR then return 0 end
 return base*(dist-G.FADE_NEAR)/(G.FADE_FAR-G.FADE_NEAR)
end
--- ghosts: {{trace, t, label, color={r,g,b}, alpha}}; me: your car's position
function G.draw(ghosts,me)
 if not debugDrawer or type(me)~='table' then return end
 local size=Point2F(G.HEIGHT,G.WIDTH)
 for _,g in ipairs(ghosts) do
  local p=G.at(g.trace,g.t)
  if p and p.dx then
   local a=G.alpha(g.alpha,math.sqrt((p.x-me.x)^2+(p.y-me.y)^2+(p.z-me.z)^2))
   if a>.01 then
    local half=G.LENGTH/2;local c=g.color
    -- traces are sampled near the car's centre of gravity; lift slightly so the box sits on the road
    debugDrawer:drawSquarePrism(vec3(p.x-p.dx*half,p.y-p.dy*half,p.z+.2),vec3(p.x+p.dx*half,p.y+p.dy*half,p.z+.2),size,size,ColorF(c[1],c[2],c[3],a))
    if g.label then
     local t=math.min(1,a*2.5)
     debugDrawer:drawTextAdvanced(vec3(p.x,p.y,p.z+1.7),String(g.label),ColorF(1,1,1,t),true,false,ColorI(0,0,0,math.floor(120*t)),false,false)
    end
   end
  end
 end
end
return G
