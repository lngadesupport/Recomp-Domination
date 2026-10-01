import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from evaluate_frame_times import evaluate

POLICY = json.loads((ROOT / "config/validation_policy.json").read_text())


def frames(interval=16666667, count=3602):
    return [dict(present_ns=i * interval, guest_frame_id=i, scenario="diagnostic-fixture", phase="race")
            for i in range(count)]


class FrameTimeGateTests(unittest.TestCase):
    def test_sixty_passes_without_claiming_seventy_five_or_whole_game(self):
        result = evaluate(frames(), POLICY)
        self.assertTrue(result["target_passed"])
        self.assertFalse(result["stretch_passed"])
        self.assertFalse(result["whole_game_verified"])

    def test_seventy_five_requires_unique_frames_within_smaller_budget(self):
        result = evaluate(frames(13333334, 4502), POLICY)
        self.assertTrue(result["target_passed"])
        self.assertTrue(result["stretch_passed"])

    def test_one_spike_fails_even_when_average_is_near_sixty(self):
        rows = frames()
        for row in rows[1800:]: row["present_ns"] += 1000000
        result = evaluate(rows, POLICY)
        self.assertGreater(result["average_fps"], 59)
        self.assertFalse(result["target_passed"])
        self.assertEqual(result["target_deadline_misses"], 1)

    def test_short_sample_does_not_validate_constant_fps(self):
        result = evaluate(frames(count=100), POLICY)
        self.assertFalse(result["sample_duration_verified"])
        self.assertFalse(result["target_passed"])

    def test_dropped_guest_frame_cannot_pass_through_regular_host_presentation(self):
        rows = frames()
        for row in rows[1000:]: row["guest_frame_id"] += 1
        result = evaluate(rows, POLICY)
        self.assertEqual(result["dropped_guest_frames"], 1)
        self.assertFalse(result["target_passed"])

    def test_duplicated_frames_invalid_timestamps_and_context_changes_are_rejected(self):
        for field, value in (("guest_frame_id", 0), ("present_ns", 0),
                             ("present_ns", -1), ("phase", "host-clock"), ("scenario", "different")):
            with self.subTest(field=field):
                rows = frames(count=3); rows[1][field] = value
                with self.assertRaises(ValueError): evaluate(rows, POLICY)

    def test_host_tick_csv_does_not_satisfy_frame_telemetry_schema(self):
        with self.assertRaises(KeyError):
            evaluate([dict(host_tick=1, host_hz=75)], POLICY)


if __name__ == "__main__":
    unittest.main()
