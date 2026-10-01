#!/usr/bin/env python3
"""Build a local diagnostic ISO from extracted data (requires pycdlib).

This reconstruction has internally consistent extents, not the original disc
layout. It is a bring-up fixture and does not validate original-disc fidelity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import pycdlib

ELF_SHA256 = "adfda7b73a8f05fb20a3f0f318772e9d3797fd4d6c0a6c0078ae392df0f0cf0c"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--elf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.elf.read_bytes()).hexdigest() != ELF_SHA256:
        raise ValueError("Retail ELF identity mismatch")
    if args.output.exists():
        raise ValueError("Choose a fresh output ISO")
    root = args.root.resolve()
    if args.output.resolve().is_relative_to(root):
        raise ValueError("Output ISO must be outside the source tree")
    iso = pycdlib.PyCdlib()
    # Level 4 preserves the game's long and punctuation-containing filenames.
    iso.new(interchange_level=4, vol_ident="DOWNHILL_PROBE")
    count = 0
    for path in sorted(root.rglob("*"), key=lambda p: (len(p.relative_to(root).parts), p.as_posix())):
        if path.is_symlink():
            raise ValueError(f"Symlink in source tree: {path}")
        relative = "/" + path.relative_to(root).as_posix()
        if relative != relative.upper():
            raise ValueError(f"Expected uppercase guest path: {relative}")
        if path.is_dir():
            iso.add_directory(iso_path=relative)
        else:
            iso.add_file(str(path), iso_path=relative + ";1")
            count += 1
    iso.add_file(str(args.elf), iso_path="/SCUS_971.77;1")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    iso.write(str(args.output))
    iso.close()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({"reconstructed_disc": True,
        "original_disc_layout_verified": False, "data_files": count,
        "iso_bytes": args.output.stat().st_size, "elf_sha256": ELF_SHA256}, indent=2) + "\n")


if __name__ == "__main__":
    main()
