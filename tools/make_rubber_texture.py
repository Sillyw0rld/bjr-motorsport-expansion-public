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
    along the line). Alpha is stepped (the decal renderer drops smooth fades);
    patches overlap 2x lengthwise. Complementary optical-depth windows keep
    that overlap even, rather than printing a dark oval every two metres.
    This is the editable source of rubberstrip.png; no renderer work is added.
    """
    W, L = 256, 512
    rs = np.random.default_rng(20261018)
    u = np.linspace(-1, 1, W)[None, :]
    # Endpoint-excluded sampling means adjacent half-length patches have
    # exactly complementary Hann windows. Alpha compositing multiplies
    # transmission, so complement *optical depth*, not straight alpha.
    phase = np.arange(L)[:, None] / L
    along = .5 - .5 * np.cos(2 * np.pi * phase)
    across = np.maximum(0, np.cos(u * np.pi / 2)) ** 1.6
    # Fine longitudinal scuffing, without a broad cloudy variation that
    # repeats across the whole line. Same profile at both ends of the patch.
    strands = np.asarray(Image.fromarray((rs.random((1, W)) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(.65)), dtype=np.float32) / 255
    fine = rs.random((L, W))
    depth = 1.35 * across * (.55 + .9 * strands)
    # 0.85 is the existing fully-rubbered decal tint, kept in rubberLine.lua.
    alpha = (1 - np.exp(-depth * along)) / .85
    # Keep the engine-compatible 40/255 alpha levels. Stochastic rounding
    # distributes the thresholds as fine grain instead of visible contour
    # bands; it adds no texture samples or runtime randomness.
    alpha = np.clip(np.floor(alpha * 255 / 40 + fine) * 40, 0, 240)
    alpha[0, :] = alpha[-1, :] = 0
    alpha[:, 0] = alpha[:, -1] = 0
    shade = np.broadcast_to(19 + 5 * strands, (L, W))
    rgba = np.dstack([shade, shade, shade, alpha]).clip(0, 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(path)
    print('wrote', path)


if len(sys.argv) > 2 and sys.argv[2] == '--strip':
    strip_texture(os.path.join(os.path.dirname(sys.argv[1]), 'rubberstrip.png'))
