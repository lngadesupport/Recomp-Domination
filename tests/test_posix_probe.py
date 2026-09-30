import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("probe", Path(__file__).resolve().parents[1] / "scripts/probe_downhill_posix.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


@unittest.skipUnless(os.name == "posix", "POSIX watchdog")
class WatchdogTests(unittest.TestCase):
    def test_timeout_keeps_output(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            result = probe.run_bounded([sys.executable, "-c", "import time; print('boot-marker', flush=True); time.sleep(10)"], path, 0.3, 1048576)
            self.assertEqual(result["termination"], "timeout")
            self.assertLess(result["elapsed_seconds"], 3)
            self.assertIn("boot-marker", (path / "first_boot_probe_latest.log").read_text())

    def test_real_exit_code_and_trace(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            result = probe.run_bounded([sys.executable, "-c", "from pathlib import Path; Path('ps2_log.txt').write_text('guest-entry'); raise SystemExit(7)"], path, 3, 1048576)
            self.assertEqual((result["termination"], result["exit_code"]), ("exited", 7))
            self.assertEqual(result["execution_stage"], "host-initialization")
            self.assertIn("guest-entry", (path / "first_boot_probe_latest.log").read_text())

    def test_excessive_logs_stop_process(self):
        with tempfile.TemporaryDirectory() as temp:
            result = probe.run_bounded([sys.executable, "-c", "import time; print('x'*1100000,flush=True); time.sleep(10)"], Path(temp), 3, 1048576)
            self.assertEqual(result["termination"], "log-limit")

    def test_guest_stage_and_native_signal(self):
        with tempfile.TemporaryDirectory() as temp:
            result = probe.run_bounded([sys.executable, "-c", "import os,signal; print('ELF file loaded successfully',flush=True); os.kill(os.getpid(),signal.SIGTERM)"], Path(temp), 3, 1048576)
            self.assertEqual(result["execution_stage"], "guest")
            self.assertEqual(result["process_signal"], 15)


if __name__ == "__main__":
    unittest.main()
