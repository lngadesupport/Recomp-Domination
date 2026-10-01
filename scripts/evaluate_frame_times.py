"""Evaluate unique guest-frame presentation intervals; never infer FPS from host ticks."""
import argparse
import csv
import json
import math
from pathlib import Path


def evaluate(rows, policy):
    target, stretch = policy["target_fps"], policy["stretch_fps"]
    minimum = policy["minimum_gameplay_sample_seconds"]
    if type(target) is not int or type(stretch) is not int or not 0 < target <= stretch:
        raise ValueError("invalid FPS policy")
    if not isinstance(minimum, (int, float)) or not math.isfinite(minimum) or minimum <= 0:
        raise ValueError("invalid sample duration")
    if policy.get("frame_time_source") != "unique_guest_frames_presented":
        raise ValueError("unsupported frame-time source")
    if policy.get("require_all_frame_intervals_within_budget") is not True:
        raise ValueError("constant-frame policy must check every interval")
    previous = None
    intervals = []
    context = None
    first_timestamp = last_timestamp = None
    dropped = 0
    for row in rows:
        timestamp, frame = int(row["present_ns"]), int(row["guest_frame_id"])
        current_context = (row["scenario"], row["phase"])
        if not current_context[0] or current_context[1] not in ("menu", "race"):
            raise ValueError("gameplay scenario and phase required")
        if not 0 <= timestamp < 2**64 or not 0 <= frame < 2**64:
            raise ValueError("timestamp/frame outside uint64")
        if context is not None and current_context != context:
            raise ValueError("one scenario/phase per trace required")
        context = current_context
        if previous:
            if timestamp <= previous[0] or frame <= previous[1]:
                raise ValueError("repeated/out-of-order presentation or guest frame")
            dropped += frame - previous[1] - 1
            intervals.append(timestamp - previous[0])
        else:
            first_timestamp = timestamp
        last_timestamp = timestamp
        previous = (timestamp, frame)
        if len(intervals) > 1000000: raise ValueError("trace exceeds one million intervals")
    if not intervals: raise ValueError("at least two unique guest frames required")
    elapsed = (last_timestamp - first_timestamp) / 1e9
    budget = (1000000000 + target - 1) // target
    stretch_budget = (1000000000 + stretch - 1) // stretch
    misses = sum(value > budget for value in intervals)
    stretch_misses = sum(value > stretch_budget for value in intervals)
    enough = elapsed >= minimum
    ordered = sorted(intervals)
    return {"scenario": context[0], "phase": context[1], "sample_seconds": elapsed,
            "unique_presented_frames": len(intervals) + 1, "dropped_guest_frames": dropped,
            "average_fps": len(intervals) / elapsed, "worst_frame_ms": max(intervals) / 1e6,
            "p99_frame_ms": ordered[math.ceil(len(ordered) * 0.99) - 1] / 1e6,
            "target_fps": target, "target_budget_ns": budget, "target_deadline_misses": misses,
            "stretch_fps": stretch, "stretch_deadline_misses": stretch_misses,
            "sample_duration_verified": enough,
            "target_passed": enough and misses == 0 and dropped == 0,
            "stretch_passed": enough and stretch_misses == 0 and dropped == 0,
            "whole_game_verified": False,
            "limits": "Evaluates provided frame telemetry for one scenario only. Producer correctness and complete gameplay coverage require independent validation."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="CSV: present_ns,guest_frame_id,scenario,phase")
    parser.add_argument("--policy", type=Path, default=Path(__file__).resolve().parent.parent / "config/validation_policy.json")
    args = parser.parse_args()
    with args.trace.open(newline="") as stream:
        result = evaluate(csv.DictReader(stream), json.loads(args.policy.read_text()))
    print(json.dumps(result, indent=2))
    return 0 if result["target_passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
