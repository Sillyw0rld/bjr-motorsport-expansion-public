#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Slice the original 5x4 part-render sheet. Requires Pillow; never run at build/load time."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PARTS = 'engine turbo supercharger intake exhaust cooling fuel piston camshaft gearbox differential drivetrain tyre brakes springs alignment body aero nitrous antiroll'.split()


def main():
    source = ROOT/'docs/artwork/upgrade-parts-contact-sheet.png'
    target = ROOT/'client/ui/modModules/raceprepBJR/images'
    target.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as original:
        sheet = original.convert('RGB')
    w, h = sheet.size
    for i, name in enumerate(PARTS):
        x, y = i % 5, i // 5
        cell = sheet.crop((round(x*w/5), round(y*h/4), round((x+1)*w/5), round((y+1)*h/4)))
        cell.thumbnail((384, 384), Image.Resampling.LANCZOS)
        cell.save(target/(name+'.webp'), 'WEBP', quality=88, method=6)
    print(f'Sliced {len(PARTS)} components from {w}x{h} source')


if __name__ == '__main__':
    main()
