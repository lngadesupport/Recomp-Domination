#!/usr/bin/env python3
"""Link the SDK address fixture against an existing POSIX production build."""
import argparse
from pathlib import Path
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stub-override", type=Path, help="Compile an alternate GS.cpp for a negative control")
    parser.add_argument("--fixture", type=Path, help="Alternate production-runtime fixture source")
    args = parser.parse_args()
    source, build, output = args.source.resolve(), args.build.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    directory = build / "ps2xRuntime"
    command = shlex.split((directory / "CMakeFiles/ps2EntryRunner.dir/link.txt").read_text())
    flags = {}
    for line in (directory / "CMakeFiles/ps2_runtime.dir/flags.make").read_text().splitlines():
        if " = " in line:
            key, value = line.split(" = ", 1)
            flags[key] = shlex.split(value)
    includes = flags["CXX_INCLUDES"]
    repo = Path(__file__).resolve().parents[1]
    files = [args.fixture.resolve() if args.fixture else repo / "tests/gs_sdk_image_address_test.cpp", source / "ps2xTest/src/test_function_table.cpp"]
    if args.stub_override:
        files.append(args.stub_override.resolve())
        includes = [*includes, "-I" + str(source / "ps2xRuntime/src/lib/Kernel/Stubs")]
    objects = []
    for index, file in enumerate(files):
        object_file = output / f"fixture-{index}.o"
        subprocess.run([command[0], "-std=c++20", "-mavx2", "-O1", *flags["CXX_DEFINES"],
                        *includes, "-c", str(file), "-o", str(object_file)], check=True)
        objects.append(str(object_file))
    command = [part.replace("-flto=auto", "-flto=2") for part in command
               if not (part.endswith(".o") and "ps2EntryRunner.dir/" in part)]
    executable = output / (args.fixture.stem if args.fixture else "gs_sdk_image_address_test")
    command[command.index("-o") + 1] = str(executable)
    command[1:1] = objects
    subprocess.run(command, cwd=directory, check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
