import numpy as np
from analyze_line_status import decode

frame=np.zeros((480,640,3),dtype=np.uint8)
assert decode(frame) is None, 'black capture must not be valid zero status'
colors=((255,255,255),(0,255,255),(255,255,0),(0,255,0),
        (255,0,255),(0,0,255),(255,0,0))
for i,color in enumerate(colors): frame[:8,i*80:(i+1)*80]=color
word=0x14b8060600004f0f
for i in range(64):
    frame[8:16,64+8*i:72+8*i]=240 if word&(1<<(63-i)) else 16
r=decode(frame)
assert r==dict(minimum=20,maximum=184,h_mod256=6,lines_mod256=6,
               underflows=0,frames_mod256=79,flags=15),r
frame[:8]=0
assert decode(frame) is None, 'absent heartbeat must invalidate counters'
print('PASS health-bar qualification, status bits, black/no-heartbeat rejection')
