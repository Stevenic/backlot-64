# Tile Art Guide

How to draw for backlot-64's multicolour character playfield, and how to get more than 16 colours out of a chip that has 16.

---

## 1. The rules the hardware imposes

- A cell is 4 by 8 fat pixels, each pixel 2 by 1 real pixels.
- A cell shows four colours: three **shared** colours that are the same for every cell on screen (background 0, 1, 2, any of the 16) and one **cell colour** that only the first eight palette entries can provide (black, white, red, cyan, purple, green, blue, yellow).
- A tileset gets 192 scene cells. The other 64 hold the font.
- A metatile is 4 by 4 cells. The scroller only ever thinks in metatiles.

The consequences for drawing:

1. Large areas of ground get a shared colour. Asphalt, sidewalk, water, grass, dirt: whichever three materials dominate a region are its three shared colours.
2. Cell colours are for accents inside those areas: roof colours, windows, dashes, signs, foliage.
3. Anything in the top half of the palette (orange, brown, pink, greys, light green, light blue) can only appear as a shared colour. If a region needs brown, brown is one of its three.

---

## 2. The palette as a luminance ladder

The 16 colours were designed in five brightness levels. Two colours at the same level mix cleanly. Two colours far apart in level read as texture, not as a new colour.

| Level | Colours | Luminance (PAL) |
|---|---|---|
| 0 | black | 0 |
| 1 | blue, brown, dark grey | 1 to 2 |
| 2 | red, purple, orange, mid grey | 3 to 5 |
| 3 | cyan, green, light red, light blue, light grey | 5 to 7 |
| 4 | yellow, light green, white | 7 to 8 |

Exact luminance indices, on Pepto's scale of 0 to 8 that the tileset tool uses:

```
black 0   white 8   red 3   cyan 6   purple 4   green 5   blue 2   yellow 7
orange 4  brown 2   pink 5  dgray 3  mgray 5   lgreen 7  lblue 5  lgray 6
```

---

## 3. Dithering

A checkerboard of two colours blends on a CRT and on VICE's CRT emulation into a colour between them. It costs nothing at runtime and one of the 192 cells per distinct pattern.

**Which pairs work.** Pairs within one luminance level, or one level apart, blend into a believable intermediate. Pairs two or more levels apart shimmer and read as a pattern. The tileset tool warns on a dither whose two colours differ by more than 2 luminance steps.

Good pairs, and what they read as:

| Pair | Reads as | Use |
|---|---|---|
| dark grey + mid grey | a fourth grey | wet asphalt, concrete |
| mid grey + light grey | a fifth grey | sidewalks in shade |
| blue + dark grey | deep water at night | Grassrivers channels |
| cyan + light blue | pale turquoise | Keys shallows |
| green + light green | grass with sun on it | Ambrosia |
| red + orange | terracotta | Bellamar roofs |
| red + purple | wine, brick | Port Gellhorn |
| brown + orange | sand at dusk | Ambrosia dirt |
| yellow + white | hot sand | Bellamar Beach |
| purple + blue | night sky, neon halo | night states |

**Within a cell** you can only dither between the four colours that cell has, so plan the shared colours as pairs. If a region's three shared colours are dark grey, mid grey, and light grey, the ground has five greys available with no cell colours spent.

**Orientation.** Multicolour pixels are 2 wide, so the finest checkerboard is 2 by 1. Horizontal stripes of alternate rows blend less well than checkerboards. Vertical stripes of alternate pixels blend best on PAL because of the next section.

---

## 4. PAL blending

On a real PAL C64 through composite video, horizontally adjacent pixels of different hue smear into each other. The demo scene uses this deliberately to get hundreds of perceived colours. VICE shows it with CRT emulation on. It is free.

Rules of thumb:

- Two hues alternating pixel by pixel on the same row blend almost completely into one intermediate hue at the same brightness.
- Two hues in adjacent cells with a hard vertical edge get a one-pixel fringe. Avoid saturated red next to saturated blue at a vertical edge unless the fringe is wanted.
- Blending does not happen vertically. A horizontal edge between two colours stays sharp.

Use it for water, neon glow, and sunset gradients on the raster split, not for anything that must stay crisp such as text, dashes, and windows.

---

## 5. The palette report

`make palette` runs `tools/b64palette.py`, which enumerates every colour a screen can show for a given set of three shared colours: the solids, the blends that pass the dither rule, the mixed RGB of each blend, and how many are visually distinct. It writes a swatch PNG per trio, with each blend shown as its mixed colour above its actual checkerboard, and a markdown table with the RGB values. Draw from the swatch, not from memory.

Measured for the Priors-64 regions, day and night:

| Rule | Per screen | Whole game |
|---|---|---|
| Blends within 2 luminance steps, strict distinctness | 18 to 22 | 37 |
| Blends within 3 steps, strict distinctness | 21 to 24 | 44 |
| Blends within 3 steps, looser distinctness | | 63 |
| Any pair at all | | 73 |

So a screen shows about 20 usable colours, and the game as a whole reaches 64 if the 3-step blends are allowed. The 3-step pairs are the ones that start to read as texture on an LCD, so the rule is: use 2-step blends for flat materials that must read as one colour, and reserve 3-step blends for surfaces that are allowed to have grain, such as gravel, sawgrass, rough water, and shadow. `--step=3` on the tool shows the larger set.

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
| Leonida Keys | light blue | blue |
| Grassrivers | brown | blue |
| Port Gellhorn | orange | red |
| Ambrosia | green | mid grey |
| Mount Kalaga | light green | mid grey |

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
