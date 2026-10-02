#!/usr/bin/env python3
"""Apply version-pinned runtime fixes, accepting an already applied patch."""
from pathlib import Path
import subprocess

PIN = "75d729ce40d7eed9649fd4bb05628dee520f3d0c"
PATCHES = ("gs-host-transfer", "cdvd-iso-extents", "mpeg-program-end", "ready-queue-snapshot", "boot-performance-trace", "dmac-interrupt-trace", "cop0-dmac-condition", "vif1-command-trace", "gs-pipeline-trace", "auto-intro-skip", "gs-texture-trace", "intro-stream-window", "gs-clut-reload", "gs-upload24-continuation", "gs-clut-trace", "gs-vram-watch", "gs-clut-entry1-trace", "gs-palette-upload-trace", "gs-image-block-address", "gs-triangle-trace", "gs-clear-depth-trace", "vif-v45-color")


def apply(source):
    source = Path(source).resolve()
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != PIN:
        raise ValueError("PS2Recomp revision mismatch; refusing to apply runtime patches")
    directory = Path(__file__).resolve().parents[1] / "patches"
    # New diagnostics overlap context in older fixes. Temporarily unwind only
    # these owned additions so earlier reverse checks remain valid on reapply.
    for name in reversed(("gs-vram-watch", "gs-clut-entry1-trace", "gs-palette-upload-trace", "gs-image-block-address", "gs-triangle-trace", "gs-clear-depth-trace", "vif-v45-color")):
        patch = directory / f"ps2recomp-{name}.patch"
        command = ["git", "-C", str(source), "apply"]
        if subprocess.run([*command, "--reverse", "--check", str(patch)], capture_output=True).returncode == 0:
            subprocess.run([*command, "--reverse", str(patch)], check=True)
    for name in PATCHES:
        patch = directory / f"ps2recomp-{name}.patch"
        command = ["git", "-C", str(source), "apply"]
        reverse = subprocess.run([*command, "--reverse", "--check", str(patch)], capture_output=True)
        if reverse.returncode == 0:
            continue
        subprocess.run([*command, "--check", str(patch)], check=True)
        subprocess.run([*command, str(patch)], check=True)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    apply(parser.parse_args().source)
