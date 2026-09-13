"""Full-rate 4-bit burst probe only (not the older paired-nibble raw page).

Decode calibrated HDMI cells; inspect sync recurrence and carrier envelope.
All results are approximate because the capture dongle compresses the image.
No automated color-lock assertion is made from envelope strength alone.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from analyze_runtime_probe import cells

FS=13500000
FSC=315000000/88


def decode(raw, cal, width=160):
    values=cells(raw,width)
    known=np.arange(16*width,120*width)%16
    calibration=cells(cal,width)
    palette=np.array([np.median(calibration[known==k]) for k in range(16)])
    if np.any(np.diff(palette)<4):
        raise ValueError(f'Unreliable calibration palette: {palette}')
    error=abs(values[:,None]-palette)
    codes=error.argmin(axis=1)
    nearest=np.sort(error,axis=1)[:,:2]
    report=dict(palette=palette.tolist(), mean_palette_error=float(error.min(axis=1).mean()),
                uncertain_fraction=float((np.diff(nearest,axis=1)<3).mean()))
    return codes.astype(float)*16, report


def measure(samples):
    smooth=np.convolve(samples,np.ones(16)/16,mode='same')
    scores=[np.corrcoef(smooth[32:-k-32],smooth[k+32:-32])[0,1] for k in range(840,877)]
    period=int(np.argmax(scores))+840
    length=len(samples)//period
    folded=smooth[:length*period].reshape(length,period).mean(axis=0)
    # Lowest 40-sample interval estimates the sync tip. Avoid assuming the
    # decoder's delayed HPLL pulse is the true end of the analog sync pulse.
    circular=np.r_[folded,folded[:39]]
    tip_start=int(np.argmin(np.convolve(circular,np.ones(40)/40,mode='valid')))
    origin=(tip_start+52)%period
    starts=np.arange(origin+period,len(samples)-period,period)
    lines=np.array([samples[s:s+period] for s in starts])
    t=np.arange(len(samples))
    centered=samples-np.convolve(samples,np.ones(15)/15,mode='same')
    carrier=centered*np.exp(-2j*np.pi*FSC*t/FS)
    window=np.ones(32)/16
    phasor=np.convolve(carrier,window,mode='same')
    envelope=np.array([abs(phasor[s:s+period]) for s in starts])
    avg=envelope.mean(axis=0)
    peak=int(np.argmax(avg[:90]))
    per_line=np.array([phasor[s+peak] for s in starts])
    unit=per_line/np.maximum(abs(per_line),1e-9)
    coherence=float(abs(unit.mean()))
    report=dict(sample_rate_hz=FS, sample_count=len(samples), line_period_samples=period,
                line_correlation=float(max(scores)), lines=len(starts),
                estimated_sync_end_modulo=origin, candidate_burst_offset_samples=peak,
                candidate_amplitude_codes=float(np.median(abs(per_line))),
                carrier_phase_coherence=coherence,
                caveat='Candidate only: sync origin is estimated, compression can alter codes/phase; inspect plot.')
    return report,lines,envelope


def main(path):
    samples,report=decode(cv2.imread(str(path/'raw.png'),0),cv2.imread(str(path/'calibration.png'),0))
    measured,lines,envelope=measure(samples)
    report.update(measured)
    np.save(path/'burst_samples.npy',samples)
    (path/'burst_analysis.json').write_text(json.dumps(report,indent=2))
    fig,axes=plt.subplots(3,1,figsize=(11,9),constrained_layout=True)
    axes[0].plot(samples[:1800]); axes[0].set(title='Calibrated wider-band samples (13.5 MS/s)',ylabel='Approx ADC code')
    axes[1].plot(lines[:,:140].T,alpha=.3); axes[1].set(title='Lines aligned near estimated sync end',ylabel='Approx ADC code')
    axes[2].plot(envelope.mean(axis=0)); axes[2].axvspan(0,90,color='orange',alpha=.2)
    axes[2].set(title='Mean 3.579545 MHz carrier envelope; shaded candidate porch',xlabel='Samples after estimated sync end',ylabel='Approx amplitude')
    fig.savefig(path/'burst_analysis.png'); plt.close(fig)
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main(Path(sys.argv[1]))
