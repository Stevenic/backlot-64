; backlot-64 example: drive a car around the REU world.
; Joystick 2 moves the camera.  Assemble with -D AUTODRIVE=1 to drive a
; square on its own, for screenshots.

.include "b64.inc"
.include "slots.inc"

.export game_main

CAM_START_X     = 1300 * 32
CAM_START_Y     = 1000 * 32
SPR_CX          = 24 + 160 - 12
SPR_CY          = 50 + 100 - 10

.segment "GAMEHI"
auto_t:         .res 2
heading:        .res 1
; traffic: 20 cars driving back and forth on the road rows near the start
NCARS           = 20
car_wx:         .res NCARS
car_wxh:        .res NCARS
car_wy:         .res NCARS
car_wyh:        .res NCARS
car_dir:        .res NCARS      ; 1 = east, $FF = west
car_off:        .res NCARS      ; distance from centre, signed, for the turnaround

.segment "GAME"
game_main:
        jsr b64_init
        B64_SET24 b64_reu, SLOT_TILESET0
        jsr b64_load_tileset

        ; Bellamar day shared colours
        lda #11
        sta VIC_BG_COLOR0
        lda #15
        sta VIC_BG_COLOR1
        lda #1
        sta VIC_BG_COLOR2
        lda #11
        sta VIC_BORDERCOLOR

        B64_SET16 b64_cam_x, CAM_START_X
        B64_SET16 b64_cam_y, CAM_START_Y
        jsr b64_redraw

        ; pinned sprite 0: the car, multicolour, centred
        lda #SPR_CX
        sta VIC_SPR0_X
        lda #SPR_CY
        sta VIC_SPR0_Y
        lda #1
        sta VIC_SPR0_COLOR
        sta VIC_SPR_ENA
        sta VIC_SPR_MCOLOR
        lda #0
        sta VIC_SPR_MCOLOR0
        lda #1
        sta VIC_SPR_MCOLOR1
        lda #0
        sta auto_t
        sta auto_t+1

        jsr traffic_init
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run

; ---------------------------------------------------------------------------
traffic_init:
        ldx #0
@i:     ; wy = CAM_START_Y + 6 + (x & 1) * 14 + ((x >> 1) & 3) * 48  (four bands, all on screen)
        txa
        lsr
        and #3
        sta b64_tmp
        asl
        asl
        asl
        asl
        sta b64_tmp+1           ; k*16
        asl                     ; k*32
        clc
        adc b64_tmp+1           ; k*48
        sta b64_tmp+1
        txa
        and #1
        beq :+
        lda #20
        bne :++
:       lda #6
:       clc
        adc b64_tmp+1
        clc
        adc #<CAM_START_Y
        sta car_wy,x
        lda #>CAM_START_Y
        adc #0
        sta car_wyh,x
        ; wx = CAM_START_X - 20 + x * 16
        txa
        asl
        asl
        asl
        asl
        sta b64_tmp
        lda #0
        rol                     ; carry from the last asl (x*16 > 255 for x >= 16)
        sta b64_tmp+1
        lda b64_tmp
        clc
        adc #<(CAM_START_X - 20)
        sta car_wx,x
        lda b64_tmp+1
        adc #>(CAM_START_X - 20)
        sta car_wxh,x
        txa
        and #1
        beq :+
        lda #$FF
        bne :++
:       lda #1
:       sta car_dir,x
        lda #0
        sta car_off,x
        inx
        cpx #NCARS
        bne @i
        rts

; move every car one pixel and submit the visible ones to the multiplexer
traffic_frame:
        jsr b64_spr_begin
        ldx #0
@c:     lda car_dir,x
        bpl @east
        lda car_wx,x
        sec
        sbc #1
        sta car_wx,x
        bcs :+
        dec car_wxh,x
:       dec car_off,x
        lda car_off,x
        cmp #<(-120)
        bne @vis
        lda #1
        sta car_dir,x
        jmp @vis
@east:  inc car_wx,x
        bne :+
        inc car_wxh,x
:       inc car_off,x
        lda car_off,x
        cmp #120
        bne @vis
        lda #$FF
        sta car_dir,x
@vis:
        lda car_wx,x
        sec
        sbc b64_cam_x
        sta b64_spr_x
        lda car_wxh,x
        sbc b64_cam_x+1
        sta b64_spr_x+1
        lda b64_spr_x
        clc
        adc #24
        sta b64_spr_x
        bcc :+
        inc b64_spr_x+1
:       lda b64_spr_x+1
        bmi @next
        cmp #2
        bcs @next
        beq @chk344
        jmp @y
@chk344:
        lda b64_spr_x
        cmp #<344
        bcs @next
@y:     lda car_wy,x
        sec
        sbc b64_cam_y
        sta b64_spr_y
        lda car_wyh,x
        sbc b64_cam_y+1
        bne @next
        lda b64_spr_y
        clc
        adc #50
        bcs @next
        sta b64_spr_y
        cmp #250
        bcs @next
        stx b64_tmp+7
        lda car_dir,x
        bpl :+
        lda #3
        bne :++
:       lda #1
:       jsr frame_addr
        ldx b64_tmp+7
        inx
        stx b64_spr_slot        ; slots 1..20
        ldx b64_tmp+7
        txa
        and #7
        clc
        adc #2
        sta b64_spr_colour
        lda #B64_SPR_FLAG_MC
        sta b64_spr_flags
        stx b64_tmp+7
        jsr b64_spr_add
        ldx b64_tmp+7
@next:  inx
        cpx #NCARS
        beq @done
        jmp @c
@done:  jmp b64_spr_end

; ---------------------------------------------------------------------------
frame:
.ifdef AUTODRIVE
        ; 100 frames each: right, down, left, up, then repeat
        inc auto_t
        bne :+
        inc auto_t+1
:       lda auto_t+1
        and #1
        bne @odd
        lda auto_t
        cmp #100
        bcc @right
        cmp #200
        bcc @down
        lda #0
        sta auto_t
        inc auto_t+1
        jmp @right
@odd:   lda auto_t
        cmp #100
        bcc @left
        cmp #200
        bcc @up
        lda #0
        sta auto_t
        inc auto_t+1
        jmp @left
@right: lda #8
        bne @joy
@down:  lda #2
        bne @joy
@left:  lda #4
        bne @joy
@up:    lda #1
@joy:   sta b64_joy
.endif
        lda #0
        sta b64_tmp+2           ; dx
        sta b64_tmp+3           ; dy
        lda b64_joy
        lsr
        bcc :+
        lda #<(-2)
        sta b64_tmp+3
        lda #0
        sta heading
:       lda b64_joy
        and #2
        beq :+
        lda #2
        sta b64_tmp+3
        sta heading
:       lda b64_joy
        and #4
        beq :+
        lda #<(-2)
        sta b64_tmp+2
        lda #3
        sta heading
:       lda b64_joy
        and #8
        beq :+
        lda #2
        sta b64_tmp+2
        lda #1
        sta heading
:       lda b64_tmp+2
        ldx b64_tmp+3
        jsr b64_move_camera
        lda heading
        jsr frame_addr
        jsr b64_spr_pinned
        jsr traffic_frame
        jmp b64_bench_show

; frame_addr: A = frame index in the sprite library -> b64_reu = SLOT_SPRITES0 + A*64
frame_addr:
        sta b64_tmp+4
        lda #0
        sta b64_tmp+5
        asl b64_tmp+4
        rol b64_tmp+5
        asl b64_tmp+4
        rol b64_tmp+5
        asl b64_tmp+4
        rol b64_tmp+5
        asl b64_tmp+4
        rol b64_tmp+5
        asl b64_tmp+4
        rol b64_tmp+5
        asl b64_tmp+4
        rol b64_tmp+5
        lda b64_tmp+4
        clc
        adc #<SLOT_SPRITES0
        sta b64_reu
        lda b64_tmp+5
        adc #>SLOT_SPRITES0
        sta b64_reu+1
        lda #^SLOT_SPRITES0
        adc #0
        sta b64_reu+2
        rts
