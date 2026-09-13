"""Render a deterministic README banner from the owner's actual demo footage.

Requires ffmpeg with zscale, tonemap and drawtext. Does not generate hardware
imagery. Source video is intentionally not distributed in the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('video', type=Path)
    parser.add_argument('--out', type=Path, default=Path('assets'))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    output = args.out / 'color-video-banner.png'
    bold = "C\\:/Windows/Fonts/segoeuib.ttf"
    regular = "C\\:/Windows/Fonts/segoeui.ttf"
    filters = [
        '[0:v]zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,'
        'tonemap=tonemap=mobius:desat=0,zscale=t=bt709:m=bt709:r=tv,'
        'format=yuv420p,crop=1150:750:405:0,scale=884:576,setpts=PTS-STARTPTS[shot]',
        '[1:v][shot]overlay=650:54:shortest=1[base]',
    ]
    titles = [
        ('KEITARK / TANG NANO 4K', 64, 66, 23, '0x66e5cc', regular),
        ('Tiny FPGA.', 60, 156, 67, 'white', bold),
        ('Real color', 60, 238, 67, 'white', bold),
        ('video.', 60, 320, 67, 'white', bold),
        ('Passive front end. FPGA decoding.', 64, 440, 25, '0xc6cddc', regular),
        ('NTSC IN  /  HDMI OUT', 64, 488, 24, '0x66e5cc', bold),
        ('320 x 240 COLOR  /  3 LINE BUFFERS', 64, 564, 22, 'white', bold),
        ('No external ADC or video-decoder IC', 64, 606, 22, '0xc6cddc', regular),
        ('ACTUAL HARDWARE DEMO / 13 SEP 2026', 650, 651, 20, '0xc6cddc', regular),
    ]
    text_filters = [
        f"drawtext=fontfile='{font}':text='{text}':x={x}:y={y}:fontsize={size}:fontcolor={color}"
        for text, x, y, size, color, font in titles
    ]
    filters.append('[base]' + ','.join(text_filters) + ',format=rgb24[out]')
    command = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
               '-ss', '0.8', '-i', str(args.video), '-f', 'lavfi', '-i',
               'color=c=0x101827:s=1600x700:r=1', '-filter_complex',
               ';'.join(filters), '-map', '[out]', '-frames:v', '1', str(output)]
    subprocess.run(command, check=True)
    def sha(path):
        with path.open('rb') as handle:
            return hashlib.file_digest(handle, 'sha256').hexdigest()
    manifest = {
        'source': args.video.name, 'source_sha256': sha(args.video),
        'source_frame_seconds': 0.8, 'classification': 'engineering-evidence',
        'authorization': 'Owner supplied video and requested repository header.',
        'rights': 'Private project use; no new rights in depicted third-party demo content granted.',
        'transform': 'HDR-to-SDR tone mapping, crop, proportional resize, deterministic title overlay',
        'crop_xywh': [405, 0, 1150, 750], 'dimensions': [1600, 700],
        'output_sha256': sha(output), 'renderer': 'tools/make_repo_banner.py',
        'generated_hardware_imagery': False,
    }
    (args.out / 'banner-provenance.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(output)


if __name__ == '__main__':
    main()
