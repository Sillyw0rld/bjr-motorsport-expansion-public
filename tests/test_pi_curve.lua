-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;server/RacePrep/?.lua;'..package.path
local R=dofile('client/lua/ge/extensions/raceprep/rating.lua')
local S=dofile('server/RacePrep/RatingStore.lua')
local I=dofile('server/RacePrep/RatingIdentity.lua')

-- Load real seed via json2lua
local function readSeed(rel)
    local h=assert(io.popen('python3 -I tests/json2lua.py '..rel))
    local s=h:read('*a');h:close()
    return assert(loadstring(s))()
end
local clientSeed=readSeed('client/lua/ge/extensions/raceprep/ratings-seed.json')
local serverSeed=readSeed('server/RacePrep/ratings-seed.json')
assert(clientSeed.constants and clientSeed.constants.curve,'client seed must define constants.curve')
assert(serverSeed.constants and serverSeed.constants.curve,'server seed must define constants.curve')
for k,v in pairs(R.CURVE) do
    assert(clientSeed.constants.curve[k]==v and serverSeed.constants.curve[k]==v and S.CURVE[k]==v,'curve param mismatch: '..k)
end

-- 1. Client and server copies give identical output everywhere; fitted low end <= 300; never > 999
local prev=100
for raw=-3000,3000 do
    local c1=R.curve(raw)
    local c2=S.curve(raw)
    local c3=R.curve(raw,clientSeed.constants)
    local c4=S.curve(raw,serverSeed.constants)
    assert(c1==c2 and c1==c3 and c1==c4,'client/server curve mismatch at raw='..raw)
    assert(c1%1==0 and c1>=100 and c1<=999,'bounds/integer violation at raw='..raw)
    assert(c1>=prev,'monotonicity violation at raw='..raw)
    prev=c1
    if raw>=300 then
        assert(c1==R.curve(raw,{knee=300,cap=999,a=.495,b=.58,c=.29}),'upper curve changed')
    end
    -- When constants.curve is absent, curve is the identity (clamped 100..999)
    local idExpected=math.max(100,math.min(999,raw))
    assert(R.curve(raw,{})==idExpected and S.curve(raw,{})==idExpected,'absent constants.curve must be identity at '..raw)
end

-- 2. Continuity at the knee; unchanged smooth upper branch with unit right slope
local p=clientSeed.constants.curve
local H=p.cap-p.knee
local function cont(raw)
    if raw<=p.knee then return math.max(100,100+(p.knee-100)*(raw-p.lowRaw)/(p.knee-p.lowRaw)) end
    local u=(raw-p.knee)/H
    local z=u+(p.a*u*u+p.b*u^4)/(1+p.c*u^3)
    return p.knee+H*(1-math.exp(-z))
end
local eps=1e-5
local slopeLeft=(cont(300)-cont(300-eps))/eps
local slopeRight=(cont(300+eps)-cont(300))/eps
assert(math.abs(slopeLeft-(p.knee-100)/(p.knee-p.lowRaw))<1e-6 and math.abs(slopeRight-1)<1e-6,'fitted left slope and frozen right slope at knee')
assert(math.abs(cont(300-eps)-cont(300+eps))<2*eps,'continuous knee')
local prevSlope=1
for raw=301,2500 do
    local y0,y1=cont(raw-1),cont(raw)
    local d=y1-y0
    assert(y1>y0 and d>0 and d<prevSlope,'continuous curve must be strictly increasing with strictly decreasing slope at '..raw)
    prevSlope=d
end

-- 3. Target table (with stiffer R/P/X progression; 999 only beyond 2000)
local targets={
    {300,300,0},
    {400,399,5},
    {500,497,5},
    {600,591,5},
    {700,680,5},
    {800,762,5},
    {900,832,5},
    {960,867,5},
    {1100,928,5},
    {1300,973,5},
    {1500,990,5},
}
for _,t in ipairs(targets) do
    local got=R.curve(t[1])
    assert(math.abs(got-t[2])<=t[3],string.format('raw %d: expected ~%d (+/-%d), got %d',t[1],t[2],t[3],got))
end
assert(R.curve(1500)<999,'raw 1500 must not reach 999 X')
assert(R.curve(2100)==999,'very high raw build reaches 999 X')

-- 4. Raw-space anchoring and bonuses, no double-curving, client/server bonus parity
local function clone(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=clone(v) end return o end
deepcopy=clone
jsonReadFile=function(path)
    if path:find('ratings%-seed') then return clone(clientSeed) end
    return {models={},parts={}}
end
readFile=function() return '{"models":{}}' end
jsonDecode=function() return {models={}} end
log=function() end
package.loaded['ge/extensions/raceprepRatings']=nil
local RR=dofile('client/lua/ge/extensions/raceprepRatings.lua')

-- Test anchoring above 999 raw (e.g. upgraded Hawk Trackeater SSR: stock raw 960, formula base 980, upgraded formula raw 1180 -> anchored raw 1160)
local ssrBase=RR.anchorBase('hawk_trackeater_ssr')
assert(ssrBase and ssrBase.raw.pi==960 and ssrBase.pi==R.curve(960) and ssrBase.class=='R')
local computedHigh={
    pi=R.curve(1180),pi_speed=R.curve(1200),pi_technical=R.curve(1160),
    raw={pi=1180,pi_speed=1200,pi_technical=1160},
    class=R.classOf(R.curve(1180)),source='computed'
}
local anchoredHigh=RR.anchor(clone(computedHigh),'hawk_trackeater_ssr')
local wantRaw=960+(1180-ssrBase.formula.pi)
assert(anchoredHigh.raw.pi==wantRaw,'anchoring must operate on unclamped raw values (>999), got '..tostring(anchoredHigh.raw.pi))
assert(anchoredHigh.pi==R.curve(wantRaw),'anchored PI must be curved once from raw '..wantRaw)
-- Calling anchor again on an already-anchored entry must not double-curve
local anchoredTwice=RR.anchor(clone(anchoredHigh),'hawk_trackeater_ssr')
assert(anchoredTwice.raw.pi==ssrBase.raw.pi+(wantRaw-ssrBase.formula.pi) and anchoredTwice.pi==R.curve(anchoredTwice.raw.pi))

-- Test server validate + present with raw > 999 and bonus shares: no double curving
local payload={
    model='hawk_trackeater_ssr',config='Race',parts={a='rp_body_1ef241e8e10a_race'},
    pi=anchoredHigh.pi,pi_speed=anchoredHigh.pi_speed,pi_technical=anchoredHigh.pi_technical,
    raw=anchoredHigh.raw,anchored=true,
    presentation={tuningShare=0.06,weightShare=0.03,carName='Trackeater SSR'}
}
local validated=assert(S.validate(payload,I,serverSeed.constants))
assert(validated.raw.pi==wantRaw and validated.pi==R.curve(wantRaw),'validate preserves raw and curves once')
local meta=assert(S.presentation(payload))
local presented=S.present(validated,meta,serverSeed.constants)
local wantTotal=R.curve(wantRaw*(1+0.06+0.03))
local wantTun=R.curve(wantRaw*(1+0.06))-R.curve(wantRaw)
local wantWgt=R.curve(wantRaw*(1+0.03))-R.curve(wantRaw)
assert(presented.pi==wantTotal and presented.performancePI==R.curve(wantRaw),'present computes bonus in raw space and curves once')
assert(presented.tuningPotentialPI==wantTun and presented.weightBonusPI==wantWgt,'bonus labels show curved differences')

-- Client withPotential matches server RatingStore.present on remote presentation metadata
RR.onRatings('dummy') -- no-op
local fakeKey='hawk_trackeater_ssr/Race/'..I.hash(payload.parts)
local deltaPayload={delta=true,entries={[fakeKey]={
    model='hawk_trackeater_ssr',config='Race',parts=payload.parts,
    pi=validated.pi,pi_speed=validated.pi_speed,pi_technical=validated.pi_technical,
    raw=validated.raw,class=validated.class,source='computed',anchored=true,
    presentation=meta
}},vehicles={['9']={['9-1']=fakeKey}}}
jsonDecode=function(s) if s=='delta' then return deltaPayload end return {models={}} end
RR.onRatings('delta')
local clientRemote=assert(RR.getServerVehicle('9-1'))
assert(clientRemote.pi==presented.pi and clientRemote.performancePI==presented.performancePI
    and clientRemote.tuningPotentialPI==presented.tuningPotentialPI
    and clientRemote.weightBonusPI==presented.weightBonusPI,'client withPotential and server present must match')

-- 5. Known stock cars' classes and PIs
local known={
    {'neonna_gt',296,'E'},
    {'tata_dot',R.curve(488),'C'},
    {'hawk_fm5',R.curve(513),'B'},
    {'temerario_super_gt',R.curve(809),'S'},
    {'hawk_trackeater_ssr_1000',R.curve(850),'S'},
    {'laser__tamera',R.curve(882),'R'},
    {'laser__tamere',R.curve(913),'R'},
    {'hawk_trackeater_ssr',R.curve(960),'R'},
}
for _,k in ipairs(known) do
    local model,wantPI,wantClass=k[1],k[2],k[3]
    local found
    for _,e in pairs(clientSeed.entries) do
        if e.model==model and not e.native then found=e break end
    end
    assert(found,model..' missing from seed')
    assert(found.pi==wantPI and found.class==wantClass,
        string.format('%s: expected %s %d, got %s %d',model,wantClass,wantPI,tostring(found.class), tonumber(found.pi) or -1))
end

print('PASS: PI curve properties, client/server parity, raw-space anchoring/bonuses without double curving, and known car classes')
-- A stock formula baseline previously capped at 999 must be recovered in
-- raw space too. Otherwise the new raw result creates a phantom upgrade.
local golden=dofile('tests/fixtures/rating-golden-v6.lua')
for _,f in ipairs(golden.fixtures) do
 if f.model=='laser__tamera' or f.model=='laser__tamere' then
  local current=assert(R.compute(f.static,clientSeed.constants,f.drive))
  local base=assert(RR.anchorBase(f.model))
  local unchanged=RR.anchor(current,f.model)
  for _,field in ipairs({'pi','pi_speed','pi_technical'})do
   assert(unchanged.raw[field]==base.raw[field],f.model..' stock has phantom raw '..field..': '..unchanged.raw[field]..' versus '..base.raw[field])
  end
 end
end
