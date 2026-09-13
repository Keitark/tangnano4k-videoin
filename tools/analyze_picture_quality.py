"""Saved Boing Ball capture measurements; no camera and no image enhancement.

Fixed left-border ROI is outside the ball/grid in these captures. Report a
spatial high-frequency residual, not an absolute electrical SNR measurement.
Capture compression and source texture remain possible contributors.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np
from analyze_line_status import decode


def analyze(path):
    cap=cv2.VideoCapture(str(path/'capture.avi'))
    values=[];index=0;motion=[];counter_steps=[];previous_counter=None
    try:
        while True:
            ok,frame=cap.read()
            if not ok:break
            index+=1
            status=decode(frame)
            if status is None or status['flags']!=15:continue
            if previous_counter is not None:
                counter_steps.append((status['frames_mod256']-previous_counter)&255)
            previous_counter=status['frames_mod256']
            picture=frame[24:472].astype(np.int16)
            b,g,r=cv2.split(picture)
            red=(r>g+40)&(r>b+40)&(r>100)
            yy,xx=np.nonzero(red)
            motion.append((len(xx),float(np.mean(xx)) if len(xx) else None,
                           float(np.mean(yy)+24) if len(xx) else None))
            if index%15:continue
            # Consistent fixed ROI; do not select the quietest patch per build.
            y=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY).astype(np.float32)
            smooth=cv2.GaussianBlur(y,(9,9),0)
            roi=(slice(40,330),slice(30,55))
            residual=(y-smooth)[roi]
            values.append(dict(residual_rms=float(np.sqrt(np.mean(residual**2))),
                               border_mean=float(np.mean(y[roi]))))
    finally:cap.release()
    tracked=[v for v in motion if v[0]>=1000]
    report=dict(frames_sampled=len(values),roi_xywh=[30,40,25,290],
        median={k:float(np.median([v[k] for v in values])) for k in values[0]} if values else {},
        valid_color_frames=len(motion),red_object_frames=len(tracked),
        red_pixel_range=[min(v[0] for v in motion),max(v[0] for v in motion)] if motion else [],
        red_centroid_range={k:[min(v[i] for v in tracked),max(v[i] for v in tracked)]
                            for k,i in [('x',1),('y',2)]} if tracked else {},
        frame_counter_steps={str(n):counter_steps.count(n) for n in sorted(set(counter_steps))},
        caveat='Fixed-border spatial residual only; not electrical SNR, resolution, or hue accuracy.')
    (path/'picture_quality.json').write_text(json.dumps(report,indent=2))
    print(path,json.dumps(report))


if __name__=='__main__':
    for arg in sys.argv[1:]:analyze(Path(arg))
