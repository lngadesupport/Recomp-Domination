#!/usr/bin/env python3
"""Run increasing, bounded POSIX game probes; never infer gameplay FPS from host ticks."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time

from analyze_guest_progress import classify
from probe_downhill_posix import ELF_SHA256, run_bounded


def digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as source:
        while chunk := source.read(1048576):
            result.update(chunk)
    return result.hexdigest()


def next_duration(schedule, index, remaining):
    if not schedule or any(not math.isfinite(x) or x <= 0 for x in schedule):
        raise ValueError("Probe durations must be finite and positive")
    if not math.isfinite(remaining):
        raise ValueError("Remaining budget must be finite")
    if index < 0:
        raise ValueError("Probe index must not be negative")
    return max(0.0, min(schedule[min(index, len(schedule) - 1)], remaining))


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def capture_frames(output, display, seconds, stop):
    from PIL import ImageGrab
    started = time.monotonic()
    for deadline in sorted({10.0, seconds / 2, max(0.0, seconds - 5)}):
        if deadline >= seconds or stop.wait(max(0, deadline - (time.monotonic() - started))):
            return
        try:
            ImageGrab.grab(xdisplay=display).save(output / f"frame-{deadline:g}.png")
        except Exception as error:
            (output / "capture-error.txt").write_text(str(error))


def execute_probe(runner, elf, root, iso, output, seconds, max_log_bytes,
                  expected_runner, display=None):
    if digest(runner) != expected_runner:
        raise ValueError("Runner changed before launch; refusing to continue")
    output.mkdir(parents=True, exist_ok=False)
    staged_elf = output / elf.name
    shutil.copy2(elf, staged_elf)
    if digest(staged_elf) != ELF_SHA256:
        raise ValueError("Staged ELF identity mismatch")
    # Runtime discovers these paths beside the ELF, not beside the executable.
    (output / "downhill_cd_root.txt").write_text(str(root))
    (output / "downhill_cd_image.txt").write_text(str(iso))
    stop = threading.Event()
    capture = None
    if display:
        capture = threading.Thread(target=capture_frames, args=(output, display, seconds, stop), daemon=True)
        capture.start()
    try:
        result = run_bounded([str(runner), str(staged_elf)], output, seconds, max_log_bytes)
    finally:
        stop.set()
        if capture:
            capture.join(timeout=10)
            if capture.is_alive():
                (output / "capture-error.txt").write_text("Capture thread exceeded cleanup limit")
    after = digest(runner)
    result.update(elf_sha256=ELF_SHA256, runner_sha256=expected_runner,
                  runner_sha256_after=after, runner_identity_verified=after == expected_runner,
                  runner_changed_during_probe=after != expected_runner,
                  host="posix", windows_boot_verified=False)
    write_json(output / "probe.json", result)
    text = (output / "runtime.log").read_text(errors="replace")
    progress = classify(result, text)
    progress["sprite_records"] = text.count("[gs:sprite]")
    progress["palette_texel_records"] = text.count("[gs:palette-texel]")
    progress["last_thread_snapshot"] = next((line for line in reversed(text.splitlines()) if "[boot-snapshot]" in line), None)
    write_json(output / "guest_progress.json", progress)
    return result, progress


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("runner", "elf", "root", "iso", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--budget-seconds", type=float, default=7500)
    parser.add_argument("--expected-runner-sha256", required=True,
                        help="Hash retained from the successful build/checkpoint, not a fresh hash of an unverified copy")
    parser.add_argument("--probe-seconds", type=float, nargs="+", default=[60, 120, 240, 480, 600])
    parser.add_argument("--max-log-bytes", type=int, default=33554432)
    parser.add_argument("--max-probes", type=int, default=32)
    parser.add_argument("--auto-intro-skip", action="store_true")
    parser.add_argument("--xvfb", type=Path)
    parser.add_argument("--display", default="127.0.0.1:99")
    parser.add_argument("--captures", action="store_true")
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("This runner uses POSIX process groups; use the Windows probe scripts on Windows")
    if not re.fullmatch(r"[0-9a-f]{64}", args.expected_runner_sha256):
        parser.error("Expected runner hash must contain 64 lowercase hexadecimal characters")
    if not math.isfinite(args.budget_seconds) or args.budget_seconds <= 0:
        parser.error("Budget must be finite and positive")
    next_duration(args.probe_seconds, 0, args.budget_seconds)
    if args.max_log_bytes < 1048576:
        parser.error("Log bound must be at least 1 MiB")
    if args.max_probes < 1:
        parser.error("Maximum probe count must be positive")
    if args.xvfb and not re.fullmatch(r"127\.0\.0\.1:[0-9]+", args.display):
        parser.error("An owned Xvfb requires a local display such as 127.0.0.1:99")
    runner, elf, root, iso, output = [getattr(args, key).resolve() for key in ("runner", "elf", "root", "iso", "out")]
    if not runner.is_file() or not os.access(runner, os.X_OK) or digest(elf) != ELF_SHA256:
        parser.error("Executable runner and verified retail ELF required")
    if not root.is_dir() or not iso.is_file():
        parser.error("Existing extracted disc root and matching diagnostic ISO required")
    expected = digest(runner)
    if expected != args.expected_runner_sha256:
        parser.error("Runner does not match the retained build identity")
    output.mkdir(parents=True, exist_ok=False)
    plan = {"runner": str(runner), "runner_sha256": expected, "elf_sha256": ELF_SHA256,
            "harness_sha256": digest(Path(__file__).resolve()),
            "budget_seconds": args.budget_seconds, "probe_seconds": args.probe_seconds,
            "auto_intro_skip": args.auto_intro_skip, "root": str(root), "iso": str(iso),
            "max_log_bytes_per_probe": args.max_log_bytes,
            "max_probes": args.max_probes,
            "limits": "Fixed configuration; no automatic code changes, menu certification, or game FPS inference."}
    write_json(output / "plan.json", plan)
    os.environ.update(DISPLAY=args.display, PS2_DOWNHILL_AUTO_SKIP_INTRO="1" if args.auto_intro_skip else "0",
                      PS2_TRACE_BOOT_SNAPSHOT="1", PS2_TRACE_PERFORMANCE="1", PS2_TRACE_GS_PIPELINE="1",
                      PS2_TRACE_GS_TEXTURES="1", PS2_DOWNHILL_IDLE_VSYNC="1", PS2_DOWNHILL_CD_READ_YIELD="1")
    server = None
    state = {"status": "running", "runs": [], "gameplay_verified": False, "game_fps_verified": False}
    started = time.monotonic()
    try:
        if args.xvfb:
            with (output / "xvfb.log").open("wb") as log:
                server = subprocess.Popen([str(args.xvfb.resolve()), ":" + args.display.rsplit(":", 1)[1], "-screen", "0", "1024x768x24",
                                           "-listen", "tcp", "-nolisten", "unix", "-ac"], stdout=log, stderr=subprocess.STDOUT)
            time.sleep(2)
            if server.poll() is not None:
                raise RuntimeError("Xvfb exited before the first probe")
        write_json(output / "summary.json", state)
        while True:
            if len(state["runs"]) >= args.max_probes:
                state["status"] = "probe-limit"
                break
            duration = next_duration(args.probe_seconds, len(state["runs"]), args.budget_seconds - (time.monotonic() - started))
            if duration <= 0:
                state["status"] = "budget-complete"
                break
            run_output = output / f"run-{len(state['runs']) + 1:03}"
            result, progress = execute_probe(runner, elf, root, iso, run_output, duration, args.max_log_bytes,
                                             expected, args.display if args.captures else None)
            state["runs"].append({"directory": run_output.name, "probe": result, "progress": progress})
            state["elapsed_seconds"] = round(time.monotonic() - started, 3)
            write_json(output / "summary.json", state)
            print(json.dumps({"run": run_output.name, "seconds": result["elapsed_seconds"],
                              "boot_status": progress["boot_status"], "sprite_records": progress["sprite_records"]}), flush=True)
            if progress["boot_status"] != "passed":
                state["status"] = "stopped-on-failure"
                break
    except BaseException as error:
        state.update(status="interrupted" if isinstance(error, KeyboardInterrupt) else "failed", error=str(error))
        raise
    finally:
        state["elapsed_seconds"] = round(time.monotonic() - started, 3)
        write_json(output / "summary.json", state)
        if server:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)


if __name__ == "__main__":
    main()
