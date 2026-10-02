#!/usr/bin/env python3
"""Inspect extracted PCSX2 PNG dumps without changing pixels or runtime assets.

Requires Pillow. Supports the full-texture filename layout present in the
SCUS-97177 dump; region names are reported as unsupported, never guessed.
Field layout reference: PCSX2 GSTextureReplacements.cpp, TextureName.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

NAME = re.compile(r"(?P<texture>[a-fA-F0-9]{1,16})-(?:(?P<palette>[a-fA-F0-9]{1,16})-)?(?P<bits>[a-fA-F0-9]{8})(?:-mip(?P<mip>[0-9]+))?\.png")


def parse_name(name):
    match = NAME.fullmatch(name)
    if not match:
        raise ValueError("unsupported full-texture dump name")
    bits = int(match['bits'], 16)
    mip = int(match['mip'] or 0)
    if mip > 15:
        raise ValueError("mip level exceeds supported range")
    width = 1 << ((bits >> 6) & 15)
    height = 1 << ((bits >> 10) & 15)
    return {
        'texture_hash': match['texture'].lower(),
        'palette_hash': (match['palette'] or '0').lower(),
        'psm': bits & 63, 'base_width': width, 'base_height': height,
        'mip_level': mip, 'expected_width': max(1, width >> mip),
        'expected_height': max(1, height >> mip),
        'ta0': (bits >> 15) & 255, 'aem': (bits >> 23) & 1,
        'ta1': (bits >> 24) & 255,
    }


def inspect(directory):
    from PIL import Image
    rows, errors = [], []
    for path in sorted(directory.rglob('*.png')):
        name = path.relative_to(directory).as_posix()
        try:
            metadata = parse_name(path.name)
            with Image.open(path) as image:
                image.load()
                rgba = image.convert('RGBA')
                row = {'name': name, **metadata, 'width': image.width,
                       'height': image.height, 'mode': image.mode,
                       'pixel_sha256': hashlib.sha256(rgba.tobytes()).hexdigest(),
                       'alpha_extrema': list(rgba.getchannel('A').getextrema())}
                row['dimensions_match'] = (image.width == metadata['expected_width']
                                           and image.height == metadata['expected_height'])
                rows.append(row)
        except (ValueError, OSError) as error:
            errors.append({'name': name, 'error': str(error)})
    return {
        'purpose': 'reference inventory; does not install runtime replacements',
        'images': len(rows), 'dimension_mismatches': sum(not r['dimensions_match'] for r in rows),
        'psm_counts': dict(sorted(Counter(r['psm'] for r in rows).items())),
        'errors': errors, 'textures': rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not args.directory.is_dir():
        parser.error('directory must exist')
    report = inspect(args.directory)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'textures'}))
    return 1 if report['errors'] or not report['images'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
