# Modules: the VM as Overlay Manager

The program is p-code. Everything fast is assembly in modules. The VM decides which modules are in memory, because the scripts it runs are the only thing that knows what is about to be called. This file replaces the build-time "feature picker" framing in `PLAN.md` section 4: modules keep their headers, tiers and measured costs, but residency becomes a run-time decision driven by a plan the script compiler emits.

Designed 2026-09-17 with the user; the overlay loader and link tool it builds on were verified the same day (`examples/overlay`).

---

## 1. The one constraint

A load costs 9,013 cycles per 8 KB, 6,300 to 6,900 per 6 KB and 2,300 per 2 KB, measured. Anything that runs every frame for many entities cannot be paged on demand: physics for thirty cars cannot arrive mid-frame. So modules have two residency states, and the difference is who decides and when:

- **Pinned.** Loaded once when a mode or scene starts, resident until it ends. For per-frame hooks: physics, collision, the AI behaviours, the entity scheduler.
- **Cached.** Loaded when a script is about to call them, evicted when the space is needed. For everything called occasionally: a path request, the save system, dialogue, the map, a heist's special case, a bespoke routine one mission needs.

The VM pins and caches; the game never touches a DMA.

---

## 2. What a module is

An assembled binary with a jump table at its start, linked for the slot it will occupy:

```
+0   jmp entry0          ; entry table: 3 bytes each, index = syscall entry number
+3   jmp entry1
...
+3n  code and tables
```

A 16-byte descriptor lives in the packer's module table, not in the binary: name, size in 2 KB units, per-frame cost, per-entity cost, hooks (frame, entity, border, init), entry count, and the argument signature of each entry. The benchmark harness fills the costs; a claimed cost that the harness disproves fails the build.

A custom assembly routine is a module with one entry. Nothing distinguishes it from a catalogue module.

**Position.** 6502 code is not position-independent, and this engine does not relocate at load time. The module tool links each module once per slot it may occupy and packs every copy into the REU; the loader fetches the copy for the slot it chose. A 2 KB module that may land in any of the three cache slots costs 6 KB of REU, which is nothing, and zero cycles at load. *After Cadaver's c64gameframework, which relocates with an instruction-length table at load time. Changed: copies in the REU instead, because the REU has the space and the load must stay a plain DMA.*

---

## 3. The code cache

Region A ($8000-$97FF) is three 2 KB slots (four until 2026-09-18, when its top 2 KB went to the multiplexer's tables for the 64-sprite tier). A module takes one or more adjacent slots. Each slot records the REU address of what it holds, a pin bit, and a last-used stamp. This is the data page cache again at 2 KB granularity with pinning; the two share nothing but the idea.

| Operation | Cost |
|---|---|
| Is module M resident? | three compares |
| Load a 2 KB module into a free or evictable slot | 2,300 cycles, from the main loop |
| Load a 6 KB module | all three slots, 6,300 to 6,900 cycles (measured, `overlay.load_6k`), may take two frames |
| Evict | zero; the slot is overwritten |
| Pin or unpin | one bit |

The pinned area for a mode is the same format loaded into the game's module region ($6000-$7FFF, 8 KB) at mode start, so play mode can pin up to 8 KB of per-frame modules and still have the 6 KB cache for everything else. During a cutscene the $6000 region is the bitmap, so the scene's modules are all cached, which is the right shape for a scene: nothing runs per entity.

Loads run from the main loop after the game callback, one slot per frame at most unless the requester is blocked, so a prefetch never costs more than a tenth of a frame. Loading never happens in an interrupt.

---

## 4. Syscalls

A syscall in p-code names a module and an entry:

```
SYS module, entry [, args...]        ; 3 bytes plus arguments
```

The VM looks the module up in the cache (four compares), takes the slot base, and jumps through the table at `base + entry * 3`, about forty cycles over the routine. Arguments are passed the way the engine's own primitives take them, in the VM's variables and the shared zero page, so a module entry is written like any engine routine.

If the module is not resident, the thread does not fail and does not stall the frame: the VM queues the load, marks the thread as waiting on that module, and yields. When the load lands the thread resumes at the syscall and it succeeds. This is the same wait the roadmap plans for entity events; the module load is simply the first event source.

Pinned modules are called the same way through the same table, so a script does not know or care which state a module is in.

---

## 5. NEED and the plan

Lookahead is not done by peeking at upcoming p-code, which is fuzzy past any branch. It is done by the compiler, which knows every syscall in every block.

**NEED.** At the head of each basic block the compiler emits `NEED m1, m2, ...` for the modules the block calls that the previous block did not already need. NEED issues prefetches and does not wait. By the time the block reaches its first syscall the module is usually resident; if it is not, the syscall waits as above. NEED costs one opcode per block boundary that changes the working set, which in practice is one every few dozen instructions.

**The plan.** Alongside the p-code, the compiler emits a residency plan as data the VM reads when a script starts:

| Plan entry | Meaning |
|---|---|
| pinned set per mode or scene | Modules any per-frame loop in the script calls; loaded at mode start into the pinned area, refused if they exceed it |
| cache size hint | How many slots the script's working set needs at its widest block; a warning if more than three |
| prefetch order | For the first block, so a scene's opening frame has its modules before the fade ends |
| budget report | Pinned bytes against the region, worst-case per-frame cycles of the pinned set against the frame contract, from the module descriptors |

How the compiler tells pinned from cached: a syscall inside a loop that contains a YIELD (a per-frame loop) is a per-frame call and its module is pinned for that script's mode; a syscall outside any such loop is cached. The author can override either way with a directive. The plan is what the manifest used to be, generated instead of written, and checked by the same budget arithmetic.

**The report** is the design's honesty mechanism. A script that pins more than 8 KB, or whose pinned set exceeds the frame budget at the declared entity count, does not assemble. The numbers come from the harness, not from the descriptor's author.

---

## 6. The optimizer: spans

The compiler gets an optimizer that turns a hot region of p-code into native 6502, a **span**, called from the script by an ordinary SYS. A span is a generated module: it lives in a slot, is pinned or cached like any other, and is linked once per slot like any other. Nothing new is needed in the VM.

**Why the codegen is cheap.** Every opcode has a fixed native template over the VM's variable tables: `ADD v, w` with constant indices is four absolute loads and stores, about 20 cycles against 92 interpreted; branches become branches, LDT an indexed load, a syscall a `jsr`. State stays in the VM's variables, so a span reads and writes exactly what the p-code did. The generator is template expansion.

**Where a span may begin and end.** Only at yield points. A span cannot contain YIELD or WAIT, because native code cannot suspend as a thread does. The hot case is a per-frame loop, body then YIELD then a jump back; the body becomes the span and the p-code keeps `SYS span; YIELD; JMP`.

**How the optimizer decides.** Native code is three to four times the bytes of the p-code it replaces, and a per-frame span must be pinned, so it competes with physics and AI for the pinned region. The measure is cycles saved per pinned byte: rank regions, take the best until the pinned budget is full, cache the rest or leave them interpreted. The profile comes from the probe (`INSTRUMENT.md`): a run in VICE or on the hardware gives, per script offset, how often the VM was found there. Static analysis knows the loops; the profile knows which branches are taken.

**What it keeps true.** "Scripts decide, hooks execute" still holds; a hook can now be generated from a script instead of written by hand, and it still cannot crash the machine because the generator only emits templates. Expected on the cutscene: the drive body from 1,464 cycles to about 250.

## 7. What this changes elsewhere

- **`PLAN.md` section 4.** Tiers, the catalogue, hooks versus syscalls, upgrade points and bespoke modules all stand. "Resident or overlay" as a build-time kind is gone; the manifest becomes the compiler's plan; the packer checks the plan.
- **The VM.** Gains SYS, NEED, a wait-on-module state per thread, and the load queue. About 300 bytes.
- **The overlay loader.** Grows from one window to three slots with pins and stamps. About 150 bytes.
- **The tools.** `b64overlay.py` links a module once per allowed slot. A module table joins the manifest. The script assembler gains `V_SYS` and `V_NEED` now; the compiler that emits NEED and the plan automatically is the script language the game plan already calls for (`priorsc`), and it is where the analysis lives.
- **The engine's own overlays.** The map screen, the cutscene player and the save system become modules like any other, called by scripts and paged by the same cache.

---

## 8. Order of work

1. **Code cache.** Three slots, pins, stamps, LRU, loads from the main loop. `examples/overlay` grows to exercise eviction and pinning. Measured: load cost per slot, compare cost.
2. **Module format and tool.** The jump table, the descriptor, one link per allowed slot, the packer's module table.
3. **SYS and NEED opcodes.** The table jump, the wait-on-module state, the prefetch queue. A test script calls two modules alternately with and without NEED and the trace shows the difference.
4. **The plan.** First as a hand-written table for the cutscene and the overlay example; then emitted by the script compiler with the pinned-set analysis and the budget report.
5. **Spans.** The optimizer pass over the macro-assembly IR, reading the probe's JSON profile; the cutscene's drive body as the first span, measured against the interpreted body.
6. **The first real modules.** The vehicle module for Priors-64 as the first pinned module, the pathfinder as the first cached one, and the numbers from both in the plan's catalogue.

Each step is checked in VICE at both REU tiers before it is called done, with the frame trace on when timing is the question.
