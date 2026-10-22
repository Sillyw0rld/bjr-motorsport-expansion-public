-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- Stock engine package (2026-10-16): a slot not in the package gets its own
-- jbeam default back. The car's intake / engine management / internals are
-- core slots whose stock part is named like the slot; '' emptied them.
local U=require('ge/extensions/raceprep/upgrades')
local vdata={activePartsData={
 Camso_Engine_72098={slots2={{name='Camso_Intake_72098',default='Camso_Intake_72098',coreSlot=true},
  {name='Camso_EngineManagement_72098',default='Camso_EngineManagement_72098',coreSlot=true}}},
 rp_engine_hub={slots={{'type','default','description'},{'rp_engine_x_exhaust','','Exhaust'}}}}}
assert(U.slotDefault(vdata,'Camso_Intake_72098')=='Camso_Intake_72098','core intake: its stock part')
assert(U.slotDefault(vdata,'Camso_EngineManagement_72098')=='Camso_EngineManagement_72098')
assert(U.slotDefault(vdata,'rp_engine_x_exhaust')=='','Race Prep extra slot: empty by default')
assert(U.slotDefault(vdata,'missing')==nil)
print('PASS: engine packages restore each slot\'s stock default (no empty core slots)')
