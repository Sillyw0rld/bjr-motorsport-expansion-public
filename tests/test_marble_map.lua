-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local at=100
local M=dofile('server/RacePrep/MarbleMap.lua')
local m=M.new{path='server/RacePrep',now=function() return at end,read=function() return nil end,write=function() return true end}
assert(m.add('test','1,2,3,1,1,0')==1)
assert(m.store.map('test')['1:2'].a==1)
assert(m.save()==1 and not m.store.dirty.test)
at=400;m.decay('test');assert(math.abs(m.store.map('test')['1:2'].a-.5)<1e-8)
assert(not m.store.dirty.test and m.save()==0,'in-memory linear fade does not mark map dirty before expiry')
assert(M.GRIP_LOSS==.03 and M.LIFETIME==600)
at=700;local wire=m.takeChanged('test');assert(wire:find(',0.000,',1,true))
assert(m.store.dirty.test and m.save()==1,'expiry to zero marks map dirty once to persist cleanup')
assert(m.store.count('test')==0)
m.add('test','1,2,3,1,1,0');m.clean('test');assert(m.store.count('test')==0)
-- 2026-10-17 live error: a join snapshot cached before an expiry named a removed cell
do
 at=1000;local m2=M.new{path='server/RacePrep',now=function() return at end,read=function() return nil end,write=function() return true end}
 m2.add('j','5,6,1,1,1,0');m2.add('j','7,8,1,1,1,0');m2.takeChanged('j')
 at=at+601
 assert(#m2.full('j',1000)==1)          -- a join fades both to zero; snapshot cached with them
 m2.takeChanged('j')                     -- the 10 s delta removes the zeroed marbles
 local ok,chunks=pcall(m2.full,'j',1000) -- the next joiner
 assert(ok,'join after expiry must not fail: '..tostring(chunks))
 assert(#chunks==0,'removed marbles are not sent to joiners')
end
print('PASS: marble density cap, 10-minute server decay, deletion broadcasts and cleanup')
