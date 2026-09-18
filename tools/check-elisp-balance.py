#!/usr/bin/env python3
"""Scan an elisp file for string/paren balance, the way the reader would.

Not a full reader: enough to catch a docstring closed early by an unescaped
quote, which is the failure being looked for.
"""
import sys


def scan(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    i, n = 0, len(text)
    depth, line = 0, 1
    in_string = False
    string_started = 0
    tops = []          # (line, depth-at-close) for top-level forms
    trouble = []
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        # not in a string
        if c == ";":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "?":
            # a character literal: ?a, ?\(, ?\\, ?\x41
            i += 1
            if i < n and text[i] == "\\":
                i += 2
                while i < n and text[i] not in " \t\n()[];\"":
                    i += 1
            else:
                i += 1
            continue
        if c == "\\":
            # a symbol escape outside a string: \( is a symbol, not a paren
            i += 2
            continue
        if c == '"':
            in_string = True
            string_started = line
            i += 1
            continue
        if c in "([":
            if depth == 0:
                tops.append(line)
            depth += 1
            i += 1
            continue
        if c in ")]":
            depth -= 1
            if depth < 0:
                trouble.append("line %d: a closing paren too many" % line)
                depth = 0
            i += 1
            continue
        i += 1
    if in_string:
        trouble.append("a string opened on line %d is never closed"
                       % string_started)
    if depth != 0:
        trouble.append("%d form(s) left open at end of file" % depth)
    return trouble, tops


for path in sys.argv[1:]:
    trouble, tops = scan(path)
    print("%s: %d top-level forms" % (path, len(tops)))
    for t in trouble:
        print("   TROUBLE  %s" % t)
    if not trouble:
        print("   balanced")
