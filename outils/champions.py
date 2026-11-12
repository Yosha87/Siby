#!/usr/bin/env python3
# The world champions' gold king and the women's world champions' gold
# queen, shown next to the name (Yosha 2026-11-05): the board's cburnett
# pieces in gold with bronze lines, drawn large by rsvg-convert, cropped to
# what they draw, then reduced to each height from 10 to 28 pixels
# (bitmaps/champions/WC_<h>.png, WWC_<h>.png). Siby picks the height from
# the font and sits the piece on the text's baseline.
import os, subprocess, tempfile
from PIL import Image
ICI = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scidvspc', 'bitmaps')
SORTIE = os.path.join(ICI, 'champions')
os.makedirs(SORTIE, exist_ok=True)
for f in os.listdir(SORTIE):
    os.remove(os.path.join(SORTIE, f))
for piece, titre in (('wK', 'WC'), ('wQ', 'WWC')):
    t = open(os.path.join(ICI, 'cburnett', piece + '.svg'), encoding='utf-8').read()
    t = t.replace('fill="#fff"', 'fill="#f0c230"').replace('stroke="#000"', 'stroke="#5c3b00"')
    with tempfile.TemporaryDirectory() as d:
        s, o = os.path.join(d, 'p.svg'), os.path.join(d, 'p.png')
        open(s, 'w', encoding='utf-8').write(t)
        subprocess.run(['rsvg-convert', '-w', '720', '-h', '720', s, '-o', o], check=True)
        grand = Image.open(o).convert('RGBA')
        grand = grand.crop(grand.getbbox())
    for h in range(10, 29):
        w = max(1, round(grand.width * h / grand.height))
        grand.resize((w, h), Image.LANCZOS).save(os.path.join(SORTIE, f'{titre}_{h}.png'), optimize=True)
