"""Read-only comparison of preserved successful/failing FPGA build evidence."""
import hashlib
import re
from pathlib import Path

builds = ['ntsc_mono_cdc46_c6', 'ntsc_mono_cdc46_gain4_c6', 'ntsc_mono_field_c6']
modules = ['nano4k_cvbs_hdmi_clocks', 'delta_modulator_core', 'lvds_delta_adc', 'adc_level_iir']
for build in builds:
    root = Path(__file__).resolve().parents[1] / 'build' / build / 'impl'
    netlist = (root / 'gwsynthesis/project.vg').read_text()
    report = (root / 'pnr/project.rpt.txt').read_text()
    timing = (root / 'pnr/project_tr_content.html').read_text()
    print(build)
    for name in modules:
        content = re.search(r'module\s+' + name + r'\s.*?endmodule', netlist, re.S).group()
        # These two revisions differ only in suffixes on exported ADC nets.
        content = re.sub(r'\b(sample_strobe|reconstructed_level)_Z\b', r'\1', content)
        content = re.sub(r'\breconstructed_level_Z_', 'reconstructed_level_', content)
        print('  normalized module', name, hashlib.sha256(content.encode()).hexdigest()[:16])
    for check in ['Setup', 'Hold']:
        value = re.search(r'Numbers of '+check+r' Violated Endpoints</td>\s*<td>(\d+)',timing).group(1)
        print(' ', check, 'violated endpoints:', value)
    for line in report.splitlines():
        if re.match(r'^(video_p|adc_feedback)\s+\|',line):
            print(' ',line)
    print('  configuration hash', hashlib.sha256((root/'pnr/device.cfg').read_bytes()).hexdigest()[:16])
