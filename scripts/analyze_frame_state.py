#!/usr/bin/env python3
"""Summarize sampled executor observations without inferring game mode or FPS."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
FIELDS = re.compile(r"([a-z_]+)=([^ ]+)")

def analyze(text):
    records, malformed, numeric = [], 0, []
    for line in text.splitlines():
        if "[downhill:frame-state]" in line:
            try:
                f = dict(FIELDS.findall(line))
                r = {k: int(f[k], 10) for k in ("call", "vsync", "numeric_calls")}
                r.update({k: int(f[k], 16) for k in ("entry_pc", "caller", "frame", "exit_pc", "exit_sp")})
                for k in ("stack", "gpr"):
                    r[k] = [int(x, 16) for x in f[k].rstrip(",").split(",")]
                    if len(r[k]) != 32 or any(not 0 <= x <= 0xffffffff for x in r[k]):
                        raise ValueError("Expected 32 low-word observations")
                if any(r[k] < 0 for k in ("call", "vsync", "numeric_calls")):
                    raise ValueError("Negative counter")
                records.append(r)
            except (KeyError, ValueError):
                malformed += 1
        if "[downhill:resource-return]" in line and "routine=0x177da0 " in line:
            numeric.append(line)
    callers = Counter(f"0x{x['caller']:x}" for x in records)
    return {"frame_state_records": len(records), "malformed_frame_records": malformed,
            "observed_callers": dict(sorted(callers.items())),
            "maximum_numeric_wrapper_calls": max((x["numeric_calls"] for x in records), default=0),
            "numeric_return_records": len(numeric), "numeric_observed": bool(numeric) or any(x["numeric_calls"] for x in records),
            "last_frame_state": records[-1] if records else None,
            "limits": "Wrapper invocations include resumes. Sampled callers and counters do not certify game mode, complete execution coverage, gameplay, stall duration or FPS."}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--log", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()
    data = args.log.read_bytes()
    result = analyze(data.decode("utf-8", errors="replace"))
    result["runtime_log_sha256"] = hashlib.sha256(data).hexdigest()
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))

if __name__ == "__main__": main()
