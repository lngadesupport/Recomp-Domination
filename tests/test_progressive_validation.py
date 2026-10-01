import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import analyze_guest_progress as guest
import run_progressive_tests as progressive


def probe(**changes):
    result = dict(elf_sha256=guest.ELF_SHA256, runner_sha256="a" * 64,
                  runner_sha256_after="a" * 64, runner_identity_verified=True,
                  runner_changed_during_probe=False, execution_stage="guest",
                  termination="timeout", exit_code=-9)
    result.update(changes)
    return result


def wait(call=1, **changes):
    fields = dict(call=call, pc=guest.WAIT_PC, ra=0x1EBEEC, flags="0,3,1",
                  chcr=0x70000045, qwc=0, tadr=0x6202C0, dstat=7, cop0=0x10001)
    fields.update(changes)
    return "[downhill:dma-wait] " + " ".join(f"{key}={value}" for key, value in fields.items())


class ProgressGateTests(unittest.TestCase):
    def test_known_idle_channel_queue_wait_blocks_gameplay(self):
        text = wait(128) + "\n" + wait(256) + "\n[dmac:irq] call=128 cause=1 enabled=0 handlers=1"
        result = guest.classify(probe(), text)
        self.assertEqual(result["boot_status"], "passed")
        self.assertTrue(result["vif1_queue_wait_observed"])
        self.assertTrue(result["masked_vif1_completions_observed"])
        self.assertEqual(result["menu_status"], "blocked")
        self.assertEqual(result["performance_status"], "blocked")

    def test_busy_channel_changed_flags_and_reordered_samples_do_not_prove_stall(self):
        for text in (wait(1) + "\n" + wait(2, chcr=0x145),
                     wait(1) + "\n" + wait(2, flags="0,2,1"),
                     wait(2) + "\n" + wait(1), wait(1)):
            with self.subTest(text=text):
                self.assertFalse(guest.observations(text)["vif1_queue_wait_observed"])

    def test_host_clock_is_not_menu_or_game_fps_evidence(self):
        result = guest.classify(probe(), "[performance] host_hz=75\nMENU READY\n")
        self.assertEqual(result["menu_status"], "blocked")
        self.assertEqual(result["performance_status"], "blocked")

    def test_changed_runner_wrong_elf_and_unverified_identity_fail_gate(self):
        for changes in (dict(runner_sha256_after="b" * 64), dict(elf_sha256="0" * 64),
                        dict(runner_identity_verified=False), dict(runner_sha256="")):
            with self.subTest(changes=changes):
                self.assertEqual(guest.classify(probe(**changes), "")["boot_status"], "failed")

    def test_native_crash_differs_from_intentional_timeout(self):
        self.assertEqual(guest.classify(probe(termination="exited", exit_code=-11), "")["boot_status"], "failed")
        self.assertEqual(guest.classify(probe(), "")["boot_status"], "passed")
        self.assertEqual(guest.classify(probe(execution_stage="host-initialization"), "")["boot_status"], "blocked")

    def test_malformed_records_do_not_create_queue_evidence(self):
        for text in (wait(flags="0,3"), wait(flags="-1,3,1"), wait(chcr=2**32), wait(call=0)):
            with self.subTest(text=text):
                result = guest.observations(text)
                self.assertEqual(result["wait_samples"], 0)
                self.assertEqual(result["malformed_samples"], 1)

    def test_archived_retail_trace_reproduces_blocker(self):
        root = Path(__file__).parents[1] / "analysis/evidence/2026-10-01-vif1-queue"
        result = guest.classify(json.loads((root / "probe.json").read_text()), (root / "runtime.log").read_text())
        self.assertTrue(result["vif1_queue_wait_observed"])
        self.assertEqual(result["menu_status"], "blocked")


class GeneratedBatchTests(unittest.TestCase):
    def test_progression_partitions_case_ids_without_repetition(self):
        result = progressive.batches(1000000)
        self.assertEqual([row[2] for row in result], [1000, 9000, 990000])
        self.assertEqual(sum(row[2] for row in result), 1000000)
        for previous, following in zip(result, result[1:]):
            self.assertEqual(previous[1] + previous[2], following[1])

    def test_wrong_seed_range_and_family_totals_are_rejected(self):
        valid = dict(passed=1000, failed=0, seed=1, first_case=0, level=0, leaf_cases=500, iso_cases=500)
        self.assertTrue(progressive.validate_batch(valid, 1000, 1, 0, 0))
        for key in valid:
            invalid = dict(valid); invalid[key] += 1
            with self.subTest(key=key):
                self.assertFalse(progressive.validate_batch(invalid, 1000, 1, 0, 0))

    def test_budget_exhaustion_does_not_start_next_command(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            result = progressive.run_process(["this-command-must-not-start"], root, root / "log", 0)
            self.assertEqual(result["termination"], "budget-exhausted")
            self.assertTrue((root / "log").is_file())

    def test_watchdog_stops_hung_stage(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            result = progressive.run_process([sys.executable, "-c", "import time; time.sleep(30)"], root, root / "log", 0.15)
            self.assertEqual(result["termination"], "timeout")
            self.assertLess(result["elapsed_seconds"], 5)


if __name__ == "__main__":
    unittest.main()
