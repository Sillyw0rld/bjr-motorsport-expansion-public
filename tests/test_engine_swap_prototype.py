# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Offline safety for the isolated engine-swap tools; no game connection."""
from pathlib import Path
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/engine_swaps'))
from catalogue import car_table, geometry
from build_prototype import build, stabilize_engine_beams


def string(s):
    s=s.encode();return b'S'+struct.pack('<I',len(s))+s


class SwapTools(unittest.TestCase):
    def test_binary_design(self):
        raw=b'\x01T'+struct.pack('<II',0,2)+string('BlockConfig')+string('EngBlock_Inl6_Name')+string('flag')+b'1'
        self.assertEqual(car_table(raw),{'BlockConfig':'EngBlock_Inl6_Name','flag':True})
        with self.assertRaises(ValueError):car_table(raw+b'junk')
        with self.assertRaises(ValueError):car_table(b'\x01S')

    def test_legacy_design_never_executes(self):
        raw=b'do local _={Family={BlockConfig="EngBlock_V8_Name",Bore=80},Variant={Bore=75,Stroke=80}}; error("must not execute"); return _ end'
        self.assertEqual(car_table(raw)['Family']['BlockConfig'],'EngBlock_V8_Name')
        self.assertEqual(car_table(raw)['Variant']['Bore'],75)

    def test_engine_mass_not_gearbox(self):
        text='{"nodes":[{"nodeWeight":20},'+','.join('["engine%d",%d,%d,%d,{}]'%(i,i%2,i//2%2,i//4) for i in range(8))+',{"nodeWeight":90},["engine_Gearbox8",0,0,0]],"beams":[]}'
        shape=geometry(text)
        self.assertEqual(shape['massKG'],160)
        self.assertEqual(shape['sizeXYZ'],[1,1,1])

    def test_lighter_engine_beams_keep_local_stability_settings(self):
        source = '\n'.join(['{"beams": [', '["id1:", "id2:"],',
            '{"beamSpring":1000,"beamDamp":10,"beamStrength":5000,"beamDeform":100},',
            '["engine0", "engine1", {}],',
            '["engine1", "body", {"beamSpring":2000}],',
            '["body", "gearbox", {}],',
            '["engine0", "body", {}]', '] }'])
        old = [{'id':'engine0','mass':10}, {'id':'engine1','mass':10}]
        new = [{'id':'engine0','mass':2.5}, {'id':'engine1','mass':2.5}]
        result, evidence = stabilize_engine_beams(source, old, new)
        data = json.loads(result)['beams']
        self.assertEqual(evidence, {'beamsScaled':3, 'minimumMassRatio':.25})
        self.assertEqual(data[2][2], {'beamSpring':250, 'beamDamp':2.5})
        self.assertEqual(data[3][2], {'beamSpring':500, 'beamDamp':2.5})
        self.assertEqual(data[4][2], {}, 'untouched chassis/gearbox beam')
        self.assertEqual(data[5][2], {'beamSpring':250, 'beamDamp':2.5})
        self.assertEqual(data[1]['beamStrength'],5000)
        self.assertEqual(data[1]['beamDeform'],100)
        same, evidence = stabilize_engine_beams(source, old, old)
        self.assertEqual(same, source)
        self.assertEqual(evidence['beamsScaled'],0)

    def test_generator_retains_drivetrain_and_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);stock={'format':2,'vars':{'$finaldrive_f':4.7},'parts':{'Camso_Engine':'Camso_Engine_r','Camso_Transmission':'receiver_box','Camso_wheels_front':'receiver_tyres','Camso_engine_structure':'receiver_structure'}}
            structure='{"information":{"name":"Structure"},"slotType":"Camso_engine_structure","nodes":[{"nodeWeight":20},'+','.join('["engine%d",%d,%d,%d,{"engineGroup":["engine_block"]}]'%(i,i%2,i//2%2,i//4) for i in range(8))+',{"nodeWeight":50},["engine_Gearbox8",0,0,0]],"beams":[]}'
            engine='{\n// Real exports contain comments; replacement must still take effect.\n"information":{"name":"Donor"},"slotType":"Camso_Engine","slots":[["Camso_engine_structure","donor_structure","Structure"],["Camso_Transmission","donor_box","Transmission"]],"mainEngine":{"inertia":0.2,"torque":[[0,0],[3000,200]]},"soundConfigExhaust":{"sampleName":"DONOR"}}'
            ra,da=p/'receiver.zip',p/'donor.zip'
            with zipfile.ZipFile(ra,'w') as z:
                z.writestr('vehicles/r/r.pc',json.dumps(stock));z.writestr('vehicles/r/structure.jbeam','{"receiver_structure":'+structure+'}')
                z.writestr('vehicles/r/engine.jbeam','{"Camso_Engine_r":{"information":{"name":"Recipient"},"soundConfigExhaust":{"sampleName":"RECIPIENT"}}}')
            with zipfile.ZipFile(da,'w') as z:
                z.writestr('vehicles/d/eng_d/engine.jbeam','{"Camso_Engine_d":'+engine+'}')
                z.writestr('vehicles/d/d.pc',json.dumps({'parts':{}}))
                z.writestr('vehicles/d/eng_d/intake.jbeam','{"Camso_Intake_d":{"information":{"name":"Intake"},"slotType":"Camso_Intake_d"}}')
            before=ra.read_bytes(),da.read_bytes()
            shape=geometry(structure)
            recipient={'model':'r','archive':str(ra),'config':'r','engineGeometry':shape,'fuel':'Gasoline','engineDevice':'combustionEngine','engineMember':'vehicles/r/engine.jbeam','enginePart':'Camso_Engine_r','structureMember':'vehicles/r/structure.jbeam','structurePart':'receiver_structure','inertia':.1,'drive':'FWD'}
            donor={'model':'d','config':'d','archive':str(da),'engineGeometry':{**shape,'massKG':200,'nodes':[{**n,'mass':25} for n in shape['nodes']]},'fuel':'Gasoline','engineDevice':'combustionEngine','engineMember':'vehicles/d/eng_d/engine.jbeam','enginePart':'Camso_Engine_d','title':'Donor','inertia':.2,'infoHP':150}
            out=p/'output';m=build({'engines':[recipient,donor]},'r','d',out)
            pc=json.loads((out/'vehicles/r/rp_swap_d.pc').read_text())
            self.assertEqual(pc['vars'],stock['vars'])
            self.assertEqual(pc['parts']['Camso_Transmission'],'receiver_box')
            self.assertEqual(pc['parts']['Camso_wheels_front'],'receiver_tyres')
            self.assertEqual(m['massDeltaKG'],40)
            self.assertEqual((ra.read_bytes(),da.read_bytes()),before)
            new=json.loads((out/'vehicles/r/rp_swap/structure.jbeam').read_text())['rp_swap_d_structure']
            weights=[n[4]['nodeWeight'] for n in new['nodes'] if isinstance(n,list) and str(n[0]).startswith('engine') and not str(n[0]).startswith('engine_Gearbox')]
            self.assertEqual(weights,[25]*8)
            converted=p/'namespaced'
            proof=build({'engines':[{**recipient,'engineDevice':'camsoEngine'},donor]},'r','d',converted,
                        ident='rp_swap_unique',namespace=True,keep_audio=True,engine_hub='donor_hub',hub_slot='rp_unique_hub')
            self.assertEqual(proof['partRenames']['Camso_Intake_d'],'rp_swap_unique_Camso_Intake_d')
            generated=json.loads((converted/'vehicles/r/rp_swap/engine.jbeam').read_text())
            self.assertEqual(generated['rp_swap_unique_engine']['slotType'],'Camso_Engine')
            self.assertEqual(generated['rp_swap_unique_engine']['soundConfigExhaust']['sampleName'],'RECIPIENT')
            self.assertIn(['Camso_Transmission','receiver_box','Transmission'],generated['rp_swap_unique_engine']['slots'])
            self.assertIn(['Camso_engine_structure','rp_swap_unique_structure','Structure'],generated['rp_swap_unique_engine']['slots'])
            self.assertEqual(generated['rp_swap_unique_engine']['slots'][1],['rp_unique_hub','donor_hub','Engine upgrade slots'])
            intake=json.loads((converted/'vehicles/r/rp_swap/intake.jbeam').read_text())
            self.assertEqual(intake['rp_swap_unique_Camso_Intake_d']['slotType'],'rp_swap_unique_Camso_Intake_d')
            self.assertEqual((ra.read_bytes(),da.read_bytes()),before)
            oversized={**donor,'engineGeometry':{**donor['engineGeometry'],'sizeXYZ':[2,2,2]}}
            with self.assertRaises(AssertionError):build({'engines':[recipient,oversized]},'r','d',p/'rejected')
            self.assertFalse((p/'rejected').exists())


if __name__=='__main__':unittest.main()
