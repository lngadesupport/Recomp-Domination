#!/usr/bin/env python3
"""Send a recorded key sequence to the game's window in an owned probe Xvfb."""
import argparse
import ctypes as c
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--display", required=True)
    p.add_argument("--xtst", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--keys", nargs="+", default=["x"],
                   help="X11 key names; SDK pad Cross=X, Start=Return")
    p.add_argument("--interval", type=float, default=20)
    args = p.parse_args()
    if not re.fullmatch(r"127\.0\.0\.1:[0-9]+", args.display) or not 0 <= args.interval <= 60:
        p.error("Use the owned probe's TCP display and an interval from 0 to 60 seconds")
    x = c.CDLL("libX11.so.6")
    t = c.CDLL(str(args.xtst.resolve()))
    display_t, window_t = c.c_void_p, c.c_ulong
    x.XOpenDisplay.argtypes = [c.c_char_p]; x.XOpenDisplay.restype = display_t
    x.XDefaultRootWindow.argtypes = [display_t]; x.XDefaultRootWindow.restype = window_t
    x.XQueryTree.argtypes = [display_t, window_t, c.POINTER(window_t), c.POINTER(window_t), c.POINTER(c.POINTER(window_t)), c.POINTER(c.c_uint)]
    x.XFetchName.argtypes = [display_t, window_t, c.POINTER(c.c_void_p)]
    x.XFree.argtypes = [c.c_void_p]
    x.XSetInputFocus.argtypes = [display_t, window_t, c.c_int, c.c_ulong]
    x.XStringToKeysym.argtypes = [c.c_char_p]; x.XStringToKeysym.restype = c.c_ulong
    x.XKeysymToKeycode.argtypes = [display_t, c.c_ulong]; x.XKeysymToKeycode.restype = c.c_ubyte
    x.XFlush.argtypes = [display_t]; x.XCloseDisplay.argtypes = [display_t]
    t.XTestFakeKeyEvent.argtypes = [display_t, c.c_uint, c.c_int, c.c_ulong]
    display = x.XOpenDisplay(args.display.encode())
    if not display: raise RuntimeError("Owned probe Xvfb is unavailable")
    events = []
    try:
        root, parent, children, count = window_t(), window_t(), c.POINTER(window_t)(), c.c_uint()
        if not x.XQueryTree(display, x.XDefaultRootWindow(display), c.byref(root), c.byref(parent), c.byref(children), c.byref(count)):
            raise RuntimeError("Cannot inspect owned probe windows")
        window = None
        try:
            for index in range(count.value):
                name = c.c_void_p()
                if x.XFetchName(display, children[index], c.byref(name)) and name.value:
                    title = c.string_at(name).decode(errors="replace")
                    x.XFree(name)
                    if "PS2" in title or "Downhill" in title:
                        window = children[index]
                        break
        finally:
            if children: x.XFree(children)
        if window is None: raise RuntimeError("Game window not found in the owned probe display")
        x.XSetInputFocus(display, window, 2, 0)
        for index, key in enumerate(args.keys):
            if index: time.sleep(args.interval)
            code = x.XKeysymToKeycode(display, x.XStringToKeysym(key.encode()))
            if not code: raise ValueError(f"Unknown key: {key}")
            if not t.XTestFakeKeyEvent(display, code, 1, 0): raise RuntimeError("Key injection failed")
            x.XFlush(display)
            try:
                time.sleep(1)
            finally:
                t.XTestFakeKeyEvent(display, code, 0, 0); x.XFlush(display)
            events.append({"utc": datetime.now(timezone.utc).isoformat(), "key": key, "keycode": code})
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(json.dumps(events, indent=2) + "\n")
    finally:
        x.XCloseDisplay(display)


if __name__ == "__main__":
    main()
