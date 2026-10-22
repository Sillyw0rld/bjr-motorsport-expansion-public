-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local R=dofile('server/RacePrep/RubberMap.lua')
local writes,fail=0,false
local db=R.new{path='/unused',maxCells=3,read=function() return nil end,write=function(_,value)
 writes=writes+1;assert(value.schemaVersion==1);return not fail
end}
assert(db.save()==0)
assert(db.add('hirochi','1,2,3,2,1,0;1,2,3,3,1,0',3000)==2)
local wire,n=db.takeChanged('hirochi');assert(n==1 and tonumber(wire:match('^[^,]+,[^,]+,[^,]+,([^,]+)'))==5,'broadcast must be absolute')
assert(select(2,db.takeChanged('hirochi'))==0)
assert(db.add('hirochi','2,2,nan,1,1,0;2,2,3,501,1,0;2,2,3,1,inf,0;2,2,3,-1,1,0;999999999999999999,2,3,1,1,0')==0)
assert(db.add('../escape','1,2,3,1,1,0')==0)
assert(db.add('hirochi','2,2,3,1,1,0;3,2,3,1,1,0;4,2,3,1,1,0')==2,'cap new cells')
assert(db.count('hirochi')==3)
assert(db.add('hirochi','1,2,3,1,1,0')==1,'existing cells still grow at cap')
assert(#db.full('hirochi',2)==2)
assert(not db.set('hirochi',0/0,80))
assert(db.set('hirochi',.5,80))
assert(math.abs(db.map('hirochi')['1:2'].a-40)<1e-8)
assert(db.save()==1 and writes==1)
assert(db.save()==0 and writes==1)
db.add('hirochi','1,2,3,1,1,0');fail=true
assert(db.save()==0 and db.dirty.hirochi,'retry failed saves')
fail=false;assert(db.save()==1)
assert(db.set('hirochi','clean') and db.count('hirochi')==0)
assert(db.save()==1)
local loaded=R.new{path='/unused',maxCells=3,read=function() return {cells={
 ['1:2']={a=4,z=3,fx=1,fy=0},['bad']={a=4},['2:2']={a=0/0,z=3,fx=1,fy=0}}} end,write=function() return true end}
assert(loaded.count('hirochi')==1,'validate persisted cells')
local c1,c2=loaded.full('hirochi',2),loaded.full('hirochi',2)
assert(c1[1]==c2[1] and loaded.fullCache.hirochi,'wire chunks cached and reused until map revision changes')
print('PASS: rubber wire rejects, absolute deltas, cap, chunks, admin levels, clean and dirty-save retry')
