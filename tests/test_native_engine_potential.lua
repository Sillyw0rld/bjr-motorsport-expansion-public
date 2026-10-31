package.path='client/lua/?.lua;'..package.path
local function copy(t)if type(t)~='table'then return t end;local o={};for k,v in pairs(t)do o[k]=copy(v)end;return o end
deepcopy=copy
local info={native=true,stockEngine='engine',parts={}}
package.loaded['common/raceprep/engineSelection']={info=function()return info end}
local base={activeParts={['/body/engine/engine']='engine',['/body/engine/engine/intake/stock']='stock'},powertrain={{type='combustionEngine',name='mainEngine'}},mainEngine={torque={{'rpm','torque'},{0,0},{5000,100}}},variables={}}
local current=copy(base);current.activeParts['/body/engine/engine/intake/stock']=nil;current.activeParts['/body/engine/engine/intake/race']='race'
current.activePartsData={race={information={name='Stage 3 Variable Boost Turbocharger'}}};current.variables={['$wastegateStart']={max=35},['$revLimitRPM']={max=12000}}
jsonReadFile=function()return{parts={engine='engine'},vars={}}end
local calls={}
package.loaded['jbeam/loader']={loadJbeam=function(_,_,_,cfg)
 calls[#calls+1]=copy(cfg)
 local v=copy(base)
 if cfg.vars['$wastegateStart']==35 then v.mainEngine.testMaximum=true end
 return{vdata=v}
end}
local N=require('ge/extensions/raceprep/nativeEnginePotential')
local cfg={partsTree={chosenPartName='engine',children={}},vars={['$wastegateStart']=12}}
local ref=N.reference(1,{model='car',config='factory'},cfg,current)
assert(ref.nativeTier==3 and ref.nativePartsChanged and ref.nativeMax.mainEngine.testMaximum)
assert(#calls==2 and calls[2].vars['$wastegateStart']==35 and calls[2].vars['$revLimitRPM']==12000 and cfg.vars['$wastegateStart']==12,'maximum compilation never edits applied tuning')
calls={};local stock=copy(base);stock.variables=current.variables
ref=N.reference(1,{model='car',config='factory'},cfg,stock)
assert(not ref.nativeMax and #calls==1,'stock presets remain stock')
calls={};stock.activeParts['/body/engine/engine/engine_mount/race_mount']='race_mount';stock.activePartsData={race_mount={information={name='Race Engine Mount'}}}
ref=N.reference(1,{model='car',config='factory'},cfg,stock)
assert(not ref.nativeMax and #calls==1,'non-power changes never enable maximum boost')
info=nil;assert(N.reference(1,{model='car',config='factory'},cfg,current)==nil)
print('PASS: private native factory/max-boost references, correct tier, unmodified applied tuning, stock/non-power exclusions and electric/unknown exclusion')
