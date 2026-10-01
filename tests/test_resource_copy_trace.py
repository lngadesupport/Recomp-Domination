import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('resource_trace', Path(__file__).parents[1] / 'scripts/analyze_resource_copy_trace.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def record(**changes):
    fields = dict(call=1, zero_calls=0, thread=10, length=4, source=100,
                  destination=200, input_offset=0, output_after=4,
                  remaining_after=0, window=131072, input_base=100,
                  output_base=200, source_bytes='01020304',
                  destination_bytes='01020304', result=200)
    fields.update(changes)
    return module.PREFIX + ' '.join(f'{key}={value}' for key, value in fields.items())


class ResourceTraceTests(unittest.TestCase):
    def test_valid_copy_and_unrelated_logs(self):
        result = module.summarize('other log\n' + record())
        self.assertEqual(result['samples'], 1)
        self.assertEqual(result['observations'], [])

    def test_zero_copy_empty_samples_and_sampling_gap(self):
        result = module.summarize(record(length=0, zero_calls=1, source_bytes='', destination_bytes='') + '\n' + record(call=128, zero_calls=100))
        self.assertEqual(result['zero_length_samples'], 1)
        self.assertEqual(result['last_sample']['zero_calls'], 100)
        self.assertEqual(result['observations'], [])

    def test_bad_return_and_differing_sample(self):
        result = module.summarize(record(result=99, destination_bytes='00000000'))
        self.assertEqual([r['kind'] for r in result['observations']], ['return_pointer_mismatch', 'byte_samples_differ'])

    def test_truncated_and_invalid_records(self):
        result = module.summarize(module.PREFIX + 'call=1\n' + record(source_bytes='xyz') + '\n' + record(zero_calls=2))
        self.assertEqual(result['samples'], 0)
        self.assertEqual(result['malformed_records'], 3)

    def test_counter_restart(self):
        result = module.summarize(record(call=64) + '\n' + record(call=1))
        self.assertEqual(result['observations'][0]['kind'], 'counter_restart_or_reordering')


if __name__ == '__main__':
    unittest.main()
