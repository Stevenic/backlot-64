; backlot-64 data engine: the page cache.
;
; Eight 256-byte copies of REU pages at $C100-$C8FF for data read in small
; pieces whose order is not known in advance: p-code, text, tables.  A hit
; is a compare; a miss is one 256-byte DMA (361 cycles).  Replacement is
; round-robin.  The cache is used from the main loop only, never from an
; interrupt.

.include "b64.inc"

.export b64_page_get
.export b64_page_flush

PG_N            = 8
PAGES           = $C100

.segment "LOWRAM"
pg_lo:          .res PG_N       ; REU page number (address bits 8-23) per entry
pg_hi:          .res PG_N
pg_next:        .res 1          ; next entry to replace
pg_want:        .res 2
pg_last_lo:     .res 1          ; the page answered last time, for the fast path
pg_last_hi:     .res 1
pg_last_c:      .res 1
pg_tmp:         .res 1

.segment "CODE"

; b64_page_get: A = page lo, X = page hi -> A = high byte of the copy.
; Y is clobbered.  Does not touch the running DMA parameters on a hit.
b64_page_get:
        cmp pg_last_lo
        bne @look
        cpx pg_last_hi
        bne @look
        lda pg_last_c
        rts
@look:  sta pg_want
        stx pg_want+1
        ldy #PG_N-1
@scan:  lda pg_lo,y
        cmp pg_want
        bne @no
        lda pg_hi,y
        cmp pg_want+1
        beq @hit
@no:    dey
        bpl @scan
        ; miss: take the next entry round-robin and fetch the page
        ldy pg_next
        iny
        cpy #PG_N
        bcc :+
        ldy #0
:       sty pg_next
        lda pg_want
        sta pg_lo,y
        sta b64_reu+1
        lda pg_want+1
        sta pg_hi,y
        sta b64_reu+2
        lda #0
        sta b64_reu
        sta b64_ptr
        sta b64_len
        tya
        clc
        adc #>PAGES
        sta b64_ptr+1
        lda #1
        sta b64_len+1
        sty pg_tmp
        jsr b64_fetch
        ldy pg_tmp
@hit:   tya
        clc
        adc #>PAGES
        sta pg_last_c
        lda pg_want
        sta pg_last_lo
        lda pg_want+1
        sta pg_last_hi
        lda pg_last_c
        rts

; b64_page_flush: no entry matches anything (an 8 MB REU has no page $FFxx)
b64_page_flush:
        lda #$FF
        sta pg_last_hi
        ldy #PG_N-1
:       sta pg_hi,y
        dey
        bpl :-
        lda #0
        sta pg_next
        rts
