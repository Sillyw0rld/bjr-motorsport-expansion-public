#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Print a JSON file as a Lua chunk ("return {...}") for offline Lua tests."""
import json
import sys


def lua(v):
    if isinstance(v, dict):
        # Isolate each table's constants from its parent: the full factory
        # identity census exceeds LuaJIT's 65,536 constants per function.
        return '(function() return {' + ','.join('[%s]=%s' % (json.dumps(str(k)), lua(x)) for k, x in v.items()) + '} end)()'
    if isinstance(v, list):
        return '(function() return {' + ','.join(lua(x) for x in v) + '} end)()'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if v is None:
        return 'nil'
    return json.dumps(v)


print('return ' + lua(json.load(open(sys.argv[1]))))
