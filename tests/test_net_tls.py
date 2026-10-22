# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Trusted HTTPS on any Linux (2026-10-21): the Ubuntu-built executable found no
certificates on Arch, so every download failed. An empty default store falls
back to the first existing system bundle."""
from pathlib import Path
import ssl
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import net_tls  # noqa: E402


class Tls(unittest.TestCase):
    def test_empty_default_store_falls_back_to_a_system_bundle(self):
        if sys.platform == 'win32' or not any(Path(p).exists() for p in net_tls.BUNDLES):
            self.skipTest('no Linux CA bundle here')
        empty = lambda: ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)  # like the frozen OpenSSL with a foreign path
        with patch.object(net_tls.ssl, 'create_default_context', side_effect=empty):
            ctx = net_tls.context()
        self.assertGreater(ctx.cert_store_stats()['x509_ca'], 0)
        self.assertEqual(ctx.verify_mode, ssl.CERT_REQUIRED, 'certificates are still verified')

    def test_downloaders_use_it(self):
        for name in ('release_updates.py', 'optional_mods.py'):
            src = (Path(net_tls.__file__).parent / name).read_text()
            self.assertIn('context=context()', src, name)


if __name__ == '__main__':
    unittest.main(verbosity=1)
