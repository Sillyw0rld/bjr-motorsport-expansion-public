# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Asset acceptance for the existing half-length-overlap dynamic decals."""
from pathlib import Path
import subprocess
import tempfile
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class RubberTexture(unittest.TestCase):
    def test_strip(self):
        asset = ROOT / 'client/art/raceprep/rubberstrip.png'
        image = Image.open(asset)
        self.assertEqual(image.mode, 'RGBA')
        self.assertEqual(image.size, (256, 512), 'same texture footprint')
        rgba = np.asarray(image)
        a = rgba[:, :, 3]
        self.assertTrue(set(np.unique(a)).issubset(set(range(0, 241, 40))),
                        'retain engine-compatible stepped alpha')
        self.assertFalse(a[0].any() or a[-1].any() or a[:, 0].any() or a[:, -1].any())
        self.assertTrue(np.array_equal(rgba[:, :, 0], rgba[:, :, 1]))
        self.assertTrue(np.array_equal(rgba[:, :, 0], rgba[:, :, 2]))
        # Actual existing tint and level curve; alpha-over two patches at
        # the renderer's unchanged 2 m spacing / 4 m length.
        rows = a[:, 64:192] / 255
        for level, ripple_limit in [(1, .04), (.5, .08), (.1, .055)]:
            tint = .85 * level ** .6
            overlap = 1 - (1 - tint * rows[:256]) * (1 - tint * rows[256:])
            self.assertLess(np.ptp(overlap.mean(axis=1)), ripple_limit,
                            'no repeating dark oval at level ' + str(level))
            if level == 1:
                self.assertAlmostEqual(overlap.mean(), .6774, delta=.02,
                                       msg='keep prior full-line average darkness')
        # The committed bitmap comes from its editable deterministic source.
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'rubber.png'
            subprocess.run(['python3', '-I', str(ROOT / 'tools/make_rubber_texture.py'),
                            str(target), '--strip'], check=True, capture_output=True)
            self.assertEqual(asset.read_bytes(), target.with_name('rubberstrip.png').read_bytes())


if __name__ == '__main__':
    unittest.main()
