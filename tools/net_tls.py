# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Trusted HTTPS for the standalone generator on any Linux.

The Linux executable is built on Ubuntu, and its bundled OpenSSL looks for the
system's trusted certificates where Ubuntu keeps them. Other distributions keep
them elsewhere, which made every download fail certificate checks (Arch,
2026-10-21). When the default store is empty, the first existing bundle from
the common locations is used. Windows uses its own certificate store.
"""
import ssl

BUNDLES = (
    '/etc/ssl/certs/ca-certificates.crt',  # Debian, Ubuntu, Arch, Gentoo
    '/etc/pki/tls/certs/ca-bundle.crt',    # Fedora, RHEL, CentOS
    '/etc/ssl/ca-bundle.pem',              # openSUSE
    '/etc/pki/tls/cacert.pem',             # OpenELEC
    '/etc/ssl/cert.pem',                   # Alpine, Arch, macOS
)


def context():
    ctx = ssl.create_default_context()
    if ctx.cert_store_stats().get('x509_ca', 0):
        return ctx
    for path in BUNDLES:
        try:
            ctx.load_verify_locations(cafile=path)
        except (OSError, ssl.SSLError):
            continue
        if ctx.cert_store_stats().get('x509_ca', 0):
            return ctx
    return ctx
