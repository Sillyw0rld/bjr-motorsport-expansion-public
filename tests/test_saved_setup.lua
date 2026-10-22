-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- Save setup: the saved config's selector tile shows the car's rating and the
-- original car's picture (owner's Troglodyte "Race setup", 2026-10-16)
local function clone(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and clone(v) or v end return out end
deepcopy=clone
local written
jsonWriteFile=function(path,data) written={path=path,data=data} end
jsonReadFile=function(path)
 if path:find('ratings%-seed') then return {entries={},constants={}} end
 if path:find('saved%-setups') or path:find('%.pc$') then return nil end
 return {models={},parts={}}
end
readFile=function() return '{}' end
local identity=require('ge/extensions/raceprep/ratingIdentity')
local parts={['/main']='troglodyte_body',['/main/engine']='engine_2000r'}
local key=identity.key('hawk_troglodyte_2000r','stock',parts)
local car={config={model='hawk_troglodyte_2000r',partConfigFilename='vehicles/hawk_troglodyte_2000r/stock.pc',partsTree={}},
 vdata={model='hawk_troglodyte_2000r',activeParts=parts,activePartsData={}}}
core_vehicle_manager={getVehicleData=function() return car end}
jsonDecode=function(payload)
 if payload=='ratings' then return {entries={[key]={model='hawk_troglodyte_2000r',config='stock',pi=466,pi_speed=470,pi_technical=460,class='C',parts=parts}}} end
 return {models={}}
end
local R=dofile('client/lua/ge/extensions/raceprepRatings.lua')
R.onRatings('ratings')
-- 1. rating remembered under the saved name, written to the player's settings
local ok,e=R.rememberSavedSetup(7,'Race setup')
assert(ok and e.pi==466 and e.class=='C' and e.savedSetup and e.config=='Race setup','rating copied: '..tostring(ok))
assert(written and written.path=='/settings/raceprep/saved-setups.json' and written.data['hawk_troglodyte_2000r/Race setup'].pi==466,'persisted')
-- 2. the selector tile of the saved setup shows it; the model tile keeps the stock rating
local model={model={key='hawk_troglodyte_2000r',default_pc='stock',Name='Hawk Troglodyte 2000R'},
 configs={stock={key='stock',model_key='hawk_troglodyte_2000r',Name='Troglodyte 2000R'},mine={key='Race setup',model_key='hawk_troglodyte_2000r',Name='Race setup'}}}
core_vehicles={getModel=function() return model end}
pcall(R.decorateSelector)
local m=core_vehicles.getModel('hawk_troglodyte_2000r')
assert(m.configs.mine.Name:find('%[C 466%]'),'saved setup tile rated: '..m.configs.mine.Name)
-- 3. preview: copied from the factory config the car came from, never overwriting
local U=require('ge/extensions/raceprep/upgrades')
local files={['/vehicles/hawk_troglodyte_2000r/stock.jpg']=true}
local copies={}
FS={fileExists=function(_,p) return files[p]==true end,copyFile=function(_,a,b) copies[#copies+1]={a,b};files[b]=true end}
model.configs.stock.preview='/vehicles/hawk_troglodyte_2000r/stock.jpg'
assert(U.copyPreview(7,'Race setup'))
assert(copies[1][1]=='/vehicles/hawk_troglodyte_2000r/stock.jpg' and copies[1][2]=='/vehicles/hawk_troglodyte_2000r/Race setup.jpg','copied original picture')
assert(not U.copyPreview(7,'Race setup') and #copies==1,'an existing picture is never replaced')
-- from a saved (Custom) config: the model's default config picture
car.config.partConfigFilename='vehicles/hawk_troglodyte_2000r/Race setup.pc'
model.configs.mine['Config Type']='Custom'
assert(U.copyPreview(7,'Race setup v2') and copies[2][1]=='/vehicles/hawk_troglodyte_2000r/stock.jpg','default config picture for setups saved from a setup')
print('PASS: saved setup keeps the rating and the original car picture')
