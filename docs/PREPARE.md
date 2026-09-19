# Preparing Data for backlot-64

The engine is assembly plus a contract for its data. This file is the contract as instructions: what each asset type is, how to make it, which tool turns it into engine data, and what to check before it ships. It is written for an agent as much as for a person: follow it literally and the result will run on the chip.

Every asset goes through a quantiser that enforces the VIC-II's real colour rules. The quantiser reports what it had to change. Read the report. A high repair count means the source fought the hardware, and the fix is upstream in the art, not in the tool.

---

## The rules underneath everything

- 16 colours, fixed. Names and hex are in `art-style.md`.
- Multicolour pixels are 2 wide by 1 tall. Draw at 160 x 200 thinking, render at 320 x 200.
- A character cell (4 x 8) shows 3 shared colours plus 1 of the first 8.
- A bitmap cell (4 x 8) shows 1 background plus 3 of any 16.
- A sprite (12 x 21) shows 3 colours plus transparent.
- Blends are checkerboards of two colours within 2 luminance steps (3 for textured surfaces). See `docs/ART.md`.

---

## Asset types

### Set (a cutscene background)

**What:** a full-screen scene with no actors in it. The ground where actors will stop must be flat or gently textured, because parked objects composite over it.

**Make it:** generate at 1536 x 1024 with the gen-image skill against `art-style.md`. Say explicitly: no vehicles, no people, the road clear. For reflections on wet ground, ask for clean vertical streaks of flat colour with wobbly edges, two to four pixels wide, dark between them, no speckle. Speckle quantises to noise; streaks quantise to bands the shimmer can move.

**Convert:** `b64quant.py still in.png preview.png --bin=out.still --shimmer-from=<row>` where the row is the first cell row of the reflective ground. The `.still` is 10 KB: background, bitmap, screen, colour, then the shimmer cell list.

**Check:** repaired cells under 300 of 1000 and a damage score under 4000. Look at the preview at 2x. Neon text must still read.

### Object (something that moves as sprites and parks as a block)

**What:** a vehicle or prop that must be pixel-identical as sprites and as a bitmap block. The sprite rule wins: three colours plus transparent for the whole object.

**Make it:** generate on a plain black background with a dark grey floor, the subject filling the frame, from the view the game needs (side, three-quarter). State the three colours in the prompt: body colour, outline black, one accent. Wheels round and fully visible.

**Convert:** `b64object.py in.png out.b64o <gw> <gh> --colours=black,<body>,<accent> --key=black,dgray --shadow --wheels=auto --still=<set.still> --at=<cx>,<cy> --patch-still=<set-parked.still> --preview=preview.png --lights=<dx>,<dy>,<radius>,<lamp>:<colour>/<frames>,...;...`. The lights section declares the object's light sources: for each, its offset from the object's top-left in pixels, the radius in cells it lights, whether it has a lamp sprite, and its pattern of (colour, frames) with colour 0 for off. A police bar is two lights: `40,-6,11,1:2/8,0/8;52,-6,11,1:0/8,6/8`. The engine draws the lamp sprites and, with a baked lighting file, lights the set from them; the script only turns them on with LIGHTS. The keys are every background colour to make transparent; list the floor. `--still/--at` composites the block over the set at its parking cell and writes a patched set whose cells there use the same reduced colours, so parking changes no pixel outside the object. Use the patched set as the scene's set.

**Check:** the preview shows sprites left and block right; they must match. The tool prints the wheels it found; if it finds none, the tyres are not black or are touching a keyed colour. Repaired block cells should be under 15. Then prove it in the emulator: capture a frame before and after the park and diff them; only overlay pixels may differ.

### Lighting states (relighting a set without touching its bitmap)

**What:** a file of 2 KB states, each a background byte plus 800 screen and 800 colour bytes for the visible rows, for one set. The engine applies a state with `b64_cut_light` or the LIGHT opcode in a base-phase vertical blank.

**Make it:** `b64light.py <set.still> <out.bin> dusk --steps 32` for a day-to-night ramp. For an object's own lights, `b64light.py <set.still> <out.bin> object <obj.b64o> --x0 24 --xstep 8 --npos 40 --y 162`: one state per light, position and pattern colour, with the layout written into state 0's padding so the engine finds the state for (light, position, colour) itself. The object's position is quantised to `xstep` pixels; `npos` states cover the path; `--y` is the object's VIC y in the scene. A red-and-blue bar over 40 positions is 81 states, 162 KB. Add `--preview <prefix>` to write PNGs of a few states. Pack the file as a slot. A script applies one state with `V_LIGHT SLOT, v` (v in a variable), or turns an object's lights on with `V_LIGHTS <lightfile>, <lamp sprite>, 1` and off with `..., 0`; from then on the engine lands the right map whenever the object is drawn and its pattern or position changes.

**Check:** look at the previews first; in the emulator, screenshot consecutive frames through the strobe (the frame-counter watch, not wall-clock sleeps, since the strobe's period is eight frames and a fixed interval samples one phase). The background colour is one register, so colour-00 pixels do not change per cell; a set that must be lit locally should draw its lit surfaces in cell colours, not the background.

### Portrait (a big picture for about screens and dialogue)

**What:** a character block, 16 x 12 cells for a three-quarter view or 20 x 8 for a profile, on a plain background.

**Convert:** `b64quant.py block in.png preview.png <cw> <ch>`. Repairs under 80 of 192 is fine for generated art; under 20 for hand-drawn.

### Script (a scene, a mission, a behaviour)

**What:** p-code for the engine's VM. Everything a game decides. Nothing of it is resident: the VM reads it from the REU through the page cache.

**Make it:** a `.s` file of `V_*` macro lines (`include/b64.inc`), one instruction per line, in `.segment "SCRIPT"`. Variables are indices 0-31; name them with `=` at the top. Labels are jump targets. A scene is a main thread that directs and a draw thread, spawned first, that submits sprites every frame and yields.

**Convert:** `ca65 -t c64 -I include -I build -o scene.o scene.s` then `ld65 -C script.cfg -o scene.bin scene.o`. Add `slot SCENE $xxxxxx build/scene.bin` to `reu.manifest`. The resident code starts it with `b64_reu = SLOT_SCENE`, A/X = entry offset, `jsr b64_vm_start`, and calls `b64_vm_tick` once per frame.

**Check:** run it; if it stops or skips, assemble the VM with `-DVM_TRACE` and read the dispatch ring at $E100 through the monitor (thread, offset per dispatch, decoded against the `.bin`). Strings must end in 0 and stay under 40 characters.

### Tileset (playfield art)

**What:** metatiles of 4 x 4 cells drawn on the canvas DSL in `b64tileset.py`, under the region's three shared colours. Core tiles never use shared colour 2. See `docs/ART.md` section 7 for the region palettes.

**The colour budget.** A cell's colour is packed into its screen code (the low four bits), so each colour value has twelve codes. A tileset may use at most twelve characters that show a given cell colour; a multicolour character with no '11' pixel pairs never shows the cell colour and goes wherever there is room. The tool prints the count per colour value and stops, naming the colour, when one is over. Over means redraw: fewer distinct shapes in that colour, or move a material to a shared colour.

**Format:** charset (2 KB) at +$0000, metatiles by row (4 KB) at +$0800, the same by column at +$1800, properties (256 bytes) at +$2800, heights (256 bytes) at +$2900, padded to 12 KB.

**Heights.** Every solid metatile (`P_SOLID`) stands a height in storeys of 8 pixels, 1 to 15, which aircraft must clear; every other metatile stands none. Give it as the fourth argument of `ts.add`; the tool stops on a solid metatile without one, or a height on anything else. The air physics module reads the table (`PHYSICS.md`, heights). Keep a building's roof and facade metatiles at one height: they are shared by every building that uses them.

**Check:** the tool warns on dithers too far apart in luminance. Fix the art, do not silence the warning.

**Roads.** Traffic reads the world, not a route table: a road metatile carries the direction bits of the ways a car may drive it (`P_ROAD_E`, `_W`, `_S`, `_N`; a crossing has all four), and is 32 pixels across with two lanes whose centres are 8 and 24 pixels in. Eastbound traffic keeps to the lane at 24 (the south half), westbound to 8, southbound to 8 (the west half), northbound to 24: driving on the right. A one-way street sets one bit. A road that ends leads onto a metatile without the bit, and a car there leaves. `examples/traffic` drives on these rules; a tileset whose roads keep them gets its traffic for nothing.

### World

`b64world.py` writes the 2048 x 2048 metatile map and the region table. Region borders need a band of core-only metatiles at least one screen wide on both sides.

### REU image

`b64pack.py reu.manifest build/world.reu build/slots.inc`. Nothing in assembly hard-codes an REU address; use the slot symbols.

---

## Prompting the image model

Prepend nothing; the skill prepends `art-style.md`. In the per-image prompt, state:

1. The subject and the view.
2. The background: plain black with a dark grey floor for objects and portraits; the full scene for sets.
3. The colours by name, from the 16.
4. What must be fully visible (wheels, light bar, text on a sign).
5. What must be absent (people, vehicles, extra text, gradients, speckle).

Generate three candidates for objects and portraits, two for sets. Pick by: fidelity to the brief, flatness of shading, and how many cells the quantiser repairs. Keep the winner in `images/`, the candidates in `images/archive/`, and write the reasoning in `selection.json`.

---

## Acceptance in the emulator

A converted asset is not done until it has been seen running in `x64sc`. Use `-warp -limitcycles N -exitscreenshot` for a frame at a known time, or the remote monitor for a sequence. For anything that transforms on screen, diff frames before and after. The engine's benchmark counter on the HUD is the frame budget check for playfield work.

---

## When the tool fights you

- Many repaired cells in a set: the art has too many colours per 8 x 8 region. Ask for flatter shading, fewer hues per surface.
- Greys turning into hues: low-saturation pixels only map to greys; if a hue appears where grey was expected, the source pixel was more saturated than it looked. Ask for neutral greys.
- A dark band under an object: a background colour was not keyed. Add it to `--key`.
- Wheels not found: tyres must be black and not touch a keyed colour; the floor must be a different colour from the tyres.
- Spokes missing or wheels not turning: the wheel discs were smaller than 12 pixels; ask for larger wheels or draw them.
