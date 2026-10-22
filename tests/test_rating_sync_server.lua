-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- server rating sync encoders (RacePrep.lua): full store without seed parts,
-- deltas for changes and removals (2026-10-17)
local s=io.open('server/RacePrep/RacePrep.lua'):read('*a')
local i=assert(s:find('local function wireEntry(',1,true));local j=assert(s:find('local function saveRatings()',1,true))
local function enc(v) local t=type(v)
 if t=='table' then local n=0 for _ in pairs(v) do n=n+1 end if n==0 then return '[]' end
  local o={} for k,x in pairs(v) do o[#o+1]=string.format('%q',tostring(k))..':'..enc(x) end table.sort(o) return '{'..table.concat(o,',')..'}'
 elseif t=='string' then return string.format('%q',v) else return tostring(v) end end
local env=setmetatable({Util={JsonEncode=enc},ratings={entries={k1={source='measured',pi=500,parts={a='b'}},k2={source='computed',pi=600,parts={c='d'}}},constants={}},ratingVehicles={}},{__index=_G})
local chunk=assert(loadstring(s:sub(i,j-1)..'\nreturn encodeRatings,encodeDelta'))
setfenv(chunk,env)
local encodeRatings,encodeDelta=chunk()
local function has(x,y) return x:find(y,1,true)~=nil end
local full=encodeRatings();assert(not has(full,'"a":"b"') and has(full,'"c":"d"'),'measured seed parts stripped, computed parts kept')
local d=encodeDelta({k2=env.ratings.entries.k2},{['5']={['5-1']='k2'}});assert(has(d,'"delta":true') and has(d,'"5-1":"k2"') and not has(d,'"k1"'),'delta carries only the change')
local r=encodeDelta(nil,{['7']=false});assert(has(r,'"entries":{}') and has(r,'"7":false'),'removal delta')
env.ratingPresentations={k1={tuningShare=.015,weightShare=0,carName='Car One'}}
full=encodeRatings();assert(has(full,'"presentation"') and has(full,'"tuningShare":0.015'),'owner bonus metadata travels with the raw entry')
assert(env.ratings.entries.k1.pi==500 and not env.ratings.entries.k1.presentation,'wire never mutates persisted calibration entries')
print('PASS: server rating sync: full store once (seed parts stripped), deltas for changes')
