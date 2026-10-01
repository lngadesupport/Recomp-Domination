import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "scripts/probe_downhill_posix.py"
spec = importlib.util.spec_from_file_location("probe", MODULE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


@unittest.skipUnless(os.name == "posix", "POSIX runner identity probe")
class ProbeIdentityTests(unittest.TestCase):
    def exercise(self, replace_runner):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            elf = root / "elf"
            elf.write_bytes(b"test fixture, never a retail ELF")
            runner = root / "runner"
            runner.write_text("#!/usr/bin/env python3\nfrom pathlib import Path\n"
                              "print('ELF file loaded successfully', flush=True)\n" +
                              ("Path(__file__).write_text('replacement')\n" if replace_runner else ""))
            runner.chmod(0o755)
            original = hashlib.sha256(runner.read_bytes()).hexdigest()
            out = root / "probe"
            argv = [str(MODULE), "--runner", str(runner), "--elf", str(elf), "--out", str(out), "--seconds", "3"]
            with patch.object(probe, "ELF_SHA256", hashlib.sha256(elf.read_bytes()).hexdigest()), patch.object(sys, "argv", argv):
                probe.main()
            report = json.loads((out / "probe.json").read_text())
            self.assertEqual(report["runner_sha256"], original)
            self.assertEqual(report["runner_sha256_after"], hashlib.sha256(runner.read_bytes()).hexdigest())
            self.assertEqual(report["runner_changed_during_probe"], replace_runner)
            self.assertEqual(report["runner_identity_verified"], not replace_runner)
            self.assertEqual(report["execution_stage"], "guest")

    def test_stable_runner(self):
        self.exercise(False)

    def test_child_replaces_its_executable(self):
        self.exercise(True)


if __name__ == "__main__":
    unittest.main()
