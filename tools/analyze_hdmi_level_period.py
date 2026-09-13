import sys
from pathlib import Path

import cv2
import numpy as np


PIXEL_CLOCK_HZ = 25_200_000.0
HDMI_TOTAL_WIDTH = 800
HDMI_TOTAL_HEIGHT = 525
LEVEL_FIRST_ROW = 256
LEVEL_LAST_ROW = 415
MAX_LAG = 2200
FRAME_SAMPLES = 12


def main():
    repo_root = Path(__file__).resolve().parents[1]
    video_path = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else repo_root
        / "build"
        / "closed_loop_filtered_period_sweep_capture"
        / "capture.avi"
    )

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"could not open {video_path}")

    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    selected = np.linspace(
        max(0, frame_count // 10),
        max(0, frame_count - 2),
        FRAME_SAMPLES,
        dtype=int,
    )

    timing_length = HDMI_TOTAL_WIDTH * HDMI_TOTAL_HEIGHT
    fft_length = 1 << (2 * timing_length - 1).bit_length()
    correlation_sum = np.zeros(MAX_LAG + 1, dtype=np.float64)
    pair_count_sum = np.zeros(MAX_LAG + 1, dtype=np.float64)
    variance_sum = 0.0
    used_frames = 0

    visible_indices = []
    visible_rows = []
    visible_columns = []
    for row in range(LEVEL_FIRST_ROW, LEVEL_LAST_ROW + 1):
        if (row & 63) == 0:
            continue
        for column in range(1, 640):
            if ((column & 63) == 0) or (((column - 1) & 63) == 0):
                continue
            visible_indices.append(row * HDMI_TOTAL_WIDTH + column)
            visible_rows.append(row)
            visible_columns.append(column)

    visible_indices = np.asarray(visible_indices, dtype=np.int64)
    visible_rows = np.asarray(visible_rows, dtype=np.int64)
    visible_columns = np.asarray(visible_columns, dtype=np.int64)
    mask = np.zeros(timing_length, dtype=np.float32)
    mask[visible_indices] = 1.0
    mask_fft = np.fft.rfft(mask, fft_length)
    mask_correlation = np.fft.irfft(
        mask_fft * np.conjugate(mask_fft), fft_length
    )[: MAX_LAG + 1]

    for frame_index in selected:
        capture.set(cv2.CAP_PROP_POS_FRAMES, int(frame_index))
        ok, frame = capture.read()
        if not ok or frame.shape[:2] != (480, 640):
            continue

        # First-difference the live grayscale samples to reject slow level
        # drift and emphasize recurring composite-sync edges.
        samples = (
            frame[visible_rows, visible_columns, 1].astype(np.float32)
            - frame[visible_rows, visible_columns - 1, 1].astype(np.float32)
        )
        samples -= samples.mean()
        variance = float(np.mean(samples * samples))
        if variance <= 0.0:
            continue

        waveform = np.zeros(timing_length, dtype=np.float32)
        waveform[visible_indices] = samples
        waveform_fft = np.fft.rfft(waveform, fft_length)
        correlation = np.fft.irfft(
            waveform_fft * np.conjugate(waveform_fft), fft_length
        )[: MAX_LAG + 1]

        correlation_sum += correlation
        pair_count_sum += mask_correlation
        variance_sum += variance
        used_frames += 1

    capture.release()
    if used_frames == 0:
        raise RuntimeError("no usable frames")

    normalized = correlation_sum / np.maximum(pair_count_sum, 1.0)
    normalized /= variance_sum / used_frames

    search_first = 1200
    search_last = 2000
    search = normalized[search_first : search_last + 1]
    peak_offsets = np.argsort(search)[-12:][::-1]
    expected_lag = int(round(63.555e-6 * PIXEL_CLOCK_HZ))

    print(f"video={video_path}")
    print(f"frames={used_frames} expected_ntsc_lag={expected_lag}")
    print(
        f"expected_score={normalized[expected_lag]:.6f} "
        f"search_median={np.median(search):.6f}"
    )
    print("top_lags:")
    for offset in peak_offsets:
        lag = search_first + int(offset)
        period_us = lag * 1_000_000.0 / PIXEL_CLOCK_HZ
        print(f"  lag={lag} period_us={period_us:.3f} score={normalized[lag]:.6f}")


if __name__ == "__main__":
    main()
