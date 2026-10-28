-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Offline CPU benchmark; API calls are stubs, never a BeamMP test server.
local F=dofile('tests/rivals_fixture.lua')
local samples=F.samples();local iterations=10000
for _,count in ipairs({1,8}) do
 local e=F.new(count)
 -- Exercise the 1024-gate supported bound as well as the 3-gate capture.
 for _,gates in ipairs({3,1024}) do
  for i=4,gates do e.race.gates[i]={pos={x=1000+i*10,y=0,z=0},dir={x=1,y=0,z=0},width=20} end
  e.ms=e.ms+3000
  for pid=1,count do assert(e.manager.start(pid,{challenge='layout',practice=true,vehicle=pid..'-0'})) end
  local times={};local at=e.ms
  for i=1,iterations do
   local s=samples[(i-1)%#samples+1];at=at+50
   for pid=1,count do e.positions[pid]={pos=s.raw.pos,rot=s.raw.rot,vel=s.raw.vel,rvel=s.raw.rvel,tim=at/1000,ping=.05} end
   e.ms=at
   local start=os.clock();e.manager.poll();times[i]=(os.clock()-start)*1e6
  end
  table.sort(times);local sum=0;for _,t in ipairs(times) do sum=sum+t end
  local avg=sum/#times
  print(string.format('%d runs, %d gates: n=%d, mean=%.2f us/poll, p95=%.2f us, max=%.2f us, CPU@20Hz=%.4f%% of one core (stub APIs)',count,gates,#times,avg,times[math.ceil(#times*.95)],times[#times],avg*20/10000))
 end
end
