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


## Contents

Sections above **Additional features** are from the upstream
[nitardus/diogenes.el](https://github.com/nitardus/diogenes.el); everything
below is added here.

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Transient interface](#transient-interface)
- [Usage](#usage)
  - [Searching the Corpora](#searching-the-corpora)
  - [Browsing the Corpora](#browsing-the-corpora)
  - [Parsing and Dictionary Lookup](#parsing-and-dictionary-lookup)
  - [Utilities](#utilities)

**Added in this fork**

- [Additional features (Victor)](#additional-features-victor)
  - [Install](#install)
  - [Configuration](#configuration)
  - [Looking a word up](#looking-a-word-up)
    - [`C-c C-o` — any dictionary, by name](#c-c-c-o--any-dictionary-by-name)
    - [In a lookup buffer](#in-a-lookup-buffer)
  - [`C-c C-c` on words](#c-c-c-c-on-words)
  - [Forgetting the keys](#forgetting-the-keys)
  - [Which dictionaries appear](#which-dictionaries-appear)
    - [Declaring one](#declaring-one)
  - [The dictionaries themselves](#the-dictionaries-themselves)
    - [Dictionaries as entries (XML)](#dictionaries-as-entries-xml)
    - [Bailly](#bailly)
    - [Georges](#georges)
    - [Gaffiot](#gaffiot)
    - [DGE](#dge)
    - [Dictionaries as pages (scans)](#dictionaries-as-pages-scans)
    - [Prebuilt indexes (Passow, TGL, Bailly)](#prebuilt-indexes-passow-tgl-bailly)
    - [Choosing the PDF viewer](#choosing-the-pdf-viewer)
    - [A caveat on OCR and bookmarks](#a-caveat-on-ocr-and-bookmarks)
    - [Searching inside an open PDF](#searching-inside-an-open-pdf)
    - [Volume V (special menu)](#volume-v-special-menu)
  - [When an analysis is wrong](#when-an-analysis-is-wrong)
    - [Spellings the file does not use](#spellings-the-file-does-not-use)
    - [Forms with no analysis at all](#forms-with-no-analysis-at-all)
    - [Forms the wordlists never saw](#forms-the-wordlists-never-saw)
    - [Analyses that are simply wrong](#analyses-that-are-simply-wrong)
  - [Changing the keys](#changing-the-keys)
  - [Under evil (Doom, Spacemacs with evil)](#under-evil-doom-spacemacs-with-evil)
  - [A frame with only a startup page in it](#a-frame-with-only-a-startup-page-in-it)
  - [Window management](#window-management)
    - [Four behaviours](#four-behaviours)
    - [Choosing one at startup](#choosing-one-at-startup)
    - [Setting a behaviour yourself](#setting-a-behaviour-yourself)
    - [One behaviour per kind, and the rest in detail](#one-behaviour-per-kind-and-the-rest-in-detail)
    - [What each module does now](#what-each-module-does-now)
  - [Presets](#presets)
    - [Building one in a browser](#building-one-in-a-browser)
- [Appendix: other commands](#appendix-other-commands)
- [Appendix: how TGL lookups stay on target](#appendix-how-tgl-lookups-stay-on-target)

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

Now require it and point `diogenes-path` at the root of your Diogenes
installation:

    (require 'diogenes)
    (setq diogenes-path "/path/to/diogenes")

Or, with use-package (with some handy key-bindings)

    (use-package diogenes
      :init
      (setq diogenes-path "/path/to/diogenes")
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
       :branch "modular-customizable")
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
              :branch "modular-customizable")))
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
                     :branch "modular-customizable"))
```

## Configuration

[**Open the configuration builder**](https://htmlpreview.github.io/?https://raw.githubusercontent.com/VictorSousa92/diogenes.el/modular-customizable/tools/diogenes-preset-builder.html#configuration)
to fill this in by hand-holding rather than by hand: it asks what you run, takes
a dictionary path pasted from your file manager, records the keys you press,
warns about a key something else already wants, and writes the block below with
only what differs from the defaults. Or write it yourself:

Settings go in `:init`, which runs before the package loads; anything that
names something the package itself defines goes in `:config`, which runs
after. Delete the dictionaries you do not have — an unset one is invisible
rather than broken.

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
  (setq diogenes-gaffiot-pdf-file    "/path/to/Gaffiot.pdf")       ; whatever the XML lacks
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
        '(("experire"   :info "pres imperat pass 2nd sg")
          ("superstite" :lemma "superstes" :info "abl sg")))

  ;; Forms the analyses file has no entry for (see below)
  (setq diogenes-latin-extra-lemmata
        '(("valdissime" . "validus")
          ("valde"      . "validus")
          ("valdius"    . "validus")))

  ;; PDF viewer: 'auto, 'pdf-tools or 'emacs-reader
  (setq diogenes-old-pdf-viewer 'auto)

  ;; Presets, both optional.  The folder is where presets of your own live;
  ;; leave it unset and the four builtins are still offered.
  ;;
  ;;   "defer"   whatever you have installed decides -- the default
  ;;   "reuse"   one window for entries, each replacing the last
  ;;   "split"   an entry beside the text, later entries sharing it
  ;;   "frames"  each kind in a frame of its own, entries gathered
  ;;
  ;; A builtin needs no folder.  For one of your own, name the file without
  ;; its extension and set the folder as well.
  (setq diogenes-preset-directory "~/.emacs.d/diogenes-presets/")
  (setq diogenes-preset "my-preset")

  :config
  ;; Optional, if you use flyspell: it has nothing useful to say about Greek
  ;; or Latin, and marks most of an entry as a misspelling.
  (dolist (hook '(diogenes-lookup-mode-hook
                  diogenes-analysis-mode-hook))
    (add-hook hook (lambda () (flyspell-mode -1))))

  ;; Optional, if you use window-purpose (see below)
  (diogenes-purpose-install)

  :bind ("C-c d" . diogenes))
```

- Every option goes in `:init`. It runs before the package loads, which matters for one case only — declaring a dictionary by `(require 'diogenes-tll)` — but keeping the settings in one place costs nothing.
- `:config` is for the two lines above and anything like them: a `keymap-set` in one of the package's maps, an `add-to-list` on one of its variables, advice on its functions. In `:init` those are void-variable errors, the symbols not existing yet.
- The flyspell lines are worth having if you use it globally. `diogenes-browser-mode-hook` too, if you read texts in the browser.
- `(diogenes-purpose-install)` is only needed if you have uninstalled the purposes within a session; loading `diogenes-purpose` installs them already. Harmless either way, and it makes the intent visible.
- **`diogenes-path` is the only path Diogenes itself needs.** It is the root of the installation, and everything inside is reached from there: the Perl modules in `server/`, the bundled libraries in `dependencies/CPAN/`, and the Perseus analyses with the LSJ and Lewis & Short in `dependencies/data/`. That layout is the Diogenes distribution's own, so there is nothing else to name. The dictionary scans and the XML dictionaries are a separate matter — they are your files rather than part of a Diogenes installation, which is why each has a variable of its own.
- Passow and the TGL take the **parent** folder of the per-volume material; see [The dictionaries themselves](#the-dictionaries-themselves) for the layout and the OCR text files they need.
- The XML dictionaries are built once from their TEI source: `-source-file` is what you downloaded, `-file` is where the built dictionary goes. Pressing the key offers to build it.
- The two preset lines are optional, and both belong in `:init` so that the name is set before the package reads it. Leave `diogenes-preset-directory` out and `M-x diogenes-load-preset` offers `defer`, `reuse`, `split` and `frames`; leave `diogenes-preset` out and nothing is loaded until you ask. See [Presets](#presets).

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

### `C-c C-o` — any dictionary, by name

`C-c C-o` (`diogenes-lookup-in-dictionary`) is `C-c C-c` with the dictionary
asked for rather than assumed.

- For a word that is in neither default dictionary but is in another: a late or technical word Lewis & Short does not carry, a proper name, a sense Bailly gives and the LSJ does not.
- And for reading a Greek word in German or a Latin one in French, whatever the language of the entry you are looking at.
- The language is settled as `C-c C-c` settles it — the word's own tagging where the markup says, otherwise the language being read — and only that language's dictionaries are offered. Where it cannot be told, it is asked for.
- The word defaults to the headword or word at point and is **parsed first**, so an inflected form reaches its lemma. A prefix argument prompts for the word too.
- Every registered dictionary of that language is listed, declared or not, so this is also the way to reach one whose paths you have not set — it will then say what to set.
- `diogenes-lookup-always-ask-dictionary` set to non-nil makes the plain `diogenes-lookup-greek` and `-latin` ask every time, which is worth it for a reader who works mostly in Bailly or Georges rather than the defaults.

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

## `C-c C-c` on words
 
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

## Forgetting the keys

`M-x diogenes-cheatsheet` shows them in a floating panel that vanishes at the
next keystroke.

- Read from the **live keymaps**, so it lists what this installation actually has: the dictionaries you configured, the `diogenes-purpose` focus keys if that module is loaded, and nothing that would decline.
- The current buffer's keys come first, then the other Diogenes buffers', then the commands that get you into one.
- Laid out in as many columns as the frame has room for. On a terminal frame, where there are no child frames, it falls back to an ordinary help window.
- `diogenes-cheatsheet-max-height` (0.8 of the frame) and `diogenes-cheatsheet-column-gap` adjust the panel; `diogenes-cheatsheet-uninteresting-commands` hides editing and mouse commands the browser inherits from `text-mode`.

Worth binding, since it is the one command that tells you the rest:

```elisp
(with-eval-after-load 'diogenes
  (keymap-set diogenes-lookup-mode-map "?" #'diogenes-cheatsheet))
```

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

Eleven of them, in two kinds — and three exist as both.

- **As entries.** Five come as TEI XML and are shown as formatted entries in a lookup buffer, like the LSJ and Lewis & Short: **Bailly**, **Gaffiot**, **Georges**, **Pape**, the **DGE**. Each is built once from its source and then behaves as a dictionary of the package.
- **As pages.** Ten are scans, jumped to the page for an entry: **OLD**, **TLL**, **Montanari**, **CGL**, **BDAG**, **Passow**, **TGL**, and the printed **Gaffiot**, **Bailly** and **Georges**.
- **As both.** Gaffiot, Bailly and Georges have an XML and a scan, and either half alone is enough. With both, the entry comes first and the same key opens the page from inside it.

### Dictionaries as entries (XML)

| Dictionary | Lang | Source | Built to | Coverage | Also in print |
| --- | --- | --- | --- | --- | --- |
| Bailly | Gr | `diogenes-bailly-source-file` | `diogenes-bailly-file` | complete | `diogenes-bailly-pdf-file` |
| Gaffiot | La | `diogenes-gaffiot-source-file` | `diogenes-gaffiot-file` | complete, or A–F — see below | `diogenes-gaffiot-pdf-file` |
| Georges | La | `diogenes-georges-source-file` | `diogenes-georges-file` | complete | `diogenes-georges-directory` |
| Pape | Gr | `diogenes-pape-source-file` | `diogenes-pape-file` | complete | — |
| DGE | Gr | `diogenes-dge-source-file` | `diogenes-dge-file` | α–ἐπισκήπτω | — |

Where the sources came from:

- **Pape, Gaffiot and Georges** are built from the FDB databases published by the Institut für Klassische Philologie at Zürich: <https://www.iaka.uzh.ch/de/klph/it/mls.html>. Those are databases rather than TEI, so they need converting first — and the Gaffiot among them is **complete**.
- **Gaffiot** also exists as ready-made TEI at <https://digital-gaffiot.sourceforge.net/>, which needs no conversion but stops at F. See below.
- **Bailly** was tested against a TEI XML built from the GoldenDict version: <https://chaerephon.e-monsite.com/pages/litterature/grec-ancien/bailly2020.html>.
- **The DGE** is the CSIC's own XML, below.
- The **printed Georges** the page lookup expects is the 1913 edition as digitised at <http://www.zeno.org/Georges-1913>; the printed **Bailly** is the typeset *Bailly 2020 – Hugo Chávez* (<http://gerardgreco.free.fr/spip.php?article24&lang=fr>).

What is true of all five:

- Built once with `M-x diogenes-<name>-build-dictionary`; pressing the key with nothing built offers to do it. `-source-file` is what you downloaded, `-file` where the built dictionary goes — unset, it lands beside the other Diogenes dictionaries, which is often a root-owned directory, so name a path you can write.
- Reached by its key or its link from any entry of its language; `l` is the way back to the LSJ or Lewis & Short.
- Everything a lookup buffer does comes with it: `C-c C-n` / `C-c C-p` walk the dictionary, `C-c C-c` looks a word up, the print dictionaries' links open the scans, and each entry gets its own buffer, so the one you came from stays live.
- Keys are the headword reduced to bare letters, so quantities, ligatures, daggers, asterisks and leading numerals do not stand between an LSJ or Lewis & Short headword and its entry here.
- A word the dictionary lacks gives the nearest entry, with a message — except past the DGE's published boundary, where there is nothing to be near.

Below, only what is peculiar to each. **Pape** has nothing peculiar: it is
complete, built from the Zürich FDB database, has no printed companion here,
and `P` opens it.

### Bailly

- The XML is the whole of the Bailly 2020 edition — the same text its PDF prints — so there is no coverage boundary and nothing to fall back on.
- With only `diogenes-bailly-pdf-file` set and no XML built, `B` opens the printed page instead, and Bailly behaves like the OLD.
- Pressed a second time from inside a Bailly entry, `B` opens that word's page in the print. That is the only route to the PDF; `C-u B` [`SPC u B`] looks another word up in the XML.

**Gaffiot and Georges work the same way**, being the other two with both an XML
and a print: `g` inside a Gaffiot entry opens Gaffiot's page, `G` inside a
Georges entry opens Georges', and the prefix in either looks another word up in
the XML. Where the print is not configured, the letter says so and names the
option to set.

**And the prefix means one thing throughout: look a word up in that dictionary,
asking which word.** It never reaches the printed page — pressing the letter
again inside that dictionary's own entry is what does that. For a print-only
dictionary — the OLD, Montanari, the CGL, the BDAG, Passow, the TGL — the letter
opens the scan and the prefix asks which word to open it at. `C-u L` inside a
scan is the one exception that does more.

### Georges

- Complete, and `G` works the same way: the entry, then the printed page from inside it.
- With only `diogenes-georges-directory` set, `G` opens the page directly.

### Gaffiot

Gaffiot's *Dictionnaire illustré latin-français*. `g` opens the entry, `l`
returns to Lewis & Short.

**Two sources, trading completeness against the work of getting there:**

- The **FDB database at Zürich** (<https://www.iaka.uzh.ch/de/klph/it/mls.html>) is **complete, A–Z** — but it is a database, so it has to be turned into TEI before it can be built here.
- The **TEI at <https://digital-gaffiot.sourceforge.net/>** is **already TEI**, needing no such step, but is proofread as far as **F** only (some 28 000 entries).

With the complete one there is nothing more to do. With the sourceforge TEI,
for the rest of the alphabet:

- Point `diogenes-gaffiot-pdf-file` at a PDF of the 2016 typeset edition and `g` falls through to it — the XML entry where the file has one, the printed page otherwise.
- That edition bookmarks the first headword of **every** page (1 379 of them), so the page is found by binary search with no interpolation.
- Its 944 illustration bookmarks are indexed separately; when a word has a plate, the echo area says which page.
- `diogenes-gaffiot-pdf-fallback` set to nil keeps the two apart.
- `M-x diogenes-lookup-open-gaffiot-pdf` opens the PDF for any word regardless.

### DGE

The CSIC's *Diccionario Griego-Español*. `d` opens the entry, `l` returns to
the LSJ.

- Definitions are in Spanish and tagged as such, so `C-c C-c` on one does not go looking for it in the LSJ.
- The build takes a minute or two. The XML is at <https://github.com/dge-csic/xdge_xml>: one file per volume (`xdge1.xml` … `xdge8.xml`), 112 MB in all. `diogenes-dge-source-file` takes a single file, a **directory**, or a list; point it at the clone and every `*.xml` in it is read.
- Licence CC BY-NC-SA 3.0 ES: free to convert and to read, not to sell.
- The build reads 64 373 entries and writes about 80 MB; the TEI can then be deleted.

**Coverage: α to ἐπισκήπτω**, eight volumes so far, with 30 259 of the 64 373
entries under α alone. A working dictionary, not a finished one.

- Beyond the boundary there is nothing to show and no printed supplement to fall through to — what the CSIC publishes for nothing is exactly this XML. So `ὕβρις` gets *The DGE reaches ἐπισκήπτω so far; "ὕβρις" is not written yet*, rather than the last entry of vol. VIII offered as a near match.
- Inside the published range, a word with no article behaves as everywhere else: nearest entry, with a message.
- The boundary is read from the dictionary itself, so adding vol. IX and rebuilding is all that is needed. `diogenes-dge-check-coverage` turns the check off.

Also:

- Articles are large — `ἐπί` alone is 431 KB — and an entry is parsed in Lisp before display, so the prepositions and commonest verbs take a few seconds where an ordinary entry is instantaneous.
- Epigraphic letterforms are set in the private-use area of New Athena Unicode. Entries keep them as published, so install that font to see them rather than boxes; they are spelled out for sorting only (`diogenes-dge-epichoric-substitutions`).
- Etymologies get a labelled block of their own, since in a reflowed paragraph they would run on from the last citation. The label (`diogenes-dge-etymology-label`, "Etim.") is ours: the print sets them off by position alone.

### Dictionaries as pages (scans)

diogenes.el jumps a scanned dictionary to the page for a given entry. Each
has its own path variable, which must be set before use.

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
 
- OLD and TLL: the page index is the PDF's own outline, whose bookmarks are the printed running heads of each page. No extra files needed. This is what the OLD's first edition carries and what the upstream Diogenes build tools rely on.
- Montanari, BDAG, CGL: each reads its own edition's bookmark convention, and they are three different conventions rather than one. What a copy must carry, and the regexp that reads it:

| | Bookmarks per page | Regexps |
| --- | --- | --- |
| Montanari | an interval, `288: άραιρη- – Άραυάκαι`; some pages carry a single word instead | `diogenes-montanari-interval-regexp`, `-single-regexp` |
| BDAG | an interval, `2: ἀβροχία - ἀγαθός`; letter-openings and long entries carry one word | `diogenes-bdag-interval-regexp`, `-single-regexp` |
| CGL | **one** guide word, `3: άγακτίμενος`, numbered sequentially | `diogenes-cambridge-entry-regexp` |

  - The CGL is the particular one: with a single word per page, which word it is depends on the **parity** of that sequential number — even bookmarks give the page's first headword, odd ones its last, except the first odd bookmark of a letter, which opens the letter. The module refines a match using that parity, so a copy bookmarked some other way will not do, however well-formed.
  - Montanari's bookmark text is OCR'd, so its accents, breathings and iota subscripts cannot be trusted; comparison is accent-insensitive. BDAG's is clean accented Greek and is compared more strictly.
  - The regexps are ordinary options. If your copy numbers or separates its bookmarks differently, adjusting one is the fix — group 1 the first headword, group 2 the last, and for the CGL group 1 the number and group 2 the word.
  - `M-x diogenes-montanari-show-bookmarks` and its equivalents print what the package can read from your PDF, which is the quickest way to find out whether a copy will work at all.
- Bailly: its bookmarks name a word *somewhere* on the page rather than the page's bounds, so they give no page interval; the index comes from the **running heads** instead (`first lemma — page number — last lemma`), read from the PDF's text layer. No extra files needed, and nothing is built up front: a lookup reads only the dozen pages its binary search touches. Written for the typeset *Bailly 2020* named above; optionally run `M-x diogenes-bailly-build-index` once to read every head and write a portable `<pdf-name>-index.eld` beside the PDF.
- Georges: bookmarked once per page, and each bookmark names **every entry on that page** (`Bd1_Sp0005-0006_a-3_abacinus_abactio_…`), which gives some 43 000 headword-to-page pairs. A word among them lands on its exact page; one that is not — an entry a crowded bookmark could not list (those end in `ua13`, *und andere*), a spelling filed differently, or a word Georges lacks — lands where it would stand alphabetically, and the echo area says so. Volumes are routed by the letters each covers, read from its own bookmarks. No extra files needed. Built after the zeno.org digitisation named above.
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
**Fitting the page.** Neither pdf-tools nor doc-view fits a page to the
window; both open at whatever scale the last document was left at.
`diogenes-old-pdf-fit` (default `width`) rescales each page as it is shown —
`page`, `height` or nil for the viewer's own behaviour.

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
3. **For the TGL specifically**, reach a badly-OCR'd word by its **root** with `C-u L` [`SPC u L` under Doom and Spacemacs] (compounds and derivatives are often printed under the root, not as separate entries), or open volume V's index near the word with `i` (`diogenes-tgl-open-index-here`) and find it by eye. Once the index shows a reference like `t.3 c.746`, follow it with `C-u L` [`SPC u L`] (choose the index-reference / other-tome option, give that tomus and column) and it jumps straight there.
| Command / key | Does |
| --- | --- |
| `L` (in the open PDF) | Re-look-up an entry and jump to it; works for every dictionary |
| `C-u L` [`SPC u L`], approximate | Search for the word's **root** to land in the right article, then read within it |
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
| `C-u L` [`SPC u L`] | Approximate jump: type the beginning of a word (even one letter) and land at that alphabetical position |
 
Syntax note: type this as the sequence `C-u` then `L` (then answer the
prompts). It is not the usual numeric prefix, so do not type `C-u 4 L`
or the like; just `C-u L` [`SPC u L`].
 
Approximate (`C-u L` [`SPC u L`]) details:
 
- Single-PDF dictionaries: reuses their own positional index.
- TGL: navigates by the clean running headers at the top of each column (short, all-caps, far more OCR-legible than the body), so it reaches the right article even when the body is garbled. This is the most dependable way to reach a badly OCR'd word.
- TGL also offers a jump **by index reference** (the `t.N c.NNN` citations): choose the index-reference option, give the tomus and column, and it converts the column to a page. This is how you follow a reference you found in the index (e.g. `t.3 c.746`) to its place in another tome.
  - From tomes I-IV, `C-u L` [`SPC u L`] asks approximate-or-index-reference first.
  - From volume V, the reference option appears in its menu as "other tome" (see below).
### Volume V (special menu)
 
Volume V has extra structure, so `C-u L` [`SPC u L`] answering `5` to
the tomus prompt offers a small menu.
 
| Choose | Then | Result |
| --- | --- | --- |
| Index | part 1 or 2, then a column | Jumps to that column. The index is printed in two parts whose numbering each restart at 1, so the part must be chosen. Restart page auto-detected (or pin with `diogenes-tgl-v5-part2-page`). |
| Anomalous roots -> column | a column | Jumps into the "Verborum quorundam themata" section by column |
| Anomalous roots -> approximate | a fragment | One letter jumps to that letter's block; a longer fragment is placed finely by scanning the headwords printed on those pages (the section's headers give only the initial letter) |
| Other tome | a tomus and column | Follows an index reference `t.N c.NNN` into another tome (tomus 5 loops back into this index, asking the part). Use this to chase a reference you read in the index. |
 
Note on the key: lowercase `l` is taken in pdf-view-mode, so the default
is capital `L`. Change it with `diogenes-pdf-search-key` before load.

Note on the prefix: `C-u` is Emacs's universal argument and evil leaves it
alone, so `C-u L` works in normal state as it does anywhere. A configuration
that restores Vim's `C-u` for scrolling puts the argument on the leader
instead — `SPC u` under Doom and Spacemacs — and `M-1` in place of `C-u` works
either way. `(key-binding (kbd "C-u"))` says which you have.
 

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

### Forms with no analysis at all

Where the file has no entry and you know the headword, name it:

```elisp
(setq diogenes-latin-extra-lemmata
      '(("valdissime" . "validus")
        ("valde"      . "validus")
        ("valdius"    . "validus")))
```

- Consulted before Morpheus, so an entry here suppresses whatever Morpheus would have said. That is worth knowing: Morpheus returns the morphology as well as the lemma, where this can only say *"valdius does not parse; showing validus"* and open the entry.
- So it earns its keep for forms Morpheus does not have either — the comparative and superlative of the adverb `valde` are a real example, its stems carrying the adverb without its comparison — and for a form where you want a headword other than the one either source picks.
- Keys are matched through the same spelling variants as everything else, so one entry answers for the u/v and i/j spellings alike.

**Greek has the same table**, `diogenes-greek-extra-lemmata`:

```elisp
(setq diogenes-greek-extra-lemmata
      '(("οὑτοσί" . "οὗτος")
        ("ταὐτόν"  . "αὐτός")))
```

Deictic and crasis forms are what it is mostly for: the wordlists carry the
plain word and not `οὑτοσί`. Keys are compared as they stand and again stripped
of their accents, so an entry written unaccented answers for the accented form.
- On a machine with no Morpheus built, this is the only fallback there is.

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
      '(("experire"   :info "pres imperat pass 2nd sg")
        ("superstite" :lemma "superstes" :info "abl sg")))
```

`experīre` is the second singular present imperative of the deponent
*experior*, whose infinitive is *experīrī*; the file labels it a present
active infinitive. The lemma and the entry it points at are right, so only
the morphology needs saying again.

`superstite` is the ablative singular of *superstes*, the adjective, and the
file analyses it from *super-sto*, the verb — which is *superstes*'s own
etymology, so the mistake is an understandable one. Here the lemma is wrong as
well as the morphology, and that matters more: a wrong lemma sends `o`, `t`,
`g` and `G` to the wrong entry. `:lemma` says which headword is meant, and the
entry those keys open follows it.

- `:info STRING` replaces the morphology of every analysis of that form; `:info ((OLD . NEW) …)` replaces only the ones reading OLD, for a form with several analyses of which one is wrong.
- `:lemma STRING` replaces the headword, and the entry the dictionary keys open follows it — found by name among the dictionary's keys, so the spelling wants to be one the dictionary is keyed under. Where it cannot be found the morphology is still shown, with the caveat that the headword is a guess.

**Greek has the same table**, `diogenes-greek-analysis-corrections`, taking the
same keys:

```elisp
(setq diogenes-greek-analysis-corrections
      '(("ᾖ" :info "pres subj act 3rd sg")))
```

The Greek data is wrong more often than the Latin rather than less — Morpheus
knows less of it, and the LSJ keys some headwords differently from the form
Morpheus gives — so if you have worked out what a form actually is, this is
where to record it.
- `:lemma STRING` replaces the headword. The entry the dictionary keys open follows it, found by name among the dictionary's keys — so the spelling wants to be one Lewis & Short is keyed under. Where it cannot be found the morphology is still shown, with the caveat that the headword is a guess.
- `:add ((LEMMA . INFO) …)` adds analyses rather than replacing. `LEMMA` nil means the lemma the file already names — use this to record a missing reading while keeping the file's; a string is a headword, whose entry is then shown alongside.
- Keys are the form as the file files it, and are matched through the same spelling variants as everything else, so one entry answers for `experire` and `experīre` alike.
- A corrected morphology prints with `[corr.]` after it, so what you read is never silently other than what the data says. `diogenes-latin-mark-corrections` turns that off.

A long list here is an argument for reporting the analyses upstream rather
than for maintaining it: a systematic error in a batch run is one error, not
a hundred.

## Changing the keys

Every key the package binds can be moved or removed.

**The dictionary letters** — `o` for the OLD, `g` for the Gaffiot, and the rest
— are one option, keyed by the dictionary's name:

```elisp
(setq diogenes-lookup-dictionary-keys
      '((old . "O")            ; move it
        (gaffiot . "F")
        (bdag . nil)))         ; bind nothing, freeing `b'
```

The banner under an entry reads the same option, so `[OLD (O)]` says what the
key now is. `nil` frees a letter for something of your own.

**The lookup buffer's own keys** are a second table, by command:

```elisp
(setq diogenes-lookup-keys
      '((diogenes-perseus-action       . "RET")
        (diogenes-perseus-action       . "C-c C-c")
        (diogenes-lookup-in-dictionary . "C-c C-o")
        (diogenes-lookup-next          . "C-c C-n")
        (diogenes-lookup-previous      . "C-c C-p")
        (diogenes-lookup-open-tll-or-tgl . "t")
        (diogenes-lookup-lewis         . "l")
        (diogenes--quit                . "q")))
```

That is the default; change what you want and leave the rest. A command may
appear twice — the action is on `RET` and on `C-c C-c` both — and `nil` for a
key binds nothing.

**And four keys have options of their own:**

| | |
| --- | --- |
| `diogenes-pdf-search-key` | the lookup key in a scanned dictionary, `L` |
| `diogenes-tgl-index-key` | volume V's index from a TGL volume, `i` |
| `diogenes-old-visit-dictionary-key` | back to the page from an entry, `C-c C-e` |
| `diogenes-evil-normal-state-key` | out of Emacs state, `<escape>` |

Both tables are read when the maps are built, so set them in `:init` — or in a
preset, which is loaded early enough. `M-x diogenes-lookup-install-dictionary-keys`
and `M-x diogenes-tgl-install-index-key` apply a change without restarting.

Anything not listed is an ordinary keymap and an ordinary `keymap-set`:

```elisp
(with-eval-after-load 'diogenes-browser
  (keymap-set diogenes-browser-mode-map "N" #'diogenes-browser-forward))
```

## Under evil (Doom, Spacemacs with evil)

Nothing to configure — this is handled, and the reason is worth knowing.

The dictionary keys are single letters, and under evil those letters are
evil's: in normal state `o` opens a line, `d` deletes, `p` pastes, `b` moves
back a word, `q` records a macro. Evil's state maps come before the major
mode's, so none of the dictionary keys would be reached — and the buffers
being read-only, the letters do nothing useful in their place.

So the read-only Diogenes buffers start in evil's **Emacs state**, where the
keys are the ones the rest of this README describes.

Getting between the states:

| From | Press | To |
| --- | --- | --- |
| Emacs state | `ESC` | normal state — evil's motions, its searches, `C-w` for windows, `SPC` for the leader |
| normal state | `i` | insert state |
| insert state | `C-z` | Emacs state, and the dictionary keys |

`diogenes-evil-normal-state-key` is the first of those, `ESC` by default
because in Emacs state it does nothing else.

- `diogenes-evil-emacs-state-modes` is the list: lookup, analysis, search, forms, corpora.
- **The browser is not in it.** Its only single-letter key is `q`, so normal state costs almost nothing and buys evil's motions in a text you are reading. Almost: the browser loads the next page when you move past the last line, by remapping `next-line`, and evil's `j` is `evil-next-line` — so the arrow keys page and `j` does not. Add `diogenes-browser-mode` to the list if you would rather have the paging.
- `diogenes-corpus-edit-mode` is not in it either: it is the one buffer meant to be typed in.
- A mode whose state you have set yourself is left alone — an explicit `evil-set-initial-state` in your config wins.
- `diogenes-evil-manage-initial-states` nil disables the whole thing, for anyone who would rather bind the letters into normal state by hand. That costs `o d p b t g G` inside dictionary buffers and keeps `j` and `k`.

The dictionaries have the single letters when you want a dictionary, and evil
has the keyboard when you want to move about.

## A frame with only a startup page in it

Whatever module you load, and with none, a lookup made from a frame showing
only `*doom*`, `*spacemacs*`, `*dashboard*` or Emacs's own splash **reuses
that window** rather than splitting it or opening a frame beside it. There is
a window there and nothing in it worth keeping.

`diogenes-home-buffer-names` is the list, and the distributions' own
variables are consulted too, so a renamed home buffer is still recognised.

## Window management

Nothing to load and nothing to choose: three modules install themselves when
what they integrate with is present, and do nothing when it is not.

| Module | Active when | What it tells the environment |
| --- | --- | --- |
| `diogenes-purpose` | `window-purpose` is loaded | what kind of buffer a lookup is, so purpose does not file it under `edit` and show it in the window you were reading |
| `diogenes-evil` | `evil` is loaded | that the read-only buffers are Emacs-state, so the single-letter dictionary keys reach the dictionaries |
| `diogenes-doom` | Doom (optional) | commands for moving between the frames |

None of the three is Spacemacs- or Doom-specific in what it does.
**window-purpose is an ordinary package** — Spacemacs enables it for everyone,
which is how most people meet it, but anyone may load it — and so is
persp-mode, whose buffer claiming is in the core for the same reason.

### Four behaviours

There are four ways the windows can behave, and each has a name:

| | |
| --- | --- |
| `defer` | whatever is installed decides — window-purpose, a popup manager, plain `display-buffer`. The default |
| `reuse` | one window for entries, each replacing the last |
| `split` | an entry gets a window of its own beside the text, and later entries share it |
| `frames` | each kind in a frame of its own, entries gathered into the lookup frame |

`split` gives a window the first time and reuses it after — splitting again
for every entry would fill the frame with the same word. And all three of the
non-`defer` behaviours end by splitting **regardless of
`split-height-threshold`**: a distribution may set those so that no frame you
actually have can be split — Spacemacs ships 80 against a frame of 68 lines —
and without that fallback `split` would quietly become `reuse`.

`frames` switches the gathering on by itself. Whether a *new* buffer gets a
frame at all is `pop-up-frames`, which stays yours, since it governs the whole
of Emacs.

Those four names are also the four **built-in presets**, so
`M-x diogenes-load-preset` offers them with nothing configured and switching
between them is one command. A preset can hold much more than a behaviour, and
one of your own replaces a builtin of the same name — see [Presets](#presets).

### Choosing one at startup

Name it in your configuration and it is loaded when Diogenes loads:

```elisp
(use-package diogenes
  :init
  ;; One of the four. No folder needed: they are presets in their own right.
  (setq diogenes-preset "split"))
```

For a preset of your own, say where the presets live as well — a name is no use
without it:

```elisp
(use-package diogenes
  :init
  (setq diogenes-preset-directory "~/.emacs.d/diogenes-presets/")
  (setq diogenes-preset "reading"))
```

Both in `:init`, so the name is set before the package reads it. Leave
`diogenes-preset` unset and nothing is loaded until you ask with
`M-x diogenes-load-preset`.

### Setting a behaviour yourself

If you want one of the four and do not expect to switch, say so directly:

```elisp
(setq diogenes-window-behaviour 'split)
```

That is the same thing the builtin preset does, and shorter. Two differences
worth knowing:

- A preset is loaded **after** your init file, so if you set both, the preset
  wins. Use one or the other.
- `diogenes-preset "split"` means *whatever `split` names*, so writing a
  `split.el` of your own replaces it. The variable always means the behaviour.

`M-x diogenes-list-presets` shows nothing loaded when you set the variable
directly. That is correct rather than a fault: you have set a behaviour, not
loaded a preset.

### One behaviour per kind, and the rest in detail

`diogenes-window-behaviour` also takes an **alist**, so the three kinds need
not agree:

```elisp
(setq diogenes-window-behaviour '((lookup . split) (browser . frames)))
```

A kind the alist does not mention is deferred rather than guessed at. Beneath
that, three actions take precedence, and are consulted per kind — so naming
one leaves the other two on the shorthand:

| Set | To say |
| --- | --- |
| `diogenes-lookup-display-action` | where an entry or an analysis appears |
| `diogenes-browser-display-action` | where a passage appears |
| `diogenes-dictionary-display-action` | where a scanned page appears |
| `diogenes-split-direction` | `below`, `above`, `right`, `left`, or nil to let Emacs choose |
| `diogenes-split-from` | `selected`, `largest` or `root` — which window is divided |
| `diogenes-split-size` | lines, columns, or a fraction |
| `diogenes-gather-frames` | whether each kind shares a frame (follows `pop-up-frames`) |
| `diogenes-frame-parameters` | what a Diogenes frame asks for; the `name` is matchable by a tiling WM |
| `diogenes-claim-buffers` | whether a perspective is told about the buffer |

A named split direction **asks Emacs nothing**, which is the point: a
distribution may set `split-height-threshold` so that no frame you actually
have can be split — Spacemacs ships 80 against a frame of 68 lines — and then
`split` would quietly become `reuse`.

An action you set takes precedence over all three modules. Two things it
cannot override, because neither is about layout: a `C-c C-c` chain stays in
one window, and a frame holding only a startup page yields it.

#### What to write

All of these go in `:init`, or in a preset — both are read before the display
happens.

```elisp
;; How a window is made. A named direction asks Emacs nothing.
(setq diogenes-split-direction 'right)   ; below, above, right, left, or nil
(setq diogenes-split-from 'selected)     ; selected, largest, or root
(setq diogenes-split-size 0.4)           ; a fraction of what is divided...
(setq diogenes-split-size 30)            ; ...or lines, or columns
(setq diogenes-split-size                ; ...or one share per kind
      '((lookup . 0.4) (dictionary . 0.55)))

;; Frames.
(setq diogenes-gather-frames 'auto)      ; auto follows pop-up-frames; t, or nil
;; Anything `make-frame' takes. The NAME is the useful one: it is what a
;; tiling window manager matches on to place these frames by rule.
(setq diogenes-frame-parameters
      '((name . "Diogenes")))

;; A width and a height are deliberately not in the default, and are a bad
;; idea under a tiling manager: it assigns the space, and a frame that asks
;; for a size it cannot have leaves part of its tile empty. Under a floating
;; manager they are reasonable.
(setq diogenes-frame-parameters
      '((name . "Diogenes") (width . 100) (height . 45)))

;; Perspectives. Both are the defaults, so write them only to change them.
(setq diogenes-claim-buffers nil)         ; nil to stay out of them entirely
(setq diogenes-claim-buffer-function 'auto) ; auto, a function, or nil
```

**On perspectives.** persp-mode and perspective.el give each workspace its own
buffer list, and `switch-to-buffer`, `C-x <left>` and the buffer menu show only
what belongs to the one you are in. A buffer has to be *added* to that list, and
persp-mode does it by watching the ordinary ways buffers appear —
`find-file`, `switch-to-buffer`. Diogenes uses neither: it creates a buffer and
displays it, which can slip past that watch, and the result is a buffer you are
looking at that `C-x <left>` will not return to, though
`switch-to-buffer` still finds it if you type the whole name.

So Diogenes adds each buffer itself, as it is displayed —
`diogenes-claim-buffers`, on by default. `diogenes-claim-buffer-function` is how:
`auto` detects which of the two packages is running, since they share both a
minor-mode name and a `persp-add-buffer` function; give it a function of your own
for a package neither branch handles. Set `diogenes-claim-buffers` to nil and
Diogenes stays out of your perspectives, with the consequence above.

The three **display actions** take a `display-buffer` action, which is a cons
of *(FUNCTIONS . ALIST)* — so a list of functions needs the outer parentheses
as well:

```elisp
;; An entry beside the text: reuse a lookup window if there is one, else split.
(setq diogenes-lookup-display-action
      '((diogenes-display-in-role-frame display-buffer-pop-up-window)))

;; With an alist entry as well.
(setq diogenes-browser-display-action
      '((display-buffer-reuse-window display-buffer-pop-up-window)
        (inhibit-same-window . t)))

;; A single function may be written bare.
(setq diogenes-dictionary-display-action '(display-buffer-same-window))
```

`'(diogenes-display-in-role-frame display-buffer-pop-up-window)` without the
outer parentheses means *one* function and an alist entry called
`display-buffer-pop-up-window`, which is nothing, and the action is ignored.
The extra pair is easy to lose and the failure is silent, so it is worth
checking against these examples.

`diogenes-display-in-role-frame` is the package's own: it reuses a window or
frame already showing a buffer of the same kind, which is what keeps a second
entry from splitting again. `diogenes--display-split-anyway` splits without
asking `split-window-sensibly` for permission, and is worth having last in any
action of your own for the reason given above.

### What each module does now

**`diogenes-purpose`** tells window-purpose what our buffers are, by mode and
by name. Required from `diogenes.el` and installing itself when
window-purpose appears, in either load order — there is nothing to add to an
init file.

Names do the work rather than modes. A lookup buffer is created, displayed,
and only *then* put into `diogenes-lookup-mode` — so at the moment purpose
classifies it the mode is still `fundamental-mode`, and a mode table has nothing
to say about it. `diogenes-purpose-regexp-purposes` matches on the name, which
is settled when the buffer is made.

| | |
| --- | --- |
| `diogenes-purpose-manage-purposes` | nil leaves purpose's own configuration alone |
| `diogenes-purpose-regexp-purposes` | names to purposes; what actually works |
| `diogenes-purpose-mode-purposes` | modes to purposes; kept, and true once the mode is set |
| `diogenes-purpose-extra-name-purposes` | for grouping dictionary PDFs, which are named after their files |

**`diogenes-evil`** tells evil that the read-only buffers are Emacs state, so
the single-letter dictionary keys reach the dictionaries. Also automatic. See
[Under evil](#under-evil-doom-spacemacs-with-evil).

**`diogenes-doom`** gives you four commands for moving between the frames:
`diogenes-doom-focus-lookup-frame`, `-browser-frame`, `-dictionary-frame`, and
`diogenes-doom-delete-frames`, which closes them all.

Everything about where buffers go is core and applies whatever you run:

| | |
| --- | --- |
| `diogenes-gather-frames` | whether each kind shares a frame |
| `diogenes-frame-parameters` | what a Diogenes frame asks for |
| `diogenes-role-regexps` | which buffers count as which kind — add a dictionary PDF here to give the scans a frame of their own |
| `diogenes-claim-buffers` | whether persp-mode or perspective.el is told about the buffer, so `C-x <left>` can reach it |

`diogenes-doom-gather`, `diogenes-doom-frame-parameters`,
`diogenes-doom-claim-buffers` and `diogenes-doom-dictionary-regexps` are
aliases for the first four.

## Presets

The settings you want are not one set but several, and which you want depends
on what you are doing: reading at length, glancing at one word while writing,
the machine with the small screen. Those differ in a dozen variables at once.

A preset is an ordinary Lisp file that sets them:

```elisp
;;; my-preset.el --- Diogenes preset  -*- lexical-binding: t -*-
;; Description: entries beside the text, scans in their own frame
(setq diogenes-window-behaviour '((lookup . split) (dictionary . frames)))
(setq diogenes-split-direction 'right)
```

**The folder is optional.** `M-x diogenes-load-preset` offers `defer`, `reuse`,
`split` and `frames` whether one is set or not — the four behaviours are
presets in their own right. Set `diogenes-preset-directory` when you have a
file of your own to keep.

**A file replaces a builtin of the same name.** Write `split.el` and `split` is
what your file says.

| | |
| --- | --- |
| `M-x diogenes-load-preset` | offers the builtins and whatever is in the folder, annotated with each `Description` line |
| `M-x diogenes-list-presets` | what exists, which are files, which was loaded |
| `M-x diogenes-preset-write-current` | writes this session's settings out as a preset |
| `diogenes-preset` | a preset to load at startup, by name |

`diogenes-preset` takes a name, not a behaviour: `(setq diogenes-preset
"my-preset")` loads that file, where `(setq diogenes-window-behaviour 'my-preset)`
would be a display rule that does not exist. Set both
`diogenes-preset-directory` and `diogenes-preset` in `:init`, so the name is
there before the package reads it.

A preset is loaded after your init file, so it wins over it: an init file holds
what is true of the machine — the dictionary paths — and a preset what is true
of what you are doing now. `diogenes-preset-write-current` writes only the
options that differ from their standard value, so a preset says what is
particular about it and nothing else.

### Building one in a browser

[**Open the preset builder**](https://htmlpreview.github.io/?https://raw.githubusercontent.com/VictorSousa92/diogenes.el/modular-customizable/tools/diogenes-preset-builder.html#presets)
— or fetch [`tools/diogenes-preset-builder.html`](tools/diogenes-preset-builder.html)
and open it locally, which is the same thing without the intermediary:

```fish
curl -O https://raw.githubusercontent.com/VictorSousa92/diogenes.el/modular-customizable/tools/diogenes-preset-builder.html
xdg-open diogenes-preset-builder.html
```

It needs no server and no dependencies. Choose how the windows should behave
and it draws what that does, step by step: browse a text, look a word up, look
up another, follow a word *inside* an entry, open the OLD, open the TLL, close
the page. Then it hands you the file, and the two lines your init file needs.

The simulation applies the same rules in the same order the package does, and
says which rule decided each step — a `C-c C-c` chain staying put, a lone
startup window being taken, a second entry joining the first rather than
splitting again, `q` returning to the entry.

The tool has two tabs, and the `#` at the end of a link chooses which opens:
`#presets` for this one, `#configuration` for the other. Without a fragment it
opens on Configuration.

GitHub serves a `.html` in a repository as text rather than as a page, so the
plain repository link shows the source; the first link goes through
htmlpreview, which fetches the file and renders it. To be rid of the
intermediary, enable GitHub Pages for the repository and the builder is at
`https://victorsousa92.github.io/diogenes.el/tools/diogenes-preset-builder.html#presets`.

# Appendix: other commands

Everything below is reachable from the transient menu (`M-x diogenes`) as
well. `M-x diogenes-cheatsheet` lists whatever is bound in the buffer you are
in; this is the rest.

**Building an XML dictionary** — once, from its TEI source. Pressing the
dictionary's key with nothing built offers to run these for you.

- `diogenes-gaffiot-build-dictionary`
- `diogenes-bailly-build-dictionary`
- `diogenes-georges-build-dictionary`
- `diogenes-pape-build-dictionary`
- `diogenes-dge-build-dictionary`

**Prebuilt page indexes** — optional, one per machine, for the
directory-based print dictionaries. See [Prebuilt indexes](#prebuilt-indexes-passow-tgl-bailly).

- `diogenes-passow-build-index`, `diogenes-tgl-build-index`, `diogenes-bailly-build-index`

**Forgetting a cached page index** — after replacing or re-bookmarking a PDF
while Emacs is running.

- `diogenes-old-clear-cache`, `diogenes-tll-clear-cache`
- `diogenes-montanari-clear-cache`, `diogenes-cambridge-clear-cache`, `diogenes-bdag-clear-cache`
- `diogenes-gaffiot-pdf-clear-cache`, `diogenes-georges-pdf-clear-cache`
- `diogenes-passow-clear-cache`, `diogenes-tgl-clear-cache`, `diogenes-bailly-clear-cache`

**Morphology beyond a single lookup**

- `diogenes-show-all-forms-latin` / `-greek` — every attested form of a lemma
- `diogenes-show-all-lemmata-latin` / `-greek` — every lemma and form matching a query
- `diogenes-analysis-cycle` — fold a heading in an analysis buffer

**Opening a print dictionary by name**, rather than by its key from an
entry. Each takes a word, or a prefix argument to be asked for one.

- `diogenes-lookup-open-old`, `diogenes-lookup-open-tll-or-tgl` (Latin gives the TLL, Greek the TGL)
- `diogenes-lookup-open-montanari`, `diogenes-lookup-open-cambridge`, `diogenes-lookup-open-bdag`, `diogenes-lookup-open-passow`, `diogenes-lookup-open-tgl`
- `diogenes-lookup-open-gaffiot-pdf`, `diogenes-lookup-open-bailly-pdf`, `diogenes-lookup-open-georges-pdf`

**Diagnostics**

- `diogenes-list-dictionaries` — which dictionaries are declared, offered, and what their paths hold
- `diogenes-tgl-explain` — how a word is resolved in the TGL: collation key, volume, caps opening, index neighbourhood, the column and page it settles on

**Text utilities**, on the region or the buffer

- `diogenes-strip-diacritics`, `diogenes-remove-hyphenation`, `diogenes-iota-subscript-to-adscript`, `diogenes-apostrophe`

**Corpora**

- `diogenes-manage-user-corpora`, `diogenes-add-user-corpus`

**Searching and browsing** have one command per corpus, with the same seven
suffixes throughout — `tlg`, `phi`, `ddp`, `ins`, `chr`, `cop`, `misc`:

- `diogenes-search-tlg` … `diogenes-search-misc`
- `diogenes-browse-tlg` … `diogenes-browse-misc`
- `diogenes-dump-tlg` … `diogenes-dump-misc`

**In a search-result buffer**

- `diogenes-search-next` / `diogenes-search-previous` — between hits
- `diogenes-search-browse-passage` — open the hit in Browser Mode
- `diogenes-search-delete` — drop a hit from the list

**Moving in a browser or lookup buffer.** The arrow keys and `C-c C-n` /
`C-c C-p` are the everyday way; the commands behind them are
`diogenes-browser-forward-line`, `-backward-line`,
`-beginning-of-buffer`, `-end-of-buffer`, `-lookup`, `-quit`, and the same
five named `diogenes-lookup-…`. `diogenes-lookup-lewis-or-lsj` is `l`, the
way back to the language's own dictionary. `diogenes-undo` undoes in a
read-only buffer.

**Windows, with `window-purpose`**

- `diogenes-purpose-focus-lookup-window`, `diogenes-purpose-focus-browser-window`
- `diogenes-purpose-focus-dictionary-window` — bound to `Q` in a dictionary buffer, the way back from the page to the entry it came from
- `diogenes-purpose-install`, `diogenes-purpose-uninstall` — the purposes are installed for you; these are for putting them back after taking them out within a session

**Frames**

- `diogenes-doom-focus-lookup-frame`, `diogenes-doom-focus-browser-frame`, `diogenes-doom-focus-dictionary-frame`
- `diogenes-doom-delete-frames` — closes every frame holding nothing but Diogenes buffers

**Presets**

- `diogenes-load-preset`, `diogenes-list-presets`
- `diogenes-preset-write-current` — writes this session's settings to a named preset

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
