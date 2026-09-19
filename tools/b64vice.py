#!/usr/bin/env python3
"""Drive VICE through its remote monitor: the engine's test bench.

Commands wait for the monitor's prompt instead of sleeping, so a run is as
fast as the emulator (warp) and the same every time.  Used by b64check.py;
usable from a shell for one-off measurements.

    v = Vice("build/cutscene.prg", reusize=8192, reuimage="build/world8.reu",
             labels="build/cutscene.lbl")
    v.run_to("b64_obj_park")          # break on a label
    v.frames(4)                       # advance four frames
    rows = v.shot("build/check/x.png")
    v.close()
"""
import os
import re
import socket
import subprocess
import time

from b64png import read_png

PROMPT = re.compile(rb"\(C:\$[0-9a-fA-F]{4}\) $")
# every timeout is multiplied by this: a shared CI runner emulates several
# times slower than a desk machine (B64_VICE_TIMEOUT_SCALE=6 in the workflow)
SCALE = float(os.environ.get("B64_VICE_TIMEOUT_SCALE", "1"))
FRAME = 0x10                                    # b64_frame, stored once per frame by the engine IRQ


class ViceError(Exception):
    pass


def load_labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3 and p[0] == "al":
            out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


class Vice:
    def __init__(self, prg, reusize=8192, reuimage=None, labels=None, port=6510, warp=True, tries=3, x64="x64sc", reu=True, extra=()):
        self.labels = {}                    # a program's labels, then any module's (a path or several);
        for path in ([labels] if isinstance(labels, str) else labels or []):   # the first file to name a
            for name, addr in load_labels(path).items():                       # label keeps it, so a module's
                self.labels.setdefault(name, addr)                             # link to the engine's entry
                                                                               # table ($2F00) never hides the
                                                                               # engine's own routine
        self.port, self.proc, self.sock = port, None, None
        self._frame_watch = None
        args = [x64, "-default", "+sound", "+confirmonexit",
                "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}", "-autostartprgmode", "1"]
        args += ["-reu", "-reusize", str(reusize)] if reu else ["+reu"]
        if reu and reuimage:
            args += ["-reuimage", reuimage, "+reuimagerw"]
        if warp:
            args += ["-warp"]
        args += list(extra)
        last = None
        for _ in range(tries):                  # autostart sometimes lands at the BASIC prompt: start again
            try:
                self._start(args + [prg])
                self.run_to(self.labels.get("b64_init", 0x0810), timeout=40)
                return
            except ViceError as e:
                last = e
                self.close()
        raise ViceError(f"{prg} did not reach b64_init: {last}")

    def _start(self, args):
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 20 * SCALE
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=2)
                break
            except OSError:
                if time.time() > deadline or self.proc.poll() is not None:
                    raise ViceError("could not reach the VICE monitor")
                time.sleep(0.2)
        self._frame_watch = None
        self.cmd("r")                           # the first command stops the machine and brings the prompt
        self._drain()                           # on a slow machine the stop can print a second prompt: a later
                                                # command would read it as its reply (CI, 2026-09-18)

    def _drain(self, quiet=0.5):
        """Discard output until the monitor has been quiet for a moment."""
        self.sock.settimeout(quiet * SCALE)
        try:
            while self.sock.recv(65536):
                pass
        except socket.timeout:
            pass

    def _read(self, timeout):
        timeout *= SCALE
        buf, deadline = b"", time.time() + timeout
        while not PROMPT.search(buf):
            left = deadline - time.time()
            if left <= 0:
                raise ViceError(f"no prompt within {timeout}s; got {buf[-120:]!r}")
            self.sock.settimeout(left)
            try:
                d = self.sock.recv(65536)
            except socket.timeout:
                continue
            if not d:
                raise ViceError("the monitor closed the connection")
            buf += d
        return buf.decode(errors="replace")

    def cmd(self, c, timeout=10):
        self.sock.sendall((c + "\n").encode())
        return self._read(timeout)

    def addr(self, a):
        if isinstance(a, str):
            if a not in self.labels:
                raise ViceError(f"no label {a}")
            return self.labels[a]
        return a

    def mem(self, a, n=1):
        a = self.addr(a)
        out = self.cmd(f"m {a:04x} {a + n - 1:04x}")
        b = []
        for line in out.splitlines():
            m = re.match(r">C:[0-9a-f]{4}\s+((?:[0-9a-f]{2}\s{1,2})+)", line)
            if m:
                b += [int(t, 16) for t in m.group(1).split()]
        if len(b) < n:
            raise ViceError(f"short memory read at ${a:04x}: {out!r}")
        return bytes(b[:n])

    def word(self, a, n=2):
        return int.from_bytes(self.mem(a, n), "little")

    def _checkpoint(self, text):
        m = re.search(r"(?:BREAK|WATCH|TRACE): (\d+)", text)
        if not m:
            try:
                text += self._read(5)           # a stale prompt came first: the reply follows it
            except ViceError:
                pass
            m = re.search(r"(?:BREAK|WATCH|TRACE): (\d+)", text)
        if not m:
            raise ViceError(f"could not set a checkpoint: {text!r}")
        return int(m.group(1))

    def run_to(self, a, timeout=60, hits=1):
        """Continue until execution reaches a; with hits=n, the nth time."""
        a = self.addr(a)
        n = self._checkpoint(self.cmd(f"break {a:04x}"))
        if hits > 1:
            self.cmd(f"ignore {n:x} {hits - 1:x}")    # the monitor reads numbers as hex
        try:
            out = self.cmd("x", timeout)
        finally:
            self.cmd(f"del {n:x}")
        return out

    def frames(self, count=1, timeout=None):
        """Advance count frames: run to the count-th store of the frame counter."""
        if self._frame_watch is None:
            self._frame_watch = self._checkpoint(self.cmd(f"watch store {FRAME:04x}"))
        else:
            self.cmd(f"enable {self._frame_watch:x}")
        if count > 1:
            self.cmd(f"ignore {self._frame_watch:x} {count - 1:x}")
        self.cmd("x", timeout or 30 + count / 10)
        self.cmd(f"disable {self._frame_watch:x}")

    def poke(self, a, data):
        a = self.addr(a)
        self.cmd(f"> {a:04x} " + " ".join(f"{b:02x}" for b in data))

    def shot(self, path):
        """Screenshot the last complete frame -> rows of RGB bytes."""
        path = os.path.abspath(path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path):
            os.unlink(path)
        self.cmd(f'screenshot "{path}" 2')
        deadline = time.time() + 5 * SCALE
        while not os.path.exists(path) or os.path.getsize(path) == 0:
            if time.time() > deadline:
                raise ViceError(f"no screenshot at {path}")
            time.sleep(0.02)
        return read_png(path)[2]

    def close(self):
        try:
            if self.sock:
                self.sock.sendall(b"quit\n")
                self.sock.close()
        except OSError:
            pass
        if self.proc:
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.sock = self.proc = None
