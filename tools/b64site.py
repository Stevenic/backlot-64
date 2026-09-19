#!/usr/bin/env python3
"""The demo site: every example recorded in VICE, on one page.

`make pages` records each demo below with tools/b64video.py (the reference
machine: a stock C64 with an 8 MB REU, as VICE emulates it) and writes
build/site/: index.html, the videos and their posters.  `make publish-pages`
commits build/site to the gh-pages branch through a worktree and pushes it;
GitHub Pages serves that branch.  The videos never enter main.

Every number on the page is one `make check` measures; each demo names the
check that holds it.

usage: b64site.py [--only traffic,scroller] [--publish]
"""
import argparse
import datetime
import html
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import b64video                                  # noqa: E402

REPO = "https://github.com/Stevenic/backlot-64"
SITE = "build/site"

DEMOS = [
    {
        "key": "traffic", "prg": "build/traffic-auto.prg", "skip": 300, "frames": 750, "every": 1,
        "title": "Traffic, with the player's car in it",
        "source": "examples/traffic", "run": "make run-traffic",
        "text": "The light-green car is the player's, on hardware sprite 0, which the multiplexer never touches. "
                "Up to 24 others drive Bellamar's grid: they keep their lanes by reading the map's road bits, turn at "
                "crossings, stop at the lights, queue, and stay out of a crossing whose exit is jammed. A raster line "
                "can show eight sprites and the player's car is one, so traffic may put at most seven on any line; a "
                "governor counts every car against the lines it covers, so an east-west street carries at most seven "
                "moving cars besides the player.",
        "facts": ["0 sprites dropped by the multiplexer in 3,000 frames", "at most 7 traffic sprites on any line",
                  "12 to 14 cars live, 10 to 12 on screen", "1 to 5 percent of frames lost at 1 MHz, by route"],
        "check": "traffic.auto, traffic.by_hand, traffic.frames_lost",
        "note": "The status row flickers: the split that shows it sometimes lands a few cycles late. A known engine "
                "fault, recorded with its measurements, and the next one to fix.",
    },
    {
        "key": "physics", "prg": "build/physics-auto.prg", "skip": 20, "frames": 700, "every": 1,
        "title": "On foot and at the wheel",
        "source": "modules/physics", "run": "make run-physics",
        "text": "The physics module, pinned in memory while play runs. A walker gets into a sedan and drives it into "
                "a parked sports car, which is shoved into a truck: every one of them is a physics body with a mass, "
                "and a collision shares the change in velocity by mass. Cars keep their speed along and across their "
                "heading, so a hard turn or the handbrake makes them slide; walls stop them with a bounce and damage; "
                "the surface under each body sets its grip and drag.",
        "facts": ["no body ever in a wall over 690 frames, judged from the world map",
                  "the first ram: momentum 3,936 before, 4,032 after, the engine's push 64",
                  "the abandoned car comes to rest and sleeps", "two runs of the tape end in the same state"],
        "check": "physics.walls, physics.momentum, physics.rest, physics.repeat",
        "note": "At 1 MHz this demo loses about 7 percent of frames: the physics step costs about 4,500 cycles for "
                "nine bodies and is due a cost pass. The status row flickers for the reason given under traffic.",
    },
    {
        "key": "scroller", "prg": "build/scroll-auto.prg", "skip": 150, "frames": 600, "every": 1,
        "title": "A 4 MB world, scrolled",
        "source": "examples/scroll", "run": "make run-scroll",
        "text": "A 2,048 by 2,048 metatile map lives in the REU; the C64 holds only the screen. Each frame the "
                "scroller shifts the screen with one DMA from an REU copy of it and fills the new column or row from "
                "the map. The car at the centre and the cars around it are the multiplexer's test load; the numbers "
                "are the scroller's own cost in cycles.",
        "facts": ["worst cell crossing 5,754 cycles against a 6,000 target",
                  "15 frames compared cell by cell with a full redraw: 0 wrong"],
        "check": "scroll.picture, bench.scroll_*",
        "note": "",
    },
    {
        "key": "cutscene", "prg": "build/cutscene.prg", "skip": 40, "frames": 680, "every": 1,
        "title": "A cutscene in p-code",
        "source": "examples/cutscene", "run": "make run-cutscene",
        "text": "The scene is a script for the engine's virtual machine, read from the REU through a page cache; "
                "none of it is resident. A cruiser drives in as sprites, eases to a stop with its wheels turning and "
                "its light bar flashing, parks into the bitmap as a block, pixel for pixel, and drives off. The wet "
                "road's reflections shimmer by swapping colour codes, never the bitmap.",
        "facts": ["the park changes no pixel outside the ones that shimmer",
                  "after the drive off the street is the empty street, pixel for pixel",
                  "82 to 118 cycles a p-code opcode"],
        "check": "tier8.cutscene.*, cutscene.tick_*",
        "note": "",
    },
    {
        "key": "lighting", "prg": "build/showcase.prg", "skip": 40, "frames": 1100, "every": 1,
        "title": "Lighting as data",
        "source": "examples/showcase", "run": "make run-showcase",
        "text": "Dusk falls through 32 colour maps streamed from the REU, 1.6 KB each, landed in the vertical blank; "
                "the bitmap never changes. The cruiser's light bar is declared in its own object file with each "
                "lamp's offset, radius and pattern, so the lamps and the light they throw on the street move with it "
                "and cannot drift apart.",
        "facts": ["no relit pixel beyond a light's declared radius",
                  "each lamp in its own colour at the declared offset",
                  "the park is exact after the lights go off"],
        "check": "tier8.showcase.*",
        "note": "",
    },
    {
        "key": "multiplexer", "prg": "build/mux.prg", "skip": 100, "frames": 500, "every": 1,
        "title": "32 sprites from 7",
        "source": "examples/mux", "run": "make run-mux",
        "text": "The multiplexer's test harness: 32 sprites, one every 4 lines, the densest seven hardware sprites "
                "can reuse. Every decision is made in the main loop; the raster interrupts only copy, through a "
                "routine generated for each hardware sprite. A check breaks at every sprite move and holds it to the "
                "VIC-II's own timing, cycle by cycle.",
        "facts": ["0 timing violations in 1,280 sprite moves",
                  "8,586 main-loop and 8,389 interrupt cycles a frame for 32",
                  "24 on a stock C64 in a game; 32 and 64 with the Ultimate's turbo"],
        "check": "mux.normal.timing, mux.dense.timing, mux.picture",
        "note": "",
    },
    {
        "key": "mux64", "prg": "build/mux64.prg", "skip": 150, "frames": 400, "every": 1,
        "title": "64 sprites, on a machine too slow for them",
        "source": "examples/mux (MUX64)", "run": "make build/mux64.prg",
        "text": "The layout for the turbo tier's 64 sprites, one every 3 lines, run on a stock 1 MHz machine. The "
                "allocation knows how long the interrupt chain takes, so what it cannot write in time it drops whole "
                "rather than draw late: 51 of 64 here. Building a 64-sprite list takes more than a frame at 1 MHz, "
                "which is why the positions step: this is the case the turbo is for.",
        "facts": ["51 of 64 shown at 1 MHz, none written late (every write stamped)",
                  "the stamps agree with the emulator's clock to 2 cycles",
                  "untested on a C64 Ultimate until the hardware arrives"],
        "check": "muxhw.mux64, muxhw.clock",
        "note": "",
    },
]


PAGE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>backlot-64</title>
<meta name="description" content="backlot-64, a C64 and REU game engine: every demo recorded in VICE on a stock C64 with an 8 MB REU.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Condensed:wght@500;600&family=IBM+Plex+Sans:wght@400;500&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root {
  --ground: #eceef5;
  --panel: #e1e4ee;
  --ink: #1b1e31;
  --muted: #545a73;
  --rule: #c8ccdb;
  --accent: #4a3ea6;
  --screen: #1b1e31;
  --note: #7a4f10;
  --note-soft: #f1e5cf;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ground: #15172a;
    --panel: #1d2036;
    --ink: #dfe2f1;
    --muted: #9ca2c0;
    --rule: #2d3150;
    --accent: #a59cf0;
    --screen: #0c0d18;
    --note: #e6b86c;
    --note-soft: #2c2618;
  }
}
:root[data-theme="dark"] {
  --ground: #15172a;
  --panel: #1d2036;
  --ink: #dfe2f1;
  --muted: #9ca2c0;
  --rule: #2d3150;
  --accent: #a59cf0;
  --screen: #0c0d18;
  --note: #e6b86c;
  --note-soft: #2c2618;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--ground); color: var(--ink);
  font: 16px/1.6 "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  padding-inline: 20px; padding-block: 40px 64px;
}
main { max-width: 860px; margin: 0 auto; display: grid; gap: 56px; }
a { color: var(--accent); }
a:focus-visible, video:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
header { display: grid; gap: 14px; }
.mark { font: 500 13px/1 "IBM Plex Mono", ui-monospace, Menlo, monospace; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
h1 { margin: 0; font: 600 clamp(40px, 8vw, 64px)/1 "IBM Plex Sans Condensed", "Arial Narrow", sans-serif; letter-spacing: -0.01em; }
.lede { margin: 0; max-width: 64ch; font-size: 18px; }
.meta { margin: 0; max-width: 64ch; color: var(--muted); }
nav { display: flex; flex-wrap: wrap; gap: 8px 20px; font-size: 15px; }
.demos { display: grid; gap: 64px; }
article { display: grid; gap: 14px; }
.screen { background: var(--screen); border-radius: 6px; padding: 8px; }
video { display: block; width: 100%; height: auto; aspect-ratio: 384 / 272; image-rendering: pixelated; border-radius: 2px; background: #000; }
h2 { margin: 0; font: 600 26px/1.2 "IBM Plex Sans Condensed", sans-serif; text-wrap: balance; }
article p { margin: 0; max-width: 66ch; }
.facts { margin: 0; padding: 0; list-style: none; display: grid; gap: 4px; font: 400 14px/1.5 "IBM Plex Mono", monospace; font-variant-numeric: tabular-nums; }
.facts li::before { content: "measured  "; color: var(--muted); }
.how { display: flex; flex-wrap: wrap; gap: 6px 18px; font: 400 13px/1.5 "IBM Plex Mono", monospace; color: var(--muted); }
.how code { color: var(--ink); }
.note { border-left: 3px solid var(--note); background: var(--note-soft); padding: 10px 14px; border-radius: 0 6px 6px 0; max-width: 66ch; font-size: 15px; }
.note strong { color: var(--note); font-weight: 500; }
footer { border-top: 1px solid var(--rule); padding-top: 18px; color: var(--muted); font-size: 14px; display: grid; gap: 6px; }
footer p { margin: 0; max-width: 72ch; }
@media (max-width: 440px) { body { padding-inline: 16px; } .lede { font-size: 17px; } }
</style>
</head>
<body>
<main>
  <header>
    <div class="mark">A C64 and REU game engine · MIT</div>
    <h1>backlot-64</h1>
    <p class="lede">An engine for the Commodore 64 that treats a RAM Expansion Unit as the machine's real memory and the 64 KB as a cache: worlds, art, scripts and code stream in by DMA while assembly does the per-frame work.</p>
    <p class="meta">Every clip below was recorded in VICE on the reference machine, a stock 1 MHz C64 with an 8 MB REU, frame by frame at 50 frames a second. Every number is one that <code>make check</code> measures on each push.</p>
    <nav>
      <a href="__REPO__">Source on GitHub</a>
      <a href="__REPO__/blob/main/docs/PLAN.md">The plan</a>
      <a href="__REPO__/blob/main/docs/JOURNAL.md">How it is being built</a>
      <a href="__REPO__/blob/main/CREDITS.md">Credits</a>
    </nav>
  </header>
  <div class="demos">
__DEMOS__
  </div>
  <footer>
    <p>Recorded __DATE__ from commit <a href="__REPO__/commit/__SHA__"><code>__SHORT__</code></a> with <code>make pages</code> (<code>tools/b64site.py</code>, <code>tools/b64video.py</code>).</p>
    <p>backlot-64 is MIT licensed. The techniques it borrows, and where it departs from them, are credited in CREDITS.md and docs/PRIOR-ART.md.</p>
  </footer>
</main>
<script>
if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  document.querySelectorAll("video").forEach(v => { v.removeAttribute("autoplay"); v.pause(); });
}
</script>
</body>
</html>
'''

CARD = '''    <article id="{key}">
      <div class="screen"><video src="video/{key}.mp4" poster="video/{key}.png" width="768" height="544" autoplay muted loop playsinline controls preload="metadata" aria-label="{title}, recorded in VICE"></video></div>
      <h2>{title}</h2>
      <p>{text}</p>
      <ul class="facts">{facts}</ul>
{note}      <div class="how"><span>source <a href="{repo}/tree/main/{srcpath}"><code>{source}</code></a></span><span>run <code>{run}</code></span><span>checked by <code>{check}</code></span></div>
    </article>'''


def build(only=None):
    os.makedirs(f"{SITE}/video", exist_ok=True)
    for d in DEMOS:
        if only and d["key"] not in only:
            continue
        out = f"{SITE}/video/{d['key']}.mp4"
        secs = b64video.record(d["prg"], out, d["skip"], d["frames"], d["every"])
        print(f"{d['key']}: {secs:.1f} s, {os.path.getsize(out) // 1024} KB")
    cards = []
    for d in DEMOS:
        facts = "".join(f"<li>{html.escape(f)}</li>" for f in d["facts"])
        note = (f'      <p class="note"><strong>Known limits.</strong> {html.escape(d["note"])}</p>\n' if d["note"] else "")
        cards.append(CARD.format(key=d["key"], title=html.escape(d["title"]), text=html.escape(d["text"]),
                                 facts=facts, note=note, repo=REPO, srcpath=d["source"].split()[0],
                                 source=html.escape(d["source"]), run=html.escape(d["run"]), check=html.escape(d["check"])))
    sha = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    page = (PAGE.replace("__DEMOS__", "\n".join(cards)).replace("__REPO__", REPO)
            .replace("__DATE__", datetime.date.today().isoformat()).replace("__SHA__", sha).replace("__SHORT__", sha[:7]))
    with open(f"{SITE}/index.html", "w") as f:
        f.write(page)
    open(f"{SITE}/.nojekyll", "w").close()
    print(f"{SITE}/index.html")


def publish():
    """build/site -> the gh-pages branch, through a worktree at build/gh-pages."""
    wt = "build/gh-pages"
    have = subprocess.run(["git", "ls-remote", "--exit-code", "--heads", "origin", "gh-pages"], capture_output=True).returncode == 0
    if not os.path.isdir(wt):
        if have:
            subprocess.run(["git", "fetch", "origin", "gh-pages"], check=True)
            subprocess.run(["git", "worktree", "add", wt, "gh-pages"], check=True)
        else:
            subprocess.run(["git", "worktree", "add", "--detach", wt], check=True)
            subprocess.run(["git", "checkout", "--orphan", "gh-pages"], cwd=wt, check=True)
            subprocess.run(["git", "rm", "-rf", "--quiet", "."], cwd=wt, check=True)
    for name in os.listdir(wt):
        if name != ".git":
            p = os.path.join(wt, name)
            shutil.rmtree(p) if os.path.isdir(p) else os.unlink(p)
    shutil.copytree(SITE, wt, dirs_exist_ok=True)
    subprocess.run(["git", "add", "-A"], cwd=wt, check=True)
    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=wt).returncode != 0:
        subprocess.run(["git", "commit", "-q", "-m", f"Pages: the demos, recorded from {sha}"], cwd=wt, check=True)
    subprocess.run(["git", "push", "-q", "origin", "gh-pages"], cwd=wt, check=True)
    print("pushed gh-pages")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--publish", action="store_true")
    a = ap.parse_args()
    if a.publish:
        publish()
    else:
        build(set(a.only.split(",")) if a.only else None)


if __name__ == "__main__":
    main()
