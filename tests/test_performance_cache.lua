-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Regression: a PI (rated-point) reply must never populate the current-tuning
-- performance cache. getStats always collects the car's applied settings;
-- stale async replies after parts/tuning changes are rejected.
package.path='client/lua/?.lua;'..package.path
local f=dofile('tests/fixtures/rating-golden-v6.lua')
local function clone(t) if type(t)~='table' then return t end;local o={} for k,v in pairs(t) do o[k]=clone(v) end return o end
deepcopy=clone
jsonReadFile=function(path)
    if path:find('ratings%-seed') then return {entries={},constants=f.constants} end
    return {models={},parts={}}
end
readFile=function() return '{}' end;jsonDecode=function() return {models={}} end
serialize=function() return '{}' end
local vehMock={queueLuaCommand=function() end}
getObjectByID=function() return vehMock end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
local rating=require('ge/extensions/raceprep/rating')
local function get(fn,name)
    for n=1,100 do local key,value=debug.getupvalue(fn,n);if not key then break end;if key==name then return value,n end end
    error('missing upvalue '..name)
end
local function set(fn,name,v) local _,n=get(fn,name);debug.setupvalue(fn,n,v) end

-- the car: a shared data bundle; replacing data.vdata simulates a rebuild
local base
for _,x in ipairs(f.fixtures) do if x.model=='hawk_fm5' then base=x.static end end
assert(base,'hawk_fm5 fixture')
local data={vdata={nodes={},wheels={},beams={},torsionbars={},powertrain={},activeParts={}},
    config={vars={powerGain=15}}}
core_vehicle_manager={getVehicleData=function() return data end}
core_vehicles={getConfig=function() return {Drivetrain='RWD'} end}
local i={key='test/config/hash',model='test',config='config',parts={},bundle=data}
local function currentIdentity() i.vdata=data.vdata;i.bundle=data;return i end
set(R.onStatic,'currentIdentity',currentIdentity)
set(R.getStats,'currentIdentity',currentIdentity)
set(R.onStatic,'publish',function() end)
set(R.getStats,'isLocal',function() return true end)

local requests=get(R.onStatic,'requests')
local stats=get(R.getStats,'stats')
local statsRequests=get(R.getStats,'statsRequests')

local function tuned(mult)
    local st=clone(base);st.drive='RWD'
    for _,e in ipairs(st.engines) do for _,row in ipairs(e.torque) do row[2]=row[2]*mult end end
    return st
end
-- Race power part: rated at its +35% setting, currently tuned to +15%
local rated,actual15,actual35=tuned(1.35),tuned(1.15),tuned(1.35)
local want15=rating.performance(actual15,f.constants,'RWD')
local want35=rating.performance(actual35,f.constants,'RWD')
local wantRated=rating.performance(rated,f.constants,'RWD')
assert(math.abs(want15.zeroTo60-wantRated.zeroTo60)>0.01,'fixture must differ: +15% vs +35% torque')
assert(math.abs(want35.zeroTo60-wantRated.zeroTo60)<1e-9,'+35% tuning equals the rated point')

-- Order 1: rated PI reply first; it must NOT satisfy getStats with rated data
requests[7]={token='rated-1',identity=i,drive='RWD'}
R.onStatic(7,'rated-1',clone(rated))
assert(stats[7]==nil,'a rated PI reply must not write the live performance cache')
local got,prev=R.getStats(7)
assert(got==nil and prev==nil,'no live performance yet: nil until collected')
local req=statsRequests[7]
assert(req and req.token and req.rev==tostring(data.vdata),'getStats must queue a live, tuning-aware collection')
R.onStatic(7,req.token,clone(actual15))
got=R.getStats(7)
assert(got and math.abs(got.zeroTo60-want15.zeroTo60)<1e-9,
    'live collection supplies the +15% figures, not the rated +35% ones')
assert(math.abs(got.zeroTo60-wantRated.zeroTo60)>0.01)
assert(got.topSpeed==want15.topSpeed and got.estimated.topSpeed,'top speed reaches UI as an estimate when not measured')

-- PI still uses the rated point (and only it), for both tuning states
local piRated=assert(rating.compute(rated,f.constants,'RWD')).pi
local entriesTable=get(R.onStatic,'entries')
assert(entriesTable[i.key].pi==piRated,'PI stays at the rated point')

-- Same rated PI, different current-performance estimate: retune +15% -> +35%
data.vdata={nodes={},wheels={},beams={},torsionbars={},powertrain={},activeParts={}}
got=R.getStats(7)
assert(got and math.abs(got.zeroTo60-want15.zeroTo60)<1e-9,'previous figures stay visible while recollecting')
req=statsRequests[7]
assert(req and req.rev==tostring(data.vdata),'tuning change invalidates the cache')
R.onStatic(7,req.token,clone(actual35))
got=R.getStats(7)
assert(got and math.abs(got.zeroTo60-want35.zeroTo60)<1e-9,'+35% tuning shows its own performance')
assert(entriesTable[i.key].pi==piRated,'PI unchanged by tuning')

-- Order 2: live collection already filled the cache; a late rated reply must not overwrite it
requests[7]={token='rated-2',identity=i,drive='RWD'}
R.onStatic(7,'rated-2',clone(rated))
got=R.getStats(7)
assert(got and math.abs(got.zeroTo60-want35.zeroTo60)<1e-9,'a rated reply never clobbers live performance')

-- Stale replies: a collection started before a change is dropped on arrival
data.vdata={nodes={},wheels={},beams={},torsionbars={},powertrain={},activeParts={}}
local before=stats[7]
R.getStats(7)
local staleToken=statsRequests[7].token
assert(statsRequests[7].rev==tostring(data.vdata))
data.vdata={nodes={},wheels={},beams={},torsionbars={},powertrain={},activeParts={}}
R.onStatic(7,staleToken,clone(actual15)) -- collected for the previous build
assert(stats[7]==before,'a reply for the pre-change car is rejected')
req=statsRequests[7]
R.getStats(7)
req=statsRequests[7]
assert(req and req.rev==tostring(data.vdata),'a fresh collection is queued for the new build')
R.onStatic(7,req.token,clone(actual15))
got=R.getStats(7)
assert(got and math.abs(got.zeroTo60-want15.zeroTo60)<1e-9)

print('PASS: rated PI replies never seed the live performance cache; both callback orders and stale replies handled')
-- Draft replies use the exact evaluator but cannot contaminate the actual
-- rating table, live-performance cache, or an unrelated rebuilt car.
local previewCache=get(R.previewRating,'previews')
local actualEntries=get(R.onStatic,'entries');local beforeEntries=0;for _ in pairs(actualEntries)do beforeEntries=beforeEntries+1 end
local snapshot=get(R.getStats,'stats')[7]
local current=currentIdentity();local expected=assert(R.evaluate(clone(rated),current))
set(R.onStatic,'previewActive',{id=7,token='preview-test',key='draft-test',revision=data.vdata,identity=current,vd=data.vdata})
R.onStatic(7,'preview-test',clone(rated))
assert(previewCache['draft-test'].entry.pi==expected.pi and previewCache['draft-test'].entry.estimate)
local afterEntries=0;for _ in pairs(actualEntries)do afterEntries=afterEntries+1 end;assert(beforeEntries==afterEntries and get(R.getStats,'stats')[7]==snapshot,'preview cannot publish or overwrite the actual/live rating')
set(R.onStatic,'previewActive',{id=7,token='preview-stale',key='stale-draft',revision={},identity=current,vd=data.vdata})
R.onStatic(7,'preview-stale',clone(rated));assert(previewCache['stale-draft'].error=='Car changed'and not previewCache['stale-draft'].entry)
local gate=get(R.previewGate,'previewGateData');local fingerprints=R.previewGate();gate.passed=true;gate.formulaHash=fingerprints.formulaHash;gate.constantsHash=fingerprints.constantsHash;assert(R.previewGate().passed)
gate.formulaHash='changed';assert(not R.previewGate().passed,'formula mismatch must disable normal preview activation')
print('PASS: shared live/draft evaluator equality, no actual-cache contamination, stale preview rejection and formula-bound accuracy gate')
