# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Read generated JSON and BeamNG's optional-comma JBeam syntax, no eval."""
import json
import re
from engine_swaps.catalogue import uncomment

TOKEN = re.compile(r'\s*("(?:\\.|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,])', re.S)


def loads(source):
    source = uncomment(source)
    tokens, offset = [], 0
    while offset < len(source):
        match = TOKEN.match(source, offset)
        if not match:
            if not source[offset:].strip():
                break
            raise ValueError(f'Unsupported JBeam syntax at character {offset}')
        tokens.append(match[1])
        offset = match.end()
    output = []
    previous = None
    for i, token in enumerate(tokens):
        if token == ',' and (i + 1 == len(tokens) or tokens[i + 1] in ('}', ']')):
            continue
        value_start = token not in (':', ',', '}', ']')
        previous_end = previous is not None and previous not in ('{', '[', ':', ',')
        if value_start and previous_end:
            output.append(',')
        output.append(token)
        previous = token
    return json.loads(''.join(output))
