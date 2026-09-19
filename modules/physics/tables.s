.segment "PTAB"
; f(x) = x * x / 4 for x = 0-511, low bytes then high bytes (page-aligned)
f_lo:
.repeat 512, i
        .byte <((i * i) / 4)
.endrepeat
f_hi:
.repeat 512, i
        .byte >((i * i) / 4)
.endrepeat
.include "phys_tables.inc"

