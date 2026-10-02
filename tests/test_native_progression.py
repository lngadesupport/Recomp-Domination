import hashlib
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_native_progression as progression


class ProgressionTests(unittest.TestCase):
    def test_schedule_repeats_last_duration_and_obeys_remaining_budget(self):
        schedule = [60, 120, 240]
        self.assertEqual([progression.next_duration(schedule, i, 1000) for i in range(5)], [60, 120, 240, 240, 240])
        self.assertEqual(progression.next_duration(schedule, 3, 17.5), 17.5)
        self.assertEqual(progression.next_duration(schedule, 0, -1), 0)

    def test_invalid_bounds_are_rejected(self):
        for schedule in ([], [0], [-1], [float("inf")], [float("nan")]):
            with self.assertRaises(ValueError):
                progression.next_duration(schedule, 0, 100)
        for remaining in (float("inf"), float("nan")):
            with self.assertRaises(ValueError):
                progression.next_duration([1], 0, remaining)
        with self.assertRaises(ValueError):
            progression.next_duration([1], -1, 100)

    def test_runner_change_is_rejected_before_staging_or_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = root / "runner"
            runner.write_bytes(b"changed")
            output = root / "probe"
            with patch.object(progression, "run_bounded") as launch:
                with self.assertRaises(ValueError):
                    progression.execute_probe(runner, root / "elf", root, root / "disc", output, 1, 1048576, "0" * 64)
                launch.assert_not_called()
            self.assertFalse(output.exists())

    def test_failed_launch_stops_capture_thread(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner, elf = root / "runner", root / "elf"
            runner.write_bytes(b"runner"); elf.write_bytes(b"elf")
            stopped = threading.Event()
            def capture(output, display, seconds, stop):
                if stop.wait(1):
                    stopped.set()
            with patch.object(progression, "ELF_SHA256", hashlib.sha256(b"elf").hexdigest()), \
                 patch.object(progression, "capture_frames", capture), \
                 patch.object(progression, "run_bounded", side_effect=PermissionError("launch failed")):
                with self.assertRaises(PermissionError):
                    progression.execute_probe(runner, elf, root, root / "disc", root / "probe", 1, 1048576, progression.digest(runner), "display")
            self.assertTrue(stopped.is_set())

    def test_changed_runner_after_probe_is_not_certified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner, elf = root / "runner", root / "elf"
            runner.write_bytes(b"before"); elf.write_bytes(b"elf")
            def probe(command, output, seconds, bound):
                runner.write_bytes(b"after")
                (output / "runtime.log").write_text("ELF file loaded successfully\n[gs:sprite] observed\n")
                return {"execution_stage": "guest", "termination": "timeout", "exit_code": -9}
            with patch.object(progression, "ELF_SHA256", hashlib.sha256(b"elf").hexdigest()), \
                 patch.object(progression, "run_bounded", probe):
                result, progress = progression.execute_probe(runner, elf, root, root / "disc", root / "probe", 1, 1048576, progression.digest(runner))
            self.assertFalse(result["runner_identity_verified"])
            self.assertEqual(progress["boot_status"], "failed")
            self.assertEqual(progress["performance_status"], "blocked")
            self.assertEqual(progress["sprite_records"], 1)
            self.assertTrue((root / "probe/downhill_cd_root.txt").exists())
            self.assertEqual(json.loads((root / "probe/probe.json").read_text()), result)


if __name__ == "__main__":
    unittest.main()
