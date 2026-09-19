AS      = ca65
LD      = ld65
X64     = x64sc
PY      = python3

BUILD   = build
# the quantiser and the modules it imports: a change to the palette or the luma table rebuilds the art
QUANT   = tools/b64quant.py tools/b64tileset.py tools/b64palette.py tools/b64formats.py tools/b64art.py
CFG     = b64.cfg
INC     = -I include -I $(BUILD)

ENGINE_SRCS = src/b64_core.s src/b64_reu.s src/b64_scroll.s src/b64_sprites.s src/b64_hud.s src/b64_bench.s src/b64_cut.s src/b64_vm.s src/b64_page.s src/b64_plat.s   src/b64_overlay.s src/b64_probe.s
ENGINE_OBJS = $(patsubst src/%.s,$(BUILD)/%.o,$(ENGINE_SRCS))
# probe builds: the same sources assembled with -DB64_PROFILE into build/prof
PBUILD  = $(BUILD)/prof
PENGINE_OBJS = $(patsubst src/%.s,$(PBUILD)/%.o,$(ENGINE_SRCS))

REU     = $(BUILD)/world.reu
REUSIZE = 16384         # VICE REU size in KiB; 8192 runs the stock tier
# the stock tier runs the first 8 MB of the same image (VICE refuses an image
# larger than the unit)
REU8     = $(BUILD)/world8.reu
ifeq ($(REUSIZE),8192)
REUIMG   = $(REU8)
else
REUIMG   = $(REU)
endif
VICE_REU = -reu -reusize $(REUSIZE) -reuimage $(REUIMG) +reuimagerw


.PHONY: all assets run-scroll run-traffic run-physics run-boats run-sky run-hover run-plane run-debris run-marsh shot-scroll palette clean check bench

# examples/physics's scenes, name:define (the SCENE template below)
SCENES = boats:COAST sky:SKY hover:HOVER plane:PLANE debris:DEBRIS marsh:MARSH
SCENE_NAMES = $(foreach s,$(SCENES),$(word 1,$(subst :, ,$(s))))
SCENE_PRGS = $(foreach n,$(SCENE_NAMES),$(BUILD)/$(n).prg $(BUILD)/$(n)-auto.prg)
all: $(BUILD)/scroll.prg $(BUILD)/scroll-auto.prg $(BUILD)/traffic.prg $(BUILD)/traffic-auto.prg $(BUILD)/physics.prg $(BUILD)/physics-auto.prg $(BUILD)/cutscene.prg $(BUILD)/overlay.prg $(BUILD)/showcase.prg $(BUILD)/mux.prg $(BUILD)/mux64.prg $(SCENE_PRGS) $(REU)

$(BUILD):
	mkdir -p $(BUILD) $(BUILD)/formats

# ---------------------------------------------------------------------------
# assets -> REU image + slots.inc
$(BUILD)/bellamar_day.bin $(BUILD)/bellamar_day.inc $(BUILD)/sprites0.spr: tools/b64tileset.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64tileset.py bellamar_day $(BUILD)/bellamar_day.bin --sprites $(BUILD)/sprites0.spr

$(BUILD)/world.map $(BUILD)/world.reg: tools/b64world.py tools/b64tileset.py | $(BUILD)
	$(PY) tools/b64world.py bellamar_test $(BUILD)/world.map $(BUILD)/world.reg

# cutscene assets from generated art (images/) through the quantiser
CUT_SET = $(wildcard images/night-set.png)
ifeq ($(CUT_SET),)
CUT_SET = images/night-still.png
endif
$(BUILD)/night.still: $(CUT_SET) $(QUANT) | $(BUILD)
	$(PY) tools/b64quant.py still $(CUT_SET) $(BUILD)/formats/night-set.png --bin=$@ --shimmer-from=17

$(BUILD)/cruiser.grid: images/cruiser-side.png $(QUANT) | $(BUILD)
	$(PY) tools/b64quant.py sprites images/cruiser-side.png $(BUILD)/formats/cruiser-grid.png 4 2 --colours=black,white,blue --bin=$@

$(BUILD)/cruiser.bblock: images/cruiser-side.png $(QUANT) | $(BUILD)
	$(PY) tools/b64quant.py bblock images/cruiser-side.png $(BUILD)/formats/cruiser-bblock.png 12 6 --bg=black --bin=$@

# the cruiser as an object: sprite grid + block cut from one master, block composited
# over the night set at its parking cell so the park is seamless
$(BUILD)/cruiser.b64o: images/cruiser-side.png $(BUILD)/night.still tools/b64object.py $(QUANT) | $(BUILD)
	$(PY) tools/b64object.py images/cruiser-side.png $@ 4 2 --colours=black,white,blue --key=black,dgray --shadow --wheels=auto --still=$(BUILD)/night.still --at=27,14 --preview=$(BUILD)/formats/cruiser-object.png --patch-still=$(BUILD)/night-parked.still "--lights=40,-6,11,1:2/8,0/8;52,-6,11,1:0/8,6/8"

# the set with the parking cells pre-reduced is what the scene loads
$(BUILD)/night-parked.still: $(BUILD)/cruiser.b64o

# the lamp sprite an object's lights are drawn with: one hires 8x4 bar at
# rows 4..7, so a light declared at dy=-6 sits on the roof (VIC y-2..y+1)
$(BUILD)/lamp.spr: | $(BUILD)
	$(PY) -c "rows=[0]*21; rows[4:8]=[0xff]*4; open('$@','wb').write(bytes(sum(([r,0,0] for r in rows),[])+[0]))"

# the C64 Ultimate module: sampler and command interface, for region B
$(BUILD)/ultimate.bin: src/b64_ultimate.s src/b64_pcm.s src/b64_uci.s include/b64.inc ultimate.cfg | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $(BUILD)/ult_jmp.o src/b64_ultimate.s
	$(AS) -g -t c64 $(INC) -o $(BUILD)/ult_pcm.o src/b64_pcm.s
	$(AS) -g -t c64 $(INC) -o $(BUILD)/ult_uci.o src/b64_uci.s
	$(LD) -C ultimate.cfg -o $@ $(BUILD)/ult_jmp.o $(BUILD)/ult_pcm.o $(BUILD)/ult_uci.o -m $(BUILD)/ultimate.map

# a solid hires block, the multiplexer harness's sprite
$(BUILD)/block.spr: | $(BUILD)
	$(PY) -c "open('$@','wb').write(bytes([255]*63+[0]))"

$(BUILD)/slots.inc: reu.manifest tools/b64pack.py | $(BUILD)
	$(PY) tools/b64pack.py --inc reu.manifest $@

$(REU): reu.manifest tools/b64pack.py $(BUILD)/ovl1.bin $(BUILD)/ovl2.bin $(BUILD)/day.still $(BUILD)/daylight.bin $(BUILD)/nightlight.bin $(BUILD)/show.bin $(BUILD)/world.map $(BUILD)/world.reg $(BUILD)/bellamar_day.bin $(BUILD)/sprites0.spr $(BUILD)/night.still $(BUILD)/night-parked.still $(BUILD)/cruiser.grid $(BUILD)/cruiser.bblock $(BUILD)/cruiser.b64o $(BUILD)/lamp.spr $(BUILD)/block.spr $(BUILD)/ultimate.bin $(BUILD)/scene.bin $(BUILD)/benchscripts.bin $(BUILD)/physics.bin $(BUILD)/cars16.spr $(BUILD)/collision.bin $(BUILD)/water.bin $(BUILD)/boats16.spr $(BUILD)/air.bin $(BUILD)/heli16.spr $(BUILD)/helish16.spr $(BUILD)/plane16.spr $(BUILD)/planesh16.spr $(BUILD)/airboat16.spr
	$(PY) tools/b64pack.py reu.manifest $(REU) -

# p-code blobs: assembled at offset 0, packed into REU slots
$(BUILD)/scene.bin: examples/cutscene/scene.s include/b64.inc $(BUILD)/slots.inc script.cfg | $(BUILD)
	$(AS) -g -t c64 -I include -I $(BUILD) -o $(BUILD)/scene.o $<
	$(LD) -C script.cfg -o $@ $(BUILD)/scene.o -Ln $(BUILD)/scene.lbl

# the lighting showcase: a day set, its dusk states, strobe states for the night set, and its script
$(BUILD)/day.still: images/day-set.png $(QUANT) | $(BUILD)
	$(PY) tools/b64quant.py still images/day-set.png $(BUILD)/formats/day-set.png --bin=$@

$(BUILD)/daylight.bin: $(BUILD)/day.still tools/b64light.py tools/b64palette.py
	$(PY) tools/b64light.py $(BUILD)/day.still $@ dusk --steps 32

$(BUILD)/nightlight.bin: $(BUILD)/night-parked.still $(BUILD)/cruiser.b64o tools/b64light.py tools/b64palette.py
	$(PY) tools/b64light.py $(BUILD)/night-parked.still $@ object $(BUILD)/cruiser.b64o --x0 24 --xstep 8 --npos 40 --y 162

$(BUILD)/show.bin: examples/showcase/scene.s include/b64.inc $(BUILD)/slots.inc script.cfg | $(BUILD)
	$(AS) -g -t c64 -I include -I $(BUILD) -o $(BUILD)/show.o $<
	$(LD) -C script.cfg -o $@ $(BUILD)/show.o -Ln $(BUILD)/show.lbl

$(BUILD)/showcase.o: examples/showcase/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(BUILD)/showcase.prg: $(ENGINE_OBJS) $(BUILD)/showcase.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/showcase.o -m $(BUILD)/showcase.map -Ln $(BUILD)/showcase.lbl

run-showcase: $(BUILD)/showcase.prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/showcase.prg

$(BUILD)/benchscripts.bin: examples/bench/scripts.s include/b64.inc $(BUILD)/slots.inc script.cfg | $(BUILD)
	$(AS) -t c64 -I include -I $(BUILD) -o $(BUILD)/benchscripts.o $<
	$(LD) -C script.cfg -o $@ $(BUILD)/benchscripts.o

# code overlays: assembled for the window, linked against the resident
# program's map so they can call engine routines, packed as slots
$(BUILD)/overlay.o: examples/overlay/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(BUILD)/overlay.prg: $(ENGINE_OBJS) $(BUILD)/overlay.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/overlay.o -m $(BUILD)/overlay.map -Ln $(BUILD)/overlay.lbl

$(BUILD)/ovl%.bin: examples/overlay/ovl%.s $(BUILD)/overlay.prg overlay.cfg tools/b64overlay.py | $(BUILD)
	$(AS) -t c64 $(INC) -o $(BUILD)/ovl$*.o $<
	$(PY) tools/b64overlay.py $(BUILD)/overlay.lbl overlay.cfg $(BUILD)/ovl$*.o $@

run-overlay: $(BUILD)/overlay.prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/overlay.prg

$(REU8): $(REU)
	head -c 8388608 $(REU) > $@

assets: $(REU)

# ---------------------------------------------------------------------------
# engine
$(BUILD)/%.o: src/%.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(PBUILD):
	mkdir -p $(PBUILD)

$(PBUILD)/%.o: src/%.s include/b64.inc $(BUILD)/slots.inc | $(PBUILD)
	$(AS) -g -t c64 -DB64_PROFILE $(INC) -o $@ $<

$(PBUILD)/%.o: examples/%/main.s include/b64.inc $(BUILD)/slots.inc | $(PBUILD)
	$(AS) -g -t c64 -DB64_PROFILE $(INC) -o $@ $<

# the probe and its hooks do not fit the 10 KB engine area, and should not
# have to: profile builds link with the area 1 KB larger and the game
# region starting that much later.  The plain build is what budgets hold.
$(PBUILD)/b64prof.cfg: $(CFG) | $(PBUILD)
	sed -e 's/start = $$080D, size = $$27F3/start = $$080D, size = $$2BF3/' -e 's/GAME:     start = $$3000, size = $$1000/GAME:     start = $$3400, size = $$0C00/' $(CFG) > $@

$(PBUILD)/scroll-auto.o: examples/scroll/main.s include/b64.inc $(BUILD)/slots.inc | $(PBUILD)
	$(AS) -g -t c64 -DB64_PROFILE -D AUTODRIVE=1 $(INC) -o $@ $<

# a probe build of any example: make build/prof/cutscene.prg
$(PBUILD)/%.prg: $(PENGINE_OBJS) $(PBUILD)/%.o $(PBUILD)/b64prof.cfg
	$(LD) -C $(PBUILD)/b64prof.cfg -o $@ $(PBUILD)/b64_core.o $(filter-out $(PBUILD)/b64_core.o,$(PENGINE_OBJS)) $(PBUILD)/$*.o -Ln $(PBUILD)/$*.lbl

# profile an example in VICE for a few seconds and print the report
probe-%: $(PBUILD)/%.prg $(REU) $(REU8)
	$(PY) tools/b64probe.py --vice $(PBUILD)/$*.prg --reu $(REUIMG) --reusize $(REUSIZE) --labels $(PBUILD)/$*.lbl --script-labels $(BUILD)/scene.lbl --seconds 8

# example
$(BUILD)/scroll.o: examples/scroll/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(BUILD)/scroll-auto.o: examples/scroll/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -D AUTODRIVE=1 -o $@ $<

$(BUILD)/scroll.prg: $(ENGINE_OBJS) $(BUILD)/scroll.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/scroll.o -m $(BUILD)/scroll.map -Ln $(BUILD)/scroll.lbl

$(BUILD)/scroll-auto.prg: $(ENGINE_OBJS) $(BUILD)/scroll-auto.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/scroll-auto.o -Ln $(BUILD)/scroll-auto.lbl

$(BUILD)/traffic.o: examples/traffic/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(BUILD)/traffic-auto.o: examples/traffic/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -D AUTODRIVE=1 -o $@ $<

$(BUILD)/traffic.prg: $(ENGINE_OBJS) $(BUILD)/traffic.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/traffic.o -m $(BUILD)/traffic.map -Ln $(BUILD)/traffic.lbl

$(BUILD)/traffic-auto.prg: $(ENGINE_OBJS) $(BUILD)/traffic-auto.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/traffic-auto.o -Ln $(BUILD)/traffic-auto.lbl

# the demo site: every example recorded in VICE (tools/b64site.py); the videos
# live only on the gh-pages branch, which GitHub Pages serves
.PHONY: pages publish-pages
pages: all $(BUILD)/mux64.prg $(REU8)
	$(PY) tools/b64site.py
publish-pages: pages
	$(PY) tools/b64site.py --publish

# the physics module: pinned at $6000 (pinned.cfg), linked against the
# engine's labels, and an include of its tables' addresses for games
$(BUILD)/phys_tables.inc: tools/b64phystab.py | $(BUILD)
	$(PY) tools/b64phystab.py $@
PHYS_SRCS = modules/physics/defs.inc modules/physics/core.s modules/physics/foot.s modules/physics/frame.s modules/physics/wheels.s modules/physics/hull.s modules/physics/heli.s modules/physics/plane.s modules/physics/tables.s modules/physics/private.s
$(BUILD)/physics.o: modules/physics/ground.s $(PHYS_SRCS) include/b64.inc $(BUILD)/phys_tables.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -I modules/physics -o $@ $<
$(BUILD)/physics.bin $(BUILD)/physics_syms.inc: $(BUILD)/physics.o $(BUILD)/overlay.prg pinned.cfg tools/b64overlay.py
	$(PY) tools/b64overlay.py $(BUILD)/overlay.lbl pinned.cfg $(BUILD)/physics.o $(BUILD)/physics.bin --inc $(BUILD)/physics_syms.inc pb_,phys_
# the collision module: region A ($8000), beside a physics module
$(BUILD)/collision.o: modules/collision/collision.s modules/physics/defs.inc include/b64.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -I modules/physics -o $@ $<
$(BUILD)/collision.bin $(BUILD)/collision_syms.inc: $(BUILD)/collision.o $(BUILD)/overlay.prg overlay.cfg tools/b64overlay.py
	$(PY) tools/b64overlay.py $(BUILD)/overlay.lbl overlay.cfg $(BUILD)/collision.o $(BUILD)/collision.bin --inc $(BUILD)/collision_syms.inc col_,sh_,shot_,fx_,NS,th_,throw_,NT,db_,debris_,ND
$(BUILD)/cars16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py car $@
$(BUILD)/boats16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py boat $@
$(BUILD)/heli16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py heli $@
$(BUILD)/helish16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py helishadow $@
$(BUILD)/plane16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py plane $@
$(BUILD)/planesh16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py planeshadow $@
$(BUILD)/airboat16.spr: tools/b64rot.py tools/b64art.py | $(BUILD)
	$(PY) tools/b64rot.py airboat $@
# the air module: the same core assembled with AIR, foot and the helicopter
$(BUILD)/air.o: modules/physics/air.s $(PHYS_SRCS) include/b64.inc $(BUILD)/phys_tables.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -I modules/physics -o $@ $<
$(BUILD)/air.bin $(BUILD)/air_syms.inc: $(BUILD)/air.o $(BUILD)/overlay.prg pinned.cfg tools/b64overlay.py
	$(PY) tools/b64overlay.py $(BUILD)/overlay.lbl pinned.cfg $(BUILD)/air.o $(BUILD)/air.bin --inc $(BUILD)/air_syms.inc pb_,phys_
# the water module: the same core, foot and the hull, swapped in at $6000
$(BUILD)/water.o: modules/physics/water.s $(PHYS_SRCS) include/b64.inc $(BUILD)/phys_tables.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -I modules/physics -o $@ $<
$(BUILD)/water.bin $(BUILD)/water_syms.inc: $(BUILD)/water.o $(BUILD)/overlay.prg pinned.cfg tools/b64overlay.py
	$(PY) tools/b64overlay.py $(BUILD)/overlay.lbl pinned.cfg $(BUILD)/water.o $(BUILD)/water.bin --inc $(BUILD)/water_syms.inc pb_,phys_

$(BUILD)/physics-demo.o: examples/physics/main.s include/b64.inc $(BUILD)/slots.inc modules/physics/physics.inc $(BUILD)/physics_syms.inc $(BUILD)/collision_syms.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<
$(BUILD)/physics-auto.o: examples/physics/main.s include/b64.inc $(BUILD)/slots.inc modules/physics/physics.inc $(BUILD)/physics_syms.inc $(BUILD)/collision_syms.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -D AUTODRIVE=1 -o $@ $<
$(BUILD)/physics.prg: $(ENGINE_OBJS) $(BUILD)/physics-demo.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/physics-demo.o -m $(BUILD)/physics.map -Ln $(BUILD)/physics.lbl
$(BUILD)/physics-auto.prg: $(ENGINE_OBJS) $(BUILD)/physics-auto.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/physics-auto.o -Ln $(BUILD)/physics-auto.lbl
run-physics: $(BUILD)/physics.prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/physics.prg

# the example's scenes: the same program built with the scene's -D name
# (docs/PHYSICS.md): boats at the coast (COAST), a helicopter (SKY), shots
# and a hovering helicopter (HOVER), a plane (PLANE), debris (DEBRIS), an
# airboat in the marsh (MARSH)
define SCENE
$(BUILD)/$(1)-demo.o: examples/physics/main.s include/b64.inc $(BUILD)/slots.inc modules/physics/physics.inc $(BUILD)/physics_syms.inc $(BUILD)/collision_syms.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -D $(2)=1 -o $$@ $$<
$(BUILD)/$(1)-auto.o: examples/physics/main.s include/b64.inc $(BUILD)/slots.inc modules/physics/physics.inc $(BUILD)/physics_syms.inc $(BUILD)/collision_syms.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -D $(2)=1 -D AUTODRIVE=1 -o $$@ $$<
$(BUILD)/$(1).prg: $(ENGINE_OBJS) $(BUILD)/$(1)-demo.o $(CFG)
	$(LD) -C $(CFG) -o $$@ $(BUILD)/b64_core.o $$(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/$(1)-demo.o -Ln $(BUILD)/$(1).lbl
$(BUILD)/$(1)-auto.prg: $(ENGINE_OBJS) $(BUILD)/$(1)-auto.o $(CFG)
	$(LD) -C $(CFG) -o $$@ $(BUILD)/b64_core.o $$(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/$(1)-auto.o -Ln $(BUILD)/$(1)-auto.lbl
run-$(1): $(BUILD)/$(1).prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/$(1).prg
endef
$(foreach s,$(SCENES),$(eval $(call SCENE,$(word 1,$(subst :, ,$(s))),$(word 2,$(subst :, ,$(s))))))

run-traffic: $(BUILD)/traffic.prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/traffic.prg

$(BUILD)/mux.o: examples/mux/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(BUILD)/mux.prg: $(ENGINE_OBJS) $(BUILD)/mux.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/mux.o -m $(BUILD)/mux.map -Ln $(BUILD)/mux.lbl

$(BUILD)/mux64.o: examples/mux/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -D MUX64=1 -o $@ $<

$(BUILD)/mux64.prg: $(ENGINE_OBJS) $(BUILD)/mux64.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/mux64.o -m $(BUILD)/mux64.map -Ln $(BUILD)/mux64.lbl

# the multiplexer's test builds: the engine assembled with -DB64_MUXLOG, which
# logs the raster line every sprite group starts on and stamps every entry
# with a CIA clock, for tools/b64muxhw.py on VICE or on a C64 Ultimate
# (docs/INSTRUMENT.md)
MBUILD  = $(BUILD)/mlog
MENGINE_OBJS = $(patsubst src/%.s,$(MBUILD)/%.o,$(ENGINE_SRCS))
$(MBUILD):
	mkdir -p $(MBUILD)
$(MBUILD)/%.o: src/%.s include/b64.inc $(BUILD)/slots.inc | $(MBUILD)
	$(AS) -g -t c64 -DB64_MUXLOG $(INC) -o $@ $<
$(MBUILD)/mux.prg: $(MENGINE_OBJS) $(BUILD)/mux.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(MBUILD)/b64_core.o $(filter-out $(MBUILD)/b64_core.o,$(MENGINE_OBJS)) $(BUILD)/mux.o -Ln $(MBUILD)/mux.lbl
$(MBUILD)/mux64.prg: $(MENGINE_OBJS) $(BUILD)/mux64.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(MBUILD)/b64_core.o $(filter-out $(MBUILD)/b64_core.o,$(MENGINE_OBJS)) $(BUILD)/mux64.o -Ln $(MBUILD)/mux64.lbl

run-mux: $(BUILD)/mux.prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/mux.prg

$(BUILD)/cutscene.o: examples/cutscene/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 $(INC) -o $@ $<

$(BUILD)/cutscene.prg: $(ENGINE_OBJS) $(BUILD)/cutscene.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/cutscene.o -m $(BUILD)/cutscene.map -Ln $(BUILD)/cutscene.lbl

$(BUILD)/bench.o: examples/bench/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -g -t c64 -I include -I $(BUILD) -o $@ $<

$(BUILD)/bench.prg: $(ENGINE_OBJS) $(BUILD)/bench.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/bench.o -m $(BUILD)/bench.map -Ln $(BUILD)/bench.lbl

# everything the engine claims, proven in VICE at both REU tiers (docs/CHECK.md)
check: all $(BUILD)/bench.prg $(REU8) $(PBUILD)/cutscene.prg $(PBUILD)/scroll-auto.prg $(MBUILD)/mux.prg $(MBUILD)/mux64.prg
	$(PY) tools/b64check.py $(CHECKFLAGS)

bench: $(BUILD)/bench.prg $(REU) $(REU8)
	$(PY) tools/b64bench.py $(REUIMG) $(REUSIZE)

run-cutscene: $(BUILD)/cutscene.prg $(REU) $(REU8)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/cutscene.prg

# screenshots of the cutscene at three points
shot-cutscene: $(BUILD)/cutscene.prg $(REU)
	for t in 5 8 12; do \
	  $(X64) -default $(VICE_REU) -warp +sound +confirmonexit -limitcycles $${t}000000 \
	    -exitscreenshot $(BUILD)/cut-$$t.png -autostartprgmode 1 $(BUILD)/cutscene.prg >/dev/null 2>&1; \
	done



run-scroll: $(BUILD)/scroll.prg $(REU)
	$(X64) $(VICE_REU) -autostartprgmode 1 $(BUILD)/scroll.prg

# screenshots of the autodrive build at two points in time
shot-scroll: $(BUILD)/scroll-auto.prg $(REU)
	$(X64) -default $(VICE_REU) -warp +sound +confirmonexit -limitcycles 6000000 \
	  -exitscreenshot $(BUILD)/scroll-1.png -autostartprgmode 1 $(BUILD)/scroll-auto.prg >/dev/null 2>&1; \
	$(X64) -default $(VICE_REU) -warp +sound +confirmonexit -limitcycles 12000000 \
	  -exitscreenshot $(BUILD)/scroll-2.png -autostartprgmode 1 $(BUILD)/scroll-auto.prg >/dev/null 2>&1

# palette report: every colour each region can show, as swatches and tables
palette: | $(BUILD)
	$(PY) tools/b64palette.py $(BUILD)/palette

clean:
	rm -rf $(BUILD)

.SECONDARY:
