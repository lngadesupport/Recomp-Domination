"""Classify observed guest progress; host ticks never establish gameplay/FPS."""
import argparse
import json
from pathlib import Path
import re

ELF_SHA256 = "adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c"
WAIT_PC = 0x1B4648


def observations(text):
    waits, interrupts, malformed = [], [], 0
    for prefix, destination in [("[downhill:dma-wait]", waits), ("[dmac:irq]", interrupts)]:
        for match in re.finditer(re.escape(prefix) + r"([^\n]*)", text):
            try:
                fields = dict(part.split("=", 1) for part in match[1].split())
                if prefix == "[downhill:dma-wait]":
                    row = {key: int(fields[key], 0) for key in ("call", "pc", "ra", "chcr", "qwc", "tadr", "dstat", "cop0")}
                    row["flags"] = [int(value, 0) for value in fields["flags"].split(",")]
                    if len(row["flags"]) != 3: raise ValueError("flag count")
                    values = list(row.values())[:-1] + row["flags"]
                else:
                    row = {key: int(fields[key], 0) for key in ("call", "cause", "enabled", "handlers")}
                    if row["enabled"] not in (0, 1): raise ValueError("invalid mask")
                    values = row.values()
                if row["call"] < 1 or any(value < 0 or value > 0xFFFFFFFFFFFFFFFF for value in values):
                    raise ValueError("invalid counter/value")
                if any(value > 0xFFFFFFFF for key, value in row.items() if key not in ("call", "flags")):
                    raise ValueError("invalid guest word")
                if any(value > 0xFFFFFFFF for value in row.get("flags", [])):
                    raise ValueError("invalid guest flag")
                destination.append(row)
            except (KeyError, ValueError):
                malformed += 1
    tail = waits[-2:]
    stalled = len(tail) == 2 and all(
        row["pc"] == WAIT_PC and any(row["flags"]) and not row["chcr"] & 0x100 and row["qwc"] == 0
        for row in tail
    ) and tail[0]["flags"] == tail[1]["flags"] and tail[1]["call"] > tail[0]["call"]
    return {"wait_samples": len(waits), "irq_samples": len(interrupts), "malformed_samples": malformed,
            "last_wait": waits[-1] if waits else None,
            "masked_vif1_completions_observed": any(row["cause"] == 1 and row["enabled"] == 0 for row in interrupts),
            "vif1_queue_wait_observed": stalled,
            "limits": "Sampled observations do not establish cause, elapsed stall duration, a playable menu, or game FPS."}


def classify(probe, text):
    result = observations(text)
    identity = (probe.get("elf_sha256") == ELF_SHA256 and
                bool(re.fullmatch(r"[0-9a-f]{64}", str(probe.get("runner_sha256", "")))) and
                probe.get("runner_sha256") == probe.get("runner_sha256_after") and
                probe.get("runner_identity_verified") is True and
                probe.get("runner_changed_during_probe") is False)
    if not identity:
        status, reason = "failed", "unverified executable or ELF identity"
    elif probe.get("execution_stage") != "guest":
        status, reason = "blocked", "guest execution was not observed"
    elif probe.get("termination") not in ("timeout", "exited"):
        status, reason = "blocked", "probe did not finish with a supported observation bound"
    elif probe.get("termination") == "exited" and probe.get("exit_code") != 0:
        status, reason = "failed", "runner exited with an error or native signal"
    else:
        status, reason = "passed", "guest execution observed; gameplay remains unverified"
    result.update({"boot_status": status, "boot_reason": reason,
                   "menu_status": "blocked",
                   "menu_reason": "VIF1 queue wait observed" if result["vif1_queue_wait_observed"] else "no validated menu scenario/checkpoint",
                   "race_status": "blocked", "performance_status": "blocked"})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe", type=Path, help="Directory containing probe.json and runtime.log")
    args = parser.parse_args()
    print(json.dumps(classify(json.loads((args.probe / "probe.json").read_text()),
                              (args.probe / "runtime.log").read_text(errors="replace")), indent=2))


if __name__ == "__main__":
    main()
