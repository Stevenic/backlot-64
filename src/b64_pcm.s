; backlot-64: Ultimate Audio, the 7-channel PCM sampler of the Ultimate 64 /
; C64 Ultimate / 1541 Ultimate-II.  Samples play straight out of the REU
; by DMA inside the cartridge, so playing one costs the CPU a dozen
; register writes and nothing per frame.
;
; Register map (Ultimate Audio Register API v0.2): channel n at
; $DF20 + n*32, write-only, multi-byte fields big-endian:
;   $00 control: bit0 gate, bit1 repeat, bit2 irq, bits 5-4 mode
;                (00 = 8-bit PCM, 01 = 16-bit little-endian), bit6 interleave
;   $01 volume 0-63       $02 pan 0-15 (7 or 8 = centre)
;   $04-$07 start: $01, hi, mid, lo   (the $01 selects REU memory)
;   $09-$0B length hi, mid, lo        $0E-$0F rate divider hi, lo
;   $11-$13 repeat A                  $15-$17 repeat B
;   $1F irq clear
; Rate divider = 6,250,000 / Hz: 8 kHz 781, 11 kHz 567, 16 kHz 391,
; 22 kHz 281, 32 kHz 195, 44.1 kHz 142, 48 kHz 130.
;
; Every entry is a no-op without the module (b64_plat bit), so a game or a
; script can ask for a sound on any machine.
; UNTESTED on hardware as of 2026-09-17: VICE does not emulate the module.

.include "b64.inc"

.import b64_plat

.export b64_pcm_play
.export b64_pcm_loop
.export b64_pcm_stop
.export b64_pcm_volume

.segment "CODE"
pcm_ch = b64_ptr                ; the channel's registers (indirect addressing needs zero page)

; channel_ptr: X = channel 0-6 -> pcm_ch = $DF20 + X*32.  C = 0 if absent.
channel_ptr:
        lda b64_plat
        and #B64_PLAT_AUDIO
        beq @no
        txa
        and #7
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<B64_UA_BASE
        sta pcm_ch
        lda #>B64_UA_BASE
        adc #0
        sta pcm_ch+1
        sec
        rts
@no:    clc
        rts

; b64_pcm_play: X = channel, b64_reu = sample address, b64_val = length
; (24-bit), b64_tmp/b64_tmp+1 = rate divider, b64_tmp+2 = volume 0-63,
; b64_tmp+3 = pan 0-15.  8-bit PCM, one shot.
b64_pcm_play:
        jsr channel_ptr
        bcc @done
        jsr set_common
        lda #%00000001          ; gate, 8-bit
        ldy #0
        sta (pcm_ch),y
@done:  rts

; b64_pcm_loop: as play, plus b64_tmp+4..6 = repeat A (24-bit) and
; b64_tmp+7 / b64_len = repeat B lo/mid, b64_len+1 = hi... too many inputs:
; loops repeat from A = 0 to B = length, which is what a looping ambience
; wants.
b64_pcm_loop:
        jsr channel_ptr
        bcc @done
        jsr set_common
        ldy #$11                ; repeat A = 0
        lda #0
        sta (pcm_ch),y
        iny
        sta (pcm_ch),y
        iny
        sta (pcm_ch),y
        ldy #$15                ; repeat B = length
        lda b64_val+2
        sta (pcm_ch),y
        iny
        lda b64_val+1
        sta (pcm_ch),y
        iny
        lda b64_val
        sta (pcm_ch),y
        lda #%00000011          ; gate, repeat, 8-bit
        ldy #0
        sta (pcm_ch),y
@done:  rts

; b64_pcm_stop: X = channel
b64_pcm_stop:
        jsr channel_ptr
        bcc @done
        lda #0
        tay
        sta (pcm_ch),y
@done:  rts

; b64_pcm_volume: X = channel, A = volume 0-63
b64_pcm_volume:
        pha
        jsr channel_ptr
        pla
        bcc @done
        and #$3F
        ldy #1
        sta (pcm_ch),y
@done:  rts

; set_common: gate off, then volume, pan, start, length, rate
set_common:
        ldy #0
        lda #0
        sta (pcm_ch),y
        ldy #1
        lda b64_tmp+2
        and #$3F
        sta (pcm_ch),y
        iny
        lda b64_tmp+3
        and #$0F
        sta (pcm_ch),y
        ldy #4
        lda #$01                ; REU memory
        sta (pcm_ch),y
        iny
        lda b64_reu+2
        sta (pcm_ch),y
        iny
        lda b64_reu+1
        sta (pcm_ch),y
        iny
        lda b64_reu
        sta (pcm_ch),y
        ldy #9
        lda b64_val+2
        sta (pcm_ch),y
        iny
        lda b64_val+1
        sta (pcm_ch),y
        iny
        lda b64_val
        sta (pcm_ch),y
        ldy #$0E
        lda b64_tmp+1
        sta (pcm_ch),y
        iny
        lda b64_tmp
        sta (pcm_ch),y
        rts
