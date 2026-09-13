import csv
import time
from collections import Counter
from pathlib import Path

import cv2
import numpy as np


DEVICE_INDEX = 3
CAPTURE_SECONDS = 12.0


def decode_bar(frame, y_start, y_stop, color):
    band = frame[y_start:y_stop, :, :].mean(axis=0)
    blue, green, red = band[:, 0], band[:, 1], band[:, 2]
    if color == "magenta":
        active = (red > 80) & (blue > 80) & (red > green * 1.5) & (blue > green * 1.5)
    else:
        active = (blue > 80) & (green > 80) & (red < 80)

    width = 0
    for pixel_active in active:
        if not pixel_active:
            break
        width += 1
    code = int(round((width - 8) / 2.0))
    return code if 0 <= code <= 255 else None


def classify_status(frame):
    blue, green, red = frame[8:60, :, :].mean(axis=(0, 1))
    if green > 120 and red < 100:
        return "locked"
    if red > 120 and green > 70:
        return "activity"
    if red > 120:
        return "inactive"
    return "unknown"


def main():
    repo_root = Path(__file__).resolve().parents[1]
    output_dir = repo_root / "build" / "runtime_auto_cal_capture"
    output_dir.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(DEVICE_INDEX, cv2.CAP_MSMF)
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    capture.set(cv2.CAP_PROP_FPS, 60)
    if not capture.isOpened():
        raise RuntimeError(f"MSMF capture index {DEVICE_INDEX} did not open")

    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    writer = cv2.VideoWriter(
        str(output_dir / "auto_cal.avi"),
        cv2.VideoWriter_fourcc(*"MJPG"),
        fps,
        (width, height),
    )

    rows = []
    representative = None
    started = time.monotonic()
    failures = 0
    while time.monotonic() - started < CAPTURE_SECONDS:
        ok, frame = capture.read()
        if not ok:
            failures += 1
            continue
        writer.write(frame)
        reference = decode_bar(frame, 74, 94, "magenta")
        threshold = decode_bar(frame, 99, 107, "cyan")
        status = classify_status(frame)
        top = frame[8:60, :, :].mean(axis=(0, 1))
        level = frame[270:400, :, :].mean(axis=(0, 1))
        bottom = frame[450:478, :, :].mean(axis=(0, 1))
        elapsed = time.monotonic() - started
        rows.append((elapsed, reference, threshold, status, *top, *level, *bottom))
        if representative is None or status == "locked":
            representative = frame.copy()

    capture.release()
    writer.release()

    with (output_dir / "metrics.csv").open("w", newline="", encoding="utf-8") as handle:
        output = csv.writer(handle)
        output.writerow(
            [
                "seconds", "reference", "threshold", "status",
                "top_b", "top_g", "top_r",
                "level_b", "level_g", "level_r",
                "bottom_b", "bottom_g", "bottom_r",
            ]
        )
        for row in rows:
            output.writerow([f"{row[0]:.6f}", *row[1:4], *[f"{value:.3f}" for value in row[4:]]])

    if representative is not None:
        cv2.imwrite(str(output_dir / "representative.png"), representative)

    references = Counter(row[1] for row in rows if row[1] is not None)
    thresholds = Counter(row[2] for row in rows if row[2] is not None)
    statuses = Counter(row[3] for row in rows)
    print(f"capture={width}x{height}@{fps:.3f} frames={len(rows)} failures={failures}")
    print(f"references={dict(references)}")
    print(f"thresholds={dict(thresholds)}")
    print(f"statuses={dict(statuses)}")
    if rows:
        print(f"final_reference={rows[-1][1]} final_threshold={rows[-1][2]} final_status={rows[-1][3]}")


if __name__ == "__main__":
    main()
