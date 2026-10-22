# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Read Automation's legacy Lua *table literal*, without running Lua code.

Only the first table after ``do local _=`` is read. The return wrapper and any
trailing text are never executed. Expressions, calls and references inside the
table are rejected. Arrays use the same one-based dictionary keys as .car's
binary format, keeping both representations identical for consumers.
"""
import math
import re


def read(raw):
    # Some exports embed arbitrary bytes in quoted AdditionalData strings.
    # Preserve those bytes without corrupting the surrounding UTF-8 metadata.
    text = raw.decode('utf8', 'surrogateescape')
    prefix = re.match(r'\s*do\s+local\s+_\s*=\s*', text)
    if not prefix:
        raise ValueError('unsupported .car format')
    pos = prefix.end()
    count = 0

    def skip():
        nonlocal pos
        while pos < len(text):
            if text[pos].isspace():
                pos += 1
            elif text.startswith('--', pos):
                # Automation emits line comments at most; long Lua comments
                # are deliberately outside this table-literal grammar.
                if text.startswith('--[', pos):
                    raise ValueError('unsupported Lua long comment')
                end = text.find('\n', pos)
                pos = len(text) if end < 0 else end + 1
            else:
                break

    def string():
        nonlocal pos
        quote = text[pos]
        pos += 1
        result = []
        escapes = {'a':'\a', 'b':'\b', 'f':'\f', 'n':'\n', 'r':'\r',
                   't':'\t', 'v':'\v', '\\':'\\', '"':'"', "'":"'"}
        while pos < len(text):
            char = text[pos]
            pos += 1
            if char == quote:
                return ''.join(result)
            if char != '\\':
                result.append(char)
                continue
            if pos >= len(text):
                break
            char = text[pos]
            pos += 1
            if char.isascii() and char.isdigit():
                digits = char
                while len(digits) < 3 and pos < len(text) and text[pos] in '0123456789':
                    digits += text[pos]
                    pos += 1
                number = int(digits)
                if number > 255:
                    raise ValueError('invalid Lua decimal escape')
                result.append(chr(number))
            elif char in escapes:
                result.append(escapes[char])
            elif char == '\n':
                result.append('\n')
            else:
                raise ValueError('unsupported Lua string escape')
        raise ValueError('unterminated Lua string')

    def value(depth=0):
        nonlocal pos, count
        count += 1
        if depth > 60 or count > 500000:
            raise ValueError('invalid .car depth/length')
        skip()
        if pos >= len(text):
            raise ValueError('truncated Lua table')
        char = text[pos]
        if char in ('"', "'"):
            return string()
        if char == '{':
            pos += 1
            result = {}
            index = 1
            while True:
                skip()
                if pos >= len(text):
                    raise ValueError('unterminated Lua table')
                if text[pos] == '}':
                    pos += 1
                    return result
                name = re.match(r'([A-Za-z_][A-Za-z_0-9]*)\s*=', text[pos:])
                if name:
                    key = name[1]
                    pos += name.end()
                elif text[pos] == '[':
                    pos += 1
                    key = value(depth + 1)
                    skip()
                    if not text.startswith(']', pos):
                        raise ValueError('invalid Lua table key')
                    pos += 1
                    skip()
                    if not text.startswith('=', pos):
                        raise ValueError('missing Lua key assignment')
                    pos += 1
                    if not isinstance(key, (str, int, float)) or isinstance(key, bool):
                        raise ValueError('unsupported Lua table key')
                else:
                    key = index
                    index += 1
                item = value(depth + 1)
                if key in result:
                    raise ValueError('duplicate Lua table key')
                result[key] = item
                skip()
                if pos < len(text) and text[pos] in ',;':
                    pos += 1
                elif pos >= len(text) or text[pos] != '}':
                    raise ValueError('missing Lua table separator')
        number = re.match(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?', text[pos:])
        if number:
            pos += number.end()
            result = float(number[0])
            if not math.isfinite(result):
                raise ValueError('nonfinite .car number')
            return result
        word = re.match(r'[A-Za-z_][A-Za-z_0-9]*', text[pos:])
        if word and word[0] in ('true', 'false', 'nil'):
            pos += word.end()
            return {'true':True, 'false':False, 'nil':None}[word[0]]
        raise ValueError('unsupported Lua expression in .car')

    result = value()
    if not isinstance(result, dict):
        raise ValueError('.car root is not a table')
    return result
