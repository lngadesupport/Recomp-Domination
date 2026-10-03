import importlib.util
from pathlib import Path
import unittest
path=Path(__file__).resolve().parents[1]/'scripts/analyze_frame_state.py'
spec=importlib.util.spec_from_file_location('frame_state',path)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def sample(caller='123456',numeric=0,words=32):
    lanes=','.join(['0']*words)+','
    return f'[downhill:frame-state] call=120 vsync=40 numeric_calls={numeric} entry_pc=0x238c50 caller=0x{caller} frame=0x8000 exit_pc=0x238c70 exit_sp=0x8020 stack={lanes} gpr={lanes}'
class FrameState(unittest.TestCase):
    def test_empty(self):
        r=module.analyze('other');self.assertFalse(r['numeric_observed']);self.assertEqual(r['frame_state_records'],0)
    def test_callers(self):
        r=module.analyze(sample()+'\n'+sample('abcdef',7));self.assertEqual(r['observed_callers'],{'0x123456':1,'0xabcdef':1});self.assertEqual(r['maximum_numeric_wrapper_calls'],7);self.assertTrue(r['numeric_observed'])
    def test_truncated(self):
        r=module.analyze(sample(words=31));self.assertEqual(r['malformed_frame_records'],1);self.assertIsNone(r['last_frame_state'])
    def test_invalid(self):
        r=module.analyze(sample().replace('vsync=40','vsync=bad')+'\n'+sample(numeric=-1));self.assertEqual(r['malformed_frame_records'],2)
    def test_numeric_after_cap(self):
        r=module.analyze('[downhill:resource-return] call=65536 routine=0x177da0 exit_pc=0x1234');self.assertTrue(r['numeric_observed']);self.assertEqual(r['numeric_return_records'],1)
if __name__=='__main__':unittest.main()
