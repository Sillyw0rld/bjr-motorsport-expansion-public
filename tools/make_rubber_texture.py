#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Generate the rubber decal texture (Race Prep "scratch-on" rubber).

A dark, grainy smudge with soft edges and faint streaks along the driving
direction (texture +Y), tileable enough that overlapping cells read as one
rubbered-in line. Deterministic (fixed seed), original work: no licensing.

usage: python3 -I tools/make_rubber_texture.py client/art/raceprep/rubber.png
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

N = 512
rng = np.random.default_rng(20261014)
y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
# soft round edge: full inside r 0.55, fading to 0 at r 1
r = np.sqrt(x * x + y * y)
edge = np.clip((1.0 - r) / 0.45, 0, 1) ** 1.6
# grain: fine noise, blurred a little
grain = Image.fromarray((rng.random((N, N)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
grain = np.asarray(grain, dtype=np.float32) / 255
# streaks along the driving direction (+Y): noise stretched vertically
streak = Image.fromarray((rng.random((N // 16, N)) * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
streak = np.asarray(streak.filter(ImageFilter.GaussianBlur(2)), dtype=np.float32) / 255
alpha = edge * np.clip(0.55 + 0.35 * (streak - 0.5) * 2 + 0.25 * (grain - 0.5) * 2, 0, 1)
shade = 18 + 14 * grain + 8 * streak  # near-black rubber, slight variation
# BeamNG's dynamic decal renderer drops smooth alpha fades (tested 2026-10-14:
# a smooth radial fade never drew, stepped alpha does), so alpha is stepped
alpha = np.floor(alpha * 255 / 48) * 48 / 255
rgba = np.dstack([shade, shade, shade * 0.95, alpha * 255]).clip(0, 255).astype(np.uint8)
Image.fromarray(rgba, 'RGBA').save(sys.argv[1])
print('wrote', sys.argv[1], rgba.shape, 'mean alpha %.2f' % (alpha.mean()))


def line_textures(folder):
    """Racing-line strip (DecalRoad material): u = across the line, v = along
    it (tiles). Colour: near-black rubber with faint streaks; opacity: soft
    edges across, darker core, streaky along. Materials may fade smoothly."""
    W, L = 256, 512
    rs = np.random.default_rng(20261015)
    u = np.linspace(-1, 1, W)[None, :]
    across = np.clip(1 - np.abs(u) ** 2.2, 0, 1)  # soft edges, full in the middle
    streak = Image.fromarray((rs.random((L // 32, W)) * 255).astype(np.uint8)).resize((W, L), Image.BICUBIC)
    streak = np.asarray(streak.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32) / 255
    streak = (streak + np.roll(streak, L // 2, axis=0)) / 2  # tile along v
    grain = np.asarray(Image.fromarray((rs.random((L, W)) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255
    opacity = np.clip(across * (0.75 + 0.35 * (streak - 0.5) * 2 + 0.15 * (grain - 0.5) * 2), 0, 1)
    shade = (16 + 10 * grain + 6 * streak).astype(np.uint8)
    Image.fromarray(np.dstack([shade, shade, shade]), 'RGB').save(folder + '/rubberline_b.color.png')
    Image.fromarray((opacity * 255).astype(np.uint8), 'L').save(folder + '/rubberline_o.data.png')
    print('wrote line textures in', folder, 'mean opacity %.2f' % opacity.mean())


if len(sys.argv) > 2 and sys.argv[2] == '--line':
    line_textures(os.path.dirname(sys.argv[1]))


def strip_texture(path):
    """Racing-line patch for dynamic decals placed along the line (decal +Y =
    along the line); patches overlap 2x lengthwise. Complementary optical-depth
    windows keep that overlap even, rather than printing a dark oval every two
    metres. The look follows the game's own track rubber (2026-10-23, compared
    in game on Hirochi): mottled at several scales, fine tyre streaks drifting
    along the line, ragged edges and a few worn specks. Original work.
    Alpha is smooth: BeamNG 0.40's dynamic decals draw smooth fades (the
    stepped-alpha rule of 2026-10-14 no longer holds). This is the editable
    source of rubberstrip.png; no renderer work is added.
    """
    W, L = 256, 512
    rs = np.random.default_rng(20261023)

    def noise(cells, blur):
        """value noise on a (rows, cols) grid, upscaled smoothly to L x W"""
        small = Image.fromarray((rs.random(cells) * 255).astype(np.uint8))
        big = small.resize((W, L), Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur))
        return np.asarray(big, dtype=np.float32) / 255

    u = np.linspace(-1, 1, W)[None, :]
    # Endpoint-excluded sampling means adjacent half-length patches have
    # exactly complementary Hann windows. Alpha compositing multiplies
    # transmission, so complement *optical depth*, not straight alpha.
    phase = np.arange(L)[:, None] / L
    along = .5 - .5 * np.cos(2 * np.pi * phase)
    # mottling at three scales, stretched along the line
    m = .45 * noise((6, 24), 2) + .35 * noise((16, 64), 1.2) + .2 * noise((64, 128), .6)
    m = np.clip((m - .5) * 1.8 + .5, 0, 1)
    # fine tyre streaks, drifting slowly sideways along the patch
    base = np.asarray(Image.fromarray((rs.random((1, W)) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(.5)), dtype=np.float32)[0] / 255
    drift = (np.asarray(Image.fromarray((rs.random((4, 1)) * 255).astype(np.uint8)).resize(
        (1, L), Image.BICUBIC), dtype=np.float32)[:, 0] / 255 - .5) * 6
    strands = np.stack([np.interp(np.arange(W) + d, np.arange(W), base) for d in drift])
    strands = np.clip((strands - .5) * 2.2 + .5, 0, 1)
    # ragged edges: the band's edge wanders at two scales
    wander = (noise((40, 12), 1.5) - .5) * .16 + (noise((120, 40), .6) - .5) * .08
    across = np.clip(1 - (np.abs(u) / (.88 + wander)) ** 2.6, 0, 1)
    grain = rs.random((L, W)).astype(np.float32)
    specks = np.asarray(Image.fromarray(((rs.random((L, W)) > .985) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(.7)), dtype=np.float32) / 255
    depth = np.clip(1.7 * across * (.3 + .8 * m + .55 * strands + .2 * (grain - .5) - 1.2 * specks), 0, None)
    # every patch is the same bitmap, so a darker row would repeat every 2 m:
    # level each row's mean depth, keeping the detail within it
    rowmean = depth[:, 64:192].mean(axis=1, keepdims=True)
    depth = depth * (rowmean.mean() / np.maximum(rowmean, 1e-6))
    alpha = 1 - np.exp(-depth * along)
    # then even out what two overlapping patches show at full level (the
    # renderer's 0.85 tint): a few fixed-point passes on each row pair
    for _ in range(6):
        rows = alpha[:, 64:192]
        shown = 1 - (1 - .85 * rows[:L // 2]) * (1 - .85 * rows[L // 2:])
        fix = (shown.mean() / np.maximum(shown.mean(axis=1), 1e-6))[:, None]
        depth = depth * np.vstack([fix, fix])
        alpha = 1 - np.exp(-depth * along)
    alpha[0, :] = alpha[-1, :] = 0
    alpha[:, 0] = alpha[:, -1] = 0
    shade = 16 + 10 * m + 4 * strands
    rgba = np.dstack([shade, shade, shade, alpha * 255]).clip(0, 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(path)
    print('wrote', path)


if len(sys.argv) > 2 and sys.argv[2] == '--strip':
    strip_texture(os.path.join(os.path.dirname(sys.argv[1]), 'rubberstrip.png'))
