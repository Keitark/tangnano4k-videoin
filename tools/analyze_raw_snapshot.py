"""Approximate sequential ADC waveform from the frozen 128x120 HDMI view.

Capture compression/range conversion makes these display codes, not bit-exact
ADC telemetry. The first 14 rows are excluded because status overlays them.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

path = Path(sys.argv[1])
im = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
if im is None or im.shape != (480, 640):
    raise ValueError('Expected 640x480 frozen raw-snapshot capture')
samples = im[58:480:4, 3:640:5].astype(float).ravel()
scores = [(k, float(np.corrcoef(samples[:-k], samples[k:])[0, 1]))
          for k in range(800, 921)]
best = max(scores, key=lambda v: v[1])
result = dict(sample_count=len(samples), sample_rate_hz=13500000,
              first_sample_index=1792,
              caveat='Display codes approximate ADC codes; compressed HDMI capture',
              percentiles=np.percentile(samples, [0, 5, 25, 50, 75, 95, 100]).tolist(),
              below_15_fraction=float(np.mean(samples < 15)),
              above_240_fraction=float(np.mean(samples > 240)),
              best_line_lag=best[0], best_line_correlation=best[1],
              nominal_858_correlation=dict(scores)[858])
path.with_name('raw_analysis.json').write_text(json.dumps(result, indent=2))
np.save(path.with_name('raw_display_samples.npy'), samples)
fig, axes = plt.subplots(3, 1, figsize=(12, 8), constrained_layout=True)
axes[0].plot(np.arange(len(samples))/13.5, samples, lw=.6)
axes[0].set(xlabel='Time (microseconds)', ylabel='Display code', title='Frozen raw ADC snapshot (no sync/decoder gating)')
axes[1].plot(np.arange(2574)/13.5, samples[:2574], lw=.8)
axes[1].set(xlabel='Time (microseconds)', ylabel='Display code', title='Three nominal NTSC line periods')
axes[2].plot(*zip(*scores))
axes[2].axvline(858, color='r', ls='--')
axes[2].set(xlabel='Lag (13.5 MHz samples)', ylabel='Correlation', title='Expected line period near 858 samples')
fig.savefig(path.with_name('raw_waveform.png'), dpi=120)
print(json.dumps(result, indent=2))
