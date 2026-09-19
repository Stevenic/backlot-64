; backlot-64 collision: the questions a game asks, and shots (docs/PHYSICS.md).
;
; A module for region A ($8000, overlay.cfg), loaded beside a physics module
; and reading the same body tables at their fixed addresses
; (modules/physics/defs.inc).  Detection and response for moving bodies stay
; in the physics module; this answers questions about the world and the
; bodies in it, and moves shots, which are too fast for the physics step:
; a shot's path is traced in steps of 4 pixels, less than the smallest
; body, so it cannot pass through a wall or a body between frames.
;
; Zero page $90-$9F is the module's.

.include "b64.inc"
.include "defs.inc"

.export col_init, col_line, col_point, col_box, col_tile, col_near, shot_fire, shot_step
.export col_x0, col_y0, col_x1, col_y1, col_skip, col_mask, col_body, col_hx, col_hy, col_bits, col_z
.export sh_on, sh_xl, sh_xh, sh_yl, sh_yh, NS
.export fx_x, fx_y, fx_t, fx_k
.export throw_fire, th_on, th_xl, th_xh, th_yl, th_yh, th_zh, NT

NS      = 8                     ; shots in flight at once
NT      = 4                     ; things thrown at once
GRAV    = 12                    ; gravity, 1/256 pixel a frame each frame
FUSE    = 70                    ; frames before a grenade goes off
BLAST   = 40                    ; its reach, pixels
STEP    = 4                     ; a traced path's step, pixels: under the smallest body (6)

q0      = $90                   ; temporaries
q1      = $91
q2      = $92
q3      = $93
q4      = $94
q5      = $95
lx      = $96                   ; the traced point, 16.8: fraction, low, high
lxl     = $97
lxh     = $98
ly      = $99
lyl     = $9A
lyh     = $9B
sxl     = $9C                   ; the step, 8.8 signed
sxh     = $9D
syl     = $9E
syh     = $9F

.segment "OVERLAY"
        jmp col_init            ; +0   no shots
        jmp col_line            ; +3   col_x0/y0 to col_x1/y1: C=1 on a hit
        jmp col_point           ; +6   col_x0/y0: C=1, col_body = a body there
        jmp col_box             ; +9   col_x0/y0 - col_x1/y1: col_bits, C=1 if any
        jmp col_tile            ; +12  col_x0/y0: A = the properties there
        jmp col_near            ; +15  X = body, A = reach: Y = the nearest, C=1
        jmp shot_fire           ; +18  col_x0/y0, A = heading, Y = speed, X = owner
        jmp shot_step           ; +21  every shot and every thrown thing one frame
        jmp throw_fire          ; +24  col_x0/y0, A = heading, Y = speed: a grenade

col_init:
        ldx #NS-1
        lda #0
:       sta sh_on,x
        dex
        bpl :-
        ldx #NT-1
:       sta th_on,x
        dex
        bpl :-
        sta fx_t
        sta col_z
        rts

; level: X = body -> C=1 if it is 8 pixels or more above or below col_z, the
; height a question is asked at: bodies at different heights pass each other
level:
        lda pb_zh,x
        sec
        sbc col_z
        bcs :+
        eor #$FF
        adc #1
:       cmp #8
        rts

; ---------------------------------------------------------------------------
; col_tile: col_x0/y0 -> A = the properties of the metatile there.  One byte
; of DMA, unless it is the metatile asked about last.
col_tile:
        lda col_x0              ; metatile x = x >> 5, y = y >> 5
        sta q0
        lda col_x0+1
        sta q1
        lda col_y0
        sta q2
        lda col_y0+1
        sta q3
        ldy #5
:       lsr q1
        ror q0
        lsr q3
        ror q2
        dey
        bne :-
        lda q0
        cmp tile_x
        bne @fetch
        lda q1
        cmp tile_x+1
        bne @fetch
        lda q2
        cmp tile_y
        bne @fetch
        lda q3
        cmp tile_y+1
        bne @fetch
        lda tile_p
        rts
@fetch: lda q0
        sta tile_x
        lda q1
        sta tile_x+1
        lda q2
        sta tile_y
        lda q3
        sta tile_y+1
        lda q2                  ; world + (y << 11 | x)
        and #31
        asl
        asl
        asl
        ora q1
        sta q4
        lda q3
        asl
        asl
        asl
        sta q5
        lda q2
        lsr
        lsr
        lsr
        lsr
        lsr
        ora q5
        pha
        lda q0
        clc
        adc phys_world
        sta b64_reu
        lda q4
        adc phys_world+1
        sta b64_reu+1
        pla
        adc phys_world+2
        sta b64_reu+2
        lda #<tile_b
        sta b64_ptr
        lda #>tile_b
        sta b64_ptr+1
        lda #1
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ldy tile_b
        lda B64_PROPS,y
        sta tile_p
        rts

; ---------------------------------------------------------------------------
; col_point: col_x0/y0 -> C=1 and col_body = the first body whose box holds it
col_point:
        ldx #NB-1
@b:     lda pb_mov,x
        beq @n
        cpx col_skip
        beq @n
        jsr level
        bcs @n
        jsr inbox
        bcs @hit
@n:     dex
        bpl @b
        lda #$FF
        sta col_body
        clc
        rts
@hit:   stx col_body
        sec
        rts

; inbox: X = body, (col_x0, col_y0) -> C=1 if the point is in its box
inbox:
        lda col_x0
        sec
        sbc pb_xl,x
        sta q0
        lda col_x0+1
        sbc pb_xh,x
        jsr within
        bcc @no
        lda col_y0
        sec
        sbc pb_yl,x
        sta q0
        lda col_y0+1
        sbc pb_yh,x
        jmp within
@no:    rts
; within: q0 = low byte, A = high byte of a difference, X = body -> C=1 if |d| <= its half size
within:
        beq @pos
        cmp #$FF
        bne @out
        lda q0                  ; negative: -d <= hw  <=>  d + hw >= 0
        clc
        adc pb_hw,x
        rts                     ; C=1 if it did not borrow past zero
@pos:   lda pb_hw,x
        cmp q0
        rts                     ; C=1 if hw >= d
@out:   clc
        rts

; col_box: col_x0/y0 - col_x1/y1 (x0 <= x1, y0 <= y1) -> col_bits, a bit a
; body whose box overlaps (bit b of col_bits for body b), C=1 if any
col_box:
        lda #0
        sta col_bits
        sta col_bits+1
        ldx #NB-1
@b:     lda pb_mov,x
        beq @n
        jsr level
        bcs @n
        jsr overlap
        bcc @n
        txa                     ; set the body's bit
        cmp #8
        bcs @hi
        tay
        lda bits,y
        ora col_bits
        sta col_bits
        jmp @n
@hi:    sbc #8
        tay
        lda bits,y
        ora col_bits+1
        sta col_bits+1
@n:     dex
        bpl @b
        lda col_bits
        ora col_bits+1
        cmp #1                  ; C=1 if any
        rts

; overlap: X = body -> C=1 if its box overlaps col_x0/y0 - col_x1/y1
overlap:
        lda pb_xl,x             ; body right = x + hw >= x0
        clc
        adc pb_hw,x
        sta q0
        lda pb_xh,x
        adc #0
        sta q1
        lda q0
        cmp col_x0
        lda q1
        sbc col_x0+1
        bcc @no
        lda pb_xl,x             ; body left = x - hw <= x1
        sec
        sbc pb_hw,x
        sta q0
        lda pb_xh,x
        sbc #0
        sta q1
        lda col_x1
        cmp q0
        lda col_x1+1
        sbc q1
        bcc @no
        lda pb_yl,x             ; the same in y
        clc
        adc pb_hw,x
        sta q0
        lda pb_yh,x
        adc #0
        sta q1
        lda q0
        cmp col_y0
        lda q1
        sbc col_y0+1
        bcc @no
        lda pb_yl,x
        sec
        sbc pb_hw,x
        sta q0
        lda pb_yh,x
        sbc #0
        sta q1
        lda col_y1
        cmp q0
        lda col_y1+1
        sbc q1
@no:    rts

; col_near: X = body, A = reach -> Y = the nearest other body within reach
; on both axes (by the larger distance), C=1; C=0 if none
col_near:
        sta q4
        stx q5
        lda #$FF
        sta q3                  ; the best distance so far
        sta col_body
        ldy #NB-1
@b:     lda pb_mov,y
        beq @n
        cpy q5
        beq @n
        lda pb_zh,y             ; at the asker's height, within 8 pixels
        sec
        sbc pb_zh,x
        bcs :+
        eor #$FF
        adc #1
:       cmp #8
        bcs @n
        lda pb_xl,y
        sec
        sbc pb_xl,x
        sta q0
        lda pb_xh,y
        sbc pb_xh,x
        jsr absd
        bcs @n
        sta q1
        lda pb_yl,y
        sec
        sbc pb_yl,x
        sta q0
        lda pb_yh,y
        sbc pb_yh,x
        jsr absd
        bcs @n
        cmp q1                  ; the larger of the two
        bcs :+
        lda q1
:       cmp q4
        bcs @n                  ; beyond reach
        cmp q3
        bcs @n                  ; no nearer than the best
        sta q3
        sty col_body
@n:     dey
        bpl @b
        ldy col_body
        cpy #$FF
        beq @none
        sec
        rts
@none:  clc
        rts
; absd: q0 = low byte, A = high byte -> A = |d| with C=0 if under 256
absd:
        beq @pos
        cmp #$FF
        bne @far
        lda q0
        beq @far
        eor #$FF
        clc
        adc #1
        clc
        rts
@pos:   lda q0
        clc
        rts
@far:   sec
        rts

; ---------------------------------------------------------------------------
; col_line: from col_x0/y0 to col_x1/y1 (at most 255 pixels on each axis),
; in steps of STEP pixels along the longer axis.  At each step the map
; (the wall bits in col_mask) and every body whose box could lie on the path
; (but col_skip).  C=1 on a hit: col_body = the body, or $FF for a wall;
; col_hx/hy = the last clear point for a wall, the point in the body for a
; body.  C=0: the path is clear to its end.
col_line:
        lda col_x1              ; dx, dy
        sec
        sbc col_x0
        sta dxl
        lda col_x1+1
        sbc col_x0+1
        sta dxh
        lda col_y1
        sec
        sbc col_y0
        sta dyl
        lda col_y1+1
        sbc col_y0+1
        sta dyh
        lda dxl                 ; the steps: the longer |d| / STEP, at least 1
        sta q0
        lda dxh
        jsr absd
        bcc :+
        lda #255
:       sta q1
        lda dyl
        sta q0
        lda dyh
        jsr absd
        bcc :+
        lda #255
:       cmp q1
        bcs :+
        lda q1
:       clc
        adc #STEP-1
        bcc :+
        lda #255
:       lsr
        lsr                     ; / 4
        bne :+
        lda #1
:       sta nstep
        ; the step, 8.8: d * 256 / n
        lda dxl
        ldy dxh
        jsr stepof
        stx sxl
        sta sxh
        lda dyl
        ldy dyh
        jsr stepof
        stx syl
        sta syh
        ; the bodies that could lie on the path: their boxes meet the path's box
        lda col_x0              ; the start, kept: path_box puts the ends in order
        sta pa_x0
        lda col_x0+1
        sta pa_x0+1
        lda col_y0
        sta pa_y0
        lda col_y0+1
        sta pa_y0+1
        jsr path_box
        lda #0
        sta ncand
        ldx #NB-1
@c:     lda pb_mov,x
        beq @cn
        cpx col_skip
        beq @cn
        jsr level
        bcs @cn
        jsr overlap
        bcc @cn
        txa
        ldy ncand
        sta cand,y
        inc ncand
@cn:    dex
        bpl @c
        ; walk the path
        lda #$80                ; start at the middle of the pixel
        sta lx
        sta ly
        lda pa_x0
        sta lxl
        lda pa_x0+1
        sta lxh
        lda pa_y0
        sta lyl
        lda pa_y0+1
        sta lyh
@walk:  lda lxl                 ; the point: is it in a wall?
        sta col_x0
        lda lxh
        sta col_x0+1
        lda lyl
        sta col_y0
        lda lyh
        sta col_y0+1
        jsr col_tile
        and col_mask
        bne @wall
        ldy ncand               ; in a body?
        beq @clear
@cb:    ldx cand-1,y
        sty q5
        jsr inbox
        ldy q5
        bcs @body
        dey
        bne @cb
@clear: lda col_x0              ; the last clear point
        sta col_hx
        lda col_x0+1
        sta col_hx+1
        lda col_y0
        sta col_hy
        lda col_y0+1
        sta col_hy+1
        dec nstep
        bmi @end
        lda lx                  ; one step on
        clc
        adc sxl
        sta lx
        lda lxl
        adc sxh
        sta lxl
        lda sxh
        and #$80
        beq :+
        lda #$FF
:       adc lxh
        sta lxh
        lda ly
        clc
        adc syl
        sta ly
        lda lyl
        adc syh
        sta lyl
        lda syh
        and #$80
        beq :+
        lda #$FF
:       adc lyh
        sta lyh
        jmp @walk
@end:   lda #$FF
        sta col_body
        clc
        rts
@wall:  lda #$FF
        sta col_body
        sec
        rts
@body:  stx col_body
        lda col_x0
        sta col_hx
        lda col_x0+1
        sta col_hx+1
        lda col_y0
        sta col_hy
        lda col_y0+1
        sta col_hy+1
        sec
        rts

; stepof: A = low, Y = high of a signed difference (|d| < 256) -> X = low,
; A = high of d * 256 / nstep, 8.8 signed
stepof:
        sta q0
        sty q2                  ; the sign
        tya
        jsr absd
        bcc :+
        lda #255
:       sta q1                  ; |d|: the dividend is |d| * 256
        lda #0
        sta q0
        ; 16 by 8 division: (q1:q0) / nstep -> quotient in q1:q0
        ldx #16
        lda #0
@div:   asl q0
        rol q1
        rol a
        bcs @sub
        cmp nstep
        bcc @next
@sub:   sbc nstep
        inc q0
@next:  dex
        bne @div
        lda q2
        bpl @pos
        lda #0
        sec
        sbc q0
        tax
        lda #0
        sbc q1
        rts
@pos:   ldx q0
        lda q1
        rts

; path_box: col_x0/y0 - col_x1/y1 put in order, x0 <= x1 and y0 <= y1,
; for the overlap test against each body
path_box:
        lda dxh                 ; x0 > x1: swap
        bpl :+
        lda col_x0
        ldy col_x1
        sta col_x1
        sty col_x0
        lda col_x0+1
        ldy col_x1+1
        sta col_x1+1
        sty col_x0+1
:       lda dyh
        bpl :+
        lda col_y0
        ldy col_y1
        sta col_y1
        sty col_y0
        lda col_y0+1
        ldy col_y1+1
        sta col_y1+1
        sty col_y0+1
:       rts

; ---------------------------------------------------------------------------
; shots.  shot_fire: from col_x0/y0 at heading A, Y pixels a frame, fired by
; body X (which it never hits) -> C=1 if a shot was free
shot_fire:
        sta q4                  ; the heading
        sty q5                  ; the speed
        stx q3
        ldx #NS-1
:       lda sh_on,x
        beq @free
        dex
        bpl :-
        clc
        rts
@free:  lda #40                 ; frames it flies
        sta sh_on,x
        lda q3
        sta sh_own,x
        ldy q3                  ; at the firer's height (none: the ground)
        lda #0
        cpy #NB
        bcs :+
        lda pb_zh,y
:       sta sh_z,x
        lda #$80
        sta sh_xf,x
        sta sh_yf,x
        lda col_x0
        sta sh_xl,x
        lda col_x0+1
        sta sh_xh,x
        lda col_y0
        sta sh_yl,x
        lda col_y0+1
        sta sh_yh,x
        lda q4                  ; vx = cos * speed, vy = sin * speed (8.8)
        clc
        adc #64
        tay
        lda PHYS_SINE,y
        jsr times_speed
        sta sh_vxl,x
        tya
        sta sh_vxh,x
        ldy q4
        lda PHYS_SINE,y
        jsr times_speed
        sta sh_vyl,x
        tya
        sta sh_vyh,x
        sec
        rts
; times_speed: A = a sine (1.7) -> A = low, Y = high of sine * q5 * 2 (8.8)
times_speed:
        sta q0
        lda #0
        sta q1
        lda q0                  ; sign-extend, * 2
        bpl :+
        dec q1
:       asl q0
        rol q1
        lda #0
        sta q2
        sta q3
        ldy q5
        beq @done
@add:   lda q2
        clc
        adc q0
        sta q2
        lda q3
        adc q1
        sta q3
        dey
        bne @add
@done:  lda q2
        ldy q3
        rts

; shot_step: every shot one frame along its path.  A wall stops it; a body
; it meets takes damage and a push along the shot, and is knocked down if it
; is on foot; either way the shot ends and leaves an effect (fx_x/y, fx_t
; frames) for the game to draw.
shot_step:
        lda fx_t
        beq :+
        dec fx_t
:       jsr throw_step
        ldx #NS-1
@s:     lda sh_on,x
        beq @n
        stx cur_s
        jsr one_shot
        ldx cur_s
@n:     dex
        bpl @s
        lda #0                  ; the game's questions: at the ground again
        sta col_z
        rts

one_shot:
        dec sh_on,x
        bne :+
        rts                     ; spent
:       lda sh_xl,x             ; from here...
        sta col_x0
        lda sh_xh,x
        sta col_x0+1
        lda sh_yl,x
        sta col_y0
        lda sh_yh,x
        sta col_y0+1
        lda sh_xf,x             ; ...to where the velocity takes it
        clc
        adc sh_vxl,x
        sta sh_xf,x
        lda sh_xl,x
        adc sh_vxh,x
        sta sh_xl,x
        sta col_x1
        lda sh_vxh,x
        and #$80
        beq :+
        lda #$FF
:       adc sh_xh,x
        sta sh_xh,x
        sta col_x1+1
        lda sh_yf,x
        clc
        adc sh_vyl,x
        sta sh_yf,x
        lda sh_yl,x
        adc sh_vyh,x
        sta sh_yl,x
        sta col_y1
        lda sh_vyh,x
        and #$80
        beq :+
        lda #$FF
:       adc sh_yh,x
        sta sh_yh,x
        sta col_y1+1
        lda sh_own,x
        sta col_skip
        lda sh_z,x
        sta col_z
        lda #P_SOLID
        sta col_mask
        jsr col_line
        bcs @hit
        rts
@hit:   ldx cur_s
        lda #0
        sta sh_on,x
        lda col_hx              ; the effect where it stopped
        sta fx_x
        lda col_hx+1
        sta fx_x+1
        lda col_hy
        sta fx_y
        lda col_hy+1
        sta fx_y+1
        lda #6
        sta fx_t
        lda #1                  ; a shot's stop
        sta fx_k
        ldy col_body
        cpy #$FF
        beq @done               ; a wall
        lda pb_dmg,y            ; a body: damage
        clc
        adc #16
        bcc :+
        lda #255
:       sta pb_dmg,y
        lda #16
        sta pb_hit,y
        lda sh_vxh,x            ; a push: a quarter of the shot's velocity... over
        cmp #$80                ; the body's own: add vx / 4, vy / 4
        ror a
        cmp #$80
        ror a
        clc
        adc pb_vxh,y
        sta pb_vxh,y
        lda sh_vyh,x
        cmp #$80
        ror a
        cmp #$80
        ror a
        clc
        adc pb_vyh,y
        sta pb_vyh,y
        lda pb_st,y             ; awake, its frame re-derived, and down if on foot
        and #<~ST_SLEEP
        ora #ST_WORLD
        sta pb_st,y
        lda #0
        sta pb_idle,y
        lda pb_mov,y
        cmp #M_FOOT
        bne @done
        lda pb_st,y
        ora #ST_DOWN
        sta pb_st,y
        lda #50
        sta pb_tmr,y
@done:  rts

bits:   .byte $01, $02, $04, $08, $10, $20, $40, $80

; ---------------------------------------------------------------------------
; thrown things.  throw_fire: a grenade from col_x0/y0 at heading A, Y
; pixels a frame, tossed up at a pixel a frame -> C=1 if one was free
throw_fire:
        sta q4
        sty q5
        ldx #NT-1
:       lda th_on,x
        beq @free
        dex
        bpl :-
        clc
        rts
@free:  lda #FUSE
        sta th_on,x
        lda #$80
        sta th_xf,x
        sta th_yf,x
        lda col_x0
        sta th_xl,x
        lda col_x0+1
        sta th_xh,x
        lda col_y0
        sta th_yl,x
        lda col_y0+1
        sta th_yh,x
        lda #0
        sta th_zl,x
        sta th_zh,x
        sta th_vzl,x
        lda #1                  ; tossed up at a pixel a frame: 11 pixels high, down in 40 frames
        sta th_vzh,x
        lda q4
        clc
        adc #64
        tay
        lda PHYS_SINE,y
        jsr times_speed
        sta th_vxl,x
        tya
        sta th_vxh,x
        ldy q4
        lda PHYS_SINE,y
        jsr times_speed
        sta th_vyl,x
        tya
        sta th_vyh,x
        sec
        rts

; throw_step: every thrown thing one frame: gravity, the ground (a bounce at
; a quarter of the speed it landed with, and half its speed along the ground
; lost), walls (the axis that meets one turns back at half speed), and at the
; end of its fuse, a blast
throw_step:
        ldx #NT-1
@t:     lda th_on,x
        beq @n
        stx cur_s
        jsr one_throw
        ldx cur_s
@n:     dex
        bpl @t
        rts

one_throw:
        lda th_vzl,x            ; fall: vz -= g, z += vz
        sec
        sbc #GRAV
        sta th_vzl,x
        lda th_vzh,x
        sbc #0
        sta th_vzh,x
        lda th_zl,x
        clc
        adc th_vzl,x
        sta th_zl,x
        lda th_zh,x
        adc th_vzh,x
        sta th_zh,x
        bpl @air
        lda #0                  ; the ground: bounce at a quarter speed, slow along it
        sta th_zl,x
        sta th_zh,x
        lda th_vzh,x
        sta q1
        lda th_vzl,x
        sta q0
        lda #0
        sec
        sbc q0
        sta q0
        lda #0
        sbc q1
        lsr a
        ror q0
        lsr a
        ror q0
        sta th_vzh,x
        lda q0
        sta th_vzl,x
        lda th_vxh,x            ; and half the speed along the ground
        cmp #$80
        ror th_vxh,x
        ror th_vxl,x
        lda th_vyh,x
        cmp #$80
        ror th_vyh,x
        ror th_vyl,x
@air:   lda th_xl,x             ; along x: a wall there turns it back
        clc
        adc th_vxh,x
        sta col_x0
        lda th_vxh,x
        and #$80
        beq :+
        lda #$FF
:       adc th_xh,x
        sta col_x0+1
        lda th_yl,x
        sta col_y0
        lda th_yh,x
        sta col_y0+1
        jsr col_tile
        ldx cur_s
        and #P_SOLID
        beq @mx
        lda th_vxh,x
        jsr half_back
        sta th_vxh,x
        lda #0
        sta th_vxl,x
        jmp @y
@mx:    lda th_xf,x
        clc
        adc th_vxl,x
        sta th_xf,x
        lda th_xl,x
        adc th_vxh,x
        sta th_xl,x
        lda th_vxh,x
        and #$80
        beq :+
        lda #$FF
:       adc th_xh,x
        sta th_xh,x
@y:     lda th_yl,x             ; along y, the same
        clc
        adc th_vyh,x
        sta col_y0
        lda th_vyh,x
        and #$80
        beq :+
        lda #$FF
:       adc th_yh,x
        sta col_y0+1
        lda th_xl,x
        sta col_x0
        lda th_xh,x
        sta col_x0+1
        jsr col_tile
        ldx cur_s
        and #P_SOLID
        beq @my
        lda th_vyh,x
        jsr half_back
        sta th_vyh,x
        lda #0
        sta th_vyl,x
        jmp @fuse
@my:    lda th_yf,x
        clc
        adc th_vyl,x
        sta th_yf,x
        lda th_yl,x
        adc th_vyh,x
        sta th_yl,x
        lda th_vyh,x
        and #$80
        beq :+
        lda #$FF
:       adc th_yh,x
        sta th_yh,x
@fuse:  dec th_on,x
        beq blast
        rts

; half_back: A = a velocity's high byte -> A = -(it) / 2, rounded away from
; zero; under a pixel a frame it stops
half_back:
        eor #$FF
        clc
        adc #1
        cmp #$80
        ror a
        rts

; blast: X = throw, gone off.  Every body within BLAST pixels (on both axes)
; is pushed away from it, harder the nearer, takes damage, and is knocked
; down if on foot; the flash is left for the game to draw (fx_t = 12).
blast:
        lda th_xl,x
        sta fx_x
        lda th_xh,x
        sta fx_x+1
        lda th_yl,x
        sta fx_y
        lda th_yh,x
        sta fx_y+1
        lda #12
        sta fx_t
        lda #2                  ; a blast
        sta fx_k
        ldy #NB-1
@b:     lda pb_mov,y
        bne :+
        jmp @n
:       lda pb_zh,y             ; a blast reaches 16 pixels up
        cmp #16
        bcc :+
        jmp @n
:
        lda pb_xl,y             ; dx = body - blast
        sec
        sbc fx_x
        sta q0
        lda pb_xh,y
        sbc fx_x+1
        sta bdx
        jsr absd
        bcc :+
        jmp @n
:
        cmp #BLAST
        bcc :+
        jmp @n
:
        sta q2                  ; |dx|
        lda pb_yl,y
        sec
        sbc fx_y
        sta q0
        lda pb_yh,y
        sbc fx_y+1
        sta bdy
        jsr absd
        bcc :+
        jmp @n
:
        cmp #BLAST
        bcc :+
        jmp @n
:
        cmp q2                  ; the larger of |dx| and |dy|
        bcs :+
        lda q2
:       ldx #2                  ; the push: 2 pixels a frame near, 1 beyond half the reach
        cmp #BLAST/2
        bcc :+
        dex
:       stx q3
        lda bdx                 ; away along x
        bmi :+
        lda q3
        jmp :++
:       lda #0
        sec
        sbc q3
:       clc
        adc pb_vxh,y
        sta pb_vxh,y
        lda bdy                 ; and along y
        bmi :+
        lda q3
        jmp :++
:       lda #0
        sec
        sbc q3
:       clc
        adc pb_vyh,y
        sta pb_vyh,y
        lda q3                  ; damage: 20 a pixel of push
        asl
        asl
        sta q0
        asl
        asl
        adc q0
        clc
        adc pb_dmg,y
        bcc :+
        lda #255
:       sta pb_dmg,y
        lda #32
        sta pb_hit,y
        lda pb_st,y
        and #<~ST_SLEEP
        ora #ST_WORLD
        sta pb_st,y
        lda #0
        sta pb_idle,y
        lda pb_mov,y
        cmp #M_FOOT
        beq :+
        jmp @n
:
        lda pb_st,y
        ora #ST_DOWN
        sta pb_st,y
        lda #50
        sta pb_tmr,y
@n:     dey
        bmi @done
        jmp @b
@done:  ldx cur_s
        lda #0
        sta th_on,x
        rts

; ---------------------------------------------------------------------------
.segment "OVERLAY"
col_x0: .res 2                  ; the questions' input
col_y0: .res 2
col_x1: .res 2
col_y1: .res 2
col_skip: .res 1                ; a body the question ignores ($FF none)
col_z:  .res 1                  ; the height it is asked at: bodies 8 pixels or more away pass
col_mask: .res 1                ; the wall bits col_line stops at
col_body: .res 1                ; the answers
col_hx: .res 2
col_hy: .res 2
col_bits: .res 2
tile_x: .res 2                  ; col_tile's last metatile
tile_y: .res 2
tile_p: .res 1
tile_b: .res 1
dxl:    .res 1
dxh:    .res 1
dyl:    .res 1
dyh:    .res 1
nstep:  .res 1
ncand:  .res 1
cand:   .res NB
pa_x0:  .res 2
pa_y0:  .res 2
cur_s:  .res 1
sh_on:  .res NS                 ; shots: frames left, 0 = free
sh_own: .res NS
sh_z:   .res NS                 ; the height it flies at: its firer's
sh_xf:  .res NS
sh_xl:  .res NS
sh_xh:  .res NS
sh_yf:  .res NS
sh_yl:  .res NS
sh_yh:  .res NS
sh_vxl: .res NS
sh_vxh: .res NS
sh_vyl: .res NS
sh_vyh: .res NS
th_on:  .res NT                 ; thrown things: fuse frames left, 0 = none
th_xf:  .res NT
th_xl:  .res NT
th_xh:  .res NT
th_yf:  .res NT
th_yl:  .res NT
th_yh:  .res NT
th_zl:  .res NT                 ; altitude, 8.8
th_zh:  .res NT
th_vxl: .res NT
th_vxh: .res NT
th_vyl: .res NT
th_vyh: .res NT
th_vzl: .res NT
th_vzh: .res NT
bdx:    .res 1
bdy:    .res 1
fx_x:   .res 2                  ; the last hit, for the game to draw
fx_y:   .res 2
fx_t:   .res 1
fx_k:   .res 1                  ; what it was: 1 a shot's stop, 2 a blast
