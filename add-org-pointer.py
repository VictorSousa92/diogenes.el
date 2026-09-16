#!/usr/bin/env python3
"""add-org-pointer.py -- say where the org integration lives.

This branch has none: the links, the notes, and the citation layer they rest
on are on `org-integration', which is this branch and that.  A reader who
wants them should not have to find that out by reading the source.

Two places: a line in `What this half adds', and a short section of its own
after the install instructions, where a reader deciding what to clone will be
looking.

IDEMPOTENT.  Each is looked for first and passed over where it is already in.
"""

import argparse
import os
import sys


# The line in the summary list.
SUMMARY = ("- Notes in org-roam anchored to citations rather than to page"
           " numbers — on the `org-integration` branch, see below.\n")

# The section itself.
SECTION = """
## The org-integration branch

Notes on passages — org links to a place in a text, notes found by citation,
and a command each way between the note and the browser — are on the
`org-integration` branch rather than here.

```fish
git clone -b org-integration https://github.com/VictorSousa92/diogenes.el
```

That branch is this one with the org work added: everything documented below
is on it and behaves the same way. What it adds beside the notes is a citation
layer the links rest on — `diogenes-browser-reference`, `diogenes-open-passage`
and the rest — and `diogenes-abbreviations.el`, so a passage can be named
*Arist. Metaph. 1048a27* rather than *tlg 0086/025 1048a27*.

It is a branch and not an option because the citation layer is a good deal of
code to carry for a reader who does not want it. Nothing on it needs org-roam
to be installed: the links work without it, and only the two commands that
look for notes ask for it.
"""


def main():
    parser = argparse.ArgumentParser(
        description="Point at the org-integration branch.")
    parser.add_argument("readme", nargs="?", default="README.md")
    parser.add_argument("--in-place", action="store_true")
    parser.add_argument("--remote",
                        help="a clone URL other than the one already in the "
                             "README's install instructions")
    args = parser.parse_args()

    if not os.path.exists(args.readme):
        sys.exit("%s is not here. Run this in the repository." % args.readme)

    with open(args.readme, encoding="utf-8") as handle:
        text = handle.read()

    section = SECTION
    if args.remote:
        section = section.replace(
            "https://github.com/VictorSousa92/diogenes.el", args.remote)

    done = []

    # 1. the summary line
    if "org-integration` branch, see below" in text:
        print("  the summary line     already in")
    else:
        anchor = "- Optional window management.\n"
        if anchor in text:
            text = text.replace(anchor, anchor + SUMMARY, 1)
            print("  the summary line     added")
            done.append(True)
        else:
            print("  the summary line     NOT ADDED -- the list is not as "
                  "expected")

    # 2. the section, after the install instructions
    if "## The org-integration branch" in text:
        print("  the section          already in")
    else:
        # AFTER `Install' AND BEFORE `Configuration', where a reader choosing
        # what to clone is looking -- not at the end, where it would be found
        # by whoever had already cloned the wrong one.
        anchor = "## Configuration"
        if anchor in text:
            text = text.replace(anchor, section.strip("\n") + "\n\n" + anchor,
                                1)
            print("  the section          added")
            done.append(True)
        else:
            print("  the section          NOT ADDED -- no Configuration "
                  "heading")

    # 3. the contents list
    entry = ("  - [The org-integration branch]"
             "(#the-org-integration-branch)\n")
    if "#the-org-integration-branch" in text:
        print("  the contents entry   already in")
    else:
        anchor = "  - [Configuration](#configuration)\n"
        if anchor in text:
            text = text.replace(anchor, entry + anchor, 1)
            print("  the contents entry   added")
            done.append(True)
        else:
            print("  the contents entry   NOT ADDED -- no Configuration entry")

    if not done:
        print("\nNothing to do.")
        return

    out = args.readme if args.in_place else args.readme + ".new"
    with open(out, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("\nWritten to %s" % out)
    if not args.in_place:
        print("  diff %s %s" % (args.readme, out))
        print("  mv %s %s" % (out, args.readme))


if __name__ == "__main__":
    main()
