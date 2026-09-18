AS      = ca65
LD      = ld65
X64     = x64sc
PY      = python3

BUILD   = build
CFG     = b64.cfg
INC     = -I include -I $(BUILD)

ENGINE_SRCS = src/b64_core.s src/b64_reu.s src/b64_scroll.s src/b64_sprites.s src/b64_hud.s src/b64_text.s src/b64_bench.s src/b64_cut.s src/b64_vm.s src/b64_page.s src/b64_plat.s src/b64_pcm.s src/b64_uci.s src/b64_overlay.s
ENGINE_OBJS = $(patsubst src/%.s,$(BUILD)/%.o,$(ENGINE_SRCS))

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


.PHONY: all assets run-scroll shot-scroll palette clean

all: $(BUILD)/scroll.prg $(BUILD)/scroll-auto.prg $(BUILD)/cutscene.prg $(BUILD)/overlay.prg $(REU)

$(BUILD):
	mkdir -p $(BUILD) $(BUILD)/formats

# ---------------------------------------------------------------------------
# assets -> REU image + slots.inc
$(BUILD)/vice_day.bin $(BUILD)/vice_day.inc $(BUILD)/sprites0.spr: tools/b64tileset.py | $(BUILD)
	$(PY) tools/b64tileset.py vice_day $(BUILD)/vice_day.bin --sprites $(BUILD)/sprites0.spr

$(BUILD)/world.map $(BUILD)/world.reg: tools/b64world.py tools/b64tileset.py | $(BUILD)
	$(PY) tools/b64world.py vice_test $(BUILD)/world.map $(BUILD)/world.reg

# cutscene assets from generated art (images/) through the quantiser
CUT_SET = $(wildcard images/night-set.png)
ifeq ($(CUT_SET),)
CUT_SET = images/night-still.png
endif
$(BUILD)/night.still: $(CUT_SET) tools/b64quant.py | $(BUILD)
	$(PY) tools/b64quant.py still $(CUT_SET) $(BUILD)/formats/night-set.png --bin=$@ --shimmer-from=17

$(BUILD)/cruiser.grid: images/cruiser-side.png tools/b64quant.py | $(BUILD)
	$(PY) tools/b64quant.py sprites images/cruiser-side.png $(BUILD)/formats/cruiser-grid.png 4 2 --colours=black,white,blue --bin=$@

$(BUILD)/cruiser.bblock: images/cruiser-side.png tools/b64quant.py | $(BUILD)
	$(PY) tools/b64quant.py bblock images/cruiser-side.png $(BUILD)/formats/cruiser-bblock.png 12 6 --bg=black --bin=$@

# the cruiser as an object: sprite grid + block cut from one master, block composited
# over the night set at its parking cell so the park is seamless
$(BUILD)/cruiser.b64o: images/cruiser-side.png $(BUILD)/night.still tools/b64object.py tools/b64quant.py | $(BUILD)
	$(PY) tools/b64object.py images/cruiser-side.png $@ 4 2 --colours=black,white,blue --key=black,dgray --shadow --wheels=auto --still=$(BUILD)/night.still --at=27,14 --preview=$(BUILD)/formats/cruiser-object.png --patch-still=$(BUILD)/night-parked.still

# the set with the parking cells pre-reduced is what the scene loads
$(BUILD)/night-parked.still: $(BUILD)/cruiser.b64o

# a single hires lamp sprite for the beacon overlays: a 6x3 blob
$(BUILD)/lamp.spr: | $(BUILD)
	$(PY) -c "rows=[0]*21; rows[9]=0b01111110; rows[10]=0b01111110; open('$@','wb').write(bytes(sum(([r,0,0] for r in rows),[])+[0]))"

$(BUILD)/slots.inc: reu.manifest tools/b64pack.py | $(BUILD)
	$(PY) tools/b64pack.py --inc reu.manifest $@

$(REU): reu.manifest tools/b64pack.py $(BUILD)/ovl1.bin $(BUILD)/ovl2.bin $(BUILD)/world.map $(BUILD)/world.reg $(BUILD)/vice_day.bin $(BUILD)/sprites0.spr $(BUILD)/night.still $(BUILD)/night-parked.still $(BUILD)/cruiser.grid $(BUILD)/cruiser.bblock $(BUILD)/cruiser.b64o $(BUILD)/lamp.spr $(BUILD)/scene.bin $(BUILD)/benchscripts.bin
	$(PY) tools/b64pack.py reu.manifest $(REU) -

# p-code blobs: assembled at offset 0, packed into REU slots
$(BUILD)/scene.bin: examples/cutscene/scene.s include/b64.inc $(BUILD)/slots.inc script.cfg | $(BUILD)
	$(AS) -t c64 -I include -I $(BUILD) -o $(BUILD)/scene.o $<
	$(LD) -C script.cfg -o $@ $(BUILD)/scene.o

$(BUILD)/benchscripts.bin: examples/bench/scripts.s include/b64.inc $(BUILD)/slots.inc script.cfg | $(BUILD)
	$(AS) -t c64 -I include -I $(BUILD) -o $(BUILD)/benchscripts.o $<
	$(LD) -C script.cfg -o $@ $(BUILD)/benchscripts.o

# code overlays: assembled for the window, linked against the resident
# program's map so they can call engine routines, packed as slots
$(BUILD)/overlay.o: examples/overlay/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -t c64 $(INC) -o $@ $<

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
	$(AS) -t c64 $(INC) -o $@ $<

# example
$(BUILD)/scroll.o: examples/scroll/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -t c64 $(INC) -o $@ $<

$(BUILD)/scroll-auto.o: examples/scroll/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -t c64 $(INC) -D AUTODRIVE=1 -o $@ $<

$(BUILD)/scroll.prg: $(ENGINE_OBJS) $(BUILD)/scroll.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/scroll.o -m $(BUILD)/scroll.map

$(BUILD)/scroll-auto.prg: $(ENGINE_OBJS) $(BUILD)/scroll-auto.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/scroll-auto.o

$(BUILD)/cutscene.o: examples/cutscene/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -t c64 $(INC) -o $@ $<

$(BUILD)/cutscene.prg: $(ENGINE_OBJS) $(BUILD)/cutscene.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/cutscene.o -m $(BUILD)/cutscene.map

$(BUILD)/bench.o: examples/bench/main.s include/b64.inc $(BUILD)/slots.inc | $(BUILD)
	$(AS) -t c64 -I include -I $(BUILD) -o $@ $<

$(BUILD)/bench.prg: $(ENGINE_OBJS) $(BUILD)/bench.o $(CFG)
	$(LD) -C $(CFG) -o $@ $(BUILD)/b64_core.o $(filter-out $(BUILD)/b64_core.o,$(ENGINE_OBJS)) $(BUILD)/bench.o -m $(BUILD)/bench.map

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
