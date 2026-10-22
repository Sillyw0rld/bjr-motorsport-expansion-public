# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Asset shipping and placement checks; browser tests cover loading/context/focus."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ArtworkTests(unittest.TestCase):
    def test_compact_assets(self):
        images = ROOT/'client/ui/modModules/raceprepBJR/images'
        expected = set('engine turbo supercharger intake exhaust cooling fuel piston camshaft gearbox differential drivetrain tyre brakes springs alignment body aero nitrous antiroll'.split())
        self.assertEqual({p.stem for p in images.glob('*.webp')}, expected)
        self.assertFalse(list(images.glob('*.svg')))
        for p in images.glob('*.webp'):
            raw = p.read_bytes()
            self.assertEqual(raw[:4], b'RIFF')
            self.assertEqual(raw[8:12], b'WEBP')
        self.assertLess(sum(p.stat().st_size for p in images.glob('*.webp')), 300_000)

    def test_section_guide_on_top(self):
        # 2.14 (owner-approved mockup): Upgrades and Setup show each section's
        # guide (image, title, description, tip) above the choices / sliders
        html = (ROOT/'client/ui/modModules/raceprepBJR/raceprep.html').read_text()
        setup = html.split("ng-if=\"$ctrl.tab==='setup'\"", 1)[1].split('</section>', 1)[0]
        shop = html.split("ng-if=\"$ctrl.tab==='upgrades'\"", 1)[1].split('</section>', 1)[0]
        # Setup: guide above the sliders
        self.assertEqual(setup.count('<div class="rp-guide"><img'), 1)
        self.assertIn('$ctrl.setupGuide().image', setup)
        self.assertLess(setup.index('rp-guide'), setup.index('rp-setup-grid'))
        # Upgrades (owner 2026-10-21): the dyno / performance big on top, the guide
        # in the right column
        self.assertEqual(shop.count('<div class="rp-guide rp-guide-side"><img'), 1)
        self.assertIn('$ctrl.shopGuide().image', shop)
        self.assertLess(shop.index('rp-shop-figures'), shop.index('rp-shop-options'))
        self.assertLess(shop.index('rp-shop-options'), shop.index('rp-guide-side'))
        self.assertLess(shop.index('rp-dyno-container'), shop.index('rp-shop-options'))
        self.assertIn('on-focus="$ctrl.focusSetup(v)"', setup)


if __name__ == '__main__':
    unittest.main()
