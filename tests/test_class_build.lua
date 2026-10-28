package.path='client/lua/?.lua;'..package.path
local B=require('common/raceprep/classBuild');local Rating=require('ge/extensions/raceprep/rating')
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
assert(read('server/RacePrep/ClassBuild.lua')==read('client/lua/common/raceprep/classBuild.lua'),'shared server/client eligibility/search source')
assert(B.band('A',Rating.classOf)==601)
assert(B.refusal({targetClass='A'},{pi=704},{pi=550},Rating.classOf)=='Your car is S 704: 4 PI over the A limit')
assert(B.refusal({targetClass='B'},{pi=550},{pi=601},Rating.classOf)=="This car's factory PI is already above B")
assert(not B.refusal({targetClass='B'},{pi=550},{pi=500},Rating.classOf))
assert(B.refusal({targetClass='B'},{pi=500},{pi=500},Rating.classOf):find('1 PI below'))
assert(B.refusal({targetClass='B'},{pi=550},nil,Rating.classOf):find('factory PI'))
local options={{row='tyres',name='30',category='grip'},{row='brakes',name='10',category='brakes'},{row='body',name='20',category='weight'},{row='power',name='35',category='power'},{row='power',name='200',category='power',blocked=true}}
local saw=0
local api={cap=600,draft={},options=options,limit=240,allowed=function(o)return not o.blocked end,predict=function(d)local pi=500;for _,v in pairs(d)do pi=pi+tonumber(v)end;saw=saw+1;return {pi=pi}end}
local search=B.search(api,'quick');for _=1,1000 do search.step();if search.done then break end end
assert(search.done and search.result and saw>1);local total=500;for k,v in pairs(search.result)do total=total+tonumber(v);assert(v~='200')end;assert(total==595,'balanced draft reaches cap minus five');assert(search.result.tyres and search.result.brakes and search.result.body and search.result.power)
local fit=B.search({cap=700,draft={},options={{row='a',name='10',remove=true},{row='b',name='4',remove=true}},limit=240,allowed=function()return true end,predict=function(d)local n=704;for _,v in pairs(d)do n=n-tonumber(v)end;return {pi=n}end},'fit')
for _=1,100 do fit.step();if fit.done then break end end;assert(fit.done and fit.result.b=='4'and not fit.result.a,'smallest sufficient PI removal')
local waiting=true;local async=B.search({cap=600,draft={},options={},limit=10,allowed=function()return true end,predict=function()if waiting then return nil,nil,true end;return {pi=500}end},'quick');async.step();assert(not async.done);waiting=false;for _=1,20 do async.step()end;assert(async.done)
local source=read('client/lua/ge/extensions/raceprepRatings.lua');local evaluator=assert(source:match('(local function evaluate.-)M.evaluate=evaluate'))
assert(evaluator:find('rating.compute(st,constants,st.drive)',1,true));assert(source:find('local e,err=evaluate(st,i)',1,true)and source:find('local e,err=evaluate(st,q.identity)',1,true),'same real evaluator for draft and live rating')
assert(not evaluator:find('0.495',1,true)and not evaluator:find('scale.mix',1,true),'no duplicated PI constants')
local P=dofile('server/RacePrep/EventPresets.lua');local found=0;for _,p in ipairs(P.builtins())do if p.category=='Build to class'then found=found+1;local lo,hi=B.band(p.patch.targetClass,Rating.classOf);assert(p.patch.piMin==lo and p.patch.piMax==hi)end end;assert(found==6)
-- 2.31.1: a saved setup is named after its file; the server must find the
-- same factory base as the client instead of refusing Ready forever
assert(read('server/RacePrep/AnchorSelection.lua')==read('client/lua/ge/extensions/raceprep/anchorSelection.lua'),'shared server/client anchor selection')
local seed=assert(loadstring(io.popen('python3 -I tests/json2lua.py server/RacePrep/ratings-seed.json'):read('*a')))()
local baseKey;for k,e in pairs(seed.entries)do if e.model=='etkc'and e.config=='kc6x_360_A'and e.source~='computed'then baseKey=k end end;assert(baseKey)
local main=read('server/RacePrep/RacePrep.lua');local fn=assert(main:match('(features%.factoryRating=function%(car%).-\nend)\n'))
local saved={model='etkc',config='my_build',parts=seed.entries[baseKey].parts,pi=550}
local env=setmetatable({features={autoRatings={defaultKey=function()end}},AnchorSelection=dofile('server/RacePrep/AnchorSelection.lua'),ratingSeed=seed,
 ratings={entries={saved=saved,[baseKey]=seed.entries[baseKey]},baselines=seed.baselines}},{__index=_G})
local chunk=assert(loadstring(fn..'\nreturn features.factoryRating'));setfenv(chunk,env);local factory=chunk()
assert(factory({ratingKey='saved'})==seed.entries[baseKey],'renamed saved setup resolves to its factory base')
assert(not B.refusal({targetClass='B'},saved,factory({ratingKey='saved'}),Rating.classOf),'saved B build may enter Build to B')
env.ratingSeed={entries={}};assert(factory({ratingKey='saved'})==nil,'unknown base still waits instead of guessing')
print('PASS: shared evaluator/no duplicate PI constants, six target bands, current/factory refusals, balanced margin/caps, async draft, smallest sufficient fit and renamed saved setups')
