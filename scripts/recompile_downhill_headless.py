#!/usr/bin/env python3
"""Generate retail C++ with pinned tools; does not build or run the runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import tomllib

PIN = "75d729ce40d7eed9649fd4bb05628dee520f3d0c"
SHA256 = "adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c"
ENTRIES = ("0x0010A008", "0x001FB6C0", "0x002451B0", "0x00254050", "0x00246FA0", "0x0025C440")


def scalar(text, key, value):
    literal = json.dumps(value) if isinstance(value, str) else str(value).lower()
    pattern = rf"(?m)^{re.escape(key)}\s*=.*$"
    if re.search(pattern, text):
        return re.sub(pattern, lambda _: f"{key} = {literal}", text, count=1)
    return text.replace("[general]\n", f"[general]\n{key} = {literal}\n", 1)


def array(text, key, values):
    replacement = key + " = [\n" + "".join(f"  {json.dumps(v)},\n" for v in sorted(set(values))) + "]"
    pattern = rf"(?ms)^{key}\s*=\s*\[.*?^\s*\]"
    if not re.search(pattern, text):
        raise ValueError(f"Missing {key} array")
    return re.sub(pattern, lambda _: replacement, text, count=1)


def handler_status(root, name):
    aliases = (name, name[1:] if name.startswith("_") else "_" + name)
    for alias in aliases:
        for source in sorted((root / "ps2xRuntime/src/lib").rglob("*.cpp")):
            text = source.read_text(encoding="utf-8")
            match = re.search(rf"(?m)^\s*void\s+{re.escape(alias)}\s*\(", text)
            if not match:
                continue
            tail = text[match.end():]
            next_handler = re.search(r"(?m)^\s*void\s+[A-Za-z_][A-Za-z0-9_]*\s*\(", tail)
            body = tail[:next_handler.start()] if next_handler else tail[:5000 - len(match.group())]
            return "todo" if re.search(r"\bTODO(?:_NAMED)?\s*\(", body) else "implemented"
    return "not-found"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--elf", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--analyzer", type=Path, required=True)
    parser.add_argument("--recompiler", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    elf, source, work = args.elf.resolve(), args.source.resolve(), args.work.resolve()
    data = elf.read_bytes()
    if len(data) != 1691684 or hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError("Retail ELF identity mismatch")
    if data[:6] != b"\x7fELF\x01\x01" or struct.unpack_from("<H", data, 18)[0] != 8:
        raise ValueError("Expected little-endian ELF32 MIPS")
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != PIN:
        raise ValueError("PS2Recomp revision mismatch")
    work.mkdir(parents=True, exist_ok=True)
    config = work / "downhill.toml"
    report = {"elf_sha256": SHA256, "ps2recomp_commit": head, "runtime_built": False,
              "runtime_boot_verified": False, "ghidra_map_used": False, "steps": []}
    report_path = work / "generation_report.json"

    def run(tool, arguments, label):
        with (work / f"{label}.log").open("w") as log:
            result = subprocess.run([str(tool.resolve()), *arguments], cwd=source,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
        report["steps"].append({"stage": label, "exit_code": result.returncode})
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        result.check_returncode()

    run(args.analyzer, [str(elf), str(config)], "analyzer")
    text = config.read_text()
    general = tomllib.loads(text)["general"]
    stubs = list(general["stubs"]) + ["scePadRead@0x002451B0", "sceSifSendCmd@0x0025C440"]
    entries = list(general["entry_points"]) + list(ENTRIES)
    statuses = [{"selector": stub, "status": handler_status(source, stub.split("@", 1)[0])}
                for stub in sorted(set(stubs))]
    safe = [row["selector"] for row in statuses if row["status"] == "implemented"]
    entries += [row["selector"] for row in statuses if row["status"] != "implemented" and "@" in row["selector"]]
    for key, value in {"input": str(elf), "output": str(work / "output"),
                       "single_file_output": False, "low_memory_mode": True,
                       "output_worker_threads": 1, "patch_syscalls": False,
                       "patch_cop0": False, "patch_cache": False}.items():
        text = scalar(text, key, value)
    text = array(array(text, "stubs", safe), "entry_points", entries)
    tomllib.loads(text)
    config.write_text(text)
    report["stub_filter"] = statuses
    run(args.recompiler, [str(config)], "recompiler")
    files = sorted((work / "output").glob("*.cpp"))
    table_path = work / "output/register_functions.cpp"
    if not table_path.exists():
        raise ValueError("Generated function table missing")
    table = table_path.read_text()
    for entry in ENTRIES:
        if not re.search(r"(?i)//\s*0x0*" + format(int(entry, 16), "x") + r"\b", table):
            raise ValueError(f"Required generated entry missing: {entry}")
    for address, name in ((0x2451B0, "scePadRead"), (0x254050, "memcpy"), (0x25C440, "sceSifSendCmd")):
        candidates = list((work / "output").glob(f"*_0x{address:x}.cpp"))
        if len(candidates) != 1 or not re.search(
                rf"ps2_(?:stubs|syscalls)::{name}\s*\(", candidates[0].read_text()):
            raise ValueError(f"Confirmed runtime binding missing: {name}")
    if not files:
        raise ValueError("No generated C++ files")
    report.update({"generated_cpp_files": len(files), "generated_cpp_bytes": sum(p.stat().st_size for p in files),
                   "required_entries_verified": list(ENTRIES),
                   "confirmed_bindings_verified": ["scePadRead", "memcpy", "sceSifSendCmd"], "generation_verified": True})
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "stub_filter"}, indent=2))


if __name__ == "__main__":
    main()
