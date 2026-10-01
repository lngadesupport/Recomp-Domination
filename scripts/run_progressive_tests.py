#!/usr/bin/env python3
"""Run bounded, reproducible component batches, then gated retail observations."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

from analyze_guest_progress import classify, ELF_SHA256

REPO = Path(__file__).resolve().parent.parent
PIN = "75d729ce40d7eed9649fd4bb05628dee520f3d0c"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1048576): value.update(chunk)
    return value.hexdigest()


def batches(total):
    if not 10000 <= total <= 10000000:
        raise ValueError("cases must be between 10,000 and 10,000,000")
    result = [("generated-smoke", 0, 1000, 0), ("generated-expanded", 1000, 9000, 1)]
    if total > 10000: result.append(("generated-stress", 10000, total - 10000, 2))
    return result


def validate_batch(result, count, seed, first, level):
    expected = {"passed": count, "failed": 0, "seed": seed, "first_case": first, "level": level,
                "leaf_cases": (first + count + 1) // 2 - (first + 1) // 2,
                "iso_cases": (first + count) // 2 - first // 2}
    return all(type(result.get(key)) is int and result[key] == value for key, value in expected.items())


def terminate(process):
    if os.name == "posix":
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    elif process.poll() is None:
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        if process.poll() is None: process.kill()
    process.wait(timeout=10)


def run_process(command, cwd, log, seconds, env=None, monitored=()):
    if seconds <= 0:
        log.touch()
        return {"termination": "budget-exhausted", "exit_code": None, "elapsed_seconds": 0}
    started = time.monotonic()
    reason = "exited"
    options = {"start_new_session": True} if os.name == "posix" else {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
    with log.open("wb") as stream:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                   stdout=stream, stderr=subprocess.STDOUT, **options)
        try:
            while process.poll() is None:
                size = sum(path.stat().st_size for path in (log, *monitored) if path.is_file())
                if size >= 33554432: reason = "log-limit"; break
                if time.monotonic() - started >= seconds: reason = "timeout"; break
                time.sleep(0.05)
        finally:
            if process.poll() is None: terminate(process)
            else: process.wait()
    return {"termination": reason, "exit_code": process.returncode,
            "elapsed_seconds": round(time.monotonic() - started, 3), "timeout_seconds": seconds}


def save(report, output):
    temporary = output / "progress.json.tmp"
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary.replace(output / "progress.json")


def execute(args):
    output = args.out.resolve()
    if output.exists(): raise ValueError("Choose a fresh output directory; previous results are not overwritten")
    output.mkdir(parents=True)
    policy = json.loads((REPO / "config/validation_policy.json").read_text())
    report = {"schema_version": 1, "seed": args.seed, "requested_generated_cases": args.cases,
              "generated_cases_passed": 0, "regression_tests_passed": 0, "stages": [],
              "policy": policy, "scope": "components-only" if args.components_only else "components-and-gated-retail",
              "menu_verified": False, "race_verified": False, "target_fps_verified": False,
              "stretch_fps_verified": False, "status": "running"}
    started = time.monotonic()
    save(report, output)

    def remaining(limit): return min(limit, max(0, args.budget_seconds - (time.monotonic() - started)))
    def record(name, status, **details):
        row = {"stage": name, "status": status, **details}
        report["stages"].append(row); save(report, output)
        print(json.dumps(row), flush=True)
    def finish(status):
        report["status"] = status
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        save(report, output)
        return 0 if status == "passed" else (1 if status == "failed" else 2)

    try:
        log = output / "python-regressions.log"
        run = run_process([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
                          REPO, log, remaining(180))
        if run["termination"] != "exited" or run["exit_code"] != 0:
            record("python-regressions", "failed" if run["termination"] == "exited" else "blocked", **run)
            return finish(report["stages"][-1]["status"])
        matches = re.findall(r"Ran (\d+) tests?", log.read_text(errors="replace"))
        if not matches: raise ValueError("Regression runner returned no verified test count")
        report["regression_tests_passed"] = int(matches[-1])
        record("python-regressions", "passed", tests=report["regression_tests_passed"], **run)

        source = args.source.resolve()
        pin = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        if pin != PIN: raise ValueError("Runtime upstream pin mismatch")
        log = output / "apply-patches.log"
        run = run_process([sys.executable, str(REPO / "scripts/apply_runtime_bringup_patches.py"), str(source)],
                          REPO, log, remaining(60))
        if run["termination"] != "exited" or run["exit_code"] != 0:
            record("runtime-patches", "failed", **run); return finish("failed")

        includes = [REPO / "src", source / "ps2xRuntime/include", source / "ps2xIOP/include"]
        native = output / ("generated-cases.exe" if os.name == "nt" else "generated-cases")
        compiler = shutil.which(args.compiler or ("cl" if os.name == "nt" else "g++"))
        if not compiler:
            record("native-build", "blocked", reason="C++ compiler unavailable")
            return finish("blocked")
        compiler = str(Path(compiler).resolve())
        cpp = REPO / "tests/downhill_generated_cases.cpp"
        if Path(compiler).stem.lower() == "cl":
            if args.sanitize: raise ValueError("The sanitizer option currently supports GCC/Clang builds")
            command = [compiler, "/nologo", "/std:c++20", "/EHsc", "/arch:AVX2", "/O2"]
            command += ["/I" + str(path) for path in includes] + [str(cpp), "/Fe" + str(native), "/Fo" + str(output / "generated-cases.obj")]
        else:
            command = [compiler, "-std=c++20", "-mavx2", "-O1" if args.sanitize else "-O2"]
            if args.sanitize: command += ["-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
            command += ["-I" + str(path) for path in includes] + [str(cpp), "-o", str(native)]
        run = run_process(command, output, output / "native-build.log", remaining(180))
        if run["termination"] != "exited" or run["exit_code"] != 0:
            record("native-build", "failed" if run["termination"] == "exited" else "blocked", **run)
            return finish(report["stages"][-1]["status"])
        report["native_sha256"] = digest(native)
        native_env = os.environ.copy()
        if args.sanitize:
            # LSan cannot enumerate tasks in some managed execution environments.
            # This mode promises ASan/UBSan checks, not leak detection.
            native_env["ASAN_OPTIONS"] = native_env.get("ASAN_OPTIONS", "") + ":detect_leaks=0"
            native_env["UBSAN_OPTIONS"] = native_env.get("UBSAN_OPTIONS", "") + ":halt_on_error=1"
        report["sanitizers"] = ["address", "undefined"] if args.sanitize else []
        report["leak_detection"] = False
        report["replay_environment"] = {"ASAN_OPTIONS": "detect_leaks=0", "UBSAN_OPTIONS": "halt_on_error=1"} if args.sanitize else {}
        hashed = [cpp, REPO / "src/downhill_leaf_handler.h", REPO / "config/validation_policy.json",
                  source / "ps2xIOP/include/ps2x/iop/cdvd_iso_lookup.h", source / "ps2xRuntime/include/ps2_runtime.h"]
        report["source_sha256"] = {str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path): digest(path) for path in hashed}
        report["upstream_pin"] = pin
        record("native-build", "passed", compiler=compiler, sanitized=args.sanitize, **run)

        for name, first, count, level in batches(args.cases):
            log = output / (name + ".log")
            command = [str(native), str(count), str(args.seed), str(first), str(level)]
            run = run_process(command, output, log, remaining(180), native_env)
            result = None
            for line in log.read_text(errors="replace").splitlines():
                if line.startswith("{"):
                    try: result = json.loads(line)
                    except json.JSONDecodeError: pass
            valid = (isinstance(result, dict) and validate_batch(result, count, args.seed, first, level)
                     and digest(native) == report["native_sha256"])
            passed = run["termination"] == "exited" and run["exit_code"] == 0 and valid
            status = "passed" if passed else ("blocked" if run["termination"] != "exited" else "failed")
            if passed: report["generated_cases_passed"] += count
            record(name, status, first_case=first, requested_cases=count, level=level,
                   native_result=result, replay_command=command, **run)
            if not passed: return finish(status)
        if args.components_only: return finish("passed")

        if args.historical_probe:
            probe_dir = args.historical_probe.resolve()
            probe = json.loads((probe_dir / "probe.json").read_text())
            text = (probe_dir / "runtime.log").read_text(errors="replace")
            report["retail_evidence_mode"] = "historical-observation-only"
            report["retail_evidence_sha256"] = {name: digest(probe_dir / name) for name in ("probe.json", "runtime.log")}
        elif args.runner and args.elf and args.cd_root and args.cd_image:
            runner, elf = args.runner.resolve(), args.elf.resolve()
            if digest(elf) != ELF_SHA256: raise ValueError("Retail ELF identity mismatch")
            if not args.cd_root.is_dir() or not args.cd_image.is_file(): raise ValueError("Disc root/image unavailable")
            probe_dir = output / "retail-probe"; probe_dir.mkdir()
            copied_runner = probe_dir / runner.name; shutil.copy2(runner, copied_runner)
            for dll in runner.parent.glob("*.dll"): shutil.copy2(dll, probe_dir / dll.name)
            copied_elf = probe_dir / elf.name; shutil.copy2(elf, copied_elf)
            (probe_dir / "downhill_cd_root.txt").write_text(str(args.cd_root.resolve()) + "\n")
            (probe_dir / "downhill_cd_image.txt").write_text(str(args.cd_image.resolve()) + "\n")
            env = os.environ.copy()
            env.update(PS2_TRACE_DMAC_IRQ="1", PS2_TRACE_RESOURCE_COPY="1", PS2_TRACE_BOOT_SNAPSHOT="1")
            env.pop("PS2_DOWNHILL_IDLE_VSYNC", None)
            env.pop("PS2_DOWNHILL_CD_READ_YIELD", None)
            if args.experimental_boot:
                env.update(PS2_DOWNHILL_IDLE_VSYNC="1", PS2_DOWNHILL_CD_READ_YIELD="1")
            log = probe_dir / "runtime.log"
            before = digest(copied_runner)
            probe = run_process([str(copied_runner), str(copied_elf)], probe_dir, log,
                                remaining(args.probe_seconds), env, (probe_dir / "ps2_log.txt",))
            text = log.read_text(errors="replace")
            after = digest(copied_runner)
            probe.update(elf_sha256=digest(copied_elf), runner_sha256=before, runner_sha256_after=after,
                         runner_changed_during_probe=before != after, runner_identity_verified=before == after,
                         execution_stage="guest" if "ELF file loaded successfully" in text else "host-initialization")
            (probe_dir / "probe.json").write_text(json.dumps(probe, indent=2) + "\n")
            report["retail_evidence_mode"] = "fresh-bounded-probe"
            report["experimental_boot"] = args.experimental_boot
        else:
            record("retail-boot", "blocked", reason="Runner, ELF and disc root/image must be configured for a fresh boot")
            return finish("blocked")
        progress = classify(probe, text)
        report["guest_observations"] = progress
        record("retail-boot", progress["boot_status"], reason=progress["boot_reason"],
               evidence_mode=report["retail_evidence_mode"])
        if progress["boot_status"] != "passed": return finish(progress["boot_status"])
        record("menu", "blocked", reason=progress["menu_reason"])
        record("race", "blocked", reason="Requires validated menu flow and scenario inventory")
        record("performance", "blocked", reason="Requires completed gameplay scenarios and unique guest-frame telemetry")
        return finish("blocked")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record("infrastructure", "failed", reason=str(error))
        return finish("failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=REPO / "third_party/PS2Recomp")
    parser.add_argument("--cases", type=int, default=100000)
    parser.add_argument("--seed", type=lambda text: int(text, 0), default=0xD0A11)
    parser.add_argument("--budget-seconds", type=float, default=600)
    parser.add_argument("--compiler")
    parser.add_argument("--sanitize", action="store_true")
    parser.add_argument("--components-only", action="store_true")
    parser.add_argument("--historical-probe", type=Path)
    parser.add_argument("--runner", type=Path)
    parser.add_argument("--elf", type=Path)
    parser.add_argument("--cd-root", type=Path)
    parser.add_argument("--cd-image", type=Path)
    parser.add_argument("--probe-seconds", type=float, default=240)
    parser.add_argument("--experimental-boot", action="store_true")
    args = parser.parse_args()
    try: batches(args.cases)
    except ValueError as error: parser.error(str(error))
    if not 0 <= args.seed < 2**64: parser.error("seed must fit uint64")
    if not all(math.isfinite(value) and value > 0 for value in (args.budget_seconds, args.probe_seconds)):
        parser.error("positive finite time budgets required")
    if args.historical_probe and args.runner: parser.error("Choose historical evidence or a fresh runner")
    if args.components_only and (args.historical_probe or args.runner): parser.error("Component-only mode does not run retail stages")
    try: return execute(args)
    except ValueError as error: parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
