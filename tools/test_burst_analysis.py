"""Deterministic tests of full-rate packing and candidate burst measurement."""
import unittest
import numpy as np
from analyze_burst_probe import decode, measure, FS, FSC
from decode_burst_color_strip import demodulate


class BurstAnalysisTest(unittest.TestCase):
    def test_full_rate_cells(self):
        width=160
        codes=np.arange(19200,dtype=np.uint32)%16
        cal=np.repeat(np.repeat((32+12*codes).astype(np.uint8).reshape(120,width),4,0),4,1)
        decoded,report=decode(cal,cal)
        np.testing.assert_array_equal(decoded,codes[2560:]*16)
        self.assertEqual(report['uncertain_fraction'],0)

    def test_phase_coherent_burst_and_noise_control(self):
        rng=np.random.default_rng(22)
        t=np.arange(19200)
        p=t%858
        base=np.where(p<64,24.,np.where((p>=150)&(p<790),128.,64.))
        burst=((p>=77)&(p<112))*32*np.cos(2*np.pi*FSC*t/FS+.7)
        report,_,_=measure(base+burst+rng.normal(0,1,len(t)))
        self.assertEqual(report['line_period_samples'],858)
        self.assertGreater(report['carrier_phase_coherence'],.95)
        self.assertGreater(report['candidate_amplitude_codes'],25)
        self.assertLess(report['candidate_burst_offset_samples'],65)
        quiet,_,_=measure(base+rng.normal(0,1,len(t)))
        self.assertLess(quiet['candidate_amplitude_codes'],10)

    def test_known_uv_orientation_and_gain(self):
        t=np.arange(19200)
        p=t%858
        phase=2*np.pi*FSC*t/FS+.9
        samples=np.where(p<64,24.,64.)
        samples+=((p>=77)&(p<112))*(-32*np.cos(phase))
        samples+=((p>=150)&(p<790))*(50+8*np.cos(phase)+12*np.sin(phase))
        rgb,_=demodulate(samples)
        actual=np.median(rgb[:,20:130],axis=(0,1))
        scale=255/(32*3.5)
        expected=np.array([50+1.140*12,50-.395*8-.581*12,50+2.032*8])*scale
        np.testing.assert_allclose(actual,expected,atol=8)


if __name__=='__main__':
    unittest.main()
