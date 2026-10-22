#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Original deterministic rubber flecks, transparent between individual pieces."""
from pathlib import Path
from random import Random
from PIL import Image, ImageDraw
rng=Random(20261014)
im=Image.new('RGBA',(256,256),(0,0,0,0));draw=ImageDraw.Draw(im)
for _ in range(155):
 x,y=rng.randint(6,249),rng.randint(6,249)
 width,height=rng.randint(1,3),rng.randint(2,6)
 shade=rng.randint(12,35)
 draw.ellipse((x,y,x+width,y+height),fill=(shade,shade,shade,235))
path=Path(__file__).resolve().parents[1]/'client/art/raceprep/marbles.png'
im.save(path)
print(path)
