#!/usr/bin/env python3
"""Bound a native POSIX retail probe and reuse the existing PowerShell triage."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ELF_SHA256 = "adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c"


def run_bounded(command, directory, seconds, max_log_bytes):
    if seconds <= 0 or max_log_bytes < 1048576:
        raise ValueError("Positive timeout and at least 1 MiB log limit required")
    directory.mkdir(parents=True, exist_ok=True)
    output = directory / "runtime.log"
    trace = directory / "ps2_log.txt"
    # An isolated directory prevents stale traces from earlier probes.
    if output.exists() or trace.exists():
        raise ValueError("Probe directory already contains logs; choose a fresh directory")
    started = time.monotonic()
    reason = "exited"
    with output.open("wb") as stream:
        process = subprocess.Popen(command, cwd=directory, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                total = sum(p.stat().st_size for p in (output, trace) if p.exists())
                if total >= max_log_bytes:
                    reason = "log-limit"
                    break
                if time.monotonic() - started >= seconds:
                    reason = "timeout"
                    break
                time.sleep(0.05)
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.wait(timeout=5)
    result = {"termination": reason, "exit_code": process.returncode,
              "process_signal": -process.returncode if process.returncode < 0 else None,
              "elapsed_seconds": round(time.monotonic() - started, 3),
              "timeout_seconds": seconds, "max_log_bytes": max_log_bytes}
    guest_started = False
    with output.open("rb") as stream:
        previous = b""
        while chunk := stream.read(65536):
            if b"ELF file loaded successfully" in previous + chunk:
                guest_started = True
                break
            previous = chunk[-64:]
    result["execution_stage"] = "guest" if guest_started else "host-initialization"
    combined = directory / "first_boot_probe_latest.log"
    with combined.open("wb") as target:
        for path in (output, trace):
            target.write(f"\n=== {path.name} ===\n".encode())
            if path.exists():
                with path.open("rb") as source:
                    size = path.stat().st_size
                    if size > max_log_bytes:
                        target.write(b"[earlier output truncated]\n")
                        source.seek(-max_log_bytes, os.SEEK_END)
                    while chunk := source.read(65536):
                        target.write(chunk)
    (directory / "probe.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, required=True)
    parser.add_argument("--elf", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--max-log-bytes", type=int, default=33554432)
    parser.add_argument("--pwsh", type=Path)
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("Use RUN_DOWNHILL_PROBE.cmd on Windows")
    runner, elf, output = args.runner.resolve(), args.elf.resolve(), args.out.resolve()
    if hashlib.sha256(elf.read_bytes()).hexdigest() != ELF_SHA256:
        parser.error("Retail ELF identity mismatch")
    runner_before = hashlib.sha256(runner.read_bytes()).hexdigest()
    result = run_bounded([str(runner), str(elf)], output, args.seconds, args.max_log_bytes)
    runner_after = hashlib.sha256(runner.read_bytes()).hexdigest()
    result.update({"elf_sha256": ELF_SHA256, "runner_sha256": runner_before,
                   "runner_sha256_after": runner_after, "runner_changed_during_probe": runner_before != runner_after,
                   "runner_identity_verified": runner_before == runner_after,
                   "host": "posix", "windows_boot_verified": False})
    (output / "probe.json").write_text(json.dumps(result, indent=2) + "\n")
    # A native signal can leave no exception text. Preserve it for the shared
    # triage instead of reporting a clean log for a crashed process.
    if result["termination"] == "exited" and result["process_signal"] is not None:
        with (output / "first_boot_probe_latest.log").open("a") as log:
            log.write(f"\n[host-probe] fatal process signal={result['process_signal']} stage={result['execution_stage']}\n")
    if args.pwsh:
        scripts = Path(__file__).resolve().parent
        for name, report, extra in [
            ("triage_first_boot.ps1", "first_boot_triage.json", []),
            ("suggest_bringup_fixes.ps1", "first_boot_suggestions.json", [])
        ]:
            try:
                completed = subprocess.run([str(args.pwsh.resolve()), "-NoLogo", "-NoProfile", "-File",
                                            str(scripts / name), "-Log", str(output / "first_boot_probe_latest.log"),
                                            "-Out", str(output / report), *extra], timeout=30)
                result[name] = completed.returncode
            except subprocess.TimeoutExpired:
                result[name] = "timed-out"
    (output / "probe.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
