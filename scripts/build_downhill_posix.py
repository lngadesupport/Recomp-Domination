#!/usr/bin/env python3
"""Stage verified retail C++ and build a diagnostic Linux runner (not Windows)."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zlib

PIN = "75d729ce40d7eed9649fd4bb05628dee520f3d0c"
ELF_SHA256 = "adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c"


def copy_if_changed(source, destination):
    if not destination.exists() or source.read_bytes() != destination.read_bytes():
        shutil.copy2(source, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--elf", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--raylib-source", type=Path)
    parser.add_argument("--prefix", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    source, generated, build = args.source.resolve(), args.generated.resolve(), args.build.resolve()
    elf = args.elf.resolve().read_bytes()
    if hashlib.sha256(elf).hexdigest() != ELF_SHA256:
        raise ValueError("Retail ELF identity mismatch")
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != PIN:
        raise ValueError("PS2Recomp revision mismatch")
    report = json.loads((generated.parent / "generation_report.json").read_text())
    if not report.get("generation_verified") or report.get("elf_sha256") != ELF_SHA256 or report.get("ps2recomp_commit") != PIN:
        raise ValueError("Verified retail generation report required")
    repo = Path(__file__).resolve().parent.parent
    patch = (repo / "scripts/patch_downhill_ps2recomp.ps1").read_text()
    # Reuse exact replacements from the canonical Windows patch script.
    blocks = dict(re.findall(r"\$(\w+) = @'\n(.*?)\n'@", patch, re.S))
    changes = [
        ("ps2xRuntime/src/lib/ps2_memory.cpp", [("memoryOld", "memoryNew")]),
        ("ps2xTest/src/ps2_memory_tests.cpp", [("setupOld", "setupNew"), ("assertOld", "assertNew")]),
        ("ps2xRuntime/src/lib/Kernel/Syscalls/FileIO.cpp", [("fileIoOld", "fileIoNew")]),
    ]
    planned = []
    for relative, pairs in changes:
        path = source / relative
        text = path.read_text()
        for old, new in pairs:
            if blocks[new] in text:
                continue
            if text.count(blocks[old]) != 1:
                raise ValueError(f"Pinned compatibility patch mismatch: {relative}")
            text = text.replace(blocks[old], blocks[new])
        planned.append((path, text))
    for path, text in planned:
        path.write_text(text)
    runner = source / "ps2xRuntime/src/runner"
    runner.mkdir(parents=True, exist_ok=True)
    staged = [p for p in generated.iterdir() if p.suffix in (".cpp", ".h")]
    actual_cpp = [p for p in staged if p.suffix == ".cpp"]
    if len(actual_cpp) != report["generated_cpp_files"] or sum(p.stat().st_size for p in actual_cpp) != report["generated_cpp_bytes"]:
        raise ValueError("Generated output does not match generation report")
    for pattern in ("sub_*_0x*.cpp", "register_functions.cpp", "ps2_recompiled_functions.cpp"):
        for old in runner.glob(pattern):
            if old.name not in {p.name for p in staged}:
                old.unlink()
    for path in staged:
        copy_if_changed(path, runner / path.name)
    for name in ("ps2_recompiled_functions.h", "ps2_recompiled_stubs.h"):
        copy_if_changed(generated / name, source / "ps2xRuntime/include" / name)
    override = (repo / "src/downhill_domination_overrides.cpp").read_text()
    override = re.sub(r"constexpr uint32_t kExpectedFileCrc32 = 0x[0-9A-Fa-f]{8}u;",
                      f"constexpr uint32_t kExpectedFileCrc32 = 0x{zlib.crc32(elf):08X}u;", override)
    override_path = runner / "downhill_domination_overrides.cpp"
    if not override_path.exists() or override_path.read_text() != override:
        override_path.write_text(override)
    options = ["-DCMAKE_BUILD_TYPE=Debug", "-DPS2X_BUILD_RUNTIME=ON", "-DPS2X_BUILD_RECOMP=OFF",
               "-DPS2X_BUILD_ANALYZER=OFF", "-DPS2X_BUILD_TEST=OFF", "-DPS2X_BUILD_STUDIO=OFF",
               "-DPS2X_ENABLE_FFMPEG=OFF", "-DPS2X_ENABLE_DEBUG_UI=OFF", "-DPS2X_STRICT_RETURN_DIAGNOSTICS=ON",
               "-DPS2X_ENABLE_RUNTIME_LOGS=ON", "-DPS2X_ENABLE_AGRESSIVE_LOGS=ON", "-DPS2X_ENABLE_IOP_RPC_TRACE=ON",
               "-DPS2X_ENABLE_RUNNER_UNITY_BUILD=ON", "-DPS2X_RUNNER_UNITY_BUILD_BATCH_SIZE=64", "-DCMAKE_CXX_FLAGS=-mavx2"]
    if args.raylib_source:
        options.append(f"-DFETCHCONTENT_SOURCE_DIR_RAYLIB={args.raylib_source.resolve()}")
    if args.prefix:
        prefix = args.prefix.resolve()
        options += [f"-DCMAKE_PREFIX_PATH={prefix}", f"-DCMAKE_INCLUDE_PATH={prefix / 'include'}",
                    f"-DCMAKE_LIBRARY_PATH={prefix / 'lib/x86_64-linux-gnu'}"]
    subprocess.run([args.cmake, "-S", str(source), "-B", str(build), *options], check=True)
    subprocess.run([args.cmake, "--build", str(build), "--target", "ps2EntryRunner", "--parallel", str(args.jobs)], check=True)
    executable = build / "ps2xRuntime/ps2EntryRunner"
    if not executable.is_file() or executable.stat().st_size == 0:
        raise ValueError("Native runner missing after build")
    (generated.parent / "native_build_report.json").write_text(json.dumps({
        "elf_sha256": ELF_SHA256, "ps2recomp_commit": PIN, "runtime_linked": True,
        "host": "linux-x64", "windows_link_verified": False,
        "runner_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "runner_bytes": executable.stat().st_size,
    }, indent=2) + "\n")
    print(f"Native diagnostic runner: {executable}")


if __name__ == "__main__":
    main()
