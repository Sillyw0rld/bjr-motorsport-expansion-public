import importlib.util,json,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('backfill',ROOT/'tools/backfill_progression.py');B=importlib.util.module_from_spec(spec);spec.loader.exec_module(B)
class Backfill(unittest.TestCase):
 def test_copy_idempotence_and_corrupt_input(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);(root/'history').mkdir();(root/'drivers.json').write_text(json.dumps({'drivers':{'private-id':{'name':'Test é','races':5,'finished':4,'safety':3,'wins':1,'podiums':1}}}))
   (root/'skills.json').write_text(json.dumps({'salt':'test','players':{}}))
   original=(root/'drivers.json').read_bytes();out=root/'output'
   first=B.run(root,out);before=(out/'progression.json').read_bytes();second=B.run(root,out)
   self.assertTrue(first['changed']);self.assertFalse(second['changed']);self.assertEqual(before,(out/'progression.json').read_bytes())
   self.assertEqual(first['driversRead'],1);self.assertEqual(first['drivers'][0]['licence'],'D');self.assertEqual(original,(root/'drivers.json').read_bytes())
   self.assertNotIn('private-id',before.decode())
   (root/'drivers.json').write_text('corrupt')
   with self.assertRaises(json.JSONDecodeError):B.run(root,out)
   self.assertEqual(before,(out/'progression.json').read_bytes())
if __name__=='__main__':unittest.main()
