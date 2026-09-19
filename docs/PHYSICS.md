# Physics: one core, a mover per way of moving

Designed 2026-09-18 with the user. A game has people on foot, cars, boats, helicopters, planes, bullets and debris; each moves by different rules, but all of them need the same things underneath: positions and velocities, the map under them, walls, each other, and an end to the work when nothing is happening. So the physics is a shared core and a set of movers, one per way of moving, in one pinned module (`modules/physics`).

Status, 2026-09-18: the core; on foot and driving (the ground module); on foot and boats (the water module); on foot and helicopters (the air module); each swapped in over the ground module as the player takes to the water or the air, and back on landing; and the collision module with shots and grenades. All built and checked (`modules/physics`, `modules/collision`, `examples/physics`, `make run-physics`, `make run-boats`, `make run-sky`). Next: planes, debris, and a cost pass.

---

## 1. The movers

| Mover | What moves | Model | Costs per body at 1 MHz |
|---|---|---|---|
| **foot** | the player, pedestrians, police on foot | Kinematic. Eight directions, walk and run speeds reached in a few frames, walls slide it, no momentum of its own. Knocked down by a hit: it tumbles with friction for a second, then gets up | measured in `budgets.txt` |
| **wheels** | cars, trucks, bikes, scooters | Tyres. Speed along the heading and across it; throttle, brake and reverse; steering scaled by speed and reversed when reversing; grip takes away the sideways speed a frame at a time, and what grip cannot take the car slides on (a skid); the handbrake takes most of the grip away (a drift); the surface under it sets grip, drag and top speed | |
| **hull** | boats (speedboat, launch, jet ski) | The car's frame without grip: the sideways speed loses a share of itself each frame (an eighth, a quarter) instead of a fixed amount, so a boat carries its momentum through a turn and slides out wide, throwing spray. Pulling back is reverse thrust, not a brake; with the throttle off, drag takes a thirty-second of the speed a frame. The rudder bites only while water flows past it: half as much when slow, and when still only with thrust held (the propeller's wash). Land is a wall. Airboats, which also cross marsh, are still to come | measured in `budgets.txt` (`boats.*`) |
| **air** | helicopters, planes | Altitude as a third coordinate. Fire held climbs, to a pixel a frame and a ceiling of 112 pixels; let go, the craft settles at up to half a pixel a frame onto whatever is under its box, the ground or a roof. Flying, the stick thrusts it in the world's directions and it turns to face its way; drag takes a thirty-second of its speed a frame, so it drifts on. Down, it cannot move along the ground. A building is a wall only below its height, and bodies 8 pixels or more apart in height pass each other. A plane goes where it points: up is the throttle, to 3.5 pixels a frame; at 2 or more (flying speed) fire climbs and letting go holds its height; slower it sinks, which is how it lands; down brakes on the ground and in the air throttles back to 1.5; it turns 2 a frame in the air and 1 on the ground | measured in `budgets.txt` (`sky.*`, `plane.*`) |
| **thrown** | bullets, thrown things, debris | Bullets step in short hops so they cannot pass through a wall, and hit the first body in their way. Thrown things arc under gravity, bounce off the ground and walls, and go off. Debris ignores everything but the ground | in the collision module (below) |

A body's mover is fixed when it is added; a person getting into a car is the game removing a foot body and waking a wheels body.

---

## 2. The core

**Numbers.** A position is 16.8 fixed point in world pixels (a fraction byte, then 16 bits). A velocity is 8.8 signed, in pixels a frame. Altitude is 8.8, 0 on the ground. A heading is one byte, 256 to a turn, 0 east and 64 south (screen y runs down), so a sprite frame of 16 headings is `(heading + 8) >> 4`. Sines come from a 256-byte table in 1.7 fixed point.

**Multiplying.** The 6502 has no multiply; the core multiplies 8 by 8 bits with a table of quarter squares, `a * b = f(a + b) - f(|a - b|)` with `f(x) = x * x / 4`, 1 KB for x up to 510. *After Codebase64, "Seriously fast multiplication". Changed: one table of f instead of four offset tables, so 1 KB instead of 2, for a few cycles more.*

**The map.** Each body keeps the property bytes of the 3 x 3 metatiles around it, fetched from the REU when it crosses into a new metatile (three 3-byte DMAs). Every question a mover asks of the map (what surface, is it a wall) is answered from that cache.

**Walls.** A body is a box: half-width and half-height from its class, the same at every heading (a turning car does not grow into a wall). It moves along x, and if its box then touches a wall it goes back and its x velocity turns round with a quarter of its speed; the same along y. What a mover counts as a wall is its own: walls and water for feet and wheels, anything but water for a hull, nothing above a building's height for air.

**Each other.** Two boxes that overlap are pushed apart along the axis they overlap least, and exchange velocity along it by their masses: each gets `(1 + e) * v * m_other / (m_self + m_other)` of the closing velocity, e a quarter, with the ratio from a 16 x 16 table of masses. Each takes damage from the change. A body far lighter than the other is knocked down (feet) or simply shoved.

**Rest.** A body with no input and no speed for 32 frames sleeps, costing a test a frame, until an impulse, a collision or input wakes it. This, not a smaller world, is what lets a stock machine carry the player, a few wrecks and a street of pedestrians at once.

**Each frame** (`phys_step`): every awake body's mover turns its input into velocity; the core moves it along x then y against the walls, updates its map cache and surface; then every pair of bodies that could touch is tested and resolved.

---

## 3. Modules: one core source, a module per kind of play

The pinned area is 8 KB, and one module holding the core and every mover would not fit it. So the movers are grouped by the kind of play they serve, each group a module of its own: **ground** (foot and wheels), **water** (hull, and foot for docks and beaches), **air** (helicopter and plane, and foot). The core is one source that every module assembles, so each binary carries its own copy of the multiply, the map cache and the wall and pair tests. The user accepted the repetition (2026-09-18): bytes in the REU cost nothing, and each module stays small enough to pin.

The body tables live at a fixed address outside the modules' code, so swapping modules when the player changes mode (on foot to a boat, a boat to a helicopter) keeps every body where it was. The swap is one 6.5 KB fetch of $6000-$79FF (code to $71FF, the shared tables at $7200, the module's workspace after); the tables at $7A00, each body's map cache among them, are never touched, and the module's own workspace holds nothing from one frame to the next. A body whose mover the loaded module does not carry holds still (a car on the beach while the water module is in) and its own mover takes up from rest when its module returns. A game calls every module through the jump table at its start (`PHYS_STEP` and the rest in `physics.inc`), never at an address inside one, so the same calls work whichever module is in. After each fetch it calls `PHYS_RESUME` (+15), which reloads every body's map cache in the incoming module's own form: the air module folds heights into its cache, and must not trust entries the ground module wrote.

**Heights.** The tileset carries a second table of 256 bytes beside the properties: each metatile's height in storeys of 8 pixels, which a solid metatile must have and nothing else may (`PREPARE.md`, tilesets; Bellamar's buildings all stand six storeys, 48 pixels, its palms three). The air module fetches it from the tileset's REU address (`phys_tiles`, set by the game at the start) and, when it loads a body's map cache, puts each solid metatile's height in the low four bits of its properties, the road bits, which a building never has. Its wall test for an aircraft then reads a solid metatile as a wall only if it stands higher than the craft, and the craft's floor is the tallest thing under any corner of its box. The mover leaves the craft's height above that floor in `pb_agl` for the game to draw: a craft is drawn raised by half of it, with its outline in black where it would stand. Roofs are drawn at ground level, so a craft resting on one is drawn on it, with no shadow. The classes are shared by every module, so a body keeps its box and mass through a swap. `make check` swaps twice in the coast tape and requires that the body tables are byte for byte the same before and after each fetch and that the module in place is the one asked for (`boats.swap`). Beside the physics module sits the **collision** module, which reads the same tables: the questions a game and its scripts ask (does this line reach a wall, which body is at this point or in this box, is anything in this zone) and the swept test bullets need, stepping a path so a fast thing cannot pass through a wall or a body. Detection and response for moving bodies stay in the physics modules, because they happen in the same frame on the same data.

## 4. The module and its interface

Physics runs every frame for every body, so it is pinned (`MODULES.md` section 1): loaded once into the game's module region at $6000 when play starts, 7 KB at most, linked for $6000 with `pinned.cfg` against the engine's labels. Its zero page is $80-$8F.

| Entry | Offset | In | Out |
|---|---|---|---|
| `phys_init` | +0 | | every body free |
| `phys_add` | +3 | A = mover, Y = class; `phys_x`, `phys_y` (16-bit world pixels), `phys_a` (heading) | X = the body, C=1; C=0 if none is free |
| `phys_remove` | +6 | X = body | |
| `phys_step` | +9 | | every body one frame |
| `phys_push` | +12 | X = body; `phys_x`, `phys_y` = a velocity change, 8.8 | the body woken and pushed |
| `phys_resume` | +15 | after this module was fetched over another | every body's map cache again, in this module's form |

The body table is a set of arrays at addresses the build exports (`build/physics_syms.inc`, beside the constants in `modules/physics/physics.inc`), so a game reads positions, headings, altitudes and flags directly and writes each body's input byte: bit 0 up or throttle, 1 down or brake, 2 left, 3 right, 4 fire (run, handbrake, climb). Before the first body is added it sets `phys_world` (the world map's REU address) and `phys_tiles` (the tileset's, for heights).

---

### The collision module

`modules/collision`, 2.4 KB in region A at $8000, zero page $90-$9F, reading the body tables at their fixed addresses. Its jump table:

| Entry | Offset | In | Out |
|---|---|---|---|
| `col_init` | +0 | | no shots |
| `col_line` | +3 | `col_x0/y0` to `col_x1/y1` (at most 255 pixels a side), `col_mask` (wall bits), `col_skip` (a body to ignore, $FF none) | C=1 on a hit: `col_body` (or $FF for a wall), `col_hx/hy` (the last clear point, or the point in the body) |
| `col_point` | +6 | `col_x0/y0`, `col_skip` | C=1, `col_body`: a body whose box holds the point |
| `col_box` | +9 | `col_x0/y0` - `col_x1/y1`, in order | `col_bits`: a bit a body whose box meets it; C=1 if any. A zone is a box asked about |
| `col_tile` | +12 | `col_x0/y0` | A = the properties of the metatile there (one byte of DMA, none if it is the last one asked) |
| `col_near` | +15 | X = body, A = reach | Y = the nearest other body within reach, C=1 |
| `shot_fire` | +18 | `col_x0/y0`, A = heading, Y = speed, X = the firer | C=1 if a shot was free (eight at once) |
| `shot_step` | +21 | | every shot and every thrown thing one frame |
| `throw_fire` | +24 | `col_x0/y0`, A = heading, Y = speed | C=1 if a grenade was free (four at once) |

**Debris.** Up to 12 pieces at once, each with a height: thrown out in a spread of headings, they fall under gravity, bounce off the ground at half their speed and lose half their speed along it, and when a bounce is too weak to matter (under an eighth of a pixel a frame) a piece stops, lies 6 frames and goes, so a piece is a sprite only while it is doing something (at most 48 frames). Debris ignores everything but the ground: no wall stops it, no body feels it. A game throws a burst with `debris_burst` (+27: `col_x0/y0`, A = pieces, Y = speed), and a blast throws `db_blast` pieces, which the game sets (none after `col_init`). The collision step costs a test when no piece is live (`db_live`). Every piece is a sprite: in the city scene, whose frame has no time to spare, six pieces in the air cost about half the frames while they fly (`debris.frames_lost`). A game asks for debris where it has the frame time, or throws fewer pieces.

**Height.** A question is asked at a height, `col_z` (0, the ground, unless the game sets it): `col_point`, `col_box` and `col_line` see only bodies within 8 pixels of it, and `col_near` only bodies within 8 pixels of the asker's own height. A shot flies at its firer's height, so shots from the street pass beneath a helicopter 8 pixels or more up; a blast reaches 16 pixels up. Walls stop a shot at any height for now: the collision module does not read the tileset's heights.

A traced path steps 4 pixels at a time along its longer axis, less than the smallest body (6), and tests only the bodies whose boxes meet the path's box, so a long trace across an empty street costs little and nothing can be stepped over. A shot is traced from where it was to where it is going each frame: a wall stops it; a body it meets takes 16 damage and a quarter of the shot's speed as a push, and is knocked down if on foot. The last stop is left for the game to draw (`fx_x/y`, `fx_t`). `make check` fires shots in the demo's tape and requires that no shot is ever inside a wall and that every stopping point is clear of one (`collision.shots`).

A thrown thing (a grenade) has an altitude: tossed up at a pixel a frame, it falls at 12/256 of a pixel a frame each frame, so it rises 11 pixels and lands 40 frames on. On the ground it bounces at a quarter of the speed it landed with and loses half its speed along the ground, so a grenade tossed at 2 pixels a frame settles about 90 pixels away. Along each axis it asks `col_tile` about the point it is moving to, and an axis that would enter a wall turns back at half speed, so it rebounds off buildings. It passes over bodies. After 70 frames it goes off: every body within 40 pixels on both axes is pushed away from it, 2 pixels a frame within half the reach and 1 beyond, takes 20 damage a pixel of push, is woken and marked with an impact of 32, and is knocked down if on foot. The flash is left for the game to draw (`fx_x/y`, `fx_t` 12, `fx_k` 2; a shot's stop is `fx_k` 1). The game draws a thrown thing twice: its shadow on the ground and itself raised by its altitude (`th_zh`). The demo draws a blast as four dots on a ring growing 3 pixels a frame. `make check` throws grenades in the tape and requires that none is ever inside a wall and that every body within reach of a blast shows it (`collision.thrown`).

## 5. Classes

Each mover has a small table of classes; a game will supply its own from its roster (for Priors-64, `assets/vehicles.json`), and the module's built-in ones are what the example uses.

| Mover | Class | Half size | Mass | Character |
|---|---|---|---|---|
| foot | walker | 3 x 3 | 1 | walk 1.0, run 1.75 px/frame |
| wheels | sedan | 7 x 7 | 8 | top 3.5 px/frame, middling grip |
| wheels | sports | 7 x 7 | 6 | top 4.5, quick, grippy until it is not |
| wheels | truck | 9 x 9 | 15 | top 2.5, slow to turn, rams everything |
| wheels | bike | 4 x 4 | 3 | top 4.0, turns sharply, little grip |
| hull | speedboat | 7 x 7 | 5 | top 4.0, slides an eighth of its sideways speed away a frame |
| hull | launch | 9 x 9 | 12 | top 2.5, slow to turn, loses a quarter sideways |
| hull | jet ski | 4 x 4 | 2 | top 4.5, quick to turn and to speed |
| air | helicopter | 8 x 8 | 6 | climbs a pixel a frame to 112, top about 3 pixels a frame |
| air | plane | 8 x 8 | 5 | top 3.5, flies from 2, climbs and sinks at 3/4 of a pixel a frame |

---

## 6. What it costs, and what is measured

`make check` plays `examples/physics`'s input tape: walk to a sedan, get in, drive into the sports car and the truck, brake, reverse, turn, drift, stop, get out, walk, fire, throw grenades. It requires:

- no body's box ever has a corner in a wall, judged from the world map file and the tileset's properties rather than the module's own cache (800 frames: none);
- the first ram conserves momentum along its axis, allowing for the engine's push that frame (3,936 before, 4,032 after, the push 64, in mass x 1/256 pixel a frame);
- the abandoned car comes to rest and sleeps (by frame 530, before the grenades);
- two runs of the tape end in the same state.

`make run-boats` is the same example built at the coast (`-D COAST`), where the road at metatile row 1000 meets the sea: sand, palms, and water from pixel 54,528 east. Its tape walks the player to a speedboat moored at the water's edge and gets in, which brings in the water module; rams the launch, turns away on the propeller's wash, slides south-west through a turn and runs into the beach; drifts to a stop against it, gets out on the sand, which brings the ground module back, and walks up the beach. Getting out tries south, west, north and east of the vehicle, 18 pixels away, for a place where a walker's box is clear of walls and water, and stays aboard if there is none. It requires that no body's box ever has a corner in what its own mover counts as a wall (land for a boat), the swaps above, that the boat slides (its sideways speed peaked at 394/256 of a pixel a frame, spray for 43 frames) and meets the shore, that the launch is rammed, that the player ends on foot on land with the ground module in, and that two runs end alike. The step costs 3,885 cycles at the median and 9,680 at worst; 2 frames of 700 are lost, the swaps among them.

`make run-plane` has a light plane on the road beside the player. The tape gets in, which brings the air module; opens the throttle along the road and at flying speed climbs to 75 pixels; flies a full circle over the blocks, which brings it back onto the road's line; throttles back and sinks onto the road, brakes to a stop, and gets out, which brings the ground module back. The first tape climbed for 50 frames, turned at 37 pixels over a six-storey block and flew into it: 120 damage, and the walls check had nothing to say because the building stopped it. It requires no body in its walls (for the plane, a building standing higher than it), the swaps, the plane over buildings in the air and through all 16 headings, down on the road and asleep at the end, the player on land with the ground module in, and two runs alike (`plane.*`).

**The layout.** Each module loads $6000-$79FF: code to $71FF, the shared tables at $7200 (the multiply's quarter squares, then the sine at $7600 and the mass shares at $7700, where the collision module reads them), the module's workspace after. The body tables start at $7A00 and end at $7BF7, 9 bytes short of $7C00: the next field added to every body needs room made first. The air module, with the helicopter and the plane, first outgrew a code area that ended at $6FFF; the tables moved up 512 bytes for every module.

`make run-debris` plays the city's start: get into the sedan, drive into the parked cars, back off, get out, walk clear and toss a grenade at the wrecks. The player's car throws out three pieces when it is hit hard (an impact of 16, a pixel a frame of change; the tape's rams measure 16 to 22), once a crash, on the frame the impact first crosses the line; the blast throws six. It requires a burst from a crash and one from a blast, no piece ever below the ground and every piece on the ground as it goes, no body in its walls, and two runs alike (`debris.*`), and budgets the physics step, the collision step with its debris, and the frames lost.

`make run-hover` starts in the air module with a helicopter lifting off the pavement across the road from the player, held 32 pixels up by a small pilot in the example that climbs when under the height and settles when over it, until it lets go and lands. The player fires three shots at it, which pass beneath and stop at the building beyond, and tosses a grenade under it, whose blast goes off within reach but does not reach that high; once it is down, the same shots hit it. It requires that the helicopter is never hit while 8 pixels or more up though shots cross its footprint, that a blast within reach while it is 16 or more up does not mark it, that it is hit on the ground, no body in its walls, and two runs alike (`hover.*`).

`make run-sky` is the same example with a helicopter parked on the road beside the player (`-D SKY`). Its tape walks the player to it and gets in, which brings in the air module; climbs and flies south over a six-storey block, brakes and settles onto its roof; climbs again, flies back north and settles onto the road; and gets out, which brings the ground module back. In an aircraft fire is the climb, so getting out is fire tapped with the stick pulled down, on the ground. It requires that no body's box ever has a corner in what its mover counts as a wall (for the helicopter, a building standing higher than it, judged from the map and the tileset's heights), the swaps as for the boats, that the helicopter is over the building in the air (156 frames), rests on its roof at 48 pixels (34 frames) and never passes the ceiling (highest 90), that the player ends on foot on land with the ground module in, and that two runs end alike. The step costs 3,159 cycles at the median and 6,690 at worst; 2 frames of 700 are lost.

Measured over every step of the 800-frame tape, nine bodies with up to six awake: `phys_step` 6,358 cycles at the median and 15,000 at worst, interrupts included, and 39 frames lost in 800. The worst step is a three-car pile-up, two pairs resolved in one frame; the median is dominated by the wheels mover. The costs are budgeted (`physics.*`); the stock machine needs another pass before a game carries this many cars awake at once.

**What the measurements changed while it was built.** The first step cost 13,000 cycles for nine bodies. Testing every pair fully was 2,400 of it; a compact list of live bodies with a one-byte distance test first brought pairs to under a thousand. A box wholly inside its metatile skips the wall test (the body stands in it, so it is no wall), an axis without velocity skips its move, and the map cache is consulted only when a move crosses a metatile edge. The wheels mover cost about 1,000 cycles a car a frame, most of it four or five signed multiplies turning the car's frame into the world's; a multiply by zero now costs a test (a car on an axis heading, a car standing), a speed under a pixel a frame skips the high product, and a car whose heading and speeds did not change keeps last frame's world velocity. Frames lost over the tape fell from 81 to 37 of 800, with every body's path unchanged to the bit (the momentum and repeat checks give the same figures).
