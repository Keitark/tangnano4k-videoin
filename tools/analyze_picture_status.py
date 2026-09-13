"""Decode the handshaken validation-status strip from a SAVED HDMI recording.

No camera access. Byte order: flags, accepted modulo 256, rejected saturating
uint16, and last sequential-prefix word count uint16. Not proof of image quality.
"""
import json
import sys
from collections import Counter
from pathlib import Path

import cv2
import numpy as np


def decode(frame):
    if frame.shape[:2] != (480, 640):
        raise ValueError("Expected 640x480 status layout")
    value = 0
    for bit in range(48):
        x = 32 + 12 * bit + 6
        level = float(np.median(frame[67:70, x-2:x+3]))
        if 60 < level < 190:
            return None
        value = (value << 1) | int(level >= 128)
    return dict(flags=(value >> 40) & 255, accepted_mod256=(value >> 32) & 255,
                rejected=(value >> 16) & 65535, words=value & 65535)


def decode_source(frame):
    value = 0
    for bit in range(32):
        x = 64 + 16 * bit + 8
        level = float(np.median(frame[75:78, x-2:x+3]))
        if 60 < level < 190:
            return None
        value = (value << 1) | int(level >= 128)
    return dict(minimum=(value >> 24) & 255, maximum=(value >> 16) & 255,
                h_mod256=(value >> 8) & 255, lines_mod256=value & 255)


def main(directory):
    cap = cv2.VideoCapture(str(directory / 'capture.avi'))
    if not cap.isOpened():
        raise RuntimeError('Saved recording did not open')
    counts = Counter()
    valid, uncertain = [], 0
    source_records = []
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            status = decode(frame)
            if status is None:
                uncertain += 1
            else:
                valid.append(status)
                counts[status['flags']] += 1
                if '--source-status' in sys.argv:
                    source_status = decode_source(frame)
                    if source_status is not None:
                        source_records.append(dict(**source_status, color_selected=bool(status['flags'] & 128)))
    finally:
        cap.release()
    result = dict(decoded_frames=len(valid), uncertain_frames=uncertain,
                  flag_counts=dict(counts), first=valid[0] if valid else None,
                  last=valid[-1] if valid else None,
                  word_counts=sorted(set(item['words'] for item in valid)),
                  caveat='Counters describe valid transport attempts, not correct color or recognizable imagery.')
    if source_records:
        result['source_first'] = source_records[0]
        result['source_last'] = source_records[-1]
        result['source_unique'] = [dict(zip(source_records[0], values)) for values in
            sorted(set(tuple(item.values()) for item in source_records))]
    (directory / 'picture_status.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main(Path(sys.argv[1]))
