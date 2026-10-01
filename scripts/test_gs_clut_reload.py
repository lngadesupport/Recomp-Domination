#!/usr/bin/env python3
"""Link the CLUT regression against an already-built production runtime (Linux)."""
import argparse
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--source", type=Path, default=Path("third_party/PS2Recomp"))
    args = parser.parse_args()
    build = args.build.resolve() / "ps2xRuntime"
    source = args.source.resolve()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="gs-clut-regression-") as directory:
        obj = Path(directory) / "test.o"
        executable = Path(directory) / "test"
        subprocess.run(["c++", "-std=c++20", "-mavx2", "-I" + str(source / "ps2xRuntime/include"), "-c", str(root / "tests/gs_clut_reload_test.cpp"), "-o", str(obj)], check=True)
        command = shlex.split((build / "CMakeFiles/ps2EntryRunner.dir/link.txt").read_text())
        command = [part for part in command if not part.endswith(".o") and not part.startswith("-Wl,--dependency-file=")]
        command[command.index("-o") + 1] = str(executable)
        command.insert(1, str(obj))
        subprocess.run(command, cwd=build, check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
