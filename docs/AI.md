# AI: scripts decide, the module executes

Asked for 2026-09-18 ("let's work on an advanced ai module now"). `PLAN.md` section 7 lists AI in three tiers: basic (state machines), aware (line of sight, flee and attack from what is seen, groups) and tactical (cover and flank, roadblocks and pincers, route planning). It also notes that Priors-64 wants the tactical tier, because the feel of a crime sandbox is in how the city reacts to you. This module is built toward that, on the physics and collision modules: it reads the bodies, asks the collision module what can be seen, and drives each body by writing the same input byte a player's stick writes.

Status, 2026-09-18: the first milestone is built and checked: perception, the behaviours below, panic that spreads, police that respond by heat and share what they see, and the events queue, with a demo, "the city reacts" (`make run-crowd`, `modules/ai`). It costs too much for a street of ten moving bodies at 50 ticks a second on a stock machine (section 4); the cuts that come next are in section 5.

---

## 1. The split

The rule is `PLAN.md` section 7's: scripts decide, hooks execute. A script (the game's p-code) picks a body's behaviour and its target: pursue the player, flee from this point, follow that officer. The module runs that behaviour every tick in native code, for as long as it lasts, and raises an event when something happens that the script may want to decide about: a body saw its target, lost it, heard a shot, panicked, arrived. Nothing a game decides is hard-wired into the module, and nothing that runs per body per tick is p-code.

## 2. The parts

**The brains.** Beside every physics body, a row of AI state at a fixed address in the game's hot state ($E100): the behaviour, its target (a body, or a point), the timer, the team, the alert level, whether the body sees its target, and where it last saw it. The game and its scripts read and write it directly, as they do the body tables.

**Perception**, for one body in three each tick (`PLAN.md` section 6.2's staggering). Sight: the target within range (120 pixels on the larger axis), within the body's facing cone (every way, once it is alert), and no solid metatile on the line to it (below); traced every other turn, what it saw kept between. What a body saw is kept: the last place, so a lost target is searched for where it was last seen. Hearing: a noise (a gunshot) has a place and a radius; every body inside it hears it. A body's alert level fades when nothing happens.

**Behaviours**, on the body's turn (one tick in three; between turns it holds the input it was given), each ending in the body's input byte:

| Behaviour | What the body does |
|---|---|
| idle | nothing: it stands, parks or hovers |
| wander | a new way every second or two; a wall ahead turns it |
| goto | to a point, slowing to stop there |
| follow | a body, keeping a distance |
| flee | away from a point or a body, running, until far enough; then calms |
| pursue | toward where its target will be (its position plus its velocity times 8 frames) while it is seen; to where it was last seen when not; searching after a while unseen |
| attack | pursue until in sight and in range; then stop, face the target and fire at a steady rate |
| search | to where its target was last seen; there, a look around; then gives up |

A desired heading becomes input by the mover: eight directions of the stick for a walker or a helicopter; steering toward the heading, with the throttle when it points roughly the right way, for a car or a boat. Whiskers look into the physics module's map cache 12 pixels in the direction of travel, ahead of the body's centre and of both sides of its box, and turn it (up to six ways, a quarter turn at a time) away from a wall before it walks into it. A car or a boat whose target is more than 3/8 of a turn off its nose backs round in a three-point turn.

**The city's reaction.** A civilian who hears a shot panics and flees from it, and a panicked civilian scares the calm ones near it, so fear spreads down a street. The police respond by heat, a level the game sets from the player's record: at 0 they patrol, at 1 they pursue a suspect, at 2 they attack on sight. The module offers the behaviours; the game's rules decide the response.

**Events.** A queue the game's scripts read: saw, lost, heard, panicked, arrived, gave up, fired. Until the VM waits on module events (roadmap step 15), a game reads the queue itself.

**Where it lives.** The module is 2.7 KB in region A at $8D00, beside the collision module, which it calls; its zero page is $A0-$AF. The brains are at $E100 in the game's hot state (`modules/ai/ai.inc`). A game fetches it once play starts, calls `AI_INIT`, sets each body's team, behaviour and target, and calls `AI_STEP` every tick before the physics step.

**Sight, a metatile at a time.** A line of sight is a walk over the metatiles the line crosses, each asked of the collision module (one byte of DMA), after Amanatides and Woo's grid traversal, with the distances to the next boundaries kept as integers scaled by dx and dy so a step is an addition. The first version traced the line with the collision module's own path test, 4 pixels at a step: about 20,000 cycles a trace, more than a frame. The walk costs 1,000 to 2,000.

**The police radio.** An officer who sees its target tells every officer after the same target: their last sighting becomes this one, and their count of turns unseen starts again. One memory for the force, as DMA's first design for the game that became GTA had a radio call to every police car.

## 3. What is measured

`make check` plays the crowd scene's tape (`examples/physics` built with `-D CROWD`): people about their business, two standing talking just out of earshot of the shot to come, three officers on their beat watching for the player, a cruiser parked. The player fires along the street, which the example makes heat 2, and runs. It requires that no officer goes on seeing the player through a wall for longer than its sight can lag (judged from the map, not the module); that the people within earshot flee at once and are farther from the shot 60 ticks on; that fear reaches people out of earshot; that the officers who heard close on the player or hold at firing range; that every police shot comes from an officer who sees the player; no body in its walls; two runs alike (`crowd.*`).

**What the measurements changed.** The first step cost 24,800 cycles at the median and 53,000 at worst. The sight trace was most of it (above). Behaviours moved onto the same one-in-three stagger as perception, the target's lead became a shift instead of a loop, and panic spreading rejects a far body on its low bytes before it measures: 5,900 at the median, 19,600 at worst. A walker's whiskers probed only the point ahead of its centre, so a building's corner caught the edge of its box and held it running on the spot; they now probe ahead at both sides of the box too. A car whose target sat inside its turning circle drove round it; one more than 3/8 of a turn off its nose now makes a three-point turn, backing with the other lock.

## 4. What it costs

The AI step 5,900 cycles at the median and 19,600 at worst with nine brains; the physics step 13,800 with ten bodies all moving. Together they do not fit a frame: the crowd scene runs at about 20 ticks a second (523 frames lost over 420 ticks). The step is budgeted as it is (`crowd.*`) and the cuts below are next.

## 5. Next, from other games (researched 2026-09-18)

The user asked for other engines and games to be searched for ideas to take. Ranked by what they would save or add here:

1. **Sight from the player once a tick.** Work out what the player can see once, as a field of view over the metatiles around it, and let every body look itself up in it, instead of a trace per body. Symmetric shadowcasting makes the reverse valid: if the player's field covers a body, the body can see the player. After Andrew Braybrook's Paradroid, whose robots are hidden except when in sight, and Björn Bergström's and Albert Ford's shadowcasting.
2. **The cheapest test first, and a fixed number of traces a tick**, bodies scheduled by slot and counter, and tiers by distance: full AI on screen, movement only just off it, a record in the REU beyond. After Thief (Tom Leonard), Elite (Mark Moxon) and NES games.
3. **Precomputed sight in the REU**, a byte per metatile per direction: the distance within which a line is always clear, the one beyond which never. After Killzone (Arjen Beij and Remco Straatman).
4. **Target tiles on the road grid for police cars**: a decision only at a crossing, the exit nearest the target, and roles (the chaser at the suspect, the cutter tiles ahead of it, the flanker mirrored) for pincers without planning. After the Pac-Man Dossier (Jamey Pittman).
5. **Dispatch by heat and roadblocks ahead**: a table row per heat (units, weapons, roadblocks), a roadblock two or three crossings ahead on the suspect's route, off screen. After GTA2 and Need for Speed: Most Wanted.
6. **Flow fields**: one map for every chaser and its inverse for every fleeing civilian, rebuilt a few rows a tick when the player crosses a cell. After Brian Walker's Dijkstra maps and Elijah Emerson's flow-field tiles.
7. **Context steering** with eight slots, one a joystick direction (interest and danger), in place of the whiskers' tries. After Andrew Fray.
8. **Witnesses**: a civilian who sees a crime starts a report; if it gets away, the record grows. Priors from witnesses, and silencing them a choice the game can offer. After GTA V's civilians and GTA2's crime reports.
9. **Search on the crossing graph**: where the suspect may be spreads each tick it is unseen and is cleared where officers can see (occupancy maps, Damián Isla), in place of "go to last seen and look".
10. **Alert phases and a detection meter**, and radio barks in the status row, so the player can read what the police know (Metal Gear Solid, Shadow Tactics, F.E.A.R., GTA2).

Still to come beyond these: cover (a point out of the threat's sight), flanking, squads that keep a formation, and route planning across blocks (the path module, `PLAN.md` section 7). The sources, with links: Braybrook, "Birth of a Paradroid" (codetapper.com); Bergström, "FOV using recursive shadowcasting" (RogueBasin); Ford, "Symmetric Shadowcasting" (albertford.com); Leonard, "Building an AI Sensory System" (GDC 2003); Moxon, "Scheduling tasks with the main loop counter" (bbcelite.com); Beij and Straatman, "Killzone's AI: Dynamic Procedural Tactics" (GDC Europe 2005); Pittman, "The Pac-Man Dossier"; GTA2 wanted levels (Grand Theft Wiki) and the NFS: Most Wanted pursuit system (Wikibooks); Walker, "The Incredible Power of Dijkstra Maps" (RogueBasin); Emerson, "Crowd Pathfinding and Steering Using Flow Field Tiles" (Game AI Pro); Fray, "Context Steering" (Game AI Pro 2); Isla, "Third Eye Crime: Occupancy Maps" (AIIDE 2013); DMA Design, GTA2 map format and "Character AI in GTA 2 Mission Scripts" (Project Cerbera); Orkin, "Three States and a Plan: The AI of F.E.A.R." (GDC 2006).
