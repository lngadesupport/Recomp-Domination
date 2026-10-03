#!/usr/bin/env python3
"""Reproduce numeric formatting frame corruption with supplied retail generated C++.
No game files are distributed. The controlled old variant changes only the
SQRT statement confirmed by the decoder/emitter regression; it is not a
second full runtime build. Link arguments must be supplied as a JSON argv list
for a standalone runtime fixture (one test source and a runtime archive).
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("generated", "source", "elf", "runtime-library", "link-args-json", "out"):
        p.add_argument("--" + name, type=Path, required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    generated, source, elf = a.generated.resolve(), a.source.resolve(), a.elf.resolve()
    if hashlib.sha256(elf.read_bytes()).hexdigest() != "adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c":
        raise ValueError("Retail ELF identity mismatch")
    files = {}
    for f in generated.glob("*.cpp"):
        m = re.search(r"_0x([0-9a-f]+)\.cpp$", f.name)
        if m:
            files[int(m[1], 16)] = f
    todo, seen = [0x254d68, 0x1fd300, 0x177da0], set()
    while todo:
        address = todo.pop()
        if address in seen:
            continue
        seen.add(address)
        if address not in files:
            raise ValueError(f"Missing generated function {address:#x}")
        todo.extend(int(x, 16) for x in re.findall(
            r"dispatchGuestBranch\(rdram, ctx, 0x([0-9A-F]+)u", files[address].read_text()))
    body = files[0x177da0].read_text()
    corrected = "ctx->f[4] = FPU_SQRT_S(ctx->f[4]);"
    if body.count(corrected) != 1:
        raise ValueError("Generated retail root operand is not the expected corrected form")
    original_name = re.search(r"void (\w+)\(uint8_t", body)[1]
    body = body.replace("void " + original_name + "(", "void oldNumericBody(").replace(
        corrected, "ctx->f[4] = FPU_SQRT_S(ctx->f[0]);")
    old = a.out.resolve() / "controlled-old-body.inc"
    old.write_text(body)
    includes, registration = [], []
    for address in sorted(seen):
        f = files[address]
        includes.append("#include " + json.dumps(str(f)))
        name = re.search(r"void (\w+)\(uint8_t", f.read_text())[1]
        registration.append(f" runtime.registerFunction(0x{address:x},{name});")
    includes.append("#include " + json.dumps(str(old)))
    template = Path(__file__).resolve().parents[1] / "tests/retail_numeric_chain_probe.cpp.in"
    text = template.read_text().replace("@GENERATED_INCLUDES@", "\n".join(includes)).replace(
        "@GENERATED_REGISTRATION@", "\n".join(registration)).replace("@ELF_PATH@", json.dumps(str(elf)))
    cpp, runner = a.out.resolve() / "numeric-chain.cpp", a.out.resolve() / "numeric-chain"
    cpp.write_text(text)
    argv = json.loads(a.link_args_json.read_text())
    tests = [i for i, arg in enumerate(argv) if arg.endswith(".cpp") and "test_function_table" not in arg]
    archives = [i for i, arg in enumerate(argv) if arg.endswith(".a") and "runtime" in Path(arg).name]
    if len(tests) != 1 or len(archives) != 1 or "-o" not in argv:
        raise ValueError("Expected standalone fixture link argv with one test and runtime archive")
    argv[tests[0]], argv[archives[0]] = str(cpp), str(a.runtime_library.resolve())
    argv[argv.index("-o") + 1] = str(runner)
    argv[1:1] = ["-I" + str(generated), "-I" + str(source / "ps2xRuntime/src/lib/Kernel"), "-flto=2"]
    subprocess.run(argv, check=True)
    with (a.out / "result.log").open("w") as log:
        subprocess.run([str(runner)], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=15)
    print((a.out / "result.log").read_text(), end="")


if __name__ == "__main__":
    main()
