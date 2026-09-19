.segment "PDATA"
; the module's own workspace
cache_row: .res 3
save_x: .res 2
save_f: .res 1
pi:     .res 1
pj:     .res 1
ox:     .res 1
oy:     .res 1
dx:     .res 2
dy:     .res 2
axis:   .res 1
ov:     .res 1
nsgn:   .res 1
si:     .res 1
sj:     .res 1
rel:    .res 2
plist:  .res NB
pn:     .res 1
pa:     .res 1
pb:     .res 1
push_j: .res 1
cl_x:   .res 1
w_and:  .res 1
w_eor:  .res 1
wv:     .res 6                  ; wheels: the car's frame on entry, and a byte forcing the world velocity
