; backlot-64: the Ultimate Command Interface, the register protocol to the
; Ultimate's own firmware (1541 Ultimate-II+, Ultimate 64, C64 Ultimate).
; The engine uses one thing from it: loading a file from the Ultimate's
; storage straight into the REU, which is how a game fills REU slots at
; run time on real hardware (mission packs, regions, saved games).
;
; Registers ($DF1C-$DF1F, firmware 3.15+ unlock at $D038/$D036):
;   $DF1C write control: bit0 PUSH_CMD, bit1 DATA_ACC, bit2 ABORT, bit3 CLR_ERR
;   $DF1C read  status:  bit0 CMD_BUSY, bit1 DATA_ACC, bit2 ABORT_P, bit3 ERROR,
;                        bits 5-4 state (00 idle, 01 busy, 10 data last, 11 data more),
;                        bit6 STAT_AV, bit7 DATA_AV
;   $DF1D write command byte / read id ($C9)
;   $DF1E read response data      $DF1F read status data
; Command: target byte, command byte, arguments.  DOS target 1:
;   $02 open (attrib $01 = read, then the name)   $03 close
;   $21 load REU: address32 LSB first, length32 LSB first   (from the open file)
; UNTESTED on hardware as of 2026-09-17: VICE does not emulate the interface.

.include "b64.inc"

.import b64_plat

.export uci_detect
.export b64_uci_load

UCI_UNLOCK1     = $D038
UCI_UNLOCK2     = $D036
UCI_TARGET_DOS  = 1
UCI_CMD_OPEN    = $02
UCI_CMD_CLOSE   = $03
UCI_CMD_LOADREU = $21

.segment "LOWRAM"
uci_status:     .res 1          ; first status byte of the last reply ('0' = ok)
uci_len:        .res 4
.export uci_status

.segment "CODE"

; uci_detect: C = 1 when the interface answers.  Sends the unlock first,
; harmless where it means nothing.
uci_detect:
        lda #$AB
        sta UCI_UNLOCK1
        lda #$CD
        sta UCI_UNLOCK2
        lda B64_UCI_ID
        cmp #$C9
        bne @no
        lda #$04                ; abort anything pending
        sta B64_UCI_CTRL
        sec
        rts
@no:    clc
        rts

; b64_uci_load: b64_ptr = filename (0-terminated ASCII, at most 64 chars),
; b64_reu = REU address, b64_val = 24-bit length.  Opens, loads, closes.
; C = 1 and uci_status = '0' on success.  A stock machine returns C = 0.
b64_uci_load:
        lda b64_plat
        and #B64_PLAT_UCI
        bne :+
        clc
        rts
:       ; open
        jsr cmd_begin
        lda #UCI_CMD_OPEN
        sta B64_UCI_CMD
        lda #$01
        sta B64_UCI_CMD
        ldy #0
@name:  lda (b64_ptr),y
        beq @sent
        sta B64_UCI_CMD
        iny
        cpy #64
        bne @name
@sent:  jsr cmd_run
        lda uci_status
        cmp #'0'
        bne @fail
        ; load into the REU
        jsr cmd_begin
        lda #UCI_CMD_LOADREU
        sta B64_UCI_CMD
        lda b64_reu
        sta B64_UCI_CMD
        lda b64_reu+1
        sta B64_UCI_CMD
        lda b64_reu+2
        sta B64_UCI_CMD
        lda #0
        sta B64_UCI_CMD
        lda b64_val
        sta B64_UCI_CMD
        lda b64_val+1
        sta B64_UCI_CMD
        lda b64_val+2
        sta B64_UCI_CMD
        lda #0
        sta B64_UCI_CMD
        jsr cmd_run
        lda uci_status
        pha
        ; close
        jsr cmd_begin
        lda #UCI_CMD_CLOSE
        sta B64_UCI_CMD
        jsr cmd_run
        pla
        sta uci_status
        cmp #'0'
        bne @fail
        sec
        rts
@fail:  clc
        rts

; cmd_begin: wait for idle, write the target byte
cmd_begin:
        lda B64_UCI_STATUS
        and #$30
        bne cmd_begin
        lda #UCI_TARGET_DOS
        sta B64_UCI_CMD
        rts

; cmd_run: push, wait, drain the response and the status, acknowledge
; every data block.  uci_status = the first status byte ('0' when "00,OK").
cmd_run:
        lda #$01
        sta B64_UCI_CTRL
        lda B64_UCI_STATUS
        and #$08
        beq @wait
        lda #$08                ; ERROR: clear and give up on this command
        sta B64_UCI_CTRL
        lda #'9'
        sta uci_status
        rts
@wait:  lda B64_UCI_STATUS
        and #$30
        cmp #$10
        beq @wait               ; busy
@block: lda #'0'
        sta uci_status
        ldx #0
@stat:  lda B64_UCI_STATUS
        and #$40
        beq @data
        lda B64_UCI_STATDATA
        cpx #0
        bne :+
        sta uci_status
:       inx
        jmp @stat
@data:  lda B64_UCI_STATUS
        bpl @ack
        lda B64_UCI_RESPDATA    ; discard: the engine wants the effect, not the text
        jmp @data
@ack:   lda B64_UCI_STATUS
        and #$30
        pha
        lda #$02
        sta B64_UCI_CTRL
:       lda B64_UCI_STATUS
        and #$02
        bne :-
        pla
        cmp #$30                ; data more: another block follows
        beq @block
        rts
