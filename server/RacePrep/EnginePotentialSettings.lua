-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local P={}
function P.load(api)
 local defaults=api.read('engine-potential.example.json') or dofile(debug.getinfo(1).source:gsub('^@',''):gsub('EnginePotentialSettings.lua$','EnginePotentialDefaults.lua'))
 local input=api.read('engine-potential.json')
 if not input then
  if api.exists('engine-potential.json')then api.log('Invalid engine-potential.json; using shipped defaults without overwriting it.')end
  return defaults
 end
 local function same(value,reference)
  if type(value)~=type(reference)then return false end
  if type(value)=='number'then return value==value and value>0 and value<1e6 end
  if type(value)=='table'then
   for k,v in pairs(reference)do if not same(value[k],v)then return false end end
   for k in pairs(value)do if reference[k]==nil then return false end end
  end
  return true
 end
 if not same(input,defaults)or input.schema~=1 or input.headroom[1]>input.headroom[2]or input.headroom[2]>input.headroom[3]or input.headroom[3]>1 or input.displacementClamp[1]>input.displacementClamp[2]or input.fallback.fullBelowHP>=input.fallback.quarterAboveHP or input.fallback.minimumScale>1 then
  api.log('Invalid engine-potential.json; using shipped defaults without overwriting it.');return defaults
 end
 return input
end
return P
