# Tile Art Guide

How to draw for backlot-64's multicolour character playfield, and how to get more than 16 colours out of a chip that has 16.

---

## 1. The rules the hardware imposes

- A cell is 4 by 8 fat pixels, each pixel 2 by 1 real pixels.
- A cell shows four colours: three **shared** colours that are the same for every cell on screen (background 0, 1, 2 in $D021 to $D023, any of the 16) and one **cell colour** that only the first eight palette entries can provide (black, white, red, cyan, purple, green, blue, yellow). Colour RAM is four bits a cell: bit 3 turns multicolour on for that cell and bits 0 to 2 are the colour, which is why only eight are reachable. (Bauer, section 3.7.3.2.)
- A tileset gets 192 scene cells. The other 64 hold the font.
- A metatile is 4 by 4 cells. The scroller only ever thinks in metatiles.

The consequences for drawing:

1. Large areas of ground get a shared colour. Asphalt, sidewalk, water, grass, dirt: whichever three materials dominate a region are its three shared colours.
2. Cell colours are for accents inside those areas: roof colours, windows, dashes, signs, foliage.
3. Anything in the top half of the palette (orange, brown, pink, greys, light green, light blue) can only appear as a shared colour. If a region needs brown, brown is one of its three.

---

## 2. The palette as a luminance ladder

Every VIC-II after the first revision has nine luma levels: black, white, and seven pairs of colours with equal luma. Two colours in the same pair mix perfectly. Two colours far apart in level read as texture, not as a new colour. (The first revision, the 6569R1, had five levels; this engine draws for the nine-level chip, which is nearly every machine.)

| Level | Colours | Luma, of 32 |
|---|---|---|
| 0 | black | 0 |
| 1 | blue, brown | 8 |
| 2 | red, dark grey | 10 |
| 3 | purple, orange | 12 |
| 4 | mid grey, light blue | 15 |
| 5 | green, light red (pink) | 16 |
| 6 | cyan, light grey | 20 |
| 7 | yellow, light green | 24 |
| 8 | white | 32 |

Source: Philip "Pepto" Timmermann's VIC-II colour analysis (pepto.de/projects/colorvic), whose late-revision luma order is 0 / 6,9 / 2,B / 4,8 / C,E / 5,A / 3,F / 7,D / 1; VICE's colour tables agree. The level is what the tools use (`LUMA` in `tools/b64tileset.py`). The levels are not evenly spaced: mid grey to green is one step and 1/32 of the range, yellow to white is one step and 8/32, so a step is a rank and not a distance.

Corrected 2026-09-18: this section used to give a five-level table that matched no chip revision and indices that were one too high for eight colours. The quantiser used the same wrong table; its output moved slightly when it was fixed.

---

## 3. Dithering

A checkerboard of two colours blends on a CRT and on VICE's CRT emulation into a colour between them. It costs nothing at runtime and one of the 192 cells per distinct pattern.

**Which pairs work.** Pairs within one luminance level, or one level apart, blend into a believable intermediate. Pairs two or more levels apart shimmer and read as a pattern. The tileset tool warns on a dither whose two colours differ by more than 2 luminance steps.

Good pairs, and what they read as:

| Pair | Reads as | Use |
|---|---|---|
| dark grey + mid grey | a fourth grey | wet asphalt, concrete |
| mid grey + light grey | a fifth grey | sidewalks in shade |
| blue + dark grey | deep water at night | Reedwater channels |
| cyan + light blue | pale turquoise | Keys shallows |
| green + light green | grass with sun on it | Canebrook |
| red + orange | terracotta | Bellamar roofs |
| red + purple | wine, brick | Port Ashby |
| brown + orange | sand at dusk | Canebrook dirt |
| yellow + white | hot sand | Bellamar Beach |
| purple + blue | night sky, neon halo | night states |

**Within a cell** you can only dither between the four colours that cell has, so plan the shared colours as pairs. If a region's three shared colours are dark grey, mid grey, and light grey, the ground has five greys available with no cell colours spent.

**Orientation.** Multicolour pixels are 2 wide, so the finest checkerboard is 2 by 1. Stripes of alternate rows blend completely on PAL only when the two colours share a luma level (blue and brown, red and dark grey, purple and orange, mid grey and light blue, green and light red, cyan and light grey, yellow and light green); with unequal luma they show as lines. Vertical stripes of alternate pixels blend best on PAL because of the next section.

---

## 4. PAL blending

On a real PAL C64 through composite video, horizontally adjacent pixels of different hue smear into each other. The demo scene uses this deliberately to get well beyond 16 perceived colours: at most 136 from two-colour mixes, about 30 of them clean equal-luma mixes on a nine-level chip. VICE's CRT emulation approximates it. It is free.

Rules of thumb:

- Two hues alternating pixel by pixel on the same row blend in hue, because PAL carries chroma at half the horizontal resolution. The result is an even brightness only if the two colours have equal luma.
- Two hues in adjacent cells with a hard vertical edge get a one-pixel fringe. Avoid saturated red next to saturated blue at a vertical edge unless the fringe is wanted.
- Chroma also blends vertically: PAL's delay line averages each line's chroma with the line above, so two colours of equal luma on alternate raster lines merge into one solid colour. Luma does not blend vertically, so a horizontal edge between colours of different luma stays sharp. (Pepto's analysis lists both effects; an earlier version of this file said there was no vertical blending, which was wrong.)

Use it for water, neon glow, and sunset gradients on the raster split, not for anything that must stay crisp such as text, dashes, and windows.

---

## 5. The palette report

`make palette` runs `tools/b64palette.py`, which enumerates every colour a screen can show for a given set of three shared colours: the solids, the blends that pass the dither rule, the mixed RGB of each blend, and how many are visually distinct. It writes a swatch PNG per trio, with each blend shown as its mixed colour above its actual checkerboard, and a markdown table with the RGB values. Draw from the swatch, not from memory.

Measured for the Priors-64 regions, day and night:

| Rule | Per screen | Whole game |
|---|---|---|
| Blends within 2 luminance steps | 13 to 21 | 36 |
| Blends within 3 steps | 15 to 24 | 42 |

So a screen shows up to about 20 usable colours, and the game as a whole about 40. (Recounted 2026-09-18 with the corrected luma table; the earlier, larger figures came from the wrong one.) The 3-step pairs are the ones that start to read as texture on an LCD, so the rule is: use 2-step blends for flat materials that must read as one colour, and reserve 3-step blends for surfaces that are allowed to have grain, such as gravel, sawgrass, rough water, and shadow. `--step=3` on the tool shows the larger set.

The other way to widen a screen's palette is a raster split. A screen with two bands has two trios and roughly 35 colours; the engine's split table allows eight.

## 6. What to reserve

- **Cell colour blue** is the window colour in every daytime tileset. Every wall cell uses it. Do not spend it on anything else near buildings.
- **Cell colour white** is text and headlights. Keep it available on every row where the HUD or dialogue can appear.
- **Shared colour 2** is the neon colour at night in city regions. It flashes. Do not put it on anything that must not flash.

---

## 7. Region palettes

From the Priors-64 plan. Outdoors, shared colours 0 and 1 are fixed for the whole map: dark grey and light grey by day, black and dark grey by night. Only shared colour 2, the accent, changes per region. Tiles that do not use the accent are *core* tiles and must be drawn so they read correctly under every accent; the world's region borders are built only from them.

| Region | Day accent | Night accent |
|---|---|---|
| Bellamar | white | pink |
| Coquina Keys | light blue | blue |
| Reedwater | brown | blue |
| Port Ashby | orange | red |
| Canebrook | green | mid grey |
| Kestrel Ridge | light green | mid grey |

Interiors change all three shared colours behind a fade. See the interiors table in the Priors-64 plan.

---

## 8. For an AI drawing tiles

If tiles are generated rather than drawn by hand, these constraints are the prompt:

1. Output is a 32 by 32 pixel image per metatile, with pixels in 2 by 1 blocks, so effectively 16 by 32.
2. Each 8 by 8 pixel cell uses at most four colours: the region's three shared colours plus one from the first eight of the palette.
3. Colours are exactly the 16 of the C64 palette. No anti-aliasing, no gradients, no alpha.
4. Blends are checkerboards of two colours from the same cell's four, and only between colours within two luminance steps of each other.
5. Any pixel that is the same in every cell of a large area should be a shared colour, not a cell colour.
6. The tool rejects a metatile that breaks rule 2 and warns on one that breaks rule 4. Fix, do not override.
