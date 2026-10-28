-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local R=dofile('server/RacePrep/Rivals.lua')
local function result(time,driver)
 return {kind='rivals',verified=true,verification={version=1,method='beammp-server-crossings'},raceID=1,raceName='Circuit',runID='run-'..time,recordContext={layout='layout-a',rulesKey='rules-a',rules={trackLimits='invalid'}},
  rows={{verified=true,rivalDriver=driver or 'salted-hash',buildKey='build',model='car',car='Car',class='B',pi=550,name='Driver',best={time=time,verified=true},status='FIN'}}}
end
local groups={};R.add(groups,result(60000));R.add(groups,result(61000));R.add(groups,result(59000))
local bad=result(1000);bad.rows[1].best.invalid=true;R.add(groups,bad)
bad=result(900);bad.rows[1].status='DSQ';R.add(groups,bad)
bad=result(800);bad.rows[1].buildKey=nil;R.add(groups,bad)
local g=R.view(groups,'salted-hash');assert(#g==1 and #g[1].rows==1 and g[1].rows[1].time==59000 and g[1].rows[1].personal)
assert(g[1].rows[1].driver==nil,'private identity field is not published')
local other=result(58000,'other');other.recordContext.rulesKey='rules-b';R.add(groups,other)
other=result(57000,'other');other.recordContext.layout='layout-b';R.add(groups,other)
assert(#R.view(groups,'salted-hash')==3,'rule and layout edits form separate challenges')
assert(R.canonical({a=1,b=2})==R.canonical({b=2,a=1}),'key order does not change provenance')
assert(R.canonical({a=1})~=R.canonical({a='1'}),'typed values cannot alias')
print('PASS: valid-only records, PB, provenance, missing build rejection and layout/rules isolation')
