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
 
**(Everything in this section was added by me, Victor, on top of
Nitardus's package above. The sections above are his and unchanged.)*
 
Small corrections to the Installation section above:
 
- The variable is `diogenes-path`, not `diogenes-library-path` (the latter does not exist).
- In the `use-package` example, use `(setq diogenes-path "/path/to/diogenes")` in `:init`, not `(diogenes-path "...")`.
## Installation and setup
 
diogenes.el is the Emacs front-end; Diogenes itself (its Perl and its
data) must be installed separately, and `diogenes-path` must point at it.
The print-dictionary PDFs are also supplied by you, via the path
variables below.
 
### Fetching the package from GitHub
 
The package is on GitHub, so it is installed straight from there. Pick
by Emacs version:
 
| Emacs | Method |
| --- | --- |
| 30+ | `use-package` with `:vc` (built in) |
| 29 | `package-vc-install` (built in) |
| 28 or older | a third-party manager (`straight.el` or `quelpa`) |
 
**Emacs 30+** (the recipe fields map directly: `:url` = repo, `:branch` = branch):
 
```elisp
(use-package diogenes
  :vc (:url "https://github.com/VictorSousa92/diogenes.el"
       :branch "OLD-TLL-Montanari-GCL-BDAG-Passow-TGL")
  :init
  ;; ... path variables (see below) ...
  :bind ("C-c d" . diogenes))
```
 
**Emacs 29** (`:vc` does not exist yet; fetch once with `package-vc-install`):
 
```elisp
(unless (package-installed-p 'diogenes)
  (package-vc-install
   '(diogenes :url "https://github.com/VictorSousa92/diogenes.el"
              :branch "OLD-TLL-Montanari-GCL-BDAG-Passow-TGL")))
```
 
- The `unless` guard matters: `package-vc-install` errors if the package is already installed, so without it every start-up would fail.
- Update later with `M-x package-vc-upgrade RET diogenes RET`.
- After that one fetch, configure it with an ordinary `use-package` block **without** `:vc` (fetching and configuring are separate on 29). The variables and the key binding go in exactly the same place as on Emacs 30:
```elisp
  (use-package diogenes
    :defer t
    :init
    (setq diogenes-path "/path/to/your/diogenes/install")
    ;; ... the other path variables (see "The full configuration") ...
    :bind ("C-c d" . diogenes))
```
 
  If you would rather not use `use-package` at all, the plain equivalent is:
 
```elisp
  (require 'diogenes)
  (setq diogenes-path "/path/to/your/diogenes/install")
  ;; ... the other path variables ...
  (global-set-key (kbd "C-c d") #'diogenes)
```
 
### Where the config goes
 
The **same** `use-package` block works in both editors; only where you
put it differs.
 
- **Spacemacs**: put the `use-package` block inside `dotspacemacs/user-config` in your `.spacemacs`. To fetch from GitHub, also add the recipe to `dotspacemacs-additional-packages`:
```elisp
  dotspacemacs-additional-packages
  '((diogenes :location (recipe
                         :fetcher github
                         :repo "VictorSousa92/diogenes.el"
                         :branch "OLD-TLL-Montanari-GCL-BDAG-Passow-TGL")))
```
 
  Spacemacs installs it, and the `use-package` block in `user-config` configures it.
 
- **Traditional Emacs**: put the `use-package` block in your `init.el` (or `.emacs`). Use the `:vc` form (Emacs 30) or the `package-vc-install` form (Emacs 29) above to fetch it; there is no `dotspacemacs-additional-packages`.
### The full configuration
 
Set the data path, each dictionary's PDF path, and a key for the
transient menu. Replace each `/path/to/your/...` placeholder with the
real location on your machine.
 
```elisp
(use-package diogenes
  :defer t
  :init
  (setq diogenes-path "/path/to/your/diogenes/install")
  (setq diogenes-old-pdf-file        "/path/to/your/OLD/file")
  (setq diogenes-tll-pdf-directory   "/path/to/your/TLL/fascicles/directory")
  (setq diogenes-montanari-pdf-file  "/path/to/your/Montanari/file")
  (setq diogenes-cambridge-pdf-file  "/path/to/your/CGL/file")
  (setq diogenes-bdag-pdf-file       "/path/to/your/BDAG/file")
  (setq diogenes-passow-directory    "/path/to/your/Passow/master/directory")
  (setq diogenes-tgl-directory       "/path/to/your/TGL/master/directory")
  (setq diogenes-bailly-pdf-file     "/path/to/your/Bailly/file")
  (setq diogenes-gaffiot-source-file "/path/to/your/Gaffiot/TEI-compliant/unicode/XML/file")
  (setq diogenes-gaffiot-file "/path/to/where/you/want/your/built/Gaffiot/xml/file")
    (setq diogenes-gaffiot-pdf-file "/path/to/your/Gaffiot/file")
    (setq diogenes-georges-directory "/path/to/your/Georges/directory")
        :config
    (setq diogenes-old-pdf-viewer 'auto)
 viewer below for the options.
  :bind ("C-c d" . diogenes))
```
 
Notes:
 
- All variables go in `:init` (they must be set **before** the package loads); `:defer t` is fine, since `:init` runs regardless.
- `("C-c d" . diogenes)` in `:bind` gives you the transient menu on `C-c d` (see below).
- Only set the dictionaries you actually have. An unset one is not merely unavailable: it is invisible. See [Nothing you have not got](#nothing-you-have-not-got) below.
- For Passow and the TGL, each path is the parent folder of the per-volume material; see [Print dictionaries](#print-dictionaries-pdf) for the folder layout and the required OCR text files.
### Nothing you have not got

Every dictionary in this fork is optional, and none of them is mentioned
to a user who has not got it. Set no dictionary paths at all and the
package is Nitardus's original: the LSJ, Lewis & Short, the morphology and
the corpora, with no links line above an entry and no keys that lead
nowhere.

What is gated, and on what:

| You have | You get |
| --- | --- |
| No dictionary paths set | No links line at all, and no dictionary keys bound |
| Some paths set | A links line naming exactly those, in the usual order |
| Only a dictionary's XML | Its link opens the entry; no `[PDF]` link inside it |
| Only a dictionary's PDF | Its link opens the printed page, like the OLD |
| Both | The entry, with `[PDF]` inside it for the printed page |
| No `diogenes-morpheus-directory` | The parse works as before, with no Morpheus fallback |

The rules behind the table:

- **A dictionary is hidden, not explained.** An unset path used to leave the link in place and produce a "not set up yet, here is what to set" error when pressed. Print dictionaries are now gated like the electronic ones: the banner asks each dictionary whether it is there and lists only those that answer yes. The explanatory errors remain, for the keys and for `M-x`, where they are the right answer.
- **XML and PDF are gated separately.** Three dictionaries have both — Gaffiot, Bailly and Georges — and either half is enough. With only the XML, the `[PDF]` link is not offered inside the entry, since there would be nothing behind it. With only the PDF, the dictionary behaves like the OLD: `g` / `B` / `G` and its link open the printed page, and nothing asks you for a TEI file you do not want. With both, the entry comes first and the PDF is one more press of the same key. (Gaffiot has always worked this way, its TEI covering only A–F; Bailly and Georges now do too.)
- **A dictionary registers itself.** Each module announces itself to the lookup banner when it loads, with a predicate over its own paths, so nothing central needs to know the list. A module you do not load is not registered, is not offered, and does not bind its key — `o`, `m`, `c`, `b`, `p`, `B`, `d`, `G`, `g` each belong to the module that defines them. Adding a dictionary is one `diogenes-lookup-register-dictionary` call in one new file; removing one is deleting that file.
- **The predicate is asked afresh each time an entry is drawn.** Set a path, or finish a build, and the link appears on the next entry. No reload, no restart.
- **The cheatsheet agrees with the banner.** `diogenes-cheatsheet` lists a dictionary key only when that dictionary is available, so it never advertises a key that will decline.
- **Morpheus was already optional** and stays so. `diogenes-morpheus-directory` is nil by default; a directory that holds no built `bin/cruncher` and `stemlib` counts as unset. It is consulted only where the shipped analyses and the Latin extra-lemma table have both missed, so with it unset `diogenes-parse-and-lookup-*` behaves exactly as it did before Morpheus support existed: the form is looked up by headword instead.

The predicates are public, so an init file can ask the same questions:
`diogenes-old-available-p`, `-tll-`, `-montanari-`, `-cambridge-`,
`-bdag-`, `-passow-`, `-tgl-`, `-pape-`, `-dge-`,
`diogenes-gaffiot-available-p` (and `-xml-available-p`,
`diogenes-gaffiot-pdf-available-p`), the same three for `bailly` and
`georges`, and `diogenes-morpheus-available-p`.

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
| `diogenes-lookup-gaffiot` | Gaffiot's entry for a Latin headword, in a lookup buffer (`g`) |
| `diogenes-lookup-lewis` | Back to Lewis & Short from another Latin dictionary (`l`) |
| `diogenes-lookup-pape` | Pape's entry for a Greek headword, in a lookup buffer (`P`) |
| `diogenes-lookup-dge` | The DGE's entry for a Greek headword, in a lookup buffer (`d`) |
| `diogenes-lookup-lsj` | Back to the LSJ from another Greek dictionary (`l`) |
 
- If there is no exact match, the nearest entry is shown (a message says so).
- Use the parse-and-lookup commands for text you are reading (they handle inflected forms); use the plain ones when you already know the lemma.
- Greek input works in Unicode or Beta Code. Internally all Greek becomes Beta Code, so Beta Code is occasionally more reliable.
The result opens in **Diogenes Lookup Mode**. What you get there:
 
- The entry, formatted from its TEI XML.
- A links line at the top, listing only the dictionaries you have configured, each link naming its key: `[OLD (o)]` `[TLL (t)]` `[Georges (G)]` `[Gaffiot (g)]` for Latin, `[Montanari (m)]` `[CGL (c)]` `[BDAG (b)]` `[Pape (P)]` `[DGE (d)]` `[Bailly (B)]` `[Passow (p)]` `[TGL (t)]` for Greek (see below).
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
| `o` `t` `g``G` | Open a print dictionary at the current entry — Latin (see table below) |
| `m` `c` `b` `B` `p` | The same for Greek |
| `g` `l` | Gaffiot and Lewis & Short as *lookup entries*, not PDFs |
| `P` `d` `l` | Pape, the DGE and the LSJ, likewise *lookup entries* rather than PDFs (Greek) |
| `q` | Quit the window |
 
- Paging with `C-c C-n` / `C-c C-p` stays in the same buffer and reformats in place.
- The print-dictionary keys and links always act on the entry the cursor is currently in.
- Two of the Latin dictionaries are electronic rather than scans: Gaffiot (`g`) and Lewis & Short (`l`) open as entries in a lookup buffer, so `C-c C-n`, `C-c C-c` and the rest work inside them, and each leads to the other. Each key acts only where it makes sense — `g` from any Latin entry but not from Gaffiot, `l` and `P` from a Gaffiot entry only — and `C-u` on any of them prompts for a word and works anywhere.
- Two of the Greek dictionaries are electronic in the same way: Pape (`P`) and the DGE (`d`) open as entries, and `l` leads back to the LSJ. Each acts only where it makes sense — not inside its own buffer, where the link would lead nowhere — and `C-u` on any of them prompts for a word and works anywhere.
- `P` and `l` serve both languages, dispatching on the entry they are pressed in: `P` is Pape in a Greek entry and the printed Gaffiot in a Latin one, `l` is the LSJ in Greek and Lewis & Short in Latin.
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
## Print dictionaries (PDF)
 
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

Gaffiot's *Dictionnaire illustré latin-français* comes as TEI XML rather than
a scan, so it is shown the way the LSJ and Lewis & Short are — as an entry in
a Diogenes lookup buffer. From a Latin entry press `g` or click `[Gaffiot]`;
from inside Gaffiot, `l` or `[Lewis & Short]` leads back. Everything else the
lookup buffer does comes with it: `C-c C-n` / `C-c C-p` walk the dictionary,
`C-c C-c` on a Latin word looks it up and on a Greek one goes to the LSJ, the
`[OLD]` and `[TLL]` links open the print dictionaries, and each entry gets its
own buffer, so the one you came from stays live.

Setup — convert the TEI once into the one-entry-per-line form Diogenes
searches:

```elisp
(setq diogenes-gaffiot-source-file "/path/to/gaffiot-unicode.xml")
(setq diogenes-gaffiot-file "/path/to/gaffiot.xml")     ; the converted file
```

then `M-x diogenes-gaffiot-build-dictionary` (a few seconds; pressing `g` with
no converted file offers to do it for you). Leaving `diogenes-gaffiot-file`
unset puts it beside the other Diogenes dictionaries.

- Keys are the headword reduced to ASCII letters, so the macrons of `fŭtūtrīx`, the ligature in `cælum` and the homograph numeral of `1 ăbactus` do not stand between a Lewis & Short headword and its Gaffiot entry.
- **Coverage:** the proofread Unicode TEI in circulation covers **A–F** only, about 28 000 entries.

For the rest of the alphabet, point `diogenes-gaffiot-pdf-file` at a PDF of the
2016 typeset edition and `g` falls through to it: A–F gives you the XML entry in
a lookup buffer, G–Z opens the printed page. That edition bookmarks the first
headword of **every** page (1 379 of them), so the page is found by binary
search with no interpolation; its 944 illustration bookmarks are indexed apart
from the page guides, and when the word you looked up has a plate the echo area
says which page it is on. Set `diogenes-gaffiot-pdf-fallback` to nil to keep the
two apart, and `M-x diogenes-lookup-open-gaffiot-pdf` opens the PDF for any word
regardless.

### DGE (a lookup, not a PDF)

The CSIC's *Diccionario Griego-Español* comes as TEI XML rather than a scan,
so it is shown the way the LSJ and Lewis & Short are — as an entry in a
Diogenes lookup buffer. From a Greek entry press `d` or click `[DGE]`; from
inside the DGE, `l` or `[LSJ]` leads back. Everything else the lookup buffer
does comes with it: `C-c C-n` / `C-c C-p` walk the dictionary, `C-c C-c` on a
Greek word looks it up, the `[Montanari]` `[CGL]` `[BDAG]` `[Passow]` `[TGL]`
links open the print dictionaries, and each entry gets its own buffer, so the
one you came from stays live. Definitions are in Spanish and are tagged as
such, so `C-c C-c` on one does not go looking for it in the LSJ.

Setup — convert the TEI once into the one-entry-per-line form Diogenes
searches:

```elisp
(setq diogenes-dge-source-file "/path/to/xdge_xml")   ; the clone, or one file
(setq diogenes-dge-file "/path/to/dge.xml")           ; the converted file
```

then `M-x diogenes-dge-build-dictionary` (a minute or two; pressing `d` with
no converted file offers to do it for you). Leaving `diogenes-dge-file` unset
puts it beside the other Diogenes dictionaries — which on many installations
is a directory owned by root, so name a path you can write.

- The XML is at <https://github.com/dge-csic/xdge_xml>, one file per volume (`xdge1.xml` … `xdge8.xml`), 112 MB in all. `diogenes-dge-source-file` takes a single file, a **directory** of them, or a list; point it at the clone and every `*.xml` in it is read. CC BY-NC-SA 3.0 ES: free to convert and to read, not to sell.
- The build reads 64 373 entries and writes about 80 MB. Nothing else is needed afterwards, and the TEI can be deleted.
- Keys are the headword reduced to bare beta-code letters, so the quantities of `ἀγκῡροειδής`, the dagger of `†ἀαναίμα·`, the asterisk of `*ἀϜαλαλκάνα` and the homograph numeral of `1 ἄᾰτος` do not stand between an LSJ headword and its DGE entry.
- **Coverage:** eight volumes have appeared and they reach **ἐπισκήπτω** — α to ἐπ-, and of the 64 373 entries 30 259 are under α alone. This is a working dictionary, not a finished one.

Beyond that boundary there is nothing to show, and no printed supplement to
fall through to: what the CSIC publishes for nothing is exactly this XML.
Asking for `ὕβρις` therefore gets *The DGE reaches ἐπισκήπτω so far; "ὕβρις"
is not written yet*, rather than the last entry of vol. VIII offered as the
nearest match. Inside the published range a word the DGE has no article for
behaves as it does everywhere else in Diogenes: nearest entry, with a message
saying so. The boundary is read from the dictionary itself, so adding vol. IX
and rebuilding is all that is needed; `diogenes-dge-check-coverage` turns the
check off.

- Articles are large — `ἐπί` alone is 431 KB — and an entry is parsed in Lisp before it is displayed, so the prepositions and the commonest verbs take a few seconds to open where an ordinary entry is instantaneous.
- The DGE sets epigraphic letterforms in the private-use area of New Athena Unicode; entries keep them as published, so install that font if you want to see them rather than boxes. They are spelled out for sorting purposes only (`diogenes-dge-epichoric-substitutions`).
- An etymology is given a labelled block of its own, since in a reflowed paragraph it would run on from the last citation. The label is `diogenes-dge-etymology-label`, "Etim." by default, and it is ours rather than the CSIC's — the print sets etymologies off by position alone.

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
**Where to set it.** Unlike the path variables (which must be set **before** the package loads, hence in `:init`), `diogenes-old-pdf-viewer` is a `defcustom`, so it must be set **after** the package loads. A plain `setq` that runs before load is overwritten when the package loads and the `defcustom` installs its default value. This is true in both Spacemacs and regular Emacs; only the place you put the setting differs slightly. There are three equivalent ways, in rough order of convenience:
 
1. **`M-x customize-variable RET diogenes-old-pdf-viewer`** (either editor). Customize records the value in a way that survives the load, so ordering never matters. Simplest if you do not want to touch your init by hand.
2. **In your `use-package` block, use `:config` (not `:init`)**, which runs *after* the package loads. This is the same block in both editors (it lives in `init.el`/`.emacs` for regular Emacs, or in `dotspacemacs/user-config` for Spacemacs):
```elisp
(use-package diogenes
  :init
  (setq diogenes-path "/path/to/your/diogenes/install")
  ;; ... the path variables, which DO belong in :init ...
  :config
  (setq diogenes-old-pdf-viewer 'emacs-reader)   ; or 'pdf-tools, 'doc-view, 'auto
  :bind ("C-c d" . diogenes))
```
 
3. **A `with-eval-after-load` form**, if you are not using `use-package` for this. Put it in `init.el`/`.emacs` (regular Emacs) or in `dotspacemacs/user-config` (Spacemacs); it is identical in both:
```elisp
(with-eval-after-load 'diogenes-old
  (setq diogenes-old-pdf-viewer 'emacs-reader))
```
 
The feature to wait for is `diogenes-old` (the module that defines the variable), not `diogenes`. Leaving the variable at its default `auto` needs no configuration at all.
 
### Three ways to open a dictionary
 
**1. Clickable links.** Every entry in Diogenes Lookup Mode is preceded
by a links line — unless you have configured no dictionaries at all, in
which case there is none:
 
- Each link carries its key: `[TLL (t)]`, `[Georges (G)]`. The key is shown in the `help-key-binding` face, so it reads as a binding rather than as part of the name.
- Latin entries: `[OLD (o)]` `[TLL (t)]` `[Georges (G)]` `[Gaffiot (g)]` — and inside a Gaffiot entry, `[Lewis & Short (l)]` `[PDF (P)]` in place of `[Gaffiot (g)]`
- Latin entries also carry `[Georges]` and `[Gaffiot]`, which is not a PDF but another **lookup entry** (see below); inside a Gaffiot entry that link becomes `[Lewis & Short]`, leading back, joined by `[PDF]` for the same word in the printed Gaffiot (`P`).
- Greek entries: `[Montanari (m)]` `[CGL (c)]` `[BDAG (b)]` `[Pape (P)]` `[DGE (d)]` `[Bailly (B)]` `[Passow (p)]` `[TGL (t)]` — and inside a Pape or DGE entry, `[LSJ (l)]` in place of that dictionary's own link
- Click or press RETURN to open that dictionary at the entry's page.
- Works per entry: paging with `C-c C-n` / `C-c C-p` gives each entry its own links line and headword.
**2. Single keys** (act on the entry the cursor is in, recomputed each keypress; prefix arg prompts for a word):
 
| Key | Opens |
| --- | --- |
| **In a Latin entry** | |
| `o` | OLD |
| `t` | TLL |
| `g` | Gaffiot — the entry itself (a lookup buffer, not a PDF; the printed page beyond F) |
| `P` | If pressed inside a Gaffiot lookup buffer, the printed page in Gaffiot, for the same word |
| `G` | Georges |
| `l` | Lewis & Short — the way back from a Gaffiot entry |
| **In a Greek entry** | |
| `m` | Montanari |
| `c` | CGL |
| `b` | BDAG |
| `P` | Pape — the entry itself (a lookup buffer, not a PDF) |
| `d` | DGE — the entry itself (a lookup buffer, not a PDF; α–ἐπ only) |
| `l` | LSJ — the way back from a Pape or DGE entry |
| `B` | Bailly |
| `p` | Passow |
| `t` | TGL |
 
**3. Search inside the open PDF** (see below). Best remedy for OCR/bookmark misses.
 
 
### A caveat on OCR and bookmarks
 
These are scans of old print books, so their OCR and bookmarks are
usually **not** fully reliable: expect dropped or garbled letters,
misread diacritics, columns out of order, and wrong bookmarks. A jump
can land a page or two off. This is normal; the thing to internalise is
that a jump takes you to the right *neighbourhood*, not always the exact
page.
 
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
 
The TGL is the hard case, and diogenes.el works fairly hard behind the
scenes to keep its lookups on target despite the poor scan. If you want
to understand *why* a TGL jump usually lands well (and why
`diogenes-tgl-page-offset` normally stays 0), see
[Appendix: how TGL lookups stay on target](#appendix-how-tgl-lookups-stay-on-target).
 
### Prebuilt indexes (Passow, TGL, Bailly)
 
Passow and the TGL build their lookup index by parsing every volume's
OCR, which takes a few seconds the first time in a session. Bailly is
different in kind -- it never needs a full pass, since each lookup reads
only the pages its binary search probes -- but it can store one all the
same, which removes even that per-lookup reading.
 
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
 
Each command parses the volumes once (a few seconds) and writes a small
`.eld` index file next to them. From then on lookups load that file
instead of re-parsing, which is a noticeable speed-up, especially for the
large TGL. Run this once per machine and forget about it.
 
More detail:
 
- Even without building it by hand, the parse result is cached in memory for the session and on disk (keyed by the OCR files' modification times), so it is paid at most once per machine and redone only if you re-OCR a volume. Building it explicitly with the commands above just gets that cost out of the way before your first lookup rather than during it.
- The `.eld` file is **portable**: commit it alongside the volumes and other users skip the parse entirely.
- Rebuild after adding or re-OCRing a volume (the file records a signature and warns when stale).
- `diogenes-passow-clear-cache` / `diogenes-tgl-clear-cache` / `diogenes-bailly-clear-cache` discard the caches to force a rebuild.
- Bailly's index is optional and quick: with poppler's `pdftotext` the whole dictionary is read in one pass in a few seconds (with pdf-tools alone it goes page by page and takes longer). If the PDF's folder is not writable the table is saved under `diogenes-bailly-cache-directory` instead.
- `diogenes-passow-cache-directory` (and the TGL equivalent) sets where the session cache lives.
## Searching inside an open PDF
 
`diogenes-pdf-lookup-entry` (bound to `L` in pdf-view-mode,
doc-view-mode, and the Emacs Reader's reader-mode) looks up an entry
from inside the PDF you already have open and jumps to its page. Best
fix for a link or `o t m c b B p g G` key that landed you wrong.
 
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
 
## Window management: the optional `diogenes-purpose` module
 
`diogenes-purpose.el` is an optional helper that controls where the
Diogenes buffers are displayed. It is aimed mainly at **Spacemacs users**
and at anyone who runs with
 
```elisp
(setq pop-up-frames t)
```
 
which opens buffers in separate frames rather than splitting one frame
into windows (common among users of tiling window managers such as i3,
sway, Hyprland, and bspwm, or PlasmaZones for KDE, who let the window manager tile the Emacs
frames).
 
The problem it solves: **Spacemacs turns window-purpose
([`purpose.el`](https://github.com/bmag/emacs-purpose)) on for
everyone**, and out of the box every Diogenes buffer (the browser and
every lookup) has the same generic `edit` purpose. Because purpose shows
a buffer in a window that already carries its purpose, a lookup launched
from the corpus browser is placed in the browser's own window instead of
its own; and with `pop-up-frames t`, successive lookups or dictionary
PDFs each spawn another frame until the screen is buried.
 
`diogenes-purpose.el` fixes this the purpose-native way, by giving the
Diogenes buffers their own purposes:
 
- lookup and analysis buffers share one `diogenes-lookup` purpose;
- the corpus browser gets its own `diogenes-browser` purpose;
so a lookup never displaces the browser, and lookups reuse one
`diogenes-lookup` window instead of piling up.
 
### Loading it is a deliberate choice
 
Whether you load this module changes how a lookup picks its window, so
treat it as a switch between two behaviours:
 
- **Do not load it** (the default): lookups use Emacs's ordinary display. From the browser a lookup reuses an existing suitable window (another lookup, or a dictionary PDF) or opens a new one; on a single-window frame (for example the startup screen) it just shows the new buffer in that window. This is the historical behaviour and holds whether or not `purpose-mode` is on and whether or not `pop-up-frames` is set.
- **Load it**: lookups are placed by window-purpose into their own `diogenes-lookup` window, and the browser keeps its `diogenes-browser` window, as described above.
The package reads this choice automatically: loading `diogenes-purpose`
also makes the lookup code set its major mode before the buffer is
displayed (purpose decides placement at display time, from the major
mode), which is what lets purpose classify a lookup correctly. There is
no variable to set; loading or not loading the module is the toggle.
 
### Why window-purpose, not `pop-up-frames` or `display-buffer-alist`
 
In Spacemacs, window-purpose takes over buffer placement: its action runs
*before* `pop-up-frames` and *before* `display-buffer-alist`, so it, not
those, decides where a buffer goes. That is why the fix has to be done in
purpose's own terms (distinct purposes) rather than by setting
`display-buffer-alist` or relying on `pop-up-frames`. If you are on plain
Emacs and have never enabled `purpose-mode`, you do not need this module
at all; ordinary Emacs display (and `pop-up-frames`, if you set it)
already does the right thing.
 
 
### Setup
 
`diogenes-purpose.el` ships with the package. Load it after
window-purpose is up, so the load order does not matter:
 
```elisp
(with-eval-after-load 'window-purpose
  (require 'diogenes-purpose))
```
 
In Spacemacs, put that in `dotspacemacs/user-config`. Loading the module
installs the purposes immediately (it is idempotent, so re-loading is
safe). `M-x diogenes-purpose-uninstall` removes them again within a
session, and `-install` re-applies them.
 
### Dictionary PDFs
 
The lookup and browser buffers are handled automatically. The dictionary
PDF buffers are left alone by default, because window-purpose matches a
buffer by its major mode or its name, and a dictionary PDF is an ordinary
`pdf-view-mode` (or `reader-mode`) buffer whose name is just the file
name, with nothing to mark it as a Diogenes dictionary without listing
exact file names. If you want the PDFs to share a purpose too, add their
buffer names to `diogenes-purpose-extra-name-purposes`, for example:
 
```elisp
(setq diogenes-purpose-extra-name-purposes
      '(("Oxford Latin Dictionary.pdf" . diogenes-dict)
        ("Montanari.pdf"               . diogenes-dict)))
```
 
The single-file dictionaries have predictable buffer names; the
directory-based ones (TLL, Passow, TGL) open one file per volume, so
their names vary.
 
# Appendix: how TGL lookups stay on target
 
This appendix explains the machinery behind TGL page-finding. You do not
need any of it to use the dictionary; it is here for the curious and for
anyone debugging a bad jump. The everyday advice ("look nearby, then use
`L` / `C-u L` / `i`") is in [A caveat on OCR and bookmarks](#a-caveat-on-ocr-and-bookmarks).
 
The TGL is a 16th-century, dense, multi-column book with heavy
ligatures, so its OCR and bookmarks are the least reliable of all the
dictionaries. Rather than trust the bookmarks, diogenes.el reconstructs
the page from other evidence:
 
- **Column backbone.** The page is derived from the column number printed in the OCR, not from bookmarks (which is why `diogenes-tgl-page-offset` normally stays 0). The model uses the fact that a folio prints two columns per page, so `left-column = 2 x page + b`:
  - The origin (where column 1 sits) is found by extrapolation from the cleanest early column pairs, so it works even when "1 2" is illegible and even when a volume opens mid-alphabet at columns 5-6 (tomus III).
  - Inserted plates shift later pages; each such "seam" is detected only when several consecutive columns agree, so one garbled figure cannot derail the line, and a page whose own column is missing is still placed by its neighbours.
  - Result: about 99% of pages map correctly; the rest are garbled figures or the one-page ambiguity right at a plate.
- **Fuzzy index lookup** (`diogenes-tgl-fuzzy-lookup`): on an exact miss, retries index keys sharing the first two letters and differing by at most one letter.
- **"vide" pointers** are followed to their target.
- **"ibidem" entries** (volume V lists many words as "ibidem", meaning the same column as the entry before): the parser carries the last real column forward across such runs, ignores the trailing line-letter, and shares one column across an `X & Y` variant pair.
- **Morphological fallback** (`diogenes-tgl-morph-fallback`): last resort for a compound printed under its root with no column; strips one Greek prefix and resolves the root, only on an exact root hit and only when root and residue are long enough (`diogenes-tgl-morph-min-root`, default 4).
- **Anomalous-roots fallback**: a word found nowhere else but listed exactly in volume V's "Verborum quorundam themata" (irregular/poetic verb forms) is sent to its page there.
Together these are why a TGL jump usually lands in the right article or
within a page or two of it, despite the scan quality. When one still
misses, fall back to the user-facing remedies in the caveat section
above.
