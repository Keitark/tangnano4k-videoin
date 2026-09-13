"""Offline color proof from a short full-rate burst snapshot, not a full frame.

Convention: CVBS=Y+U*cos(wt)+V*sin(wt), burst=-U. Actual source hue/sign and
gain require a known color-bar input before this can be called color-accurate.
Burst/black estimates are per line, never derived from the grayscale picture.
"""
import json
import sys
from pathlib import Path
import cv2
import numpy as np
from analyze_burst_probe import FS, FSC, measure


def demodulate(samples):
    report,_,_=measure(samples)
    period=report['line_period_samples']
    origin=report['estimated_sync_end_modulo']
    burst_offset=report['candidate_burst_offset_samples']
    t=np.arange(len(samples))
    # Linear, unity-DC luma filter. Mix against continuous local carrier, then
    # normalize each line's complex vector to the measured burst phase.
    luma=np.convolve(samples,np.ones(15)/15,mode='same')
    carrier=np.convolve((samples-luma)*np.exp(-2j*np.pi*FSC*t/FS),np.ones(32)/16,mode='same')
    result=[]
    for start in np.arange(origin+period,len(samples)-period,period):
        burst=carrier[start+burst_offset]
        amplitude=abs(burst)
        if amplitude<8:
            continue
        black=np.median(samples[start+65:start+95])
        active=np.linspace(start+120,start+820,160).astype(int)
        uv=-carrier[active]*np.conj(burst)/amplitude
        scale=255/(amplitude*3.5)  # 20 IRE burst amplitude vs70 IRE luma span.
        y=(luma[active]-black)*scale
        u=uv.real*scale
        v=-uv.imag*scale
        rgb=np.stack((y+1.140*v,y-.395*u-.581*v,y+2.032*u),axis=-1)
        result.append(np.clip(rgb,0,255).astype(np.uint8))
    if not result:
        raise ValueError('No usable burst lines')
    return np.array(result),report


if __name__=='__main__':
    path=Path(sys.argv[1])
    rgb,report=demodulate(np.load(path/'burst_samples.npy'))
    cv2.imwrite(str(path/'color_strip_native.png'),cv2.cvtColor(rgb,cv2.COLOR_RGB2BGR))
    preview=cv2.resize(rgb,None,fx=4,fy=8,interpolation=cv2.INTER_NEAREST)
    cv2.imwrite(str(path/'color_strip_preview.png'),cv2.cvtColor(preview,cv2.COLOR_RGB2BGR))
    print(json.dumps(dict(lines=len(rgb),width=160,
        caveat='Short offline strip, provisional hue/sign/gain; not live FPGA color or a full frame.')))
