; backlot-64 physics: the core every physics module assembles (docs/PHYSICS.md).

; ---------------------------------------------------------------------------
; the interface
phys_init:
        ldx #NB-1
        lda #0
:       sta pb_mov,x
        dex
        bpl :-
        rts

; phys_resume: after this module was fetched over another.  Every body's
; map cache again, in this module's own form: the air module folds each
; building's height into it, and must not trust entries another wrote.
phys_resume:
.ifdef AIR
        jsr load_heights
.endif
        ldx #NB-1
@b:     lda pb_mov,x
        beq @n
        stx cur
        jsr cache_load
        ldx cur
@n:     dex
        bpl @b
        rts

; phys_add: A = mover, Y = class, phys_x, phys_y, phys_a -> X = body, C=1
phys_add:
        sta t0
        ldx #NB-1
:       lda pb_mov,x
        beq @free
        dex
        bpl :-
        clc
        rts
@free:  lda t0
        sta pb_mov,x
        tya
        sta pb_cls,x
        lda #0
        sta pb_xf,x
        sta pb_yf,x
        sta pb_vxl,x
        sta pb_vxh,x
        sta pb_vyl,x
        sta pb_vyh,x
        sta pb_vll,x
        sta pb_vlh,x
        sta pb_vtl,x
        sta pb_vth,x
        sta pb_st,x
        sta pb_idle,x
        sta pb_dmg,x
        sta pb_hit,x
        sta pb_tmr,x
        sta pb_in,x
        sta pb_zl,x
        sta pb_zh,x
        sta pb_vzl,x
        sta pb_vzh,x
        sta pb_agl,x
        lda phys_x
        sta pb_xl,x
        lda phys_x+1
        sta pb_xh,x
        lda phys_y
        sta pb_yl,x
        lda phys_y+1
        sta pb_yh,x
        lda phys_a
        sta pb_ang,x
        lda c_hw,y              ; the half size, for the collision module
        sta pb_hw,x
        stx cur
        jsr cache_load
        jsr surface
        sec
        rts

phys_remove:
        lda #0
        sta pb_mov,x
        rts

; phys_push: X = body, phys_x / phys_y = a velocity change, 8.8
phys_push:
        lda pb_vxl,x
        clc
        adc phys_x
        sta pb_vxl,x
        lda pb_vxh,x
        adc phys_x+1
        sta pb_vxh,x
        lda pb_vyl,x
        clc
        adc phys_y
        sta pb_vyl,x
        lda pb_vyh,x
        adc phys_y+1
        sta pb_vyh,x
wake_world:
        lda pb_st,x
        and #<~ST_SLEEP
        ora #ST_WORLD
        sta pb_st,x
        lda #0
        sta pb_idle,x
        rts

; ---------------------------------------------------------------------------
; phys_step: every awake body one frame, then every pair that could touch
phys_step:
        ldx #NB-1
@b:     stx cur
        lda pb_mov,x
        beq @next
        lda #0
        sta pb_hit,x
        lda pb_st,x
        and #<~ST_WALL
        sta pb_st,x
        bpl @awake              ; bit 7: asleep, until input wakes it
        lda pb_in,x
        beq @next
        lda pb_st,x
        and #<~ST_SLEEP
        sta pb_st,x
        lda #0
        sta pb_idle,x
@awake: jsr mover
        ldx cur
        jsr move_x
        jsr move_y
        jsr surface
        jsr rest
@next:  ldx cur
        dex
        bpl @b
        jmp pairs

; mover: X = body.  Its mover, through the module's table (mover_tab holds
; each address less one, for the rts); a mover the module does not carry is
; hold, and the body keeps still until a module that has it is loaded.
mover:
        lda pb_mov,x
        asl
        tay
        lda mover_tab+1,y
        pha
        lda mover_tab,y
        pha
        rts
; Its own mover takes up from rest when it returns (ST_WORLD: the vehicle's
; frame is worked out again from the world velocity, now none).
hold:
        lda #0
        sta pb_vxl,x
        sta pb_vxh,x
        sta pb_vyl,x
        sta pb_vyh,x
        lda pb_st,x
        ora #ST_WORLD
        sta pb_st,x
        rts

; rest: a body with no input and no speed for 32 frames sleeps
rest:
        lda pb_in,x
        bne @busy
        lda pb_st,x
        and #ST_DOWN
        bne @busy
        lda pb_vxl,x
        ora pb_vxh,x
        ora pb_vyl,x
        ora pb_vyh,x
        ora pb_vll,x
        ora pb_vlh,x
        ora pb_vtl,x
        ora pb_vth,x
        bne @busy
        inc pb_idle,x
        lda pb_idle,x
        cmp #32
        bcc @done
        lda pb_st,x
        ora #ST_SLEEP
        sta pb_st,x
@done:  rts
@busy:  lda #0
        sta pb_idle,x
        rts

; ---------------------------------------------------------------------------
; numbers.  umul8: A * Y (unsigned) -> mr_lo/mr_hi, by quarter squares:
; a * b = f(a + b) - f(|a - b|), f(x) = x * x / 4.
; After Codebase64, "Seriously fast multiplication".  Changed: one table of f
; (1 KB) indexed by the sum and the difference, instead of four offset tables.
umul8:
        sty ub
        sta ua
        clc
        adc ub
        tay                     ; a + b, bit 8 in C
        bcc @lo
        lda f_lo+256,y
        sta mr_lo
        lda f_hi+256,y
        sta mr_hi
        jmp @dif
@lo:    lda f_lo,y
        sta mr_lo
        lda f_hi,y
        sta mr_hi
@dif:   lda ua
        sec
        sbc ub
        bcs :+
        eor #$FF                ; b > a: |a - b| = b - a
        adc #1
:       tay
        lda mr_lo
        sec
        sbc f_lo,y
        sta mr_lo
        lda mr_hi
        sbc f_hi,y
        sta mr_hi
        rts

; smul: m16 (8.8, signed) * A (1.7, signed) -> res (8.8, signed).  Keeps X.
; A zero on either side costs a test (a heading along an axis, a car standing).
smul:
        ldy #0
        sty sgn
        tay
        beq @zero
        lda m16
        ora m16+1
        bne :+
@zero:  sta res                 ; A = 0 here either way
        sta res+1
        rts
:       tya
        bpl :+
        eor #$FF
        clc
        adc #1
        inc sgn
:       sta t4                  ; |s|
        lda m16+1
        bpl :+
        lda #0                  ; |m|
        sec
        sbc m16
        sta m16
        lda #0
        sbc m16+1
        sta m16+1
        inc sgn
:       lda m16                 ; |m| * |s| = lo * s + (hi * s) << 8
        ldy t4
        jsr umul8
        lda mr_lo
        sta t2                  ; p0
        lda mr_hi
        sta t3                  ; p1 (so far)
        lda m16+1
        beq @p2                 ; |m| < 1: no high product (A = p2 = 0)
        ldy t4
        jsr umul8
        lda t3
        clc
        adc mr_lo
        sta t3                  ; p1
        lda mr_hi
        adc #0                  ; p2
@p2:
        ; >> 7: (p << 1) >> 8
        asl t2
        rol t3
        rol a
        sta res+1
        lda t3
        sta res
        lda sgn
        and #1
        beq :+
        lda #0
        sec
        sbc res
        sta res
        lda #0
        sbc res+1
        sta res+1
:       rts

; sin_cos: A = heading -> t0 = sine, t1 = cosine (1.7)
sin_cos:
        tay
        lda phys_sine,y
        sta t0
        tya
        clc
        adc #64
        tay
        lda phys_sine,y
        sta t1
        rts

; ---------------------------------------------------------------------------
; the map.  HEIGHT: A = a metatile's properties, Y = the metatile.  In the air
; module a solid metatile's low four bits (road bits, which a building never
; has) become its height in storeys of 8 pixels, from the tileset's heights
; table; elsewhere nothing.
.macro HEIGHT
.ifdef AIR
        bpl :+                  ; (an unnamed label: a named one would end the
        and #$F0                ; caller's scope for its @ labels)
        ora heights,y
:
.endif
.endmacro

; cache_load: X = body.  The property bytes of the 3 x 3 metatiles
; around its centre, three 3-byte DMAs; cache[(row * 3 + col) * NB + body].
cache_load:
        stx cl_x
        lda pb_xl,x              ; metatile x, 16 bits: (x >> 5)
        sta t2
        lda pb_xh,x
        sta t3
        lda pb_yl,x
        sta t4
        lda pb_yh,x
        sta t5
        ldy #5
:       lsr t3
        ror t2
        lsr t5
        ror t4
        dey
        bne :-
        lda t2
        sta pb_cmx,x             ; the low bytes, to see when it moves on
        lda t4
        sta pb_cmy,x
        lda t2                  ; from the column to the left
        bne :+
        dec t3
:       dec t2
        lda t4                  ; and the row above
        bne :+
        dec t5
:       dec t4
        lda #0
        sta t0                  ; row
@row:   lda t4                  ; REU address: world + (y << 11 | x)
        and #31
        asl
        asl
        asl
        ora t3
        sta t1                  ; the middle byte
        lda t5
        asl
        asl
        asl
        sta ub
        lda t4
        lsr
        lsr
        lsr
        lsr
        lsr
        ora ub                  ; the high byte
        pha
        lda t2
        clc
        adc phys_world
        sta b64_reu
        lda t1
        adc phys_world+1
        sta b64_reu+1
        pla
        adc phys_world+2
        sta b64_reu+2
        lda #<cache_row
        sta b64_ptr
        lda #>cache_row
        sta b64_ptr+1
        lda #3
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ldx cl_x
        lda t0                  ; three entries of the row
        asl
        adc t0                  ; row * 3
        tay
        lda kofs,y
        sta t1
        ldy cache_row
        lda B64_PROPS,y
        HEIGHT
        ldy t1
        jsr put_cache
        ldy cache_row+1
        lda B64_PROPS,y
        HEIGHT
        pha
        lda t0
        asl
        adc t0
        tay
        lda kofs+1,y
        tay
        pla
        jsr put_cache
        ldy cache_row+2
        lda B64_PROPS,y
        HEIGHT
        pha
        lda t0
        asl
        adc t0
        tay
        lda kofs+2,y
        tay
        pla
        jsr put_cache
        inc t4                  ; the next row
        bne :+
        inc t5
:       inc t0
        lda t0
        cmp #3
        beq :+
        jmp @row
:       ldx cl_x
        rts

; put_cache: A = properties, Y = the entry's offset (k * NB), X = body
put_cache:
        pha
        stx ub
        tya
        clc
        adc ub
        tay
        pla
        sta cache,y
        rts

; cache_check: X = body.  Reload the cache if the centre moved to another metatile.
cache_check:
        lda pb_xl,x
        lsr
        lsr
        lsr
        lsr
        lsr
        sta t0
        lda pb_xh,x
        asl
        asl
        asl
        ora t0
        cmp pb_cmx,x
        bne @load
        lda pb_yl,x
        lsr
        lsr
        lsr
        lsr
        lsr
        sta t0
        lda pb_yh,x
        asl
        asl
        asl
        ora t0
        cmp pb_cmy,x
        bne @load
        rts
@load:  jmp cache_load

; wall_test: X = body.  C=1 if its box touches a wall.  The box's corners
; fall in the cached 3 x 3: column 0 if the left edge is left of the centre
; metatile, 2 if the right edge is right of it; rows the same.
wall_test:
        ldy pb_mov,x            ; what counts as a wall is the mover's
        lda wall_and,y
        sta w_and
        lda wall_eor,y
        sta w_eor
.ifdef AIR
        lda wall_alt,y
        sta w_alt
.endif
        ldy pb_cls,x
        lda pb_xl,x
        and #31
        sta t0
        sec
        sbc c_hw,y
        lda #1
        bcs :+
        lda #0
:       sta t1                  ; left column
        lda t0
        clc
        adc c_hw,y
        cmp #32
        lda #1
        bcc :+
        lda #2
:       sta t2                  ; right column
        lda pb_yl,x
        and #31
        sta t0
        sec
        sbc c_hh,y
        lda #3
        bcs :+
        lda #0
:       sta t3                  ; top row * 3
        lda t0
        clc
        adc c_hh,y
        cmp #32
        lda #3
        bcc :+
        lda #6
:       sta t4                  ; bottom row * 3
        lda t1                  ; all four corners in the centre metatile: clear
        cmp #1                  ; (the body stands in it, so it is no wall)
        bne @test
        lda t2
        cmp #1
        bne @test
        lda t3
        cmp #3
        bne @test
        lda t4
        cmp #3
        bne @test
        clc
        rts
@test:  stx ub
        lda t3                  ; top left
        clc
        adc t1
        jsr corner
        bne @wall
        lda t3                  ; top right
        clc
        adc t2
        jsr corner
        bne @wall
        lda t4                  ; bottom left
        clc
        adc t1
        jsr corner
        bne @wall
        lda t4                  ; bottom right
        clc
        adc t2
        jsr corner
        bne @wall
        clc
        rts
@wall:  sec
        rts
; corner: A = cache entry 0-8 -> A = its wall bits (Z=1 if none).  In the
; air module an aircraft's wall is a solid metatile standing higher than it.
corner:
        tay
        lda kofs,y
        clc
        adc ub
        tay
        lda cache,y
.ifdef AIR
        bit w_alt
        bpl @plain
        cmp #$80                ; solid?
        bcc @clear
        and #$0F                ; its storeys, in pixels
        asl
        asl
        asl
        cmp pb_zh,x              ; standing higher than the craft: a wall
        beq @clear
        bcc @clear
        lda #1
        rts
@clear: lda #0
        rts
@plain:
.endif
        and w_and
        eor w_eor
        rts

; surface: X = body.  pb_surf from the centre metatile: 0 road, 1 pavement,
; 2 rough ground, 3 water.
surface:
        lda cache+4*NB,x
        ldy #0
        and #$0F
        bne @set
        lda cache+4*NB,x
        ldy #1
        and #P_SIDEWALK
        bne @set
        lda cache+4*NB,x
        ldy #3
        and #P_WATER
        bne @set
        ldy #2
@set:   tya
        sta pb_surf,x
        rts

; ---------------------------------------------------------------------------
; moving and walls.  move_x: X = body.  x += vx; if the box then touches a
; wall, back, and the x velocity turns round with a quarter of its speed.
move_x:
        lda pb_vxl,x
        ora pb_vxh,x
        bne :+
        rts
:       lda pb_xf,x
        sta save_f
        lda pb_xl,x
        sta save_x
        lda pb_xh,x
        sta save_x+1
        lda pb_vxh,x             ; the sign extension of vx
        and #$80
        beq :+
        lda #$FF
:       sta t3
        lda pb_xf,x
        clc
        adc pb_vxl,x
        sta pb_xf,x
        lda pb_xl,x
        adc pb_vxh,x
        sta pb_xl,x
        lda pb_xh,x
        adc t3
        sta pb_xh,x
        lda pb_xl,x             ; crossed into another metatile?
        eor save_x
        and #$E0
        bne :+
        lda pb_xh,x
        cmp save_x+1
        beq :++
:       jsr cache_check
:       jsr wall_test
        bcc @ok
        lda save_f              ; back where it was
        sta pb_xf,x
        lda save_x
        sta pb_xl,x
        lda save_x+1
        sta pb_xh,x
        jsr cache_check
        lda pb_vxl,x             ; bounce: v = -v / 4
        sta m16
        lda pb_vxh,x
        sta m16+1
        jsr bounce
        sta pb_vxh,x
        lda m16
        sta pb_vxl,x
@ok:    rts

move_y:
        lda pb_vyl,x
        ora pb_vyh,x
        bne :+
        rts
:       lda pb_yf,x
        sta save_f
        lda pb_yl,x
        sta save_x
        lda pb_yh,x
        sta save_x+1
        lda pb_vyh,x
        and #$80
        beq :+
        lda #$FF
:       sta t3
        lda pb_yf,x
        clc
        adc pb_vyl,x
        sta pb_yf,x
        lda pb_yl,x
        adc pb_vyh,x
        sta pb_yl,x
        lda pb_yh,x
        adc t3
        sta pb_yh,x
        lda pb_yl,x
        eor save_x
        and #$E0
        bne :+
        lda pb_yh,x
        cmp save_x+1
        beq :++
:       jsr cache_check
:       jsr wall_test
        bcc @ok
        lda save_f
        sta pb_yf,x
        lda save_x
        sta pb_yl,x
        lda save_x+1
        sta pb_yh,x
        jsr cache_check
        lda pb_vyl,x
        sta m16
        lda pb_vyh,x
        sta m16+1
        jsr bounce
        sta pb_vyh,x
        lda m16
        sta pb_vyl,x
@ok:    rts

; bounce: m16 = a velocity into a wall -> m16 / A (high byte) = -v / 4;
; records the impact and marks the body
bounce:
        lda m16+1               ; the impact: |v| in 1/16 pixels, at most 255
        bpl :+
        lda #0
        sec
        sbc m16
        sta t0
        lda #0
        sbc m16+1
        jmp :++
:       lda m16
        sta t0
        lda m16+1
:       asl t0                  ; (|v| << 4) >> 8 = |v| in 16ths
        rol a
        asl t0
        rol a
        asl t0
        rol a
        asl t0
        rol a
        cmp pb_hit,x
        bcc :+
        sta pb_hit,x
:       lsr a                   ; damage: an eighth of the impact
        lsr a
        lsr a
        clc
        adc pb_dmg,x
        bcc :+
        lda #255
:       sta pb_dmg,x
        lda pb_st,x
        ora #ST_WORLD | ST_WALL
        sta pb_st,x
        lda #0                  ; -v
        sec
        sbc m16
        sta m16
        lda #0
        sbc m16+1
        cmp #$80                ; / 4, keeping the sign
        ror a
        ror m16
        cmp #$80
        ror a
        ror m16
        rts

; slow8: X = body, world velocity -= velocity / 8 (a tumble's friction), to rest
slow8:
        lda pb_vxl,x
        sta m16
        lda pb_vxh,x
        sta m16+1
        jsr less8
        lda m16
        sta pb_vxl,x
        lda m16+1
        sta pb_vxh,x
        lda pb_vyl,x
        sta m16
        lda pb_vyh,x
        sta m16+1
        jsr less8
        lda m16
        sta pb_vyl,x
        lda m16+1
        sta pb_vyh,x
        rts
; less8: m16 -= m16 >> 3, and to zero under 1/16
less8:
        lda m16+1
        sta t1
        lda m16
        sta t0
        ldy #3
:       lda t1
        cmp #$80
        ror t1
        ror t0
        dey
        bne :-
        lda m16
        sec
        sbc t0
        sta m16
        lda m16+1
        sbc t1
        sta m16+1
        ; |v| < $10: stop
        bpl :+
        cmp #$FF
        bne @keep
        lda m16
        cmp #$F0
        bcs @zero
        rts
:       bne @keep
        lda m16
        cmp #$10
        bcs @keep
@zero:  lda #0
        sta m16
        sta m16+1
@keep:  rts

; ---------------------------------------------------------------------------
; each other.  pairs: every two bodies whose boxes overlap, one of them
; awake, are pushed apart along the axis they overlap least and exchange
; velocity along it by their masses, e = 1/4.
pairs:
        ldx #NB-1               ; the live bodies, packed
        ldy #0
:       lda pb_mov,x
        beq :+
        txa
        sta plist,y
        iny
:       dex
        bpl :--
        sty pn
        cpy #2
        bcs :+
        rts
:       lda #0
        sta pa
@a:     ldy pa                  ; pi = plist[a]; pj = plist[a+1..]
        lda plist,y
        tax
        iny
        sty pb
@b:     ldy pb
        lda plist,y
        tay
        lda pb_xl,y             ; the low bytes 24 or more apart: no
        sec
        sbc pb_xl,x
        clc
        adc #24
        cmp #48
        bcs @nb
        lda pb_yl,y
        sec
        sbc pb_yl,x
        clc
        adc #24
        cmp #48
        bcs @nb
        stx pi
        sty pj
        jsr pair
        ldx pi
@nb:    inc pb
        lda pb
        cmp pn
        bcc @b
        inc pa
        lda pa
        clc
        adc #1
        cmp pn
        bcc @a
        rts

pair:
        ldx pi
        lda pb_st,x
        ldx pj
        and pb_st,x
        bpl :+
        rts
:
.ifdef AIR
        ldx pi                  ; the air module: bodies 8 pixels or more apart
        ldy pj                  ; in height pass each other
        lda pb_zh,x
        sec
        sbc pb_zh,y
        bcs :+
        eor #$FF
        adc #1
:       cmp #8
        bcc :+
        rts
:
.endif
        ldx pi                  ; dx = xj - xi, |dx| < hwi + hwj ?
        ldy pb_cls,x
        lda c_hw,y
        ldy pj
        ldx pb_cls,y
        clc
        adc c_hw,x
        sta ox                  ; the reach along x
        ldx pi
        ldy pj
        lda pb_xl,y
        sec
        sbc pb_xl,x
        sta dx
        lda pb_xh,y
        sbc pb_xh,x
        sta dx+1
        jsr absd                ; A = |dx| if under 256, else $FF with C=1
        bcc :+
        rts
:
        cmp ox
        bcc :+
        rts
:
        sta t5
        lda ox
        sec
        sbc t5
        sta ox                  ; the overlap along x
        ldx pi
        ldy pb_cls,x
        lda c_hh,y
        ldy pj
        ldx pb_cls,y
        clc
        adc c_hh,x
        sta oy
        ldx pi
        ldy pj
        lda pb_yl,y
        sec
        sbc pb_yl,x
        sta dy
        lda pb_yh,y
        sbc pb_yh,x
        sta dy+1
        lda dx                  ; absd works on dx: swap dy in and out
        pha
        lda dx+1
        pha
        lda dy
        sta dx
        lda dy+1
        sta dx+1
        jsr absd
        sta t5
        pla
        sta dx+1
        pla
        sta dx
        lda t5
        bcc :+
        rts
:
        cmp oy
        bcc :+
        rts
:
        sta t5
        lda oy
        sec
        sbc t5
        sta oy
        ; touching: resolve along the axis of least overlap
        lda ox
        cmp oy
        bcs @alongy
        jmp resolve_x
@alongy:
        jmp resolve_y
@no:    rts

; absd: dx (16-bit, signed) -> A = |dx| with C=0 if under 256, C=1 if not
absd:
        lda dx+1
        bmi @neg
        bne @far
        lda dx
        clc
        rts
@neg:   cmp #$FF
        bne @far
        lda dx
        beq @far                ; -256
        eor #$FF
        clc
        adc #1
        clc
        rts
@far:   sec
        rts

; resolve_x / resolve_y: the pair pi, pj touch along x (y).  n = the side pj
; is on.  If they are closing, each takes its share of (1 + e) times the
; closing velocity; then they are pushed apart by the overlap, the lighter
; further.
resolve_x:
        lda #0
        sta axis
        lda ox
        sta ov
        lda dx+1
        sta nsgn
        jmp resolve
resolve_y:
        lda #1
        sta axis
        lda oy
        sta ov
        lda dy+1
        sta nsgn
resolve:
        ldx pi                  ; shares: si for pi = mj / (mi + mj), sj the other way
        ldy pb_cls,x
        lda c_mass,y
        asl
        asl
        asl
        asl
        sta t4                  ; mi * 16
        ldx pj
        ldy pb_cls,x
        lda c_mass,y
        sta t5                  ; mj
        ora t4
        tay
        lda phys_share,y        ; [mi * 16 + mj]
        sta si
        lda t5
        asl
        asl
        asl
        asl
        sta t5
        ldx pi
        ldy pb_cls,x
        lda c_mass,y
        ora t5
        tay
        lda phys_share,y        ; [mj * 16 + mi]
        sta sj
        ; the closing velocity along the axis: vj - vi
        jsr vel_i               ; -> t0/t1 = pi's, t2/t3 = pj's velocity on the axis
        lda t2
        sec
        sbc t0
        sta rel
        lda t3
        sbc t1
        sta rel+1
        ; closing if rel and n have opposite signs
        eor nsgn
        bpl @apart
        ; d = (1 + 1/4) rel
        lda rel+1
        sta m16+1
        lda rel
        sta m16
        lda m16+1
        cmp #$80
        ror m16+1
        ror m16
        lda m16+1
        cmp #$80
        ror m16+1
        ror m16
        lda m16
        clc
        adc rel
        sta rel
        lda m16+1
        adc rel+1
        sta rel+1
        ; pi += d * si
        lda rel
        sta m16
        lda rel+1
        sta m16+1
        lda si
        jsr smul
        ldx pi
        jsr add_axis
        jsr knock
        ; pj -= d * sj
        lda rel
        sta m16
        lda rel+1
        sta m16+1
        lda sj
        jsr smul
        lda #0
        sec
        sbc res
        sta res
        lda #0
        sbc res+1
        sta res+1
        ldx pj
        jsr add_axis
        jsr knock
@apart: ; push apart: pi by ov * si / 127 away from pj, pj the rest
        lda ov
        ldy si
        jsr umul8
        lda mr_lo
        asl
        lda mr_hi
        rol a                   ; / 128
        sta t4
        lda ov
        sec
        sbc t4
        sta t5                  ; pj's part
        lda nsgn                ; pi moves against n, pj with it
        bmi :+
        lda #0
        sec
        sbc t4
        sta t4
        jmp :++
:       lda #0
        sec
        sbc t5
        sta t5
:       lda t5
        sta push_j
        ldx pi
        lda t4
        jsr shove
        ldx pj
        lda push_j
        jsr shove
        ldx pi
        jsr wake_world
        ldx pj
        jmp wake_world

; vel_i: the pair's velocities along the axis: t0/t1 pi's, t2/t3 pj's
vel_i:
        ldx pi
        ldy pj
        lda axis
        bne @y
        lda pb_vxl,x
        sta t0
        lda pb_vxh,x
        sta t1
        lda pb_vxl,y
        sta t2
        lda pb_vxh,y
        sta t3
        rts
@y:     lda pb_vyl,x
        sta t0
        lda pb_vyh,x
        sta t1
        lda pb_vyl,y
        sta t2
        lda pb_vyh,y
        sta t3
        rts

; add_axis: X = body, res added to its velocity along the axis; the impact
; and the damage follow the size of the change
add_axis:
        lda axis
        bne @y
        lda pb_vxl,x
        clc
        adc res
        sta pb_vxl,x
        lda pb_vxh,x
        adc res+1
        sta pb_vxh,x
        jmp @hit
@y:     lda pb_vyl,x
        clc
        adc res
        sta pb_vyl,x
        lda pb_vyh,x
        adc res+1
        sta pb_vyh,x
@hit:   lda res+1               ; |change| in 16ths of a pixel
        bpl :+
        lda #0
        sec
        sbc res
        sta t0
        lda #0
        sbc res+1
        jmp :++
:       lda res
        sta t0
        lda res+1
:       asl t0
        rol a
        asl t0
        rol a
        asl t0
        rol a
        asl t0
        rol a
        sta t1
        cmp pb_hit,x
        bcc :+
        sta pb_hit,x
:       lda t1
        lsr a
        lsr a
        clc
        adc pb_dmg,x
        bcc :+
        lda #255
:       sta pb_dmg,x
        rts

; knock: X = body.  On foot, a change of a pixel a frame or more knocks it down
knock:
        lda pb_mov,x
        cmp #M_FOOT
        bne @no
        lda t1                  ; the change in 16ths (add_axis)
        cmp #16
        bcc @no
        lda pb_st,x
        ora #ST_DOWN
        sta pb_st,x
        lda #50
        sta pb_tmr,x
@no:    rts

; shove: X = body, A = pixels to move along the axis (signed); not into a wall
shove:
        sta t0
        ora #0
        beq @done
        ldy axis
        bne @y
        lda pb_xl,x
        sta save_x
        lda pb_xh,x
        sta save_x+1
        lda t0
        bpl :+
        dec pb_xh,x
:       clc
        adc pb_xl,x
        sta pb_xl,x
        bcc :+
        inc pb_xh,x
:       jsr cache_check
        jsr wall_test
        bcc @done
        lda save_x
        sta pb_xl,x
        lda save_x+1
        sta pb_xh,x
        jmp cache_check
@y:     lda pb_yl,x
        sta save_x
        lda pb_yh,x
        sta save_x+1
        lda t0
        bpl :+
        dec pb_yh,x
:       clc
        adc pb_yl,x
        sta pb_yl,x
        bcc :+
        inc pb_yh,x
:       jsr cache_check
        jsr wall_test
        bcc @done
        lda save_x
        sta pb_yl,x
        lda save_x+1
        sta pb_yh,x
        jmp cache_check
@done:  rts

; the classes every module shares, so a body keeps its box and mass through a
; swap: 0 a walker; 1 sedan, 2 sports car, 3 truck, 4 bike (wheels); 5
; speedboat, 6 launch, 7 jet ski (hull); 8 helicopter (air)
;                  walk  sedan  sport  truck   bike  speed launch    ski   heli
c_hw:     .byte       3,     7,     7,     9,     4,     7,     9,     4,     8
c_hh:     .byte       3,     7,     7,     9,     4,     7,     9,     4,     8
c_mass:   .byte       1,     8,     6,    15,     3,     5,    12,     2,     6
kofs:     .byte 0*NB, 1*NB, 2*NB, 3*NB, 4*NB, 5*NB, 6*NB, 7*NB, 8*NB
