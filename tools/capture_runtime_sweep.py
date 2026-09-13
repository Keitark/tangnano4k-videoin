import csv
import time
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np


DEVICE_INDEX = 3
CAPTURE_SECONDS = 23.0
VALID_CODES = tuple(range(128, 256))


def decode_reference(frame):
    band = frame[74:94, :, :].mean(axis=0)
    blue, green, red = band[:, 0], band[:, 1], band[:, 2]
    magenta = (red > 80) & (blue > 80) & (red > green * 1.5) & (blue > green * 1.5)
    width = 0
    for active in magenta:
        if not active:
            break
        width += 1
    measured = int(round((width - 8) / 2.0))
    if measured not in VALID_CODES:
        return None
    return measured


def main():
    repo_root = Path(__file__).resolve().parents[1]
    output_dir = repo_root / "build" / "runtime_all_codes_capture"
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
        str(output_dir / "runtime_sweep.avi"),
        cv2.VideoWriter_fourcc(*"MJPG"),
        fps,
        (width, height),
    )

    samples = defaultdict(list)
    representatives = {}
    started = time.monotonic()
    frame_count = 0
    read_failures = 0
    while time.monotonic() - started < CAPTURE_SECONDS:
        ok, frame = capture.read()
        if not ok:
            read_failures += 1
            continue
        frame_count += 1
        writer.write(frame)
        code = decode_reference(frame)
        if code is None:
            continue
        top = frame[8:60, :, :].mean(axis=(0, 1))
        level = frame[270:400, :, :].mean(axis=(0, 1))
        bottom = frame[450:478, :, :].mean(axis=(0, 1))
        samples[code].append((frame_count, *top.tolist(), *level.tolist(), *bottom.tolist()))
        representatives.setdefault(code, frame.copy())

    capture.release()
    writer.release()

    with (output_dir / "metrics.csv").open("w", newline="", encoding="utf-8") as handle:
        rows = csv.writer(handle)
        rows.writerow(
            ["density", "frames", "top_b", "top_g", "top_r", "level_b", "level_g", "level_r", "bottom_b", "bottom_g", "bottom_r"]
        )
        for code in VALID_CODES:
            values = samples.get(code, [])
            if not values:
                rows.writerow([code, 0, "", "", "", "", "", ""])
                continue
            array = np.asarray(values, dtype=np.float64)
            mean = array[:, 1:].mean(axis=0)
            rows.writerow([code, len(values), *[f"{value:.3f}" for value in mean]])
            cv2.imwrite(str(output_dir / f"density_{code}.png"), representatives[code])

    print(f"capture={width}x{height}@{fps:.3f} frames={frame_count} failures={read_failures}")
    for code in VALID_CODES:
        values = samples.get(code, [])
        if not values:
            print(f"density={code} frames=0")
            continue
        array = np.asarray(values, dtype=np.float64)
        mean = array[:, 1:].mean(axis=0)
        print(
            f"density={code} frames={len(values)} "
            f"top_bgr={mean[0]:.1f},{mean[1]:.1f},{mean[2]:.1f} "
            f"level_bgr={mean[3]:.1f},{mean[4]:.1f},{mean[5]:.1f} "
            f"bottom_bgr={mean[6]:.1f},{mean[7]:.1f},{mean[8]:.1f}"
        )


if __name__ == "__main__":
    main()
