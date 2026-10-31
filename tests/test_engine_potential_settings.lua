package.path='client/lua/?.lua;'..package.path
local E=require('common/raceprep/engineEffects');local L=dofile('server/RacePrep/EnginePotentialSettings.lua')
local stable=require('ge/extensions/raceprep/bjr/setupLibrary').signature
local a=E.settings();assert(stable(a)==stable(dofile('server/RacePrep/EnginePotentialDefaults.lua')))
local function readJSON(file)local p=assert(io.popen('python3 -I tests/json2lua.py '..file));local s=p:read('*a');assert(p:close());return assert(loadstring(s))()end
assert(stable(a)==stable(readJSON('client/lua/common/raceprep/engine-potential.defaults.json')))
assert(stable(a)==stable(readJSON('server/RacePrep/engine-potential.example.json')))
local saved,exists,logs=nil,false,{}
local api={read=function(n)if n=='engine-potential.example.json'then return a end;return saved end,exists=function()return exists end,log=function(v)logs[#logs+1]=v end}
assert(L.load(api)==a)
exists=true;assert(L.load(api)==a and #logs==1)
saved=readJSON('client/lua/common/raceprep/engine-potential.defaults.json');saved.ceilings.I4.na=350
assert(L.load(api)==saved and E.settings(saved)==saved)
saved.schema=99;assert(L.load(api)==a and not pcall(E.settings,saved))
print('PASS: client/server/JSON defaults agree; custom settings load; missing/corrupt/unsupported files retain defaults without a write')
