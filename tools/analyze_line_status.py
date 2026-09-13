"""Read saved three-line HDMI status and representative A/B images; no camera."""
import json
import sys
from pathlib import Path
from collections import Counter
import cv2
import numpy as np


def decode(frame):
    if frame.shape[:2]!=(480,640):
        return None
    # A disconnected/black capture must not decode as valid all-zero counters.
    # These seven health-bar colors are generated independently of source sync.
    bgr=((255,255,255),(0,255,255),(255,255,0),(0,255,0),
         (255,0,255),(0,0,255),(255,0,0))
    for i,expected in enumerate(bgr):
        actual=np.median(frame[2:6,80*i+30:80*i+50],axis=(0,1))
        if np.max(np.abs(actual-np.array(expected)))>65:
            return None
    word=0
    for i in range(64):
        x=64+8*i+4
        v=float(np.median(frame[11:14,x-1:x+2]))
        if 60<v<190:
            return None
        word=(word<<1)|int(v>=128)
    return dict(minimum=(word>>56)&255,maximum=(word>>48)&255,
                h_mod256=(word>>40)&255,lines_mod256=(word>>32)&255,
                underflows=(word>>16)&65535,frames_mod256=(word>>8)&255,
                flags=word&255)


def main(path):
    cap=cv2.VideoCapture(str(path/'capture.avi'))
    records=[]; ambiguous=0; runs=Counter(); samples={}
    try:
        while True:
            ok,frame=cap.read()
            if not ok: break
            record=decode(frame)
            if record is None:
                ambiguous+=1
                continue
            records.append(record)
            mode='color' if record['flags']&8 else 'gray'
            runs[mode]+=1
            # Save a frame after a stable selection interval, not at its edge.
            if len(records)>8 and all(bool(r['flags']&8)==bool(record['flags']&8) for r in records[-8:]):
                if mode not in samples:
                    cv2.imwrite(str(path/f'line_{mode}.png'),frame)
                    samples[mode]=len(records)
    finally:
        cap.release()
    report=dict(decoded=len(records),ambiguous=ambiguous,modes=dict(runs),
                flag_counts=dict(Counter(r['flags'] for r in records)),
                first=records[0] if records else None,last=records[-1] if records else None,
                underflows=sorted({r['underflows'] for r in records}),
                ranges={k:sorted({r[k] for r in records}) for k in ('minimum','maximum','h_mod256','lines_mod256','flags')},
                caveat='Counters qualify line transport, not correct hue or image sharpness.')
    (path/'line_status.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))


if __name__=='__main__': main(Path(sys.argv[1]))
