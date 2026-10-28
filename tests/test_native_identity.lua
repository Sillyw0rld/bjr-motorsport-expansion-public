-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local I=dofile('server/RacePrep/RatingIdentity.lua')
local N=dofile('server/RacePrep/NativeIdentity.lua')
local function load(rel)
 local h=assert(io.popen('python3 -I tests/json2lua.py '..rel));local src=h:read('*a');h:close()
 return assert(loadstring(src))()
end
local function new(data)
 local reads=0
 local n=N.new{path='x',hash=I.hash,read=function() reads=reads+1;return data end}
 return n,function() return reads end
end

-- Every parts-less BeamNG factory rating in the shipped seed gets its list.
local real=load('server/RacePrep/native-identity.json')
local seed=load('server/RacePrep/ratings-seed.json')
local n,reads=new(real);local want,got=0,0
for key,e in pairs(seed.entries) do
 if e.native and not e.parts then
  want=want+1
  local parts=n.parts(key)
  if parts and I.key(e.model,e.config,parts)==key then got=got+1 end
 end
end
assert(want==740 and got==want,'factory lists for every parts-less native seed rating: '..got..'/'..want)
assert(reads()==1,'file read once')

-- Rivals compares a list with BeamMP's copy of the car: MPHelpers.simplifyVehConfig
-- keys each part by slot ID, by full slot path when two slots share an ID.
-- Emulated from each real list (the main part is BeamMP's mainPartName).
Util={JsonDecode=function() end}
local V=dofile('server/RacePrep/RivalsVerification.lua')
local R=dofile('server/RacePrep/Rivals.lua')
local matched=0
for key,e in pairs(seed.entries) do
 if e.native and not e.parts then
  local list=n.parts(key);local slots,byId={},{}
  for path,part in pairs(list) do
   local slot,id=path:match('^(.*/([^/]+))/[^/]+$')
   if slot then slots[#slots+1]={id=id,path=slot..'/',part=part};byId[id]=(byId[id] or 0)+1 end
  end
  local simple={}
  for _,s in ipairs(slots) do simple[byId[s.id]>1 and s.path or s.id]=s.part end
  local d={jbm=e.model,vcf={mainPartName=e.model,parts=simple,vars={}}}
  local ok,why=V.config('{}',function() return d end,R.canonical,list,e.model)
  assert(ok,key..': '..tostring(why));matched=matched+1
  local swap;for id,part in pairs(simple) do swap=id;break end
  simple[swap]=simple[swap]..'_other'
  assert(not V.config('{}',function() return d end,R.canonical,list,e.model),key..': a changed part must not match')
 end
end
assert(matched==740)

-- A list that doesn't reproduce its key's hash is refused, and so are
-- unknown keys, wrong hashes and a missing file.
local parts={['/main']='car',['/car_engine']='car_engine_v8'}
local h=I.hash(parts)
local data={schemaVersion=1,models={car={paths={'/main','/car_engine'},parts={'car','car_engine_v8','car_engine_i4'},
 base={{1,1},{2,2}},configs={stock={hash=h},tampered={hash=h,set={{2,3}}},dropped={hash=h,drop={2}}}}}}
n=new(data)
local p=assert(n.parts('car/stock/'..h));assert(p['/car_engine']=='car_engine_v8' and I.hash(p)==h)
assert(n.parts('car/tampered/'..h)==nil,'changed part refused')
assert(n.parts('car/dropped/'..h)==nil,'dropped part refused')
assert(n.parts('car/stock/00000000')==nil,'key with another hash refused')
assert(n.parts('car/other/'..h)==nil and n.parts('nope/stock/'..h)==nil and n.parts('garbage')==nil and n.parts(nil)==nil)
assert(new(nil).parts('car/stock/'..h)==nil,'missing file')
assert(N.new{path='x',hash=I.hash,read=function() error('broken') end}.parts('car/stock/'..h)==nil,'unreadable file')
print('PASS: native factory parts lists for all '..want..' seed ratings; tampered, unknown and missing refused')
