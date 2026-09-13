"""Compare picture-page frames, excluding status and diagnostic pages.

Registration is observational, not proof of field lock: game motion and repeated
textures can influence the estimate. Keep thumbnails for visual verification.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np


def analyze(path):
    cap = cv2.VideoCapture(str(path / 'capture.avi'))
    reference = None
    selected = []
    records = []
    index = 0
    last_selected = -30
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        index += 1
        marker = np.median(frame[59:62, 100:540], axis=(0, 1))
        if np.linalg.norm(marker - [0, 192, 0]) > 70:
            continue
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        body = gray[72:472, 40:580].astype(np.float32)
        if reference is None:
            reference = body
        shift, response = cv2.phaseCorrelate(reference, body)
        dark_rows = np.mean(body < 25, axis=1) > .85
        records.append(dict(frame=index, dx=shift[0], dy=shift[1],
                            registration_response=response,
                            mostly_black_rows=int(dark_rows.sum())))
        if index - last_selected >= 30 and len(selected) < 12:
            thumb = cv2.resize(frame, (320, 240), interpolation=cv2.INTER_AREA)
            cv2.putText(thumb, f'frame {index}', (5, 233),
                        cv2.FONT_HERSHEY_SIMPLEX, .4, (0, 0, 255), 1)
            selected.append(thumb)
            last_selected = index
    cap.release()
    if not records:
        raise ValueError('No picture-page frames')
    while len(selected) % 3:
        selected.append(np.zeros_like(selected[0]))
    montage = np.vstack([np.hstack(selected[i:i+3]) for i in range(0, len(selected), 3)])
    cv2.imwrite(str(path / 'picture_stability.png'), montage)
    strong = [r for r in records if r['registration_response'] >= .5]
    report = dict(picture_frames=len(records), strong_registration_frames=len(strong),
                  dy_range=([min(r['dy'] for r in strong), max(r['dy'] for r in strong)]
                            if len(strong) >= max(2, len(records)//2) else None),
                  max_mostly_black_rows=max(r['mostly_black_rows'] for r in records),
                  caveat='Scene registration can include game motion; not a field-lock measurement.',
                  frames=records)
    (path / 'picture_stability.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({k: v for k, v in report.items() if k != 'frames'}, indent=2))


if __name__ == '__main__':
    analyze(Path(sys.argv[1]))
