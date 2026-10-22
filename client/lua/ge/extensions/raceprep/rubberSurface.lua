-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- While dynamic rubber is enabled, neutralise converter's baked rubber
-- bonus and hide its static ribbon. Retain the road's wet/base friction.
local S={}
local originals,materials={},{}
local savedLevel
local fields={'roughnessCoefficient','defaultDepth','staticFrictionCoefficient','slidingFrictionCoefficient',
 'hydrodynamicFriction','stribeckVelocity','strength','collisiontype','fluidDensity','flowConsistencyIndex',
 'flowBehaviorIndex','dragAnisotropy','skidMarks','shearStrength'}
local function copy(gm)
 local result=ground_model();for _,key in ipairs(fields) do result[key]=gm[key] end;return result
end
function S.restore()
 if savedLevel and getCurrentLevelIdentifier()==savedLevel then
  for name,gm in pairs(originals) do
   local entry=core_environment and core_environment.groundModels[name]
   if entry then be:setGroundModel(name,gm);entry.cdata=gm end
  end
  for name,opacity in pairs(materials) do
   local mat=scenetree and scenetree.findObject(name)
   if mat then mat:setField('opacityFactor',0,tostring(opacity));mat:reload() end
  end
 end
 originals,materials,savedLevel={},{},nil;S.wet=false
end
function S.update(enabled)
 local level=getCurrentLevelIdentifier and getCurrentLevelIdentifier()
 if savedLevel and (not enabled or savedLevel~=level) then S.restore() end
 if not enabled or not level or savedLevel==level then return end
 savedLevel=level
 local root='/levels/'..level
 local meta=jsonReadFile and jsonReadFile(root..'/converter_metadata.json')
 -- Converter wet roads deliberately keep ASPHALT/RUMBLE_STRIP particle IDs
 -- for skid marks, so the collision ID alone cannot identify those roads.
 S.wet=meta and meta.wetPhysics and meta.wetPhysics.enabled==true or false
 local p=meta and meta.rubberPhysics
 if p and p.enabled and ground_model and core_environment and be then
  for _,name in pairs(p.materialAssignments or {}) do
   local entry=core_environment.groundModels[name]
   if entry and name:match('^AMS2_RUB_') then
    local coverage=(tonumber(name:match('_B(%d)_')) or 0)/4
    local penalty=name:match('_WET$') and -(p.wetPenaltyPercent or 0) or (p.dryBonusPercent or 0)
    local factor=1+penalty/100*coverage
    if factor>0 and not originals[name] then
     originals[name]=copy(entry.cdata);local clean=copy(entry.cdata)
     clean.staticFrictionCoefficient=clean.staticFrictionCoefficient/factor
     clean.slidingFrictionCoefficient=clean.slidingFrictionCoefficient/factor
     be:setGroundModel(name,clean);entry.cdata=clean
    end
   end
  end
 end
 for _,file in ipairs({'/main.materials.json','/art/racingline/main.materials.json'}) do
  for name in pairs(jsonReadFile and jsonReadFile(root..file) or {}) do
   if name=='ams2_racing_line_rubber' or name:match('_static_rubber$') then
    local mat=scenetree and scenetree.findObject(name)
    if mat and not materials[name] then
     materials[name]=tonumber(mat:getField('opacityFactor',0)) or 0
     mat:setField('opacityFactor',0,'0');mat:reload()
    end
   end
  end
 end
end
return S
