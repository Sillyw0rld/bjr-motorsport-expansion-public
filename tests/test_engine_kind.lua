-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local E=dofile('client/lua/common/raceprep/engineKind.lua')
local function detect(t,fuel,extra)
 local d={name='engine',type=t,requiredEnergyType=fuel}
 for k,v in pairs(extra or {}) do d[k]=v end
 return E.detect({d},{})
end
assert(detect('camsoEngine').kind=='automation')
assert(detect('combustionEngine','gasoline').kind=='petrol')
assert(detect('combustionEngine','diesel',{turbocharger={isExisting=true}}).forcedInduction)
assert(detect('combustionEngine','diesel',{turbocharger={isExisting=false}}).kind=='diesel')
assert(not detect('combustionEngine','hydrogen').supported)
assert(not detect('combustionEngine').supported,'never guess gasoline when fuel data is absent')
assert(not detect('customEngine','gasoline').supported)
assert(not E.detect({}).supported)
local e=E.detect({{name='rear',type='electricMotor'},{name='front',type='electricMotor'}},{})
assert(e.kind=='electric' and #e.engines==2 and e.engines[1].name=='front')
local hybrid=E.detect({{name='ice',type='combustionEngine'},{name='motor',type='electricMotor'}},
 {ice={energyStorage={'tank'},turbocharger='turbo'},turbo={}},{tank={energyType='diesel'}})
assert(hybrid.kind=='hybrid' and hybrid.supported and hybrid.forcedInduction and hybrid.engines[1].kind=='diesel')
assert(E.detect({{name='ice',type='combustionEngine'}},{ice={requiredEnergyType='diesel'}}).kind=='diesel')
assert(not E.detect({{name='a',type='electricMotor'},{name='b',type='unknown'}},{}).supported)
print('PASS: read-only Automation/petrol/diesel/electric/hybrid detection, induction flags and unknown fail-closed')
