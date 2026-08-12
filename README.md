[https://github.com/user-attachments/assets/4b0297ae-f6ca-4064-b90b-f8dc320cf83a

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
(activate them by either typing RETURN when they have the point or by
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

](https://github.com/user-attachments/assets/4b0297ae-f6ca-4064-b90b-f8dc320cf83a

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
After that, clone this repository (e.g. into `~/.emacs./elisp`) and
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
(activate them by either typing RETURN when they have the point or by
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
Nitardus's package above. It is grouped here and flagged so it is clear
which parts are his work and which are mine. The features below are new;
the sections above are unchanged.)*

*(One small correction to the Installation section above, while I am at
it: the variable to set is `diogenes-path`, not `diogenes-library-path`
— the latter name does not exist in the code. And in the `use-package`
example, the `:init` line should be `(setq diogenes-path "/path/to/diogenes")`
rather than `(diogenes-path "/path/to/diogenes")`, which would try to
call a function that does not exist.)*


## Print dictionaries (PDF)

In addition to the electronic LSJ and Lewis & Short, I have added
support for a number of scanned print dictionaries, displayed as PDFs,
which diogenes.el can jump to the page for a given entry. The following
are supported, each with its own path variable that must be set before
use:

| Abbreviation | Full Name | Language | Path variable |
| --- | --- | --- | --- |
| OLD | Oxford Latin Dictionary | Latin | `diogenes-old-pdf-file` |
| TLL | Thesaurus Linguae Latinae | Latin | `diogenes-tll-pdf-directory` |
| Montanari | Brill Dictionary of Ancient Greek | Greek | `diogenes-montanari-pdf-file` |
| CGL | Cambridge Greek Lexicon | Greek | `diogenes-cambridge-pdf-file` |
| BDAG | Bauer/Danker Greek NT lexicon | Greek | `diogenes-bdag-pdf-file` |
| Passow | Passow's Handwörterbuch | Greek | `diogenes-passow-directory` |
| TGL | Estienne, Thesaurus Graecae Linguae | Greek | `diogenes-tgl-directory` |

The OLD, Montanari, CGL and BDAG are single PDFs; the TLL is a folder of
fascicle PDFs, and Passow and the TGL are folders with one
sub-directory per volume. The page index is read from each PDF's own
outline (bookmarks) and OCR text layer, so no extra data files are
needed. The features use pdf-tools when it is available, and fall back
to the built-in doc-view otherwise.

There are three ways to use them. First, every entry shown in Diogenes
Lookup Mode is now preceded by a line of clickable links — `[OLD]` and
`[TLL]` for Latin entries, `[Montanari]`, `[CGL]`, `[BDAG]`, `[Passow]`
and `[TGL]` for Greek ones. Clicking a link (or typing RETURN on it)
opens that dictionary at the page for that entry. This works for every
entry, not just the first: when you page to the next or previous entry
(`C-c C-n` / `C-c C-p`, or by scrolling past the buffer edges), the
newly loaded entry gets its own links line, carrying its own headword,
so clicking a link inside a later entry opens the page for that entry
and not for the one the buffer was originally opened on.

Second, the same openers are bound to single keys in Diogenes Lookup
Mode: `o` (OLD), `t` (TLL for a Latin entry, TGL for a Greek one), `m`
(Montanari), `c` (CGL), `b` (BDAG) and `p` (Passow). These keys act on
whichever entry the point is currently in, wherever within it the point
sits, and they recompute this on every keypress, so moving the point
into a different entry (including entries loaded with next or previous)
simply opens the right one. With a prefix argument, the opener prompts
for a word instead.

(A note on the sources: diogenes.el does not ship any of these PDFs;
you supply your own copies and point the path variables at them. The
copies I developed and tested against are, for the TGL and Passow, the
OCR'd volumes in the DAFO dataset, which can be requested from the
Bavarian State Library's Münchener Digitalisierungszentrum (MDZ) at
<https://www.digitale-sammlungen.de/en/> (see
<https://digitizedmedievalmanuscripts.org/munchener-digitalisierungszentrum-mdz>);
for BDAG (4th ed.), the copy available at
<https://isidore.co/CalibreLibrary/Bauer,%20Walter/A%20Greek-English%20Lexicon%20of%20the%20New%20Testament%20and%20Other%20Early%20Christian%20Literature%20(BDAG%204th%20ed%20(10226)/>;
and for Montanari and the CGL, personal copies I made and cannot share.
If your copy of a dictionary is paginated differently from mine, the
per-dictionary `*-page-offset` variable lets you re-align every jump
with a constant shift.)


### A caveat on OCR and bookmarks

These are scans of print books, and their machine-readable layers are
imperfect. In many respects the OCR text is defective — dropped or
garbled letters, misread diacritics, columns read out of order — and
the PDF bookmarks (part of what the page index is built from) are
frequently wrong or incomplete as well. As a result a lookup can land a
page or two off, or occasionally on the wrong entry. This is especially
worrisome in the case of the TGL: Estienne's Thesaurus is a
16th-century work set in dense, multi-column pages with heavy use of
ligatures, so its OCR is the least reliable of the set and its lookups
the most error-prone. Passow is better but not immune; the modern
typeset dictionaries (OLD, BDAG, Montanari, CGL) are the most
dependable. It is best to treat a jump as landing you in the right
neighbourhood, and to expect to nudge a page or two by hand when the
OCR was poor.

Several mechanisms already work to keep lookups on target in spite of
this, most of them specific to the TGL, where the problem bites
hardest. Instead of trusting the bookmarks alone, the TGL backbone is
built from the column numbers printed in the OCR itself, mapping a
word's column to a physical page; because those numbers are part of the
text, this is more robust than the outline (which is why
`diogenes-tgl-page-offset` normally stays 0). When an exact index
lookup misses — the OCR often drops or garbles a single letter of an
index headword — `diogenes-tgl-fuzzy-lookup` retries against index keys
that share the word's first two letters and differ from it by at most
one inserted, deleted or substituted letter. Entries printed only as
"vide …" pointers are followed to their target. And some derived
compounds that are printed under their root, with neither a column nor
a "vide" reference, can still be placed by
`diogenes-tgl-morph-fallback`, which strips a single Greek prefix and
resolves the root — but only as a last resort, only when an exact hit
on the root is found, and only when both the root and the residue are
long enough (`diogenes-tgl-morph-min-root`, default 4) that a short tail
is not mistaken for an unrelated real lemma. For any dictionary, if
your particular scan is shifted by a constant number of pages, the
`*-page-offset` variable re-aligns every jump at once.

When a TGL jump is still wrong, two commands help. In a TGL volume PDF,
`i` (`diogenes-tgl-open-index-here`) opens volume V's comprehensive
index near the word so that you can find it by eye, and
`diogenes-tgl-explain` prints exactly how a word was resolved (its
collation key, the routed volume, whether it took an exact, fuzzy,
"vide" or morphological path, and the final page), which is the
quickest way to see why a lookup went where it did.


## Searching inside an open PDF

The third and most practical way to use the print dictionaries — and
the best remedy for the OCR and bookmark problems just described — is to
search inside the PDF you already have open. The command
`diogenes-pdf-lookup-entry` — bound to `L` in pdf-view-mode and
doc-view-mode — lets you type a headword in the minibuffer and jumps the
current PDF to that entry's page. It is the in-PDF counterpart of
`diogenes-lookup-greek` and `diogenes-lookup-latin`: the same minibuffer
workflow, but it drives the print dictionary you are already reading.
When a link or one of the `o t m c b p` keys lands you on the wrong
page, you need not scroll around blindly; you can look up a different
entry (a neighbour, or an entirely unrelated word) straight from the
open scan, and re-query it as often as you like until you are on the
right page.

The command works for every one of the print dictionaries above. It
figures out which one the buffer is showing by matching the visited
file against the path variables, so a single key serves them all (the
prompt names the dictionary, e.g. "Look up in Montanari: "). The word at
point, or the PDF's current text selection, is offered as the default.
For the multi-file TLL, Passow and TGL, if the word lives in a different
fascicle or volume than the one on screen, that sibling PDF is opened
instead.

(A note on `L`: lowercase `l` is already taken in pdf-view-mode, where
it is inherited from image-mode as `image-forward-hscroll`, so the
default binding is capital `L`, for "Lookup". You can change it by
setting `diogenes-pdf-search-key` before the package loads. The setup is
already wired into the package, so nothing needs to be added to your
init file.)


## `C-c C-c` on words inside dictionary entries

I have also extended `diogenes-perseus-action` (`C-c C-c`) in Diogenes
Lookup Mode. Beyond activating the links and the words explicitly marked
as Latin or Greek in the XML — which is Nitardus's original behaviour —
it now parses and looks up the Greek or Latin word at point wherever it
occurs in an entry. It recognises the word's language in three ways: a
word explicitly marked as Latin or Greek in the XML is parsed as such;
failing that, a word written in Greek script is parsed as Greek, even
when it sits in otherwise unmarked prose; and failing that, in the Lewis
& Short (a Latin dictionary) any remaining word is parsed as Latin. In
an LSJ (Greek) entry, a word in Latin script that is not explicitly
marked is taken to be an English gloss and left alone, so `C-c C-c`
there does nothing rather than attempt a spurious parse.

So, in short: put the point on any Greek word and press `C-c C-c` to
parse it as Greek; do the same on any word in a Lewis & Short entry to
parse it as Latin. On a link, `C-c C-c` still performs the link's
action, exactly as before.
)
