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

*Everything from here on was added by me, Victor, on top of Nitardus's
package above. The sections before this point are his, and unchanged.*

What this half adds:

- Eleven more dictionaries beside the LSJ and Lewis & Short, reached from any entry by a single key.
- A links line at the top of each entry, naming the dictionaries you have.
- Contraction-aware Latin parsing, and a Morpheus fallback for forms the shipped data never saw.
- Corrections for analyses the shipped data gets wrong.
- Optional window management.

## Install

Diogenes itself — its Perl and its data — is installed separately;
`diogenes-path` points at it. The dictionaries are your own files, named by
the path variables below.

**Emacs 30+**, with `use-package`'s built-in `:vc`:

```elisp
(use-package diogenes
  :vc (:url "https://github.com/VictorSousa92/diogenes.el"
       :branch "modular")
  :init
  ;; ... configuration, see below ...
  :bind ("C-c d" . diogenes))
```

**Emacs 29**, where `:vc` does not exist yet — fetch once, then configure
with an ordinary `use-package` block:

```elisp
(unless (package-installed-p 'diogenes)
  (package-vc-install
   '(diogenes :url "https://github.com/VictorSousa92/diogenes.el"
              :branch "modular")))
```

The `unless` guard matters: `package-vc-install` signals an error if the
package is already there, so without it every start-up fails. Update with
`M-x package-vc-upgrade RET diogenes RET`.

**Spacemacs**, which fetches through quelpa — add the recipe to
`dotspacemacs-additional-packages` and put the `use-package` block in
`dotspacemacs/user-config`:

```elisp
(diogenes :location (recipe
                     :fetcher github
                     :repo "VictorSousa92/diogenes.el"
                     :branch "modular"))
```

## Configuration

One block, everything in `:init`. Delete the dictionaries you do not have —
an unset one is invisible rather than broken.

```elisp
(use-package diogenes
  :defer t
  :init
  (setq diogenes-path "/path/to/diogenes")           ; Diogenes itself

  ;; Latin, printed
  (setq diogenes-old-pdf-file        "/path/to/OLD.pdf")
  (setq diogenes-tll-pdf-directory   "/path/to/TLL/fascicles/")

  ;; Latin, XML with a printed edition beside it
  (setq diogenes-gaffiot-source-file "/path/to/gaffiot.tei.xml")  ; to build from
  (setq diogenes-gaffiot-file        "/path/to/build/gaffiot.xml") ; where it goes
  (setq diogenes-gaffiot-pdf-file    "/path/to/Gaffiot.pdf")       ; A-F in XML, rest here
  (setq diogenes-georges-source-file "/path/to/georges.tei.xml")
  (setq diogenes-georges-file        "/path/to/build/georges.xml")
  (setq diogenes-georges-directory   "/path/to/Georges/volumes/")

  ;; Greek, printed
  (setq diogenes-montanari-pdf-file  "/path/to/Montanari.pdf")
  (setq diogenes-cambridge-pdf-file  "/path/to/CGL.pdf")
  (setq diogenes-bdag-pdf-file       "/path/to/BDAG.pdf")
  (setq diogenes-passow-directory    "/path/to/Passow/")           ; parent folder
  (setq diogenes-tgl-directory       "/path/to/TGL/")              ; parent folder

  ;; Greek, XML
  (setq diogenes-pape-source-file    "/path/to/pape.tei.xml")
  (setq diogenes-pape-file           "/path/to/build/pape.xml")
  (setq diogenes-dge-source-file     "/path/to/dge/xml/")
  (setq diogenes-dge-file            "/path/to/build/dge.xml")
  (setq diogenes-bailly-source-file  "/path/to/bailly.tei.xml")
  (setq diogenes-bailly-file         "/path/to/build/bailly.xml")
  (setq diogenes-bailly-pdf-file     "/path/to/Bailly.pdf")

  ;; Morphology
  (setq diogenes-morpheus-directory  "/path/to/morpheus")          ; optional, see below

  ;; Dictionaries you use whatever their paths say (see below)
  (setq diogenes-declared-dictionaries '(old tll bailly tgl))

  ;; Analyses the shipped data gets wrong (see below)
  (setq diogenes-latin-analysis-corrections
        '(("experire" :info "pres imperat pass 2nd sg")))

  ;; PDF viewer: 'auto, 'pdf-tools or 'emacs-reader
  (setq diogenes-old-pdf-viewer 'auto)
  :bind ("C-c d" . diogenes))
```

- Everything goes in `:init`, which runs before the package loads. That matters for one case only — declaring a dictionary by `(require 'diogenes-tll)` — but keeping every setting in one place costs nothing.
- `diogenes-path` is the variable; there is no `diogenes-library-path`.
- Passow and the TGL take the **parent** folder of the per-volume material; see [The dictionaries themselves](#the-dictionaries-themselves) for the layout and the OCR text files they need.
- The XML dictionaries are built once from their TEI source: `-source-file` is what you downloaded, `-file` is where the built dictionary goes. Pressing the key offers to build it.

## Looking a word up

`M-x diogenes` opens the transient menu, which reaches nearly everything
(searching, browsing, parsing, the lookups below) with mnemonic keys.
`C-c d` in the configuration above binds it.

| Command | Does |
| --- | --- |
| `diogenes-parse-and-lookup-latin` | Analyse an inflected Latin form, then look its lemma up |
| `diogenes-parse-and-lookup-greek` | The same, for Greek |
| `diogenes-lookup-latin` | Lewis & Short, by headword |
| `diogenes-lookup-greek` | The LSJ, by headword |
| `diogenes-lookup-gaffiot` | Gaffiot's entry, in a lookup buffer |
| `diogenes-lookup-pape` | Pape's entry |
| `diogenes-lookup-dge` | The DGE's entry |
| `diogenes-lookup-bailly` | Bailly's entry |
| `diogenes-lookup-georges` | Georges' entry |
| `diogenes-lookup-lewis` / `-lsj` | Back to the default dictionary of that language |

- Use the parse-and-lookup pair for text you are reading; the plain ones when you already know the lemma.
- Greek input works in Unicode or Beta Code. Internally everything becomes Beta Code, so Beta Code is occasionally more reliable.
- With no exact match, the nearest entry is shown and a message says so.

### In a lookup buffer

- The entry is formatted from its TEI XML.
- Citations are clickable: RETURN or double-click opens the passage in Browser Mode.
- `C-c C-n` / `C-c C-p` page between entries; each entry carries its own links line.
- Every dictionary is reachable from every entry, by clicking its link or pressing its key.
- A key acts on the entry the cursor is in, recomputed at each keypress. A prefix argument prompts for a word instead.

| Key | Latin entries | Key | Greek entries |
| --- | --- | --- | --- |
| `o` | OLD | `m` | Montanari |
| `t` | TLL | `c` | CGL |
| `g` | Gaffiot — the entry, or the printed page past F | `b` | BDAG |
| `G` | Georges | `P` | Pape |
| `l` | Lewis & Short, the way back | `d` | DGE (α–ἐπ) |
| | | `B` | Bailly |
| | | `p` | Passow |
| | | `t` | TGL |
| | | `l` | LSJ, the way back |

- Inside a dictionary's own entry, its link becomes the way back: `[Lewis & Short (l)]`, `[LSJ (l)]`.
- Where that dictionary also has a scan, `[PDF]` joins it — so `g` inside a Gaffiot entry, or `B` inside a Bailly one, opens that word in the printed edition.

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
- In a Gaffiot xml entry, cursor on any Latin word in the definition, `C-c C-c`: opens that Latin word's entry in Lewis & Short.
- In a Gaffiot entry, cursor on a Greek word, `C-c C-c`: opens that word's LSJ (Greek) entry.
- In an LSJ entry, cursor on an English word of the gloss: nothing happens.
- Cursor on a `[Montanari]` link: opens Montanari, not a word lookup.
**Same window option.** When you `C-c C-c` a word while already in a
lookup buffer, it asks:
 
- `Open the result in this same window?`
- **yes**: the new entry replaces the view in the current window (you stay put).
- **no**: it opens in another window, as before.
- Either way a fresh buffer is used, so the entry you came from stays alive and reachable.

## Which dictionaries appear

Nothing you have not got is ever mentioned. Set no dictionary paths and the
package is Nitardus's original: the LSJ, Lewis & Short, the morphology and
the corpora, with no links line and no keys that lead nowhere.

| You have | You get |
| --- | --- |
| Nothing set, nothing declared | No links line, no dictionary keys bound |
| Some paths set | A links line naming exactly those |
| A dictionary declared, paths unset | Its link and key appear, and say what to set |
| A path set but broken (typo, moved file) | Its link appears; pressing it says what it could not read |
| Only a dictionary's XML | Its link opens the entry; no `[PDF]` link inside it |
| Only a dictionary's PDF | Its link opens the printed page, like the OLD |
| Both | The entry, with `[PDF]` inside it |
| No `diogenes-morpheus-directory` | The parse works as before, with no Morpheus fallback |

- A path is a statement of intent: a dictionary whose path is set counts as wanted even when the path is wrong — a moved volume, an unmounted drive.
- Only an unset path with no declaration leaves a dictionary out.

### Declaring one

Declaring says "I use this" whatever the paths are doing: the link, the key
and the chooser entry are all there, and pressing one explains what to set.
Two ways, either sufficient, both together harmless:

```elisp
(setq diogenes-declared-dictionaries '(old tll bailly tgl))
```

```elisp
(require 'diogenes-tll)     ; in :init, before diogenes.el loads
```

The ids are `old`, `tll`, `montanari`, `cambridge`, `bdag`, `passow`, `tgl`,
`gaffiot`, `gaffiot-pdf`, `georges`, `georges-pdf`, `pape`, `dge`, `bailly`,
`bailly-pdf`. Order in the list means nothing; the banner is ordered by each
dictionary's own place in it.

- The variable is read afresh whenever an entry is drawn, so editing it takes effect at once.
- The `require` route depends on load order. `diogenes.el` loads every module itself, and `require` is a no-op once a feature is present — so a `require` placed *after* it, in `:config` or a `with-eval-after-load`, declares nothing, silently.
- Put declaring requires in `:init`, or use the variable, which does not care.

`M-x diogenes-list-dictionaries` shows every dictionary, whether it is
declared and by which route, whether it is being offered, and what each of
its own paths holds — including a path that is set but points at nothing.

## The dictionaries themselves
 
diogenes.el can jump a scanned print dictionary (shown as a PDF) to the
page for a given entry. Each dictionary has its own path variable, which
must be set before use.
 
| Abbr. | Dictionary | Lang | Path variable | Layout |
| --- | --- | --- | --- | --- |
| **Latin** | | | | |
| OLD | Oxford Latin Dictionary | La | `diogenes-old-pdf-file` | single PDF |
| TLL | Thesaurus Linguae Latinae | La | `diogenes-tll-pdf-directory` | folder of fascicles |
| Gaffiot | Gaffiot, Dictionnaire latin-français | La | `diogenes-gaffiot-pdf-file` | single PDF |
| Georges | Georges, Lateinisch-deutsches Handwörterbuch | La | `diogenes-georges-directory` | one folder, two volume PDFs |
| **Greek** | | | | |
| Montanari | Brill Dict. of Ancient Greek | Gr | `diogenes-montanari-pdf-file` | single PDF |
| CGL | Cambridge Greek Lexicon | Gr | `diogenes-cambridge-pdf-file` | single PDF |
| BDAG | Bauer/Danker Greek NT | Gr | `diogenes-bdag-pdf-file` | single PDF |
| Bailly | Bailly, Dictionnaire grec-français | Gr | `diogenes-bailly-pdf-file` | single PDF |
| Passow | Passow's Handwörterbuch | Gr | `diogenes-passow-directory` | one folder per volume (PDF + OCR `.txt`) |
| TGL | Estienne, Thesaurus Graecae Linguae | Gr | `diogenes-tgl-directory` | one folder per volume (PDF + OCR `.txt`) |
 
Notes on the data:
 
- OLD, TLL, Montanari, CGL, BDAG: page index comes from each PDF's own bookmarks and embedded OCR layer. No extra files needed.
- Bailly: its bookmarks name a word *somewhere* on the page rather than the page's bounds, so they give no page interval; the index comes from the **running heads** instead (`first lemma — page number — last lemma`), read from the PDF's text layer. No extra files needed, and nothing is built up front: a lookup reads only the dozen pages its binary search touches. Written for the freely available typeset edition *Bailly 2020 – Hugo Chávez* (http://gerardgreco.free.fr/spip.php?article24&lang=fr); optionally run `M-x diogenes-bailly-build-index` once to read every head and write a portable `<pdf-name>-index.eld` beside the PDF.
- Georges: bookmarked once per page, and each bookmark names **every entry on that page** (`Bd1_Sp0005-0006_a-3_abacinus_abactio_…`), which gives some 43 000 headword-to-page pairs. A word among them lands on its exact page; one that is not — an entry a crowded bookmark could not list (those end in `ua13`, *und andere*), a spelling filed differently, or a word Georges lacks — lands where it would stand alphabetically, and the echo area says so. Volumes are routed by the letters each covers, read from its own bookmarks. No extra files needed.
- Passow and TGL: each volume folder needs **two files**, the volume PDF and a plain-text OCR `.txt` of the same volume. Lookups run against the `.txt`, so it is required.
  - First `*.pdf` and first `*.txt` in the folder are used (override with `diogenes-passow-pdf-regexp` / `-text-regexp`, and the `diogenes-tgl-*` equivalents).
  - The OCR `.txt` must delimit pages with lines `----- N / TOTAL -----`.
  - TGL volume folders **must be named by Roman numeral** (`I`, `II`, `III`, `IIII`, `V`); the name is the tomus number. Volume V's `.txt` holds the comprehensive index, the TGL's main lookup path.
  - Passow folder names do not matter; letter ranges are detected from the OCR.
- pdf-tools is used when available; otherwise doc-view. A third option, the Emacs Reader, is described just below.
- A dictionary opens in the window the lookup was made from, replacing the entry; close the document buffer to get the entry back. For the side-by-side arrangement of the original Diogenes desktop application, set `diogenes-old-display-in-other-window` to t (and `diogenes-passow-display-in-other-window` / `diogenes-tgl-display-in-other-window` for those two).
- If your copy is paginated differently, set the per-dictionary `*-page-offset` to shift every jump by a constant.
diogenes.el ships none of these PDFs; supply your own and point the path
variables at them. The TGL and Passow copies I tested are the OCR'd MDZ
volumes (DAFO dataset) from the [Bavarian State Library's
MDZ](https://www.digitale-sammlungen.de/en/).
 

### Gaffiot (a lookup, not a PDF)

Gaffiot's *Dictionnaire illustré latin-français* comes as TEI XML, so it is
shown as an entry in a lookup buffer, like the LSJ and Lewis & Short.

- **In:** `g` or `[Gaffiot]` from any Latin entry. **Out:** `l` or `[Lewis & Short]`.
- Everything a lookup buffer does comes with it: `C-c C-n` / `C-c C-p` walk the dictionary, `C-c C-c` looks up a Latin word (a Greek one goes to the LSJ), `[OLD]` and `[TLL]` open the scans, and each entry gets its own buffer, so the one you came from stays live.
- Keys are the headword reduced to ASCII letters, so the macrons of `fŭtūtrīx`, the ligature in `cælum` and the numeral of `1 ăbactus` do not stand between a Lewis & Short headword and its Gaffiot entry.

**Setup.** Convert the TEI once into the one-entry-per-line form Diogenes
searches:

```elisp
(setq diogenes-gaffiot-source-file "/path/to/gaffiot-unicode.xml")
(setq diogenes-gaffiot-file "/path/to/gaffiot.xml")     ; the converted file
```

- Then `M-x diogenes-gaffiot-build-dictionary` — a few seconds. Pressing `g` with no converted file offers to do it for you.
- Leaving `diogenes-gaffiot-file` unset puts it beside the other Diogenes dictionaries.

**Coverage: A–F only** (about 28 000 entries), that being as far as the
proofread Unicode TEI in circulation goes. For the rest of the alphabet:

- Point `diogenes-gaffiot-pdf-file` at a PDF of the 2016 typeset edition and `g` falls through to it — A–F the XML entry, G–Z the printed page.
- That edition bookmarks the first headword of **every** page (1 379 of them), so the page is found by binary search with no interpolation.
- Its 944 illustration bookmarks are indexed separately; when a word has a plate, the echo area says which page.
- `diogenes-gaffiot-pdf-fallback` set to nil keeps the two apart.
- `M-x diogenes-lookup-open-gaffiot-pdf` opens the PDF for any word regardless.

### DGE (a lookup, not a PDF)

The CSIC's *Diccionario Griego-Español* comes as TEI XML, so it too is shown
as an entry in a lookup buffer.

- **In:** `d` or `[DGE]` from any Greek entry. **Out:** `l` or `[LSJ]`.
- `C-c C-n` / `C-c C-p` walk the dictionary; `C-c C-c` looks a Greek word up; `[Montanari]` `[CGL]` `[BDAG]` `[Passow]` `[TGL]` open the scans; each entry gets its own buffer.
- Definitions are in Spanish and tagged as such, so `C-c C-c` on one does not go looking for it in the LSJ.
- Keys are the headword reduced to bare beta-code letters, so the quantities of `ἀγκῡροειδής`, the dagger of `†ἀαναίμα·`, the asterisk of `*ἀϜαλαλκάνα` and the numeral of `1 ἄᾰτος` do not stand between an LSJ headword and its DGE entry.

**Setup.** Convert the TEI once:

```elisp
(setq diogenes-dge-source-file "/path/to/xdge_xml")   ; the clone, or one file
(setq diogenes-dge-file "/path/to/dge.xml")           ; the converted file
```

- Then `M-x diogenes-dge-build-dictionary` — a minute or two. Pressing `d` with no converted file offers to do it.
- The XML is at <https://github.com/dge-csic/xdge_xml>: one file per volume (`xdge1.xml` … `xdge8.xml`), 112 MB in all. `diogenes-dge-source-file` takes a single file, a **directory**, or a list; point it at the clone and every `*.xml` in it is read.
- Licence CC BY-NC-SA 3.0 ES: free to convert and to read, not to sell.
- The build reads 64 373 entries and writes about 80 MB; the TEI can then be deleted.
- Leaving `diogenes-dge-file` unset puts it beside the other Diogenes dictionaries — often a root-owned directory, so name a path you can write.

**Coverage: α to ἐπισκήπτω**, eight volumes so far, with 30 259 of the 64 373
entries under α alone. A working dictionary, not a finished one.

- Beyond the boundary there is nothing to show and no printed supplement to fall through to — what the CSIC publishes for nothing is exactly this XML. So `ὕβρις` gets *The DGE reaches ἐπισκήπτω so far; "ὕβρις" is not written yet*, rather than the last entry of vol. VIII offered as a near match.
- Inside the published range, a word with no article behaves as everywhere else: nearest entry, with a message.
- The boundary is read from the dictionary itself, so adding vol. IX and rebuilding is all that is needed. `diogenes-dge-check-coverage` turns the check off.

Three things peculiar to this dictionary:

- Articles are large — `ἐπί` alone is 431 KB — and an entry is parsed in Lisp before display, so the prepositions and commonest verbs take a few seconds where an ordinary entry is instantaneous.
- Epigraphic letterforms are set in the private-use area of New Athena Unicode. Entries keep them as published, so install that font to see them rather than boxes; they are spelled out for sorting only (`diogenes-dge-epichoric-substitutions`).
- Etymologies get a labelled block of their own, since in a reflowed paragraph they would run on from the last citation. The label (`diogenes-dge-etymology-label`, "Etim.") is ours: the print sets them off by position alone.

### Prebuilt indexes (Passow, TGL, Bailly)
 
- Passow and the TGL build their lookup index by parsing every volume's OCR — a few seconds, the first time in a session.
- Bailly is different in kind: it never needs a full pass, each lookup reading only the pages its binary search probes. It can store an index all the same, which removes even that per-lookup reading.
 
**Highly recommended: build the index once, up front.** Doing this makes
every subsequent Passow/TGL lookup start instantly instead of paying the
parse on the first lookup of a session. To do it:
 
1. Start Emacs and load diogenes (open the transient menu with `M-x diogenes`, or just do any one lookup, so the package is loaded).
2. Run the build command for each dictionary you have, by typing `M-x`, then the command name, then `RET`:
   
| Command | Writes |
| --- | --- |
| `M-x diogenes-passow-build-index` | `passow-index.eld` in the Passow folder |
| `M-x diogenes-tgl-build-index` | `tgl-index.eld` in the TGL folder |
| `M-x diogenes-bailly-build-index` | `<pdf-name>-index.eld` beside the Bailly PDF |
 
- Each command parses the volumes once and writes a small `.eld` index file beside them.
- Lookups then load that file instead of re-parsing — a noticeable speed-up, especially for the large TGL.
- Run once per machine and forget about it.
 
More detail:
 
- Even without building it by hand, the parse result is cached in memory for the session and on disk (keyed by the OCR files' modification times), so it is paid at most once per machine and redone only if you re-OCR a volume. Building it explicitly with the commands above just gets that cost out of the way before your first lookup rather than during it.
- The `.eld` file is **portable**: commit it alongside the volumes and other users skip the parse entirely.
- Rebuild after adding or re-OCRing a volume (the file records a signature and warns when stale).
- `diogenes-passow-clear-cache` / `diogenes-tgl-clear-cache` / `diogenes-bailly-clear-cache` discard the caches to force a rebuild.
- Bailly's index is optional and quick: with poppler's `pdftotext` the whole dictionary is read in one pass in a few seconds (with pdf-tools alone it goes page by page and takes longer). If the PDF's folder is not writable the table is saved under `diogenes-bailly-cache-directory` instead.
- `diogenes-passow-cache-directory` (and the TGL equivalent) sets where the session cache lives.

### Choosing the PDF viewer
 
Every dictionary is opened by the same routine, and you choose which
in-Emacs viewer it uses with one variable, `diogenes-old-pdf-viewer`
(it lives in the OLD module but governs all of them):
 
| Value | Viewer |
| --- | --- |
| `auto` (default) | pdf-tools if it is installed, otherwise the built-in doc-view |
| `pdf-tools` | force pdf-tools |
| `doc-view` | force the built-in doc-view |
| `emacs-reader` | the [Emacs Reader](https://codeberg.org/MonadicSheep/emacs-reader), a MuPDF-backed reader (`reader-mode`) |
 
- All four are in-Emacs viewers, so ordinary window management applies to their buffers (including the window-purpose helper described later).
- The Emacs Reader must be installed separately (see its Codeberg page); it needs MuPDF and a small C module built at install time.
- One caveat with the Emacs Reader: it renders pages as images and exposes no text layer, so the in-PDF search (`L`, see below) still works but cannot pre-fill the prompt with the word under the cursor. Everything else (the links, the `o t m c b B p g G` keys, jumping to the right page) works with all three viewers.
- The Emacs Reader has no "document ready" signal, so the jump to a page waits for the document to finish rendering by polling; if a very large volume ever loads too slowly for the default wait, raise `diogenes-old-reader-jump-retries` or `diogenes-old-reader-jump-retry-interval`.
**Where to set it.** In `:init` with everything else, as in the
configuration above. It is an ordinary `defcustom` with no `:set` function,
so a `setq` before the package loads is respected — `defcustom` installs its
default only for a variable that is unbound. `M-x customize-variable RET
diogenes-old-pdf-viewer` works too, and leaving it at `auto` needs no
configuration at all.

### A caveat on OCR and bookmarks
 
These are scans of old print books, so their OCR and bookmarks are usually
**not** fully reliable.

- Expect dropped or garbled letters, misread diacritics, columns out of order, wrong bookmarks.
- A jump can land a page or two off. This is normal.
- The thing to internalise: a jump takes you to the right *neighbourhood*, not always the exact page.
 
How reliable, by dictionary:
 
- Most reliable: Bailly (a modern re-typesetting, so no OCR at all), then OLD, BDAG, Montanari, CGL (modern typeset).
- Less so: Passow.
- Least reliable: TGL (16th-century, dense multi-column, heavy ligatures).
What to do about it, as a user, when a jump lands you off:
 
1. **Look nearby first.** The target is usually only a page or two away, so scroll a little before anything else. This alone resolves most misses.
2. **Search inside the open PDF with `L`.** From the PDF, `L` re-looks-up an entry and jumps to it (see [Searching inside an open PDF](#searching-inside-an-open-pdf)); it is the best remedy for a link or `o t m c b B p g G` key that landed wrong.
3. **For the TGL specifically**, reach a badly-OCR'd word by its **root** with `C-u L` (compounds and derivatives are often printed under the root, not as separate entries), or open volume V's index near the word with `i` (`diogenes-tgl-open-index-here`) and find it by eye. Once the index shows a reference like `t.3 c.746`, follow it with `C-u L` (choose the index-reference / other-tome option, give that tomus and column) and it jumps straight there.
| Command / key | Does |
| --- | --- |
| `L` (in the open PDF) | Re-look-up an entry and jump to it; works for every dictionary |
| `C-u L`, approximate | Search for the word's **root** to land in the right article, then read within it |
| `i` (`diogenes-tgl-open-index-here`) | Opens volume V's index near the word, to find it by eye |
 
The TGL is the hard case, and a good deal happens behind the scenes to keep
its lookups on target despite the scan. For *why* a TGL jump usually lands
well — and why `diogenes-tgl-page-offset` normally stays 0 — see
[Appendix: how TGL lookups stay on target](#appendix-how-tgl-lookups-stay-on-target).
 

### Searching inside an open PDF
 
`diogenes-pdf-lookup-entry` looks up an entry from inside the PDF you
already have open and jumps to its page.

- Bound to `L` in `pdf-view-mode`, `doc-view-mode` and the Emacs Reader's `reader-mode`.
- The best fix for a link or an `o t m c b B p g G` key that landed you wrong.
 
- Works for every print dictionary above; it detects which one from the visited file (prompt names it).
- Default is the word at point or the current PDF text selection. (In the Emacs Reader there is no text layer, so no default is offered and the prompt starts empty; you type the word, exactly as `L` expects anyway.)
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
 
Volume V has extra structure, so `C-u L` answering `5` to
the tomus prompt offers a small menu.
 
| Choose | Then | Result |
| --- | --- | --- |
| Index | part 1 or 2, then a column | Jumps to that column. The index is printed in two parts whose numbering each restart at 1, so the part must be chosen. Restart page auto-detected (or pin with `diogenes-tgl-v5-part2-page`). |
| Anomalous roots -> column | a column | Jumps into the "Verborum quorundam themata" section by column |
| Anomalous roots -> approximate | a fragment | One letter jumps to that letter's block; a longer fragment is placed finely by scanning the headwords printed on those pages (the section's headers give only the initial letter) |
| Other tome | a tomus and column | Follows an index reference `t.N c.NNN` into another tome (tomus 5 loops back into this index, asking the part). Use this to chase a reference you read in the index. |
 
Note on the key: lowercase `l` is taken in pdf-view-mode, so the default
is capital `L`. Change it with `diogenes-pdf-search-key` before load.
 

## When an analysis is wrong

Diogenes' morphology is a batch run of Morpheus over wordlists harvested
from the corpora, so it has three distinguishable kinds of gap, and this
package answers each in its own place.

| The file | What happens | The option |
| --- | --- | --- |
| has the form under another spelling | the spelling is normalised before the lookup | none needed — see below |
| has no analysis for the form | the headword you name is looked up | `diogenes-latin-extra-lemmata` |
| has no analysis, and you would rather not name one | Morpheus is asked | `diogenes-morpheus-directory` |
| analyses the form wrongly | the morphology you give is printed | `diogenes-latin-analysis-corrections` |

### Spellings the file does not use

The corpora print what their editors chose; the analyses file is keyed by
bare ASCII. A Latin form is therefore tried as it stands, then with its
circumflexes read as **contractions**, then with all marks removed.

The middle step is the one that matters:

- The texts mark no quantities, so a circumflex in them is not decoration — it says the syllable is contracted, the vowel standing for the two it was made from.
- `desîmus` is `desiimus`, the syncopated perfect of *desino*.
- `desimus` without the mark is a key too — the present subjunctive of *dēsum* — so treating the mark as decoration answers about a word the text did not print.
- `diogenes-latin-expand-contractions` set to nil turns the reading off, for a text that uses the mark otherwise.

### Forms the wordlists never saw

The shipped analyses are a batch run over words that occur in the corpora, so
a form none of those texts happens to use is absent rather than misspelt —
`transilire`, `illidant`, `aedium`, while their sibling forms are all there.
Morpheus generates paradigms from stems and knows them, so it can be asked
directly.

```elisp
(setq diogenes-morpheus-directory "/path/to/morpheus")
```

- Consulted **only** after the shipped analyses and `diogenes-latin-extra-lemmata` have both missed, so leaving it unset changes nothing.
- The directory must hold `bin/cruncher` and `stemlib/`; one without them counts as unset.
- `diogenes-morpheus-timeout` (10 seconds) bounds the wait.
- A lemma Morpheus returns is resolved against the dictionary's own keys, Morpheus having no notion of file offsets. Found, the entry is shown as usual; not found, the morphology is still shown, with the caveat that the headword is a guess.

**Which Morpheus.** Use my fork, which has the more complete stems and is the
one this was tested against:

```sh
git clone https://github.com/VictorSousa92/morpheus
cd morpheus/src && make CC="gcc -std=gnu17 -fpermissive" && make install
cd ../stemlib/Latin && env PATH="$PWD/../../bin:$PATH" MORPHLIB="$PWD/.." make
```

Nothing in the package requires that particular build — any Morpheus laid out
the same way is run the same way — but another one must print the
`<NL>…</NL>` output the parser reads, and must spell its lemmata as Lewis &
Short keys them.

### Analyses that are simply wrong

```elisp
(setq diogenes-latin-analysis-corrections
      '(("experire" :info "pres imperat pass 2nd sg")))
```

`experīre` is the second singular present imperative of the deponent
*experior*, whose infinitive is *experīrī*; the file labels it a present
active infinitive. The lemma and the entry it points at are right, so only
the morphology needs saying again.

- `:info STRING` replaces the morphology of every analysis of that form; `:info ((OLD . NEW) …)` replaces only the ones reading OLD, for a form with several analyses of which one is wrong.
- `:add ((LEMMA . INFO) …)` adds analyses rather than replacing. `LEMMA` nil means the lemma the file already names — use this to record a missing reading while keeping the file's; a string is a headword, whose entry is then shown alongside.
- Keys are the form as the file files it, and are matched through the same spelling variants as everything else, so one entry answers for `experire` and `experīre` alike.
- A corrected morphology prints with `[corr.]` after it, so what you read is never silently other than what the data says. `diogenes-latin-mark-corrections` turns that off.

A long list here is an argument for reporting the analyses upstream rather
than for maintaining it: a systematic error in a batch run is one error, not
a hundred.

## Optional: window management

`diogenes-purpose.el` controls where Diogenes buffers are displayed. It
matters for **Spacemacs**, which turns window-purpose on for everyone, and
for anyone running `(setq pop-up-frames t)` — common with tiling window
managers.

**The problem:**

- Out of the box every Diogenes buffer has the same generic `edit` purpose.
- Purpose shows a buffer in a window that already carries its purpose, so a lookup launched from the browser lands in the browser's window instead of its own.
- With `pop-up-frames t`, every lookup spawns another frame until the screen is buried.

**The fix:** purposes of their own — one `diogenes-lookup` for lookups and
analyses, `diogenes-browser` for the browser — so a lookup never displaces the
browser and lookups reuse one window.

- It has to be done in purpose's terms: in Spacemacs, purpose runs *before* `pop-up-frames` and `display-buffer-alist` and overrides both.
- On plain Emacs without `purpose-mode` you do not need the module at all.

### Loading it is the switch

There is no variable — loading the module is the toggle.

- **Loaded:** the lookup code sets its major mode before display, which is what lets purpose classify a lookup.
- **Not loaded:** Emacs's ordinary display is in charge, reusing a suitable window or opening a new one.

```elisp
(with-eval-after-load 'window-purpose
  (require 'diogenes-purpose nil t))
```

In Spacemacs that goes in `dotspacemacs/user-config`. Loading installs the
purposes immediately and is idempotent;
`M-x diogenes-purpose-uninstall` and `-install` toggle them within a session.

### Dictionary PDFs

PDF buffers are left alone, because purpose matches on major mode or buffer
name and a dictionary PDF is an ordinary `pdf-view-mode` buffer named after
its file. To group them, name them:

```elisp
(setq diogenes-purpose-extra-name-purposes
      '(("Oxford Latin Dictionary.pdf" . diogenes-dict)
        ("Montanari.pdf"               . diogenes-dict)))
```

Single-file dictionaries have predictable names; the directory-based ones
(TLL, Passow, TGL) open one file per volume, so theirs vary.

# Appendix: how TGL lookups stay on target

Not needed to use the dictionary — here for debugging a bad jump. The
everyday remedies are in [A caveat on OCR and
bookmarks](#a-caveat-on-ocr-and-bookmarks).

The TGL is a 16th-century multi-column book with heavy ligatures, so its OCR
and bookmarks are the least reliable of any dictionary here. Rather than
trust the bookmarks, the page is reconstructed from other evidence:

- **Column backbone.** A folio prints two columns per page, so `left-column = 2 × page + b`, and the page is derived from the column number in the OCR (which is why `diogenes-tgl-page-offset` normally stays 0). The origin is found by extrapolating from the cleanest early column pairs, so it works when "1 2" is illegible and when a volume opens mid-alphabet (tomus III starts at columns 5–6). Inserted plates shift later pages; each seam is accepted only when several consecutive columns agree, so one garbled figure cannot derail the line. About 99% of pages map correctly; the rest are garbled figures or the one-page ambiguity at a plate.
- **Fuzzy index lookup.** On an exact miss, keys sharing the first two letters and differing by at most one are retried.
- **"vide" pointers** are followed to their target.
- **"ibidem" entries.** Volume V lists many words as "ibidem", meaning the column of the entry before, so the parser carries the last real column forward across such runs and shares one column across an `X & Y` variant pair.
- **Morphological fallback.** For a compound printed under its root with no column of its own: one Greek prefix is stripped and the root resolved, only on an exact root hit and only when both parts are long enough (`diogenes-tgl-morph-min-root`, default 4).
- **Anomalous roots.** A word found nowhere else but listed in volume V's *Verborum quorundam themata* is sent to its page there.
