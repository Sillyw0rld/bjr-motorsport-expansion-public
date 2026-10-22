# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from engine_swaps import fuel

class FuelConversion(unittest.TestCase):
    def test_real_tank_clone(self):
        with tempfile.TemporaryDirectory() as tmp:
            rows=[]
            for model, label, energy, density, liquid in [('r','Gasoline','gasoline',46400000,.76),('d','Ethanol','gasoline',27000000,.79)]:
                path=Path(tmp)/(model+'.zip')
                tank={'information':{'name':'Original tank'},'slotType':'Camso_FuelTank',
                      'mainTank':{'energyType':energy,'energyDensity':density,'fuelLiquidDensity':liquid,'fuelCapacity':80,'startingFuelCapacity':'$fuel','breakTriggerBeam':'fuelTank'},
                      'variables':[['$fuel','range','L','Engine',80,0,80]],'nodes':[['id','x','y','z']], 'beams':[]}
                with zipfile.ZipFile(path,'w') as z:
                    z.writestr(f'vehicles/{model}/c.pc',json.dumps({'parts':{}}))
                    z.writestr(f'vehicles/{model}/tank.jbeam',json.dumps({'tank_'+model:tank}))
                rows.append({'archive':str(path),'model':model,'config':'c','fuel':label})
            result=fuel.generate(*rows,'test')
            cloned=json.loads(result['text'])['test_fuel_tank']
            self.assertEqual(cloned['mainTank']['energyDensity'],27000000)
            self.assertEqual(cloned['mainTank']['fuelLiquidDensity'],.79)
            self.assertEqual(cloned['mainTank']['fuelCapacity'],80)
            self.assertEqual(cloned['mainTank']['startingFuelCapacity'],'$fuel')
            self.assertEqual(cloned['mainTank']['breakTriggerBeam'],'fuelTank')
            self.assertEqual(result['stockPart'],'tank_r')
            self.assertIsNone(fuel.compatibility(*rows))
            self.assertIsNone(fuel.generate(rows[0],rows[0],'same'))
    def test_native_intake_uses_donor_curve(self):
        from engine_swaps.native_intakes import generate
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'native.zip'
            engine={'information':{'name':'Engine'},'slotType':'Camso_Engine',
                    'slots':[['type','default','description'],['Camso_Intake_x','stock_intake','Intake']],
                    'mainEngine':{'torque':[['rpm','torque'],[0,0],[1000,100],[2000,200]],'maxRPM':2000}}
            intake={'information':{'name':'Stock Intake'},'slotType':'Camso_Intake_x'}
            with zipfile.ZipFile(path,'w') as z:
                z.writestr('vehicles/d/eng/engine.jbeam',json.dumps({'engine':engine}))
                z.writestr('vehicles/d/eng/intake.jbeam',json.dumps({'stock_intake':intake}))
            parts=generate({'archive':str(path),'engineMember':'vehicles/d/eng/engine.jbeam','enginePart':'engine','engineDevice':'combustionEngine'},'test',{'Camso_Intake_x':'unique_intake'},2000)
            self.assertEqual(len(parts),2)
            self.assertEqual(parts['test_intake_race']['slotType'],'unique_intake')
            self.assertEqual(parts['test_intake_race']['mainEngine']['torqueModIntake'][-1],[2000,12])

    def test_missing_data_blocks_cross_fuel(self):
        r={'archive':'absent','model':'r','config':'c','fuel':'Gasoline'}
        d={**r,'fuel':'Ethanol'}
        # Missing source archives are an input error, never a silently usable swap.
        self.assertTrue(fuel.compatibility(r,d).startswith('Fuel conversion unavailable:'))

if __name__=='__main__':unittest.main()
