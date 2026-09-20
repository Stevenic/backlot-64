# Views: how the city is drawn

What the playfield looks like, why, and what each choice costs. The decisions
here were taken between 17 and 19 September 2026, against reference sheets and
then against a generated reference image. Everything stated as a cost was
measured; the tools that measured it are named at each point.

## 1. The question

A top-down city has no elevation: a six-storey block and a bungalow are the
same rectangle. Five ways of telling a building's height were drawn as
reference sheets and built as tilesets (`tools/b64tileset.py`,
`city_tileset`), so the cost of each is a number rather than an opinion:

| style | what marks the height | characters |
|---|---|---|
| `flat` | the shadow's length alone | 57 |
| `reveal` | a wall face below the south edge and beside the east | 72 |
| `tiers` | setbacks, a smaller roof stacked on the one below | 63 |
| `bands` | floor lines round the south and east edges | 61 |
| `cut` | a cutaway slice down one side, its floors showing | 68 |

All five fit. `flat` was kept for the district at 800,900 because the shadow
costs nothing per building: it is the same three characters however tall the
block is.

## 2. The band city

The direction that survived the exploration is not a height cue at all. It
comes from a generated reference (`images/city-band.png`, chosen from the variants of `images/city-mono.png`):
the street is drawn as three horizontal bands — **the far side's facades
along the top, the road across the middle, the near side's roofs below**.
Elevation is told by which band you are in, not by any per-building trick.

The district at 1200,1200 is laid in a period of seven metatile rows, 224
pixels, so one screen holds the whole composition (`tools/b64world.py`,
`district_band`):

| rows | what |
|---|---|
| 0 | the far roofs behind their parapet, and the cornice |
| 1 | two storeys of windows, the awning, the shopfront |
| 2 | the far pavement, kerbed on the road side |
| 3-4 | the road: two lanes, the broken centre line, a crossing every 24 |
| 5 | the near pavement and the roof's north parapet |
| 6 | the roofs, with their plant: air handlers, tanks, stairwells |

`bellamar_band` draws it in **33 characters and 22 metatiles**.

## 3. The colour arithmetic

This is what decides the art, and it is easy to get backwards.

In multicolour text mode a cell's own colour is the **low three bits** of its
colour nibble; bit 3 only marks the cell multicolour. So the colour a cell may
add is one of the first eight — and of those only black and white are grey.
Every other grey has to come from the three registers the whole screen shares
(`docs/ART.md` section 1, after Bauer 3.7.3.2).

The band city therefore shares black, dark grey and light grey, and lets a
cell add white. Four greys a cell, five on screen if a raster split changes a
register between bands.

On top of the chip, this engine packs a cell's colour into its screen code so
the scroller writes one byte a cell and never reads a colour table (after
Cadaver; `tools/b64tileset.py`, `pack`). A colour value gets twelve codes and
no more, so **white detail across the whole city is a budget of twelve
characters**. `bellamar_band` spends ten of them.

## 4. Encoding a picture into a charset

`tools/b64band.py` takes any image and fits it to the chip at design time:
scale to C64 pixels, quantise every 8x8 cell against the shared registers,
then cluster the cells onto a legal charset — Lloyd's algorithm, a cluster's
character drawn from its members' mean, twelve per colour for the characters
that show a colour and the rest sharing what is left.

    b64band.py measure <image.png>                what it would cost
    b64band.py analyse <image.png>                where the detail goes
    b64band.py encode  <image.png> --chars 96 --tileset out.bin --strip out.strip
                       --road 3,4 --walk 2,5 --solid 0,1,6,7

`encode` emits an engine tileset: the fitted cells are the charset, every
distinct 4x4 block is a metatile, and the block ids are a strip the world lays
down (`tools/b64world.py`, `district_image`). The row kinds give the metatiles
their properties, which is what makes the result a map rather than a backdrop
— traffic drives on an encoded picture. The district at 1500,1200 is the
reference image itself: **94 characters, 96 metatiles**.

## 5. What the encoding costs

Measured on the reference at 384x256 (`b64band.py analyse`), as mean absolute
luma error of 255 per displayed pixel:

| stage | error | the cost of |
|---|---|---|
| multicolour pairing, 320 to 160 across | 7.0 | the format |
| + four colours a cell | 14.3 | the palette |
| + 96 characters, 12 a colour | 20.9 | the charset |

Roughly a third each. Drawn freely the picture wants 852 characters and 179
of them show white; the engine has 192 codes and 12 white ones.

What relaxing each limit would buy:

| | error | gain |
|---|---|---|
| 192 characters instead of 96 | 19.5 | 7% |
| a colour byte a cell (a colour table, doubling the fill) | 18.8 | 10% |
| per-band registers and per-band charset | 17.5 | 16% |
| no charset limit at all | 14.3 | 32% |
| hires cells where they beat multicolour | 14.3 | none: 24 cells of 1536 want hires |

Two conclusions the engine should act on. **The charset is not the binding
constraint** — doubling it buys 1.4 luma. And **hires is not the answer for a
grey city**: a hires cell keeps the full 320 pixels but shows two colours, and
almost every cell of this picture needs three or four.

The loss is not spread evenly. By band, fitted at 96 characters:

    rows  4-11   facade windows and shopfronts   28.0, 29.3
    rows 16-19   the road                         8.9
    rows 24-31   the roofs                       26.6, 23.6

Flat asphalt survives; the detail the eye goes to does not.

## 6. What to do next: bands all the way down

The city is banded by construction, so the band boundaries are free
information, and both of the chip's per-screen limits are per-*band* limits if
the raster is used:

- **The three shared registers** can be rewritten at a band boundary. Facades,
  road and roofs each get their own three greys.
- **`$D018` selects which 2 KB of the VIC bank is the charset.** One store,
  three cycles, and every row below it reads a different set. Per-band
  charsets cost nothing at the raster; they cost bank space.

Measured together, that is the 17.5 above: a 16% gain, larger than any other
relaxation available.

The constraint is residency, not bandwidth. Bank 1 has eight 2 KB slots and
seven are spoken for — screens at $4000, the charset at $4800, sprites from
$5000 to $5BFF, the cutscene's colour screen at $5C00, the physics module at
$6000. A second resident charset needs the sprite frames cut from 48 to 32, or
the physics module moved out of the bank.

Streaming keeps them fed. REU DMA measured inside the display (`budgets.txt`):
64 bytes 180 cycles, 256 bytes 380, 1 KB 1,280, 4 KB 4,810 — about 1.2 cycles
a byte plus 116 of setup. So a whole 2 KB charset is about 2,500 cycles, 13% of
a PAL frame; one band's worth of characters is 380, about 2%. What cannot be
done is rewriting a character mid-screen between two rows: a badline leaves the
CPU about 20 cycles. Charset streaming belongs in the vertical blank, and the
mid-screen change is the `$D018` flip.
