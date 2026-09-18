#!/usr/bin/env python3
"""Record an example running in VICE as a video.

Drives x64sc through its monitor (tools/b64vice.py), screenshots every
`--every`th frame after `--skip` frames, and encodes the frames with ffmpeg
as H.264 at twice the size with square pixels kept square (nearest
neighbour), playing at 50 / every frames a second, so a clip runs at the
speed the machine ran it.  Writes a poster image (the first frame) beside
the video.

What it records is VICE's own picture of each frame, the same one the
checks look at; the frames are taken with the emulator stopped, so the
recording never drops or blends a frame the way a screen capture can.

usage: b64video.py <prg> <out.mp4> [--skip 100] [--frames 500] [--every 1]
                   [--reu build/world8.reu --reusize 8192]
needs: x64sc, ffmpeg
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64vice import Vice                         # noqa: E402


def record(prg, out, skip=100, frames=500, every=1, reu="build/world8.reu", reusize=8192, port=6690):
    tmp = tempfile.mkdtemp(prefix="b64video-")
    try:
        v = Vice(prg, reusize, reu, os.path.splitext(prg)[0] + ".lbl", port)
        try:
            v.frames(skip)
            for k in range(frames):
                v.frames(every)
                v.shot(os.path.join(tmp, f"f{k:05d}.png"))
        finally:
            v.close()
        rate = 50 / every
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", f"{rate:g}",
                        "-i", os.path.join(tmp, "f%05d.png"),
                        "-vf", "scale=iw*2:ih*2:flags=neighbor", "-c:v", "libx264", "-preset", "slow",
                        "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out], check=True)
        poster = os.path.splitext(out)[0] + ".png"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(tmp, "f00000.png"),
                        "-vf", "scale=iw*2:ih*2:flags=neighbor", poster], check=True)
        return frames / rate
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("out")
    ap.add_argument("--skip", type=int, default=100)
    ap.add_argument("--frames", type=int, default=500)
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--reu", default="build/world8.reu")
    ap.add_argument("--reusize", type=int, default=8192)
    ap.add_argument("--port", type=int, default=6690)
    a = ap.parse_args()
    secs = record(a.prg, a.out, a.skip, a.frames, a.every, a.reu, a.reusize, a.port)
    print(f"{a.out}: {secs:.1f} s, {os.path.getsize(a.out) // 1024} KB")


if __name__ == "__main__":
    main()
