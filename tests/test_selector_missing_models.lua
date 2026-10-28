package.path='client/lua/?.lua;'..package.path
local function clone(t) if type(t)~='table' then return t end local out={};for k,v in pairs(t)do out[k]=clone(v)end;return out end
deepcopy=clone
local entries={real={model='real',config='stock',pi=500,class='C',source='measured'},stored={model='stored',config='stock',pi=600,class='B',source='measured'}}
jsonReadFile=function(path)if path:find('ratings%-seed')then return {entries=clone(entries),constants={}}end;return {models={},parts={}}end
readFile=function()return '{}'end
jsonDecode=function()return {models={}}end
-- Retained add-on parts make BOTH directories exist, but only one car is installed.
FS={directoryExists=function()return true end}
local registry={real={info={}}}
local calls={}
local models={real={model={key='real'},configs={}},stored={model={key='stored'},configs={}}}
core_vehicles={getModelsData=function()return registry end,getModel=function(model)
 calls[model]=(calls[model]or 0)+1
 assert(registry[model],'Vehicle not available: '..model)
 return models[model]
end}
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
R.decorateSelector();R.decorateSelector()
assert(calls.real==2 and not calls.stored,'part-only folders must never trigger missing-car lookups')
-- No permanent negative cache: a subsequently mounted car becomes available.
registry.stored={info={}}
R.decorateSelector()
assert(calls.stored==1,'late mounting must be detected without a restart')
print('PASS: selector skips part-only retained models and discovers later-mounted cars')
