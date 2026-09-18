; backlot-64 multiplexer harness.
;
; 32 virtual sprites, each a solid 24 x 21 block in its own colour, on paths
; the checker can reproduce exactly: sprite i sits in column (i mod 8), 38
; pixels apart, and falls two lines a frame, wrapping every 128 lines:
;
;     x = 24 + (i mod 8) * 38
;     y = 60 + ((2 * t + phase[i]) & 127)
;
; For the first 400 lists the four sprites of a column are 32 lines apart
; and the columns 4 lines apart, so no line has more than six.  After that
; the columns bunch into 8 lines and the sets 16 apart, so lines carry up to
; sixteen: the multiplexer's overload behaviour is what shows.
;
; Each frame the callback builds the list between b64_bench_begin/end, then
; counts in a fixed loop until raster line 240, so the count is the time
; the frame had left over after the list and every interrupt.
; Results at $E000 for tools/b64check.py:
;   +0  free, last frame (loop passes, 23 cycles each)   +2  free, worst frame
;   +4  build cycles, last (24-bit)                      +7  build cycles, worst
;   +10 t of the list just built (16-bit)                +12 1 once dense
;   +13 the $D031 value asked for   +14 spr_limit   +15 mux_first
; test_done is reached once, after the dense phase has run 200 lists.
;
; Assembled with -D MUX64 it is the turbo tier's harness: 64 sprites, eight
; columns of eight, one sprite every 3 lines down 192 lines, so each column's
; sprites are 24 lines apart: a hardware sprite comes free two lines before
; its next occupant.  All eight hardware sprites are multiplexed and the
; turbo is asked for at its fastest.  The fast tier's model (a 1-line lead)
; takes all 64.  Without the turbo (VICE) it runs at 1 MHz, where the
; allocation drops what the chain cannot write in time, and a 64-sprite
; list takes more than a frame to build.
;
; The freeze protocol, for tools/b64muxhw.py on VICE or on a C64 Ultimate
; over its REST API: the host writes 1 to $E020; the harness stops building
; lists, so the engine shows the same list every frame and every table and
; log holds still; three frames later it writes 1 to $E021.  The host reads
; what it needs and writes 0 to $E020 to let it run on.

.include "b64.inc"
.include "slots.inc"

.export game_main
.import spr_limit, mux_first, b64_turbo

.ifdef MUX64
NSPR    = 64
.else
NSPR    = 32
.endif
DENSE_AT = 400
FREEZE_REQ = $E020
FREEZE_ACK = $E021

.segment "GAMETOP"
res:    .res 16
t:      .res 2
t2:     .res 1                  ; MUX64: 2t mod 192
frozen: .res 1
f0:     .res 1
cnt:    .res 2
idx:    .res 1

.segment "GAME"
game_main:
        jsr b64_init
        ; the harness tests the 32-sprite path in VICE at 1 MHz, where the
        ; engine would allow 24: it raises the limit itself
.ifdef MUX64
        jsr b64_turbo_fast      ; nothing happens without the Ultimate's register
        lda #0
        sta mux_first           ; all eight hardware sprites
.endif
        lda #B64_MAX_SPRITES    ; this is a test of the multiplexer's full list
        sta spr_limit
        lda b64_turbo
        sta res+13
        lda spr_limit
        sta res+14
        lda mux_first
        sta res+15
        lda #0
        sta FREEZE_REQ
        sta FREEZE_ACK
        sta frozen
        sta t2
        B64_SET24 b64_reu, SLOT_TILESET0
        jsr b64_load_tileset    ; the HUD's font
        ldx #12
        lda #0
:       sta res,x
        dex
        bpl :-
        sta t
        sta t+1
        lda #$FF
        sta res+2
        sta res+3
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run

frame:
        lda FREEZE_REQ
        beq @live
        lda frozen              ; frozen: no new list, so the engine re-shows the last
        cmp #3
        bcs :+
        inc frozen
        rts
:       lda #1
        sta FREEZE_ACK
        rts
@live:  lda #0
        sta frozen
        sta FREEZE_ACK
        jsr b64_bench_begin
        jsr b64_spr_begin
        ldx #0
@s:     stx idx
        lda xs_lo,x
        sta b64_spr_x
        lda xs_hi,x
        sta b64_spr_x+1
.ifdef MUX64
        lda t2                  ; (t2 + 3i) mod 192, from line 50
        clc
        adc phase64,x
        bcs @wrap
        cmp #192
        bcc @inrange
        sbc #192
        jmp @inrange
@wrap:  adc #63                 ; carry set: (sum - 256) + 64 = sum - 192
@inrange:
        clc
        adc #50
.else
        lda t
        asl
        clc
        ldy res+12
        bne :+
        adc phase_n,x
        jmp :++
:       adc phase_d,x
:       and #127
        clc
        adc #60
.endif
        sta b64_spr_y
        lda colours,x
        sta b64_spr_colour
        txa
        and #7
        clc
        adc #1
        sta b64_spr_slot        ; eight slots shared: every sprite shows the same block
        lda #0
        sta b64_spr_flags
        B64_SET24 b64_reu, SLOT_BLOCK
        jsr b64_spr_add
        ldx idx
        inx
        cpx #NSPR
        bne @s
        jsr b64_spr_end
        jsr b64_bench_end
        lda b64_val
        sta res+4
        lda b64_val+1
        sta res+5
        lda b64_val+2
        sta res+6
        ; worst build
        lda res+9
        cmp b64_val+2
        bcc @newmax
        bne @keepmax
        lda res+8
        cmp b64_val+1
        bcc @newmax
        bne @keepmax
        lda res+7
        cmp b64_val
        bcs @keepmax
@newmax:
        lda b64_val
        sta res+7
        lda b64_val+1
        sta res+8
        lda b64_val+2
        sta res+9
@keepmax:
        lda t
        sta res+10
        lda t+1
        sta res+11
        inc t
        bne :+
        inc t+1
:
.ifdef MUX64
        lda t2
        clc
        adc #2
        cmp #192
        bcc :+
        sbc #192
:       sta t2
        jmp @soak0              ; one layout, no dense phase
.endif
        ; dense from list DENSE_AT; done 200 lists later
        lda t+1
        cmp #>DENSE_AT
        bne :+
        lda t
        cmp #<DENSE_AT
        bne :+
        lda #1
        sta res+12
:       lda t+1
        cmp #>(DENSE_AT+200)
        bne @soak0
        lda t
        cmp #<(DENSE_AT+200)
        bne @soak0
        jsr test_done
@soak0: ; count until raster line 240, just before the vertical blank:
        ; what is left of this frame for a game (the count stops short of the
        ; blank so the engine's own loop still runs every frame)
        lda #0
        sta cnt
        sta cnt+1
@soak:  inc cnt                 ; 5
        bne :+                  ; 3
        inc cnt+1
:       lda VIC_CTRL1           ; 4
        bmi @soak               ; 2: lines 256-311, keep counting
        lda VIC_HLINE           ; 4
        cmp #240                ; 2
        bcc @soak               ; 3: 23 cycles a pass
soaked:                         ; line 240: every visible row of this frame is drawn (the checker screenshots here)
        lda cnt
        sta res
        lda cnt+1
        sta res+1
        cmp res+3
        bcc @newmin
        bne @keepmin
        lda cnt
        cmp res+2
        bcs @keepmin
@newmin:
        lda cnt
        sta res+2
        lda cnt+1
        sta res+3
@keepmin:
        rts

test_done:                      ; the test runner breaks here
        rts

.segment "GAME"                ; example data lives with the example, not in the engine area
xs_lo:
.repeat NSPR, i
        .byte <(24 + (i .mod 8) * 38)
.endrepeat
.ifdef MUX64
; one sprite every 3 lines: eight columns 3 lines apart, each column's
; sprites 24 lines apart
phase64:
.repeat NSPR, i
        .byte i * 3
.endrepeat
.endif
xs_hi:
.repeat NSPR, i
        .byte >(24 + (i .mod 8) * 38)
.endrepeat
; normal: columns 4 lines apart, the four sprites of a column 32 apart
phase_n:
.repeat NSPR, i
        .byte <((i .mod 8) * 4 + (i / 8) * 32)
.endrepeat
; dense: eight columns within 8 lines, the sets 16 apart
phase_d:
.repeat NSPR, i
        .byte <((i .mod 8) * 1 + (i / 8) * 16)
.endrepeat
colours:
.repeat NSPR, i
        .byte 1 + (i .mod 15)
.endrepeat
