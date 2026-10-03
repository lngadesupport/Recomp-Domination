#!/usr/bin/env python3
"""Repeat the bounded frame-observer navigation; no game-mode/FPS certification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workspace',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--display',default='127.0.0.1:128')
    args=p.parse_args();root=args.workspace.resolve();out=args.out.resolve()
    scripts=Path(__file__).resolve().parent
    runner=root/'native-build/ps2xRuntime/ps2EntryRunner'
    receipt=json.loads((root/'generated/native_build_report.json').read_text())
    if receipt.get('ffmpeg_enabled') is not True:raise ValueError('FFmpeg is required for this comparison')
    expected=receipt['runner_sha256']
    if runner.stat().st_size!=receipt['runner_bytes'] or hashlib.sha256(runner.read_bytes()).hexdigest()!=expected:
        raise ValueError('Runner identity mismatch')
    out.mkdir(parents=True,exist_ok=True)
    (out/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    env={**os.environ,'LD_LIBRARY_PATH':str(root/'deps/usr/lib/x86_64-linux-gnu'),
         'PYTHONPATH':str(root/'python-deps'),'LIBGL_ALWAYS_SOFTWARE':'1',
         'PS2_TRACE_DOWNHILL_FRAME_STATE':'1','PS2_TRACE_GUEST_MISSING_TARGETS':'1',
         'PS2_TRACE_GS_PIPELINE':'1','PS2_TRACE_DOWNHILL_RESOURCE_RETURN':'1'}
    cmd=[sys.executable,str(scripts/'run_native_progression.py'),'--runner',str(runner),
         '--elf',str(root/'retail/SCUS_971.77'),'--root',str(root/'disc'),'--iso',str(root/'probe.iso'),
         '--out',str(out),'--budget-seconds','630','--probe-seconds','620','--max-probes','1',
         '--expected-runner-sha256',expected,'--auto-intro-skip',
         '--xvfb',str(root/'deps/usr/bin/Xvfb-local'),'--display',args.display,'--captures']
    started=time.monotonic();process=subprocess.Popen(cmd,env=env)
    def capture():
        from PIL import ImageGrab
        for deadline in range(30,620,20):
            time.sleep(max(0,deadline-(time.monotonic()-started)))
            if process.poll() is not None:return
            try:ImageGrab.grab(xdisplay=args.display).save(out/'run-001'/f'dense-{deadline}.png')
            except Exception as error:print('capture error:',error,flush=True)
    threading.Thread(target=capture,daemon=True).start()
    def keys(values,path,interval=None):
        if process.poll() is not None:raise RuntimeError('Probe exited before navigation')
        c=[sys.executable,str(scripts/'send_native_probe_keys.py'),'--display',args.display,
           '--xtst',str(root/'deps/usr/lib/x86_64-linux-gnu/libXtst.so.6'),'--out',str(path),'--keys',*values]
        if interval is not None:c+=['--interval',str(interval)]
        subprocess.run(c,env=env,check=True,timeout=195 if interval else 15)
    try:
        time.sleep(max(0,25-(time.monotonic()-started)))
        keys(['x','Return','x','x','x','x','x'],out/'inputs.json',15)
        for deadline,key in [(220,'x'),(300,'x'),(360,'Return'),(420,'x'),(480,'x'),(540,'Return')]:
            time.sleep(max(0,deadline-(time.monotonic()-started)))
            keys([key],out/f'input-at-{deadline}.json')
        process.wait(timeout=140)
        if process.returncode:raise RuntimeError('Probe failed')
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:process.kill();process.wait()
    subprocess.run([sys.executable,str(scripts/'analyze_frame_state.py'),'--log',
                    str(out/'run-001/runtime.log'),'--out',str(out/'frame-observations.json')],check=True)


if __name__=='__main__':main()
