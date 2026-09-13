"""Inspect recorded color-trial frames, never access a camera.

The status strip reports the decoder's qualification, not proven correct hue.
R/G differences distinguish chroma activity from unequal RGB332 gray steps.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np


def main(path):
    cap=cv2.VideoCapture(str(path/'capture.avi'))
    counts={'phase_qualified':0,'phase_unqualified':0,'diagnostic_or_unknown':0}
    scores=[]
    best=-1
    try:
        while True:
            ok,frame=cap.read()
            if not ok: break
            marker=np.median(frame[59:62,100:540],axis=(0,1))
            distances=[np.linalg.norm(marker-c) for c in ([0,192,0],[0,192,192])]
            kind=int(np.argmin(distances))
            if distances[kind]>70:
                counts['diagnostic_or_unknown']+=1
                continue
            counts[['phase_qualified','phase_unqualified'][kind]]+=1
            body=frame[80:460,35:580].astype(float)
            score=float((abs(body[:,:,2]-body[:,:,1])>30).mean())
            scores.append(score)
            if score>best:
                best=score
                cv2.imwrite(str(path/'most_chroma.png'),frame)
    finally:
        cap.release()
    result=dict(status_frames=counts,max_rg_chroma_fraction=best,
                mean_rg_chroma_fraction=float(np.mean(scores)) if scores else None,
                caveat='Chroma activity/decoder status are not proof of correct or stable color.')
    (path/'color_trial_analysis.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))


if __name__=='__main__': main(Path(sys.argv[1]))
