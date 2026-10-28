local C=dofile('server/RacePrep/Challenges.lua')
local function proof(t) return {time=t or 10000,sectors={3000,4000,3000},trace={{t=1}}} end
for _,kind in ipairs(C.ORDER)do
 local r=C.newRun(kind,{});assert(not r.add(proof(),false),'invalid '..kind)
end
assert(C.newRun('bestLap').add(proof(),true).time==10000)
local streak=C.newRun('cleanStreak');assert(streak.add(proof(),true).metric.value==1);assert(streak.add(proof(),true).metric.value==2);streak.add(proof(),false);assert(streak.add(proof(),true).metric.value==1)
local consistency=C.newRun('consistency');for i=1,4 do assert(not consistency.add(proof(10000+i*100),true))end
assert(consistency.add(proof(10500),true).metric.value==400)
assert(not consistency.add(proof(13000),true))
local sector=C.newRun('sectorAttack');assert(sector.add(proof(),true).metric.value==3000);assert(not sector.add({time=10000,sectors={}},true))
local tyre=C.newRun('tyreSaver',{minLaps=2});assert(not tyre.add(proof(10000),true));assert(tyre.add(proof(10100),true).metric.value==2);assert(not tyre.add(proof(11000),true));assert(not tyre.add(proof(9000),true));assert(tyre.add(proof(9010),true).metric.value==2)
local race={loopable=true,startPositions={{pos={x=0,y=0,z=0}}},gates={{pos={x=0,y=0,z=0},dir={x=1,y=0,z=0}},{pos={x=100,y=0,z=0},dir={x=1,y=0,z=0}},{pos={x=150,y=20,z=0},dir={x=0,y=1,z=0}}}}
local trap=assert(C.trap(race,C.settings()));assert(trap.from==1 and trap.to==2 and trap.x==50)
local speed=C.newRun('speedTrap',{trap=trap});speed.position(0,{pos={40,0,0}},'');speed.position(200,{pos={60,0,0}},'');assert(speed.add(proof(),true).metric.value==100);assert(not speed.add(proof(),true))
speed.position(300,{pos={40,50,0}},'');speed.position(500,{pos={60,50,0}},'');assert(not speed.add(proof(),true),'outside trap width')
local distance=C.newRun('raceDistance',{laps=2,start=race.startPositions[1]})
distance.position(0,{pos={0,0,0}},'');distance.position(2000,{pos={0,0,0}},'');distance.position(7000,{pos={0,0,0}},'')
assert(not distance.add({time=10000,started=7000,crossedAt=17000},true));assert(distance.add({time=10000,started=17000,crossedAt=27000},true).metric.value==20000)
local bad=C.newRun('raceDistance',{laps=1,start=race.startPositions[1]});assert(not bad.add({time=10000,started=0,crossedAt=10000},true),'standing start required')
for _,kind in ipairs(C.ORDER)do local v=kind=='speedTrap'and 55 or kind=='consistency'and 100 or kind=='cleanStreak'and 8 or kind=='tyreSaver'and 5 or 10000;local m=assert(C.metric(kind,v));assert(C.validMetric(m,kind));m.metric.value=v+1;assert(not C.validMetric(m,kind))end
print('PASS: all seven server scorers, invalid resets, stationary distance start, sector/trap geometry and crossing, metric validation')
