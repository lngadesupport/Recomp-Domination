import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from analyze_guest_progress import thread_observations


def snapshot(tick, status=5, running=0):
    return f"[boot-snapshot] host_tick={tick} running={running} thread=1:pc=0x1031210:ra=0x1031210:priority=0:status={status}:wait=0:wait_id=0\n"


class ThreadProgressTests(unittest.TestCase):
    def test_repeated_dormant_records(self):
        result = thread_observations(snapshot(3840) + snapshot(3960))
        self.assertTrue(result["repeated_all_dormant_snapshots"])
        self.assertEqual(result["last_thread_state"]["threads"][0]["pc"], 0x1031210)

    def test_ready_waiting_running_and_single_snapshot_are_not_dormancy(self):
        for status in range(5):
            self.assertFalse(thread_observations(snapshot(1) + snapshot(2, status))["repeated_all_dormant_snapshots"])
        self.assertFalse(thread_observations(snapshot(1))["repeated_all_dormant_snapshots"])
        self.assertFalse(thread_observations(snapshot(1) + snapshot(2, running=1))["repeated_all_dormant_snapshots"])

    def test_malformed_or_partial_state_is_not_accepted(self):
        result = thread_observations(snapshot(1) + snapshot(2).rstrip() + " thread=2:pc=oops\n")
        self.assertFalse(result["repeated_all_dormant_snapshots"])
        self.assertEqual(result["malformed_thread_snapshots"], 1)
        self.assertFalse(thread_observations(snapshot(1, status=99))["repeated_all_dormant_snapshots"])
        self.assertFalse(thread_observations(snapshot(1) + snapshot(2) + "[boot-snapshot] truncated\n")["repeated_all_dormant_snapshots"])

    def test_duplicate_or_reverse_ticks_do_not_establish_repetition(self):
        for tick in (1, 0):
            self.assertFalse(thread_observations(snapshot(1) + snapshot(tick))["repeated_all_dormant_snapshots"])


if __name__ == "__main__":
    unittest.main()
