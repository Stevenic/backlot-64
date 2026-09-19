# Physics: one core, a mover per way of moving

Designed 2026-09-18 with the user. A game has people on foot, cars, boats, helicopters, planes, bullets and debris; each moves by different rules, but all of them need the same things underneath: positions and velocities, the map under them, walls, each other, and an end to the work when nothing is happening. So the physics is a shared core and a set of movers, one per way of moving, in one pinned module (`modules/physics`).

Status, 2026-09-18: the core, on foot and driving (the ground module), the split into modules with the body tables at fixed addresses, and the collision module with shots are built and checked (`modules/physics`, `modules/collision`, `examples/physics`, `make run-physics`). Next, in order: thrown things and debris, water, air.

---

## 1. The movers

| Mover | What moves | Model | Costs per body at 1 MHz |
|---|---|---|---|
| **foot** | the player, pedestrians, police on foot | Kinematic. Eight directions, walk and run speeds reached in a few frames, walls slide it, no momentum of its own. Knocked down by a hit: it tumbles with friction for a second, then gets up | measured in `budgets.txt` |
| **wheels** | cars, trucks, bikes, scooters | Tyres. Speed along the heading and across it; throttle, brake and reverse; steering scaled by speed and reversed when reversing; grip takes away the sideways speed a frame at a time, and what grip cannot take the car slides on (a skid); the handbrake takes most of the grip away (a drift); the surface under it sets grip, drag and top speed | |
| **hull** | boats, airboats | The wheels model with little grip and much drag, on water only: land is a wall. Airboats also cross marsh | planned |
| **air** | helicopters, planes | Altitude as a third coordinate. A helicopter hovers, climbs and moves any way; a plane keeps a minimum speed and turns harder the faster it goes. Buildings are walls only below their height. The craft is drawn raised and its shadow on the ground | planned |
| **thrown** | bullets, thrown things, debris | Bullets step in short hops so they cannot pass through a wall, and hit the first body in their way. Thrown things arc under gravity and bounce. Debris ignores everything but the ground | planned |

A body's mover is fixed when it is added; a person getting into a car is the game removing a foot body and waking a wheels body.

---

## 2. The core

**Numbers.** A position is 16.8 fixed point in world pixels (a fraction byte, then 16 bits). A velocity is 8.8 signed, in pixels a frame. Altitude is 8.8, 0 on the ground. A heading is one byte, 256 to a turn, 0 east and 64 south (screen y runs down), so a sprite frame of 16 headings is `(heading + 8) >> 4`. Sines come from a 256-byte table in 1.7 fixed point.

**Multiplying.** The 6502 has no multiply; the core multiplies 8 by 8 bits with a table of quarter squares, `a * b = f(a + b) - f(|a - b|)` with `f(x) = x * x / 4`, 1 KB for x up to 510. *After Codebase64, "Seriously fast multiplication". Changed: one table of f instead of four offset tables, so 1 KB instead of 2, for a few cycles more.*

**The map.** Each body keeps the property bytes of the 3 x 3 metatiles around it, fetched from the REU when it crosses into a new metatile (three 3-byte DMAs). Every question a mover asks of the map (what surface, is it a wall) is answered from that cache.

**Walls.** A body is a box: half-width and half-height from its class, the same at every heading (a turning car does not grow into a wall). It moves along x, and if its box then touches a wall it goes back and its x velocity turns round with a quarter of its speed; the same along y. What a mover counts as a wall is its own: P_SOLID for feet and wheels, anything but water for a hull, nothing above a building's height for air.

**Each other.** Two boxes that overlap are pushed apart along the axis they overlap least, and exchange velocity along it by their masses: each gets `(1 + e) * v * m_other / (m_self + m_other)` of the closing velocity, e a quarter, with the ratio from a 16 x 16 table of masses. Each takes damage from the change. A body far lighter than the other is knocked down (feet) or simply shoved.

**Rest.** A body with no input and no speed for 32 frames sleeps, costing a test a frame, until an impulse, a collision or input wakes it. This, not a smaller world, is what lets a stock machine carry the player, a few wrecks and a street of pedestrians at once.

**Each frame** (`phys_step`): every awake body's mover turns its input into velocity; the core moves it along x then y against the walls, updates its map cache and surface; then every pair of bodies that could touch is tested and resolved.

---

## 3. Modules: one core source, a module per kind of play

The pinned area is 8 KB, and one module holding the core and every mover would not fit it. So the movers are grouped by the kind of play they serve, each group a module of its own: **ground** (foot and wheels), **water** (hull, and foot for docks and beaches), **air** (helicopter and plane, and foot). The core is one source that every module assembles, so each binary carries its own copy of the multiply, the map cache and the wall and pair tests. The user accepted the repetition (2026-09-18): bytes in the REU cost nothing, and each module stays small enough to pin.

The body tables live at a fixed address outside the modules' code, so swapping modules when the player changes mode (on foot to a boat, a boat to a helicopter) keeps every body where it was. Beside the physics module sits the **collision** module, which reads the same tables: the questions a game and its scripts ask (does this line reach a wall, which body is at this point or in this box, is anything in this zone) and the swept test bullets need, stepping a path so a fast thing cannot pass through a wall or a body. Detection and response for moving bodies stay in the physics modules, because they happen in the same frame on the same data.

## 4. The module and its interface

Physics runs every frame for every body, so it is pinned (`MODULES.md` section 1): loaded once into the game's module region at $6000 when play starts, 7 KB at most, linked for $6000 with `pinned.cfg` against the engine's labels. Its zero page is $80-$8F.

| Entry | Offset | In | Out |
|---|---|---|---|
| `phys_init` | +0 | | every body free |
| `phys_add` | +3 | A = mover, Y = class; `phys_x`, `phys_y` (16-bit world pixels), `phys_a` (heading) | X = the body, C=1; C=0 if none is free |
| `phys_remove` | +6 | X = body | |
| `phys_step` | +9 | | every body one frame |
| `phys_push` | +12 | X = body; `phys_x`, `phys_y` = a velocity change, 8.8 | the body woken and pushed |

The body table is a set of arrays at addresses the build exports (`build/physics_syms.inc`, beside the constants in `modules/physics/physics.inc`), so a game reads positions, headings and flags directly and writes each body's input byte: bit 0 up or throttle, 1 down or brake, 2 left, 3 right, 4 fire (run, handbrake).

---

### The collision module

`modules/collision`, 1.6 KB in region A at $8000, zero page $90-$9F, reading the body tables at their fixed addresses. Its jump table:

| Entry | Offset | In | Out |
|---|---|---|---|
| `col_init` | +0 | | no shots |
| `col_line` | +3 | `col_x0/y0` to `col_x1/y1` (at most 255 pixels a side), `col_mask` (wall bits), `col_skip` (a body to ignore, $FF none) | C=1 on a hit: `col_body` (or $FF for a wall), `col_hx/hy` (the last clear point, or the point in the body) |
| `col_point` | +6 | `col_x0/y0`, `col_skip` | C=1, `col_body`: a body whose box holds the point |
| `col_box` | +9 | `col_x0/y0` - `col_x1/y1`, in order | `col_bits`: a bit a body whose box meets it; C=1 if any. A zone is a box asked about |
| `col_tile` | +12 | `col_x0/y0` | A = the properties of the metatile there (one byte of DMA, none if it is the last one asked) |
| `col_near` | +15 | X = body, A = reach | Y = the nearest other body within reach, C=1 |
| `shot_fire` | +18 | `col_x0/y0`, A = heading, Y = speed, X = the firer | C=1 if a shot was free (eight at once) |
| `shot_step` | +21 | | every shot one frame |

A traced path steps 4 pixels at a time along its longer axis, less than the smallest body (6), and tests only the bodies whose boxes meet the path's box, so a long trace across an empty street costs little and nothing can be stepped over. A shot is traced from where it was to where it is going each frame: a wall stops it; a body it meets takes 16 damage and a quarter of the shot's speed as a push, and is knocked down if on foot. The last stop is left for the game to draw (`fx_x/y`, `fx_t`). `make check` fires shots in the demo's tape and requires that no shot is ever inside a wall and that every stopping point is clear of one (`collision.shots`).

## 5. Classes

Each mover has a small table of classes; a game will supply its own from its roster (for Priors-64, `assets/vehicles.json`), and the module's built-in ones are what the example uses.

| Mover | Class | Half size | Mass | Character |
|---|---|---|---|---|
| foot | walker | 3 x 3 | 1 | walk 1.0, run 1.75 px/frame |
| wheels | sedan | 7 x 7 | 8 | top 3.5 px/frame, middling grip |
| wheels | sports | 7 x 7 | 6 | top 4.5, quick, grippy until it is not |
| wheels | truck | 9 x 9 | 15 | top 2.5, slow to turn, rams everything |
| wheels | bike | 4 x 4 | 3 | top 4.0, turns sharply, little grip |

---

## 6. What it costs, and what is measured

`make check` plays `examples/physics`'s input tape: walk to a sedan, get in, drive into the sports car and the truck, brake, reverse, turn, drift, stop, get out, walk. It requires:

- no body's box ever has a corner in a wall, judged from the world map file and the tileset's properties rather than the module's own cache (690 frames: none);
- the first ram conserves momentum along its axis, allowing for the engine's push that frame (3,936 before, 4,032 after, the push 64, in mass x 1/256 pixel a frame);
- the abandoned car comes to rest and sleeps;
- two runs of the tape end in the same state.

Measured after the tape, nine bodies with five awake: `phys_step` 4,521 cycles at the median and 6,551 at worst, interrupts included, and 51 frames lost in 690. That is too much for a stock machine with a game on top; the costs are budgeted (`physics.*`) and the next pass on them comes with the split.

**What the measurements changed while it was built.** The first step cost 13,000 cycles for nine bodies. Testing every pair fully was 2,400 of it; a compact list of live bodies with a one-byte distance test first brought pairs to under a thousand. A box wholly inside its metatile skips the wall test (the body stands in it, so it is no wall), an axis without velocity skips its move, and the map cache is consulted only when a move crosses a metatile edge.
