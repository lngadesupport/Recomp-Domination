#!/usr/bin/env python3
"""Verify extracted RAR data against member CRCs and stage uppercase guest paths.

Requires rarfile for metadata only; extract all volumes with a native unrar
first. Game data remains local and is never included in the repository.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import shutil
import zlib


def verify_and_stage(archive, extracted, output):
    import rarfile
    rows = []
    names = set()
    extracted, output = extracted.resolve(), output.resolve()
    if extracted == output or extracted in output.parents or output in extracted.parents:
        raise ValueError("Extracted source and staging output must be separate directories")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Choose a fresh staging directory; existing files may belong to an older partial extraction")
    for entry in rarfile.RarFile(archive).infolist():
        relative = PurePosixPath(entry.filename.replace("\\", "/"))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unsafe archive path: {relative}")
        if entry.isdir() or relative.parts[0].lower() == "tools":
            continue
        guest = Path(*(part.upper() for part in relative.parts))
        if guest.as_posix() in names:
            raise ValueError(f"Case-folded path collision: {guest}")
        names.add(guest.as_posix())
        source = extracted.joinpath(*relative.parts)
        if not source.resolve().is_relative_to(extracted):
            raise ValueError(f"Extracted file escapes source directory: {source}")
        crc, size = 0, 0
        with source.open("rb") as stream:
            while chunk := stream.read(1048576):
                crc = zlib.crc32(chunk, crc)
                size += len(chunk)
        if size != entry.file_size or crc != entry.CRC:
            raise ValueError(f"CRC or size mismatch: {relative}")
        target = output / guest
        if not target.resolve().is_relative_to(output):
            raise ValueError(f"Staging file escapes output directory: {target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        staged_crc, staged_size = 0, 0
        with target.open("rb") as stream:
            while chunk := stream.read(1048576):
                staged_crc = zlib.crc32(chunk, staged_crc)
                staged_size += len(chunk)
        if staged_size != size or staged_crc != crc:
            raise ValueError(f"Staged copy failed verification: {guest}")
        rows.append({"path": guest.as_posix(), "bytes": size, "crc32": f"{crc:08X}"})
    return {"staged_crc_verified": True, "verified_files": len(rows), "verified_bytes": sum(row["bytes"] for row in rows), "files": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--extracted", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = verify_and_stage(args.archive, args.extracted, args.output)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "files"}))


if __name__ == "__main__":
    main()
