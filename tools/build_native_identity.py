#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Parts lists for the seed's native factory configs (server-only, for Rivals).

The seed rates BeamNG's factory configs by key (model/config/parts hash) but
stores no parts list, so the server has nothing to compare BeamMP's copy of a
car with. The static probes recorded each config's activeParts. A list is kept
only when it reproduces a parts-less seed key exactly (RatingIdentity's FNV-1a),
so the file can't name a list the seed did not rate.

Per model, `paths` and `parts` list each path and part name once; entries are
[path number, part number] (1-based). `base` holds each path's most common part
and each config stores only its differences (`set`, and `drop` for base paths
it lacks). Reads only
the probes and the seed; writes one file.
usage: build_native_identity.py --probes DIR [DIR...] [--out FILE] [-v]"""
import argparse, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / 'server/RacePrep/ratings-seed.json'
OUT = ROOT / 'server/RacePrep/native-identity.json'


def canonical(parts):
    # RatingIdentity.canonical: byte-sorted paths, "#path:path#part:part" lines
    keys = sorted((p for p, v in parts.items() if isinstance(p, str) and isinstance(v, str) and v != ''),
                  key=lambda p: p.encode())
    return '\n'.join(f'{len(p.encode())}:{p}{len(parts[p].encode())}:{parts[p]}' for p in keys).encode()


def fnv(parts):
    h = 2166136261
    for b in canonical(parts):
        h = ((h ^ b) * 16777619) & 0xffffffff
    return f'{h:08x}'


def clean(parts):
    return {p: v for p, v in parts.items() if isinstance(p, str) and isinstance(v, str) and v != ''}


def build(probes, seed, verbose=False):
    entries = json.loads(seed.read_text())['entries']
    wanted = {k for k, v in entries.items() if isinstance(v, dict) and v.get('native') and not v.get('parts')}
    found = {}
    for d in probes:
        for f in sorted(Path(d).glob('*.json')):
            try:
                p = json.loads(f.read_text())
            except (OSError, ValueError):
                continue
            model, config, parts = p.get('model'), p.get('config'), p.get('activeParts')
            if not isinstance(model, str) or not isinstance(config, str) or not isinstance(parts, dict):
                continue
            parts = clean(parts)
            key = f'{model}/{config}/{fnv(parts)}'
            if key in wanted and key not in found:
                found[key] = (model, config, parts)
    models = {}
    for key, (model, config, parts) in sorted(found.items()):
        models.setdefault(model, {})[config] = (key.rsplit('/', 1)[1], parts)
    out = {'schemaVersion': 1, 'models': {}}
    for model, configs in models.items():
        lists = [parts for _, parts in configs.values()]
        # base: each path's most common part, when most configs have it
        count = {}
        for l in lists:
            for p, v in l.items():
                count.setdefault(p, {}).setdefault(v, 0)
                count[p][v] += 1
        base = {}
        for p, values in count.items():
            v, n = max(sorted(values.items()), key=lambda x: x[1])
            if n * 2 > len(lists): base[p] = v
        paths, names = {}, {}
        def path(x): return paths.setdefault(x, len(paths) + 1)
        def pair(x, v): return [path(x), names.setdefault(v, len(names) + 1)]
        entry = {'base': [pair(x, v) for x, v in sorted(base.items())], 'configs': {}}
        for config, (h, parts) in sorted(configs.items()):
            c = {'hash': h}
            add = [pair(x, v) for x, v in sorted(parts.items()) if base.get(x) != v]
            drop = [path(x) for x in sorted(base) if x not in parts]
            if add: c['set'] = add
            if drop: c['drop'] = drop
            entry['configs'][config] = c
        entry['paths'], entry['parts'] = list(paths), list(names)
        out['models'][model] = entry
    missing = sorted(wanted - set(found))
    if verbose:
        print(f'{len(found)} of {len(wanted)} parts-less seed configs matched a probe parts list; {len(models)} models')
        for k in missing[:20]: print('  no probe list:', k)
    return out, missing


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--probes', type=Path, nargs='+', required=True)
    ap.add_argument('--out', type=Path, default=OUT)
    ap.add_argument('-v', action='store_true')
    a = ap.parse_args()
    out, missing = build(a.probes, SEED, a.v)
    a.out.write_text(json.dumps(out, separators=(',', ':'), sort_keys=True) + '\n')
    print(f'wrote {a.out} ({a.out.stat().st_size // 1024} KB, {sum(len(m["configs"]) for m in out["models"].values())} configs; {len(missing)} without a probe list)')


if __name__ == '__main__':
    main()
