-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local S=require('ge/extensions/raceprep/bjr/selector')
local data={legal={class='B',pi=560},tooFast={class='A',pi=650},tooSlow={class='B',pi=510},banned={class='S',pi=700}}
local ratings={getConfig=function(model,key) return model=='car' and data[key] end}
local rules={allowedClasses={S=false},piMin=550,piMax=600}
for name,expected in pairs({legal=true,tooFast=false,tooSlow=false,banned=false,unknown=true}) do
 local req={state=true};S.authorize(req,'car','vehicles/car/'..name..'.pc',rules,ratings);assert(req.state==expected,name)
end
local no={state=false};S.authorize(no,'car','legal',rules,ratings);assert(not no.state,'native restrictions/search never overridden')
assert(S.check('car',nil,rules,ratings),'raw captured parts checked at Ready')
local fake={passesFilters=function(i) return i.matches~=false end}
local getModel=function(m) return {configs=m=='allBanned' and {a={key='fast'},b={key='banned'}} or {a={key='legal'},b={key='banned'}}} end
local ownRatings={getConfig=function(_,key) return ({fast=data.tooFast,banned=data.banned,legal=data.legal})[key] end}
local bound=S.wrap(fake,function() return true end,function() return rules end,function() return ownRatings end,getModel)
assert(not fake.passesFilters{model='allBanned'} and fake.passesFilters{model='mixed'},'hide a model folder only when every known config is disallowed')
assert(not fake.passesFilters{model='mixed',matches=false})
S.restore(bound);assert(fake.passesFilters{model='allBanned'})
print('PASS: selector class/PI exclusion, config paths, pending ratings and native-denial preservation')
