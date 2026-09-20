#!/usr/bin/env python3
"""dialog_shots.py [OUTDIR] [ROWSxCOLS]: run dialog_shots.sh and rasterise every frame to OUTDIR/*.png (uses screenshots.py)."""
import glob, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import screenshots as S
from PIL import ImageFont
out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/dabt_dialogs'; size = sys.argv[2] if len(sys.argv) > 2 else '30x100'
subprocess.run(['bash', os.path.join(S.HERE, 'dialog_shots.sh'), out, size], check=True, stdin=subprocess.DEVNULL)
rows, cols = map(int, size.split('x'))
fpath = next(iter(glob.glob('/usr/share/fonts/**/JetBrainsMonoNerdFont-Regular.ttf', recursive=True) + glob.glob('/usr/share/fonts/**/DejaVuSansMono.ttf', recursive=True)))
font = ImageFont.truetype(fpath, 16); cw = round(font.getlength('M')); asc, desc = font.getmetrics()
for f in sorted(glob.glob(out + '/*.ans')):
    scr = S.Screen(rows, cols); scr.feed(open(f, encoding='utf-8', errors='replace').read())
    S.render(scr, font, font, cw, asc + desc, asc, f[:-4] + '.png'); print(f[:-4] + '.png')
print(open(out + '/log.txt').read())
