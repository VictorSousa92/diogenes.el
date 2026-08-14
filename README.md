https://github.com/user-attachments/assets/4b0297ae-f6ca-4064-b90b-f8dc320cf83a

Diogenes.el strives to be a complete interface to P. Heslin's
Diogenes, allowing its users to browse and search the TLG and PHI
Greek and Latin databases from within Emacs. In addition to this, it
also can interactively display the lexicographical material that comes
with Diogenes (the LSJ Greek and Lewis & Short Latin dictionaries), as
well as use its rich morphological databases to analyse Greek and
Latin forms.

This package is intended to be useful both as user facing program and
as a LISP library. At the moment, however, there is no public API yet,
but that should change soon. All functions that are intended to be
used in other LISP programs will be described either in this document
or in the info manual that should be written at some point.

Unlike the previous version of this package, it now uses custom Perl
scripts to communicate with Diogenes' Perl API and tries to cover it
entirely.


# Prerequisites

This package has been developed on Linux and GNU Emacs 29. It works on
Mac OS,too, but I have not yet had the time to make it work on
Windows, too (but it works fine using WSL2). It should run on earlier
Emacsen, too, but I haven't tested it yet.


# Installation

Please make sure that you have a working installation of Diogenes.
After that, clone this repository (e.g. into \`~/.emacs./elisp\`) and
add it to your load-path:

    (add-to-list 'load-path (expand-file-name "~/.emacs.d/elisp/diogenes.el"))

Now require it and set the path to the diogenes-libary-path variable
to the root of your Diogenes installation:

    (require 'diogenes)
    (setq diogenes-library-path "/path/to/diogenes)

Or, with use-package (with some handy key-bindings)

    (use-package diogenes
      :init
      (diogenes-path "/path/to/diogenes")
        :bind (("C-c d" . diogenes))
        :commands (diogenes-ad-to-ol
                 diogenes-ol-to-ad
                 diogenes-utf8-to-beta
                 diogenes-beta-to-utf8))


# Transient interface

Nearly all of the functionality of this package (besides the utility
functions, see below) is exposed via its new transient user interface,
which can be invoced with the `diogenes` command. Note that this new
interface is still experimental, so expect some rough edges.


# Usage

As there is a plethora of corpora that Diogenes can search and browse,
diogenes.el defines for each of these copora in each of the following
categories a specialised command. In order to avoid redundancy, the
placeholder CORPUS will be used in command names that are defined for
each of the following corpora:

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">


<colgroup>
<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-left">Abbreviation</th>
<th scope="col" class="org-left">Full Name</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-left">tlg</td>
<td class="org-left">Thesaurus Lingae Graecae</td>
</tr>


<tr>
<td class="org-left">phi</td>
<td class="org-left">PHI Latin Texts</td>
</tr>


<tr>
<td class="org-left">ddp</td>
<td class="org-left">Duke Documentary Papyri</td>
</tr>


<tr>
<td class="org-left">ins</td>
<td class="org-left">Classical Inscriptions</td>
</tr>


<tr>
<td class="org-left">chr</td>
<td class="org-left">Christian Inscriptions</td>
</tr>


<tr>
<td class="org-left">misc</td>
<td class="org-left">Miscellaneous PHI Texts</td>
</tr>


<tr>
<td class="org-left">cop</td>
<td class="org-left">PHI Coptic Texts</td>
</tr>
</tbody>
</table>


## Searching the Corpora

The command `M-x diogenes-search-CORPUS` starts a search in a corpus.
You can narrow down the scope of the search to individual authors. At
the moment, the search result produced by Diogenes is inserted without
any processing; this should however change soon.

When used with a prefix argument (e.g. `C-u M-x
diogenes-search-CORPUS`), a more complex search query can be
constructed. Note, however, that this interface is perliminary and is
likely to change in the near future.


## Browsing the Corpora

There are two sets of commands that display the text of a specific
work. The first one, `diogenes-dump-CORPUS`, just dumps itvin its
entirety into a dedicated buffer without any post processing. This is
primarily intended if you plan to use this to construct larger corpora
of plain text files that should be used by other programs. Note,
however, that due to some limitations in the current implementation,
Diogenes prints some lines beyond the end of the requested work. At
the moments, these must be removed manually. Other post-processing
tasks include the deletion of the integrated citations with a
rectangle command, or the removal of the hyphenations that interfere
with searches. Some utilities for these tasks can be found in
diogenes-legacy.el, but should be replaced in the near future.

The second command, `diogenes-browse-CORPUS`, opens an interactive
browser at a specified location in the corpus. It post processes the
output so that every line gets its own citation, and puts the citation
even in its text properties so that it will be preserved even if it is
copied elsewhere (use `M-x describe-text-properties` to inspect it).
You can browse forward and backward with `C-c C-n`
(diogenes-browser-forward) and `C-c C-p` (diogenes-browser-backward),
or simply by reaching the beginning or end of the buffer and using the
arrow keys to go beyond the boundaries of the current buffer. 

Additionally, there are commands in the browser mode that facilitate
the post processing of the texts. `diogenes-browser-toggle-citations-
(bound to ~C-c C-t`) removes or reinserts all citations from the
buffer. `diogenes-browser-remove-hyphenation` (bound to `C-c C--`)
joins all hyphenated words at the line-ends, while
`diogenes-browser-reinsert-hyphenations` (`C-c C-+`) restores them to
their original form.


## Parsing and Dictionary Lookup

The command `diogenes-lookup-greek` and `diogenes-lookup-latin` search the
LSJ Greek Dictionary and the Lewis & Short Latin dictionary for the
entered headword. If nothing can be found, the nearest result is
displayed in Diogenes Lookup Mode. While only a subset of the TEI XML
tags is currently recognized and handled, this mode can display the
most prominent markup of the files and, most importantly, the embedded
citations that can be used to browse the texts in Browser Mode
(activate them by either typing RETURN when they have the cursor on it or by
double-clicking. The command `diogenes-perseus-action` (bound to
`C-c C-c`) can also activate these links, but additionally tries to
parse and lookup every word that is marked either as Latin or Greek in
the XML tags.

The commands `diogenes-parse-and-lookup-greek` and
`diogenes-parse-and-lookup-latin` also do a dictionary lookup, but
first try to analyse the form by using the morphological databases
that come with Diogenes. When they fail to get a literal match (Greek
diacritics included), they fall back to a simple dictionary lookup.
This is also the function used by `diogenes-perseus-action`.

Last, there are the commands `diogenes-parse-greek` and
`diogenes-parse-latin`. These commands are quite expensive (at any
rate when executed the first time in a Emacs session) because they
parse and load an entire analysis file into memory. This in turn
allows the user to query these databases in a more general way. In
this type of search, the queries do not have to be literal matches.
Instead, thr user can supply a specialised function to do the lookup.
The predefined functions are `string=` (literal matches),
`string-prefix-p` (matches at the beginning), `string-suffix-p`
(matches at the end), `string-search` (matches anywhere in the form),
and `string-match-p` (using regular expressions), but any function, or
even a custom lambda can be supplied. All these functions can match
not the forms disregarding both the letter case and the diacritics.

(A note on Greek input: You can enter greek words either in Unicode or
in Beta Code. Note, however, that internally, all Greek is converted
to Beta Code, so it may be in some cases more reliable to use Beta
Code. Please inform me if you spot something that only works with Beta
Code!)


## Utilities

At the moment, the package provides two utilites.
`diogenes-beta-to-utf8` and `diogenes-utf8-to-beta` can be used to convert
form and to beta code, both interactively in the minibuffer or in the
current region, and `diogenes-ol-to-ad` and `diogenes-ad-to-ol` convert between 
dates in BC/AD and Olympiads.

# Additional features (Victor)
 
*(Everything in this section was added by me, Victor, on top of
Nitardus's package above. The sections above are his and unchanged.)*
 
Small corrections to the Installation section above:
 
- The variable is `diogenes-path`, not `diogenes-library-path` (the latter does not exist).
- In the `use-package` example, use `(setq diogenes-path "/path/to/diogenes")` in `:init`, not `(diogenes-path "...")`.
## Getting started with dictionary lookup
 
The sections above list the commands but not the everyday workflow.
Here is the short version.
 
Easiest entry point: `M-x diogenes` opens the **transient menu**, which
exposes nearly all of the package (searching, browsing, parsing, and the
lookups below) with mnemonic keys, so you need not remember command
names. The individual commands below can also be called or bound
directly.
 
Bind it to a key so you need not type `M-x diogenes` each time. If you
install with `use-package` (as in the Installation section above), add a
`:bind`:
 
```elisp
(use-package diogenes
  :bind ("C-c d" . diogenes))
```
 
Or bind it directly in your `.emacs` / `init.el` / `.spacemacs`:
`(global-set-key (kbd "C-c d") #'diogenes)`.
 
Look a word up:
 
| Command | Does |
| --- | --- |
| `diogenes-lookup-greek` | Plain LSJ lookup of a Greek headword |
| `diogenes-lookup-latin` | Plain Lewis & Short lookup of a Latin headword |
| `diogenes-parse-and-lookup-greek` | Analyse the inflected form first, then look up its lemma |
| `diogenes-parse-and-lookup-latin` | Same, for Latin |
 
- If there is no exact match, the nearest entry is shown (a message says so).
- Use the parse-and-lookup commands for text you are reading (they handle inflected forms); use the plain ones when you already know the lemma.
- Greek input works in Unicode or Beta Code. Internally all Greek becomes Beta Code, so Beta Code is occasionally more reliable.
The result opens in **Diogenes Lookup Mode**. What you get there:
 
- The entry, formatted from its TEI XML.
- A links line at the top for the print dictionaries (see below).
- Clickable citations: press RETURN or double-click to open the cited text in Browser Mode.
Looking words up while reading a text (Browser Mode):
 
- `C-c C-c` on a word parses it and opens its dictionary entry, in a separate window, so the text you are reading stays visible.
- The language follows the text you are browsing (Greek or Latin).
- This is the quickest way to read a text and check words as you go.
Diogenes Lookup Mode keys:
 
| Key | Action |
| --- | --- |
| `RET`, double-click | Activate the citation, link, or word at point (see `C-c C-c`) |
| `C-c C-c` | Same as RET: activate link, or parse and look up the word at point |
| `C-c C-n` | Next entry in the dictionary |
| `C-c C-p` | Previous entry |
| `n` / `p` arrows | Move by line (also load the next/previous entry at the buffer edges) |
| `o` `t` `m` `c` `b` `p` | Open a print dictionary at the current entry (see table below) |
| `q` | Quit the window |
 
- Paging with `C-c C-n` / `C-c C-p` stays in the same buffer and reformats in place.
- The print-dictionary keys and links always act on the entry the cursor is currently in.
## `C-c C-c` on words inside dictionary entries
 
This is the main way to move around while reading. Put the cursor on
anything in an entry and press `C-c C-c` (or RET, or double-click).
It does the right thing depending on what is under the cursor:
 
| Under the cursor | `C-c C-c` does |
| --- | --- |
| A citation (author/work reference) | Opens that text in Browser Mode |
| A print-dictionary link (`[OLD]`, `[TGL]`, ...) | Opens that dictionary at the entry's page |
| A Greek or Latin word | Parses it and shows its dictionary entry |
| An English gloss word in an LSJ entry | Nothing (avoids a spurious parse) |
 
How it decides a word's language, in order:
 
1. A word explicitly tagged Latin or Greek in the XML is parsed as such.
2. Otherwise a word in Greek script is parsed as Greek, even in unmarked prose.
3. Otherwise the entry's own language is used.
Point 3 is what makes a Latin word inside a Lewis & Short entry work:
the body Latin there is not tagged in the XML, so it falls back to the
buffer's language (Latin) instead of failing.
 
Caveat: the same fallback means an **English word** in a Lewis & Short
entry is also parsed as Latin, since it too is untagged. `C-c C-c` on
such a word gives a spurious or nearest-match Latin entry. (An LSJ entry
does not have this problem: there, untagged Latin-script words are
treated as English glosses and left alone.)
 
Examples:
 
- In an LSJ entry, cursor on a Greek quotation, `C-c C-c`: opens that Greek word's entry.
- In a Lewis & Short entry, cursor on any Latin word in the definition, `C-c C-c`: opens that Latin word's entry.
- In a Lewis & Short entry, cursor on a Greek word, `C-c C-c`: opens that word's LSJ (Greek) entry.
- In an LSJ entry, cursor on an English word of the gloss: nothing happens.
- Cursor on a `[Montanari]` link: opens Montanari, not a word lookup.
**Same window option.** When you `C-c C-c` a word while already in a
lookup buffer, it asks:
 
- `Open the result in this same window?`
- **yes**: the new entry replaces the view in the current window (you stay put).
- **no**: it opens in another window, as before.
- Either way a fresh buffer is used, so the entry you came from stays alive and reachable.
## Print dictionaries (PDF)
 
diogenes.el can jump a scanned print dictionary (shown as a PDF) to the
page for a given entry. Each dictionary has its own path variable, which
must be set before use.
 
| Abbr. | Dictionary | Lang | Path variable | Layout |
| --- | --- | --- | --- | --- |
| OLD | Oxford Latin Dictionary | La | `diogenes-old-pdf-file` | single PDF |
| TLL | Thesaurus Linguae Latinae | La | `diogenes-tll-pdf-directory` | folder of fascicles |
| Montanari | Brill Dict. of Ancient Greek | Gr | `diogenes-montanari-pdf-file` | single PDF |
| CGL | Cambridge Greek Lexicon | Gr | `diogenes-cambridge-pdf-file` | single PDF |
| BDAG | Bauer/Danker Greek NT | Gr | `diogenes-bdag-pdf-file` | single PDF |
| Passow | Passow's Handwörterbuch | Gr | `diogenes-passow-directory` | one folder per volume (PDF + OCR `.txt`) |
| TGL | Estienne, Thesaurus Graecae Linguae | Gr | `diogenes-tgl-directory` | one folder per volume (PDF + OCR `.txt`) |
 
Notes on the data:
 
- OLD, TLL, Montanari, CGL, BDAG: page index comes from each PDF's own bookmarks and embedded OCR layer. No extra files needed.
- Passow and TGL: each volume folder needs **two files**, the volume PDF and a plain-text OCR `.txt` of the same volume. Lookups run against the `.txt`, so it is required.
  - First `*.pdf` and first `*.txt` in the folder are used (override with `diogenes-passow-pdf-regexp` / `-text-regexp`, and the `diogenes-tgl-*` equivalents).
  - The OCR `.txt` must delimit pages with lines `----- N / TOTAL -----`.
  - TGL volume folders **must be named by Roman numeral** (`I`, `II`, `III`, `IIII`, `V`); the name is the tomus number. Volume V's `.txt` holds the comprehensive index, the TGL's main lookup path.
  - Passow folder names do not matter; letter ranges are detected from the OCR.
- pdf-tools is used when available; otherwise doc-view.
- If your copy is paginated differently, set the per-dictionary `*-page-offset` to shift every jump by a constant.
diogenes.el ships none of these PDFs; supply your own and point the path
variables at them. The TGL and Passow copies I tested are the OCR'd MDZ
volumes (DAFO dataset) from the [Bavarian State Library's
MDZ](https://www.digitale-sammlungen.de/en/).
 
### Three ways to open a dictionary
 
**1. Clickable links.** Every entry in Diogenes Lookup Mode is preceded
by a links line:
 
- Latin entries: `[OLD]` `[TLL]`
- Greek entries: `[Montanari]` `[CGL]` `[BDAG]` `[Passow]` `[TGL]`
- Click or press RETURN to open that dictionary at the entry's page.
- Works per entry: paging with `C-c C-n` / `C-c C-p` gives each entry its own links line and headword.
**2. Single keys** (act on the entry the cursor is in, recomputed each keypress; prefix arg prompts for a word):
 
| Key | Opens |
| --- | --- |
| `o` | OLD |
| `t` | TLL (Latin entry) or TGL (Greek entry) |
| `m` | Montanari |
| `c` | CGL |
| `b` | BDAG |
| `p` | Passow |
 
**3. Search inside the open PDF** (see below). Best remedy for OCR/bookmark misses.
 
 
### A caveat on OCR and bookmarks
 
These are scans of old print books, so their OCR and bookmarks are
imperfect: dropped or garbled letters, misread diacritics, columns out
of order, wrong bookmarks. A jump can land a page or two off.
 
- Most reliable: OLD, BDAG, Montanari, CGL (modern typeset).
- Less so: Passow.
- Least reliable: TGL (16th-century, dense multi-column, heavy ligatures).
- Treat a jump as landing in the right neighbourhood; nudge by hand when OCR was poor.
Mechanisms that keep TGL lookups on target:
 
- **Column backbone.** Page is derived from the column number printed in the OCR, not from bookmarks (so `diogenes-tgl-page-offset` normally stays 0). The model uses the fact that a folio prints two columns per page, so `left-column = 2 x page + b`:
  - The origin (where column 1 sits) is found by extrapolation from the cleanest early column pairs, so it works even when "1 2" is illegible and even when a volume opens mid-alphabet at columns 5-6 (tomus III).
  - Inserted plates shift later pages; each such "seam" is detected only when several consecutive columns agree, so one garbled figure cannot derail the line, and a page whose own column is missing is still placed by its neighbours.
  - Result: about 99% of pages map correctly; the rest are garbled figures or the one-page ambiguity right at a plate.
- **Fuzzy index lookup** (`diogenes-tgl-fuzzy-lookup`): on an exact miss, retries index keys sharing the first two letters and differing by at most one letter.
- **"vide" pointers** are followed to their target.
- **"ibidem" entries** (volume V lists many words as "ibidem", meaning the same column as the entry before): the parser carries the last real column forward across such runs, ignores the trailing line-letter, and shares one column across an `X & Y` variant pair.
- **Morphological fallback** (`diogenes-tgl-morph-fallback`): last resort for a compound printed under its root with no column; strips one Greek prefix and resolves the root, only on an exact root hit and only when root and residue are long enough (`diogenes-tgl-morph-min-root`, default 4).
- **Anomalous-roots fallback**: a word found nowhere else but listed exactly in volume V's "Verborum quorundam themata" (irregular/poetic verb forms) is sent to its page there.
When a TGL jump is still wrong:
 
- First check the **vicinity**: the target is usually a page or two away, so scroll a little before doing anything else.
- If it is not nearby, use one of the alternatives below.
| Command / key | Does |
| --- | --- |
| `C-u L`, approximate | Search for the word's **root** to land in the right article, then read within it (compounds and derivatives are often printed under the root, not as separate entries) |
| `i` (`diogenes-tgl-open-index-here`) | Opens volume V's index near the word, to find it by eye |
 
- Once the index shows you a reference like `t.3 c.746`, follow it with `C-u L`: choose the index-reference / other-tome option, give that tomus and column, and it jumps straight there.
### Prebuilt indexes (Passow and TGL)
 
Passow and the TGL build their lookup index by parsing every volume's
OCR, which takes a few seconds the first time in a session.
 
- That work is cached in memory for the session and on disk (keyed by the OCR files' modification times), so it is paid at most once per machine and redone only if you re-OCR a volume.
- You can also build a **portable** index once and keep it as a small file:
| Command | Writes | Effect |
| --- | --- | --- |
| `M-x diogenes-passow-build-index` | `passow-index.eld` in the Passow folder | Every later lookup loads instantly, even the first of a session |
| `M-x diogenes-tgl-build-index` | `tgl-index.eld` in the TGL folder | Same; portable across machines |
 
- Commit the `.eld` file alongside the volumes and other users skip the parse entirely.
- Rebuild after adding or re-OCRing a volume (the file records a signature and warns when stale).
- `diogenes-passow-clear-cache` / `diogenes-tgl-clear-cache` discard the caches to force a rebuild.
- `diogenes-passow-cache-directory` (and the TGL equivalent) sets where the session cache lives.
## Searching inside an open PDF
 
`diogenes-pdf-lookup-entry` (bound to `L` in pdf-view-mode and
doc-view-mode) looks up an entry from inside the PDF you already have
open and jumps to its page. Best fix for a link or `o t m c b p` key that
landed you wrong.
 
- Works for every print dictionary above; it detects which one from the visited file (prompt names it).
- Default is the word at point or the current PDF text selection.
- For multi-file TLL/Passow/TGL, a word in another fascicle or volume opens that sibling PDF.
| Key | Action |
| --- | --- |
| `L` | Exact lookup of a headword |
| `C-u L` | Approximate jump: type the beginning of a word (even one letter) and land at that alphabetical position |
 
Syntax note: type this as the sequence `C-u` then `L` (then answer the
prompts). It is not the usual numeric prefix, so do not type `C-u 4 L`
or the like; just `C-u L`.
 
Approximate (`C-u L`) details:
 
- Single-PDF dictionaries: reuses their own positional index.
- TGL: navigates by the clean running headers at the top of each column (short, all-caps, far more OCR-legible than the body), so it reaches the right article even when the body is garbled. This is the most dependable way to reach a badly OCR'd word.
- TGL also offers a jump **by index reference** (the `t.N c.NNN` citations): choose the index-reference option, give the tomus and column, and it converts the column to a page. This is how you follow a reference you found in the index (e.g. `t.3 c.746`) to its place in another tome.
  - From tomes I-IV, `C-u L` asks approximate-or-index-reference first.
  - From volume V, the reference option appears in its menu as "other tome" (see below).
### Volume V (special menu)
 
Volume V has extra structure, so `C-u L` inside it (or answering `5` to
the tomus prompt) offers a small menu.
 
| Choose | Then | Result |
| --- | --- | --- |
| Index | part 1 or 2, then a column | Jumps to that column. The index is printed in two parts whose numbering each restart at 1, so the part must be chosen. Restart page auto-detected (or pin with `diogenes-tgl-v5-part2-page`). |
| Anomalous roots -> column | a column | Jumps into the "Verborum quorundam themata" section by column |
| Anomalous roots -> approximate | a fragment | One letter jumps to that letter's block; a longer fragment is placed finely by scanning the headwords printed on those pages (the section's headers give only the initial letter) |
| Other tome | a tomus and column | Follows an index reference `t.N c.NNN` into another tome (tomus 5 loops back into this index, asking the part). Use this to chase a reference you read in the index. |
 
Note on the key: lowercase `l` is taken in pdf-view-mode, so the default
is capital `L`. Change it with `diogenes-pdf-search-key` before load.
