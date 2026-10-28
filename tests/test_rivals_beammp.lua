-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local V=dofile('server/RacePrep/RivalsVerification.lua')
local R=dofile('server/RacePrep/Rivals.lua')
local Adapter=dofile('server/RacePrep/RivalsBeamMP.lua')
local parts={['/main']='car',['/main/engine']='engine',['/main/axle/wheel']='wheel'}
local d={jbm='car',vcf={mainPartName='car',parts={engine='engine',wheel='wheel'},vars={pressure=28}}}
local signature=assert(V.config('1-0:{packet}',function() return d end,R.canonical,parts,'car'))
d.vcf.vars.pressure=30
assert(signature~=V.config('1-0:{packet}',function() return d end,R.canonical,parts,'car'),'tuning changes server identity')
d.vcf.parts.engine='different';assert(not V.config('{}',function() return d end,R.canonical,parts,'car'),'false rated key cannot hide different parts')
d.vcf.parts.engine='engine';d.vcf.parts.wheel=nil;assert(not V.config('{}',function() return d end,R.canonical,parts,'car'),'incomplete parts fail closed')
d.vcf.parts.wheel='wheel';d.jbm='other';assert(not V.config('{}',function() return d end,R.canonical,parts,'car'))
d.jbm='car';local calls=0;local cars={[0]='1-0:{packet}'}
local mp={GetServerTimeMS=function() return 123456 end,GetPlayerVehicles=function(pid) assert(pid==1);return cars end,
 GetPositionRaw=function(pid,vid) assert(pid==1 and vid==0);calls=calls+1;return {pos={1,2,3},rot={0,0,0,1},vel={0,0,0},rvel={0,0,0},tim=3,ping=.05},'' end}
local b=Adapter.new(mp,function() return d end,R.canonical,V)
assert(b.available() and b.clock()==123456)
local raw,err=b.position(1,'1-0');assert(err=='' and raw.pos[1]==1 and raw.tim==3)
assert(not b.position(1,'2-0') and calls==1,'vehicle ID ownership enforced')
local car={model='car',key='rated',parts=parts};assert(b.config(1,'1-0',car));cars[0]=nil
assert(not b.config(1,'1-0',car),'removed vehicle cannot use cached identity')
-- A cached sample with changed coordinates but an unchanged packet time is
-- ignored. tim cannot act as official elapsed time.
local race={gates={{pos={x=0,y=0,z=0},dir={x=1,y=0,z=0}},{pos={x=60,y=0,z=0},dir={x=1,y=0,z=0}}}}
local tracker=assert(V.new(race,100));tracker.sample(0,{pos={-1,0,0},tim=1},'');tracker.sample(50,{pos={1,0,0},tim=1},'')
assert(not tracker.running())
-- Reverse start crossing cannot begin a lap.
tracker=assert(V.new(race,100));tracker.sample(0,{pos={1,0,0},tim=1},'');tracker.sample(50,{pos={-1,0,0},tim=2},'');assert(not tracker.running())
local automation={['/Camso_core']='Camso_core',['/Camso_Trim/Camso_Engine/engine_123']='engine_123'}
assert(V.config('{}',function() return {jbm='hawk',vcf={mainPartName='Camso_core',parts={Camso_Engine='engine_123'},vars={}}} end,R.canonical,automation,'hawk'))
assert(not V.config('{}',function() return d end,R.canonical,nil,'car'),'ratings without parts fail closed')
tracker=assert(V.new(race,100))
for i=0,12 do tracker.sample(i*50,{pos={-1+i*5.5,0,0},tim=i},'') end
assert(tracker.reason():find('Sustained speed'),'sustained speed above rated ceiling voids lap')
assert(not V.new({gates={false,false}},100),'malformed geometry fails closed')
print('PASS: BeamMP numeric vehicle ID, raw packet shape, cache freshness, server parts/tune identity, owner and reverse-crossing checks')
