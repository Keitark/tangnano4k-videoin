"""Decode the runtime probe's paired-nibble raw page using its calibration page.

Usage: python tools/analyze_runtime_probe.py raw.png calibration.png [128|160]
Images must be unscaled 640x480 captures. Raw sample rate is 6.75MHz, NOT
the 13.5MHz rate of the old standalone 8-bit snapshot. Compression can make
nibbles ambiguous; report palette errors rather than claiming bit-exact data.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np


def cells(gray, width=128):
    if gray.shape != (480, 640):
        raise ValueError('Expected unscaled 640x480 frame')
    # Skip 16 rows hidden by the health/telemetry/page strips.
    if width not in (128, 160):
        raise ValueError('Supported source widths: 128 or 160')
    step = 640 // width
    return gray[66:480:4, step//2+1:640:step].astype(float).ravel()


def decode(raw_gray, calibration_gray, width=128):
    cal = cells(calibration_gray, width)
    first_sample = 16*width//2
    known = np.arange(first_sample, 120*width//2) % 256
    expected = np.column_stack((known >> 4, known & 15)).ravel()
    palette = np.array([np.median(cal[expected == k]) for k in range(16)])
    # Full-range grayscale can clip at the capture device. Retain an explicitly
    # approximate measurement if most codes remain separable, and flag every
    # byte whose high or low nibble falls in an ambiguous neighborhood.
    indistinct = np.diff(palette) < 4
    if palette[-1]-palette[0] < 150 or np.count_nonzero(indistinct) > 3:
        raise ValueError('Calibration has insufficient distinguishable levels')
    values = cells(raw_gray, width)
    distance = abs(values[:, None] - palette[None, :])
    nibble = distance.argmin(axis=1).astype(np.uint8)
    samples = (nibble[::2] << 4) | nibble[1::2]
    nearest = np.partition(distance, 1, axis=1)[:, :2]
    ambiguous = abs(nearest[:, 1] - nearest[:, 0]) < 3
    uncertain_bytes = ambiguous[::2] | ambiguous[1::2]
    result = dict(sample_rate_hz=6750000, source_width=width, first_sample_index=first_sample,
                  sample_count=len(samples), palette=palette.tolist(),
                  ambiguous_nibble_fraction=float(ambiguous.mean()),
                  uncertain_byte_fraction=float(uncertain_bytes.mean()),
                  clipped_or_indistinct_pairs=np.flatnonzero(indistinct).tolist(),
                  mean_palette_error=float(distance.min(axis=1).mean()),
                  percentiles=np.percentile(samples,[0,5,25,50,75,95,100]).tolist(),
                  caveat='Reconstructed via compressed HDMI; check palette errors')
    if samples.std() > 0:
        scores=[(k,float(np.corrcoef(samples[:-k],samples[k:])[0,1])) for k in range(400,461)]
        best=max(scores,key=lambda v:v[1])
        result.update(best_line_lag=best[0],best_line_correlation=best[1])
    return samples, result


if __name__ == '__main__':
    raw_path, cal_path = map(Path, sys.argv[1:3])
    width = int(sys.argv[3]) if len(sys.argv)>3 else 128
    samples, report = decode(cv2.imread(str(raw_path),0),cv2.imread(str(cal_path),0),width)
    np.save(raw_path.with_name('runtime_samples.npy'),samples)
    raw_path.with_name('runtime_analysis.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
