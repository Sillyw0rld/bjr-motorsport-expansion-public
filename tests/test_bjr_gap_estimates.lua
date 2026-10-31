package.path='client/lua/?.lua;'..package.path
local G=require('ge/extensions/raceprep/bjr/raceGaps')
local race={name='S-bend',loopable=true,branchingEnabled=false,gates={
 {pos={x=0,y=0,z=0},width=12},
 {pos={x=100,y=0,z=0},width=12},
 {pos={x=100,y=100,z=0},width=12},
 {pos={x=0,y=100,z=0},width=12},
}}
local s={id='lap-one',phaseIndex=1,state='RACE',participants={
 {playerID=1,playerName='Ana',currentGate=1,currentLap=1},
 {playerID=2,playerName='Ben',currentGate=1,currentLap=1},
},leaderboard={{playerName='Ben',displayName='Ben'},{playerName='Ana',displayName='Ana'}}}
local cars={
 [1]={id=11,localDriver=true,pos={x=20,y=45,z=0}},
 [2]={id=22,pos={x=18,y=45,z=0}},
}
local function sample(now,view)
 return G.update(now,s,race,function() return cars end,view,0)
end
local oldOffLimit=math.max(40,race.gates[1].width*2)
assert(45>oldOffLimit,'the synthetic S-bend point exceeds the former straight-chord off-route limit')
G.reset()
local p=sample(100,'Ana')
assert(p.ahead and p.ahead.distanceM==2,'lap one gets a distance from the checkpoint estimate despite >40 m chord offset')
assert(p.ahead.estimated and p.ahead.distanceOffM>40,'packet marks curvy fallback as an estimate and retains its offset')
assert(not p.ahead.liveMs and p.ahead.liveReason=='Need another position sample','first sample explains why no live time is available')
cars[1].pos={x=22,y=45,z=0};cars[2].pos={x=30,y=45,z=0}
p=sample(200,'Ana')
assert(p.ahead.distanceM==8,'lap one distance follows forward movement on the curved section')
assert(p.ahead.liveMs and p.ahead.liveMs>0 and p.ahead.liveMs<100,'crossing time is interpolated after the other car passes')
local behind=sample(300,'Ben')
assert(behind.behind and behind.behind.playerName=='Ana' and behind.behind.distanceM>0,'the same estimate is available for the car behind')

-- Lap two uses the same synthetic curvy road and still produces a checkpoint estimate.
G.reset();s.id='lap-two';s.participants[1].currentLap=2;s.participants[2].currentLap=2
cars[1].pos={x=20,y=45,z=0};cars[2].pos={x=18,y=45,z=0}
p=sample(400,'Ana');assert(p.ahead and p.ahead.distanceM==2,'later lap gets a distance on the same curved segment')

-- Missing playerID mapping and history discontinuity produce short actionable reasons.
G.reset();s.id='missing-car';cars[2]=nil
p=sample(500,'Ana');assert(p.ahead.distanceReason=='No vehicle found for player ID 2','missing remote car names the unmatched BJR player ID')
s.participants[1].currentLap=1;s.participants[2].currentLap=1;cars[2]={id=22,pos={x=18,y=45,z=0}}
G.reset();s.id='reset-history';sample(600,'Ana');cars[2].pos={x=30,y=45,z=0};sample(700,'Ana')
cars[2].pos={x=75,y=45,z=0}
p=sample(800,'Ana');assert(p.ahead.distanceReason=='History reset: car jumped between samples','travelled guard exposes its history reset cause')

G.reset();s.id='not-crossed';cars[2].pos={x=30,y=45,z=0};cars[1].pos={x=20,y=45,z=0};sample(900,'Ana')
cars[2].pos={x=35,y=45,z=0};cars[1].pos={x=25,y=45,z=0}
p=sample(1000,'Ana');assert(p.ahead.distanceM==10 and p.ahead.liveReason=='Not crossed yet','a missing live crossing is diagnosed while distance remains available')

G.reset();s.id='off-route';cars[2].pos={x=20,y=250,z=0}
p=sample(1050,'Ana');assert(p.ahead.distanceReason=='Off route (250 m > 150 m)','extreme off-route positions report measured offset and limit')

G.reset();s.id='branched';race.branchingEnabled=true
p=sample(1100,'Ana');assert(p.ahead.distanceReason=='Layout branches; route distance unavailable','branching layout explains unavailable route distance')
print('BEFORE: synthetic S-bend line is 45 m from the checkpoint chord; old limit was '..oldOffLimit..' m, so progress was discarded')
print('AFTER: lap one and later laps retain checkpoint estimates, both leaderboard sides get distance, and unavailable causes are reported')
print('PASS: lap-one and later-lap curvy estimates, both leaderboard sides, remote lookup, resets and unavailable reasons')
