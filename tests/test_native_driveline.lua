-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local D=dofile('client/lua/common/raceprep/driveline.lua')
local rows={
 {name='engine',type='combustionEngine'},
 {name='gearbox',type='manualGearbox',inputName='engine',gearRatio=2},
 {name='reactor',type='torsionReactor',inputName='gearbox'},
 {name='diff',type='differential',inputName='reactor',gearRatio=1},
 {name='left',type='shaft',inputName='diff',connectedWheel='FL'},
 {name='right',type='shaft',inputName='diff',connectedWheel='FR'},
}
local fixed,err,paths=D.resolve(rows,{reactor={gearRatio=4.23}},{FL=true,FR=true},{engine=true})
assert(fixed,err) assert(math.abs(fixed[1].ratio-4.23)<1e-6) assert(#paths==2)
-- Distinct front/rear EV reduction branches must not compound.
local ev={
 {name='frontMotor',type='electricMotor'}, {name='rearMotor',type='electricMotor'},
 {name='front',type='torsionReactor',inputName='frontMotor',gearRatio=7.6},
 {name='rear',type='differential',inputName='rearMotor',gearRatio=7.6},
 {name='fl',type='shaft',inputName='front',connectedWheel='FL'},
 {name='rr',type='shaft',inputName='rear',connectedWheel='RR'},
}
fixed,err=D.resolve(ev,{}, {FL=true,RR=true},{frontMotor=true,rearMotor=true})
assert(fixed,err) assert(fixed[1].ratio==7.6)
ev[4].gearRatio=8
fixed,err,paths=D.resolve(ev,{}, {FL=true,RR=true},{frontMotor=true,rearMotor=true})
assert(not fixed and err:find('Unequal') and #paths==2)
rows[3].inputName='diff'
fixed,err=D.resolve(rows,{}, {FL=true,FR=true},{engine=true})
assert(not fixed and err:find('cycle'))
rows[3].inputName='missing'
fixed,err=D.resolve(rows,{}, {FL=true,FR=true},{engine=true})
assert(not fixed and err:find('Incomplete'))
fixed,err=D.resolve({}, {}, {FL=true},{engine=true})
assert(not fixed and err:find('No powertrain path'))
print('PASS: canonical native final-drive paths, parallel EV branches and unsupported topology')

-- Compiled truck overrides, road-range selection and parallel planetary hubs.
local truck={
 {name='engine',type='combustionEngine',cid=1},
 {name='gearbox',type='manualGearbox',inputName='engine',cid=2},
 {name='range',type='rangeBox',inputName='gearbox',gearRatios={0,4,1},cid=3},
 {name='diff',type='differential',inputName='range',gearRatio=1,cid=4},
 {name='diff',type='differential',inputName='range',gearRatio=4,cid=5},
 {name='lhub',type='shaft',inputName='diff',gearRatio=3.333,cid=6},
 {name='rhub',type='shaft',inputName='diff',gearRatio=3.333,cid=7},
 {name='l',type='shaft',inputName='lhub',connectedWheel='RL',cid=8},
 {name='r',type='shaft',inputName='rhub',connectedWheel='RR',cid=9},
 {name='accessory',type='shaft',inputName='gearbox',gearRatio=72,cid=10},
}
fixed,err,paths=D.resolve(truck,{}, {RL=true,RR=true},{engine=true})
assert(fixed,err);assert(math.abs(fixed[1].ratio-4*3.333)<1e-6);assert(#paths==2)
truck[5].cid=nil
fixed,err=D.resolve(truck,{}, {RL=true,RR=true},{engine=true})
assert(not fixed and err:find('duplicate'))
print('PASS: truck CID overrides, high range and parallel hubs; ambiguous duplicates rejected')
