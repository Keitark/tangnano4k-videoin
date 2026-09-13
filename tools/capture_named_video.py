"""Bounded capture of one explicitly named device; never probe other cameras."""
import json
import sys
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'build' / 'capture_python_deps'))
from cv2_enumerate_cameras import enumerate_cameras
from capture_closed_loop import classify_status


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else 'FY HD Video'
    duration = float(sys.argv[2]) if len(sys.argv) > 2 else 4.0
    if not 1 <= duration <= 30:
        raise ValueError('Capture duration must be 1..30 seconds')
    matches = [c for c in enumerate_cameras(cv2.CAP_MSMF) if c.name == name]
    if len(matches) != 1:
        raise RuntimeError(f'Expected one {name!r} device, found {len(matches)}')
    device = matches[0]
    print(f'Opening {device.name}: index={device.index}, path={device.path}', flush=True)
    output = ROOT / 'build' / 'fy_capture_check' / datetime.now().strftime('%Y%m%d_%H%M%S')
    output.mkdir(parents=True)
    cap = cv2.VideoCapture()
    writer = None
    frames = 0
    failures = 0
    statuses = Counter()
    probe_pages = {}
    page_last = None
    page_run = 0
    try:
        if not cap.open(device.index, cv2.CAP_MSMF):
            raise RuntimeError('FY Media Foundation interface did not open')
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        started = time.monotonic()
        while time.monotonic() - started < duration:
            ok, frame = cap.read()
            if not ok:
                failures += 1
                if failures >= 5:
                    break
                continue
            if writer is None:
                height, width = frame.shape[:2]
                fps = cap.get(cv2.CAP_PROP_FPS) or 30
                writer = cv2.VideoWriter(str(output / 'capture.avi'),
                    cv2.VideoWriter_fourcc(*'MJPG'), fps, (width, height))
                if not writer.isOpened():
                    raise RuntimeError('Output recorder did not open')
                cv2.imwrite(str(output / 'first.png'), frame)
                print(f'Receiving {width}x{height}, reported fps={fps}', flush=True)
            writer.write(frame)
            frames += 1
            if frame.shape[:2] == (480, 640):
                statuses[classify_status(frame)] += 1
                # Runtime probe strip at rows 56..63: BGR green/orange/magenta.
                marker = np.median(frame[59:62, 100:540], axis=(0, 1))
                colors = {'picture': np.array([0,192,0]),
                          'raw': np.array([0,128,255]),
                          'calibration': np.array([255,0,255])}
                page = min(colors, key=lambda key: np.linalg.norm(marker-colors[key]))
                if np.linalg.norm(marker-colors[page]) > 70:
                    page = None
                page_run = page_run+1 if page is not None and page == page_last else 0
                page_last = page
                if page is not None and page_run >= 12 and page not in probe_pages:
                    cv2.imwrite(str(output / f'{page}.png'), frame)
                    probe_pages[page] = frames
            last_frame = frame
        if frames:
            cv2.imwrite(str(output / 'last.png'), last_frame)
        result = dict(device=name, frames=frames, read_failures=failures,
                      statuses=dict(statuses), probe_pages=probe_pages,
                      duration_seconds=duration, output=str(output))
        (output / 'summary.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(result), flush=True)
        if not frames:
            raise RuntimeError('No frames received from FY')
    finally:
        cap.release()
        if writer is not None:
            writer.release()


if __name__ == '__main__':
    main()
