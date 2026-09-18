;;; classicist-lookup.el --- the buffer a dictionary entry is shown in -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; WHERE AN ENTRY IS READ.  The buffer, the keys that move about in it, the
;; links a reader can follow, and the nxml buffer an entry is edited in when a
;; dictionary's XML is wrong.
;;
;; AND THE REGISTRY, which is the suite's extension point:
;; `classicist-lookup-register-dictionary' is called by fifteen dictionary
;; modules to announce themselves, and the banner at the head of an entry is
;; built from what they said.  One clause instead of the fifteen that had to
;; be added to by hand whenever a dictionary was.
;;
;; IT SITS ON `classicist-lexicon\=' and calls into the morphology three times,
;; each at a keypress: the dispatcher asks for a parse or for every attested
;; form when a reader follows a link, and `--lookup-lemma-of' is named
;; `lookup-\=' and does nothing but parse.  Declared, not required -- the
;; morphology requires this file.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'classicist-groups)
(require 'classicist-lexicon)


;; the dispatcher's two, run when a reader follows a link
(declare-function classicist--parse-and-lookup "classicist-morphology" (word lang))
(declare-function classicist--show-all-forms "classicist-morphology" (lemma lang))

;; named `lookup-' and doing nothing but parse, so it went the other way
(declare-function classicist--lookup-lemma-of "classicist-morphology" (word lang))

;; DEFINED IN THIS FILE, and the compiler cannot see it.
;; `classicist--lookup-insert-xml' sits inside `(let ((numeric-id 0)) ...)',
;; a closure over a counter so that each invalid entry gets a unique id -- and
;; a `defun' nested in a `let' is not a definition the byte-compiler counts.
;; `diogenes-perseus.el' carried three declarations of this kind for itself.
(declare-function classicist--lookup-insert-xml "classicist-lookup"
                  (xml start end buffer))

;; IN THE BROWSER, which requires nothing of this file: a word broken across a
;; line is rejoined before it is looked up, and a passage is opened when a
;; reader follows a citation out of an entry.
(declare-function classicist--browse-work "classicist-browser"
                  (options passage))

;; IN `diogenes.el', THE ENTRY POINT, so declared and not required:
;; requiring the entry point from a layer it loads is the circle this suite
;; exists to avoid.  `--perseus-path' is the one upstream patch 5 moved down
;; into a `diogenes-lemmata.el'; it was not ported here because perseus was
;; going to be cut, and now that it has been it wants a home in one of the
;; four.
(declare-function diogenes--perseus-path "diogenes" ())
(declare-function diogenes--dict-file "diogenes" (lang))

;; OPTIONAL, from `rng-valid', and called only when a reader has just tried to
;; submit invalid XML.  `check-declare' reports "file not found" for it and the
;; gate filters that: the declaration is right and the library is not on the
;; load-path.
(declare-function rng-first-error "rng-valid" ())

;; the browser's, and this layer reads it to join a word broken
;; across a line -- a variable, so a bare `defvar' says it exists
;; elsewhere without pretending to own it
(defvar classicist-browser-join-broken-words)

(defgroup classicist-lookup nil
  "The buffer a dictionary entry is read in, and the registry the\ndictionaries announce themselves to."
  :group 'classicist)

;;; What this buffer is showing

;; SIX VARIABLES, AND ONE OF THEM WAS DEFINED.  `--lookup-lang' had a `defvar'
;; fifty lines below its first assignment; the other five had none anywhere,
;; so `setq' made globals on first use -- which works, and which the compiler
;; reported as an assignment to a free variable, eleven times.
;;
;; It is also why five of them kept the old prefix: the cut renames what the
;; file DEFINES, and these were defined nowhere.

(defvar-local classicist--lookup-file nil
  "The dictionary file this buffer is showing an entry from.
Read to tell whether a lookup buffer is already showing the dictionary asked
for, and by the openers to recognise their own buffer.")

(defvar-local classicist--lookup-lang nil
  "The language of the entry in this buffer, as Diogenes names it.
\"greek\" or \"latin\".  Read by every opener that has to assert it is looking
at the right kind of dictionary.")

(defvar-local classicist--lookup-bufstart nil
  "Where this entry begins in the dictionary file.")

(defvar-local classicist--lookup-bufend nil
  "Where this entry ends in the dictionary file.
With `classicist--lookup-bufstart\=', what `classicist-lookup-next\=' and
`-previous\=' walk from: the next entry begins where this one ended.")

(defvar-local classicist--lookup-buffer nil
  "The lookup buffer an nxml buffer is editing an entry for.
Set in the nxml buffer, not in the lookup buffer: it is how
`classicist--xml-submit\=' finds its way back to the entry being fixed.")

(defvar-local classicist--lookup-entry-id nil
  "Which invalid entry the nxml buffer is editing.
A `key\=' attribute where the entry has one, and a counter where it has not --
see the closure over `numeric-id\=' in `classicist--lookup-insert-xml\='.")


(let ((numeric-id 0))
  (defun classicist--lookup-insert-xml (xml start end buffer)
    "Give the user the change to fix invalid XML in the dictionaries."
    (let* ((key (and (string-match "key=\"\\([^\"]+\\)\"" xml)
		     (match-string 1 xml)))
	   (id (or key (cl-incf numeric-id)))
	   (inhibit-read-only t))
      (message "Invalid xml in entry: Showing entry!")
      (insert (propertize (classicist--fontify-nxml xml)
			  'invalid-xml id
			  'inhibit-read-only t
			  'keymap (let ((map (make-sparse-keymap)))
				    (keymap-set map "q" #'self-insert-command)
				    map)
			  'begin start
			  'end end))
      (setq classicist--lookup-buffer buffer
	    classicist--lookup-entry-id id
	    classicist--lookup-bufstart start
	    classicist--lookup-bufend end))))

(defun classicist--lookup-xml-validate ()
  "Try to validate, parse, format and insert a corrected dictionary entry."
  (interactive)
  (let* ((id (or (get-text-property (point) 'invalid-xml)
	         (error "No XML here to validate!")))
	 (line-start (get-text-property (point) 'begin))
	 (line-end (get-text-property (point) 'end))
	 (prop-boundaries (diogenes--get-text-prop-boundaries (point)
							      'invalid-xml))
	 (xml (apply #'buffer-substring prop-boundaries))
	 (parsed (classicist--dict-parse-xml xml line-start line-end))
	 (inhibit-read-only t))
    (apply #'delete-region prop-boundaries)
    (if parsed
	(classicist--lookup-insert-and-format parsed)
      (insert (propertize (classicist--fontify-nxml xml)
			  'invalid-xml id
			  'inhibit-read-only t
			  'begin line-start
			  'end line-end)))))

(defun classicist--fontify-nxml (str)
  "Use nxml-mode to fontify a string.
All overlays added by rng-validate-mode are converted to text
properties."
  (with-temp-buffer
    (classicist-display-buffer (current-buffer))
    (insert str)
    (nxml-mode)
    (rng-validate-mode)
    (font-lock-ensure)
    (cl-loop for ov in (overlays-in (point-min) (point-max))
	     for start = (overlay-start ov)
	     for end = (overlay-end ov)
	     for values = (overlay-properties ov)
	     when (eq (plist-get values 'category) 'rng-error)
	     do (add-text-properties
		 start end
		 (list 'face 'rng-error
		       'font-lock-face 'rng-error
		       'help-echo (plist-get values 'help-echo))))
    ;; (remove-overlays)
    (let ((map (make-sparse-keymap)))
      (keymap-set map "C-c C-c" #'classicist--lookup-xml-validate)
      (keymap-set map "C-c '" #'classicist--lookup-xml-edit)
      (propertize (buffer-string)
		  'keymap map))))

(defun classicist--lookup-xml-edit ()
  "Edit a corrupt dictionary entry in XML-mode"
  (interactive)
  (let* ((id (or (get-text-property (point) 'invalid-xml)
	         (error "No corrupt XML at point to edit!")))
	 (prop-boundaries (diogenes--get-text-prop-boundaries (point)
							      'invalid-xml))
	 (xml (apply #'buffer-substring prop-boundaries))
	 (lookup-buffer (current-buffer))
	 (xml-buffer (diogenes--get-fresh-buffer "xml"))
	 (map (make-sparse-keymap)))
    (keymap-set map "C-c C-c" #'classicist--xml-submit)
    (classicist-display-buffer xml-buffer)
    (nxml-mode)
    (insert (propertize xml
			'lookup-buffer lookup-buffer
			'id id
			'prop-boundaries prop-boundaries
			'keymap map))
    (goto-char (point-min))))

(defun classicist--xml-submit ()
  "Try to submit a fixed XML dictionary entry."
  (interactive)
  (let* ((id (or (get-text-property (point) 'invalid-xml)
	         (error "No corrupt XML at point to edit!")))
	(prop-boundaries (diogenes--get-text-prop-boundaries (point)
							     'invalid-xml))
	(lookup-buffer (get-text-property (point) 'lookup-buffer))
	(xml-buffer (current-buffer))
	(invalid-xml (with-current-buffer lookup-buffer
		       (save-excursion
			 (goto-char (point-min))
			 (text-property-search-forward 'invalid-xml id t))))
	(prop-start (prop-match-beginning invalid-xml))
	(prop-end (prop-match-end invalid-xml))
	(line-start (get-text-property prop-start 'begin))
	(line-end (get-text-property prop-start 'end))
	(parsed (classicist--dict-parse-xml (buffer-string) line-start line-end))
	(inhibit-read-only t))
    (cond (parsed (kill-buffer xml-buffer)
		  ;; Back to the entry being edited, which is where we were.
		  (classicist-display-buffer lookup-buffer
					    :kind 'lookup :same-window t)
		  (delete-region prop-start prop-end)
		  (classicist--lookup-insert-and-format parsed))
	  (t (rng-first-error)))))

(defcustom classicist-lookup-show-all-entries t
  "Whether a parse shows every dictionary entry it found.
Non-nil reproduces the Diogenes application: all distinct entries named in
the analyses record are shown one after another in a single lookup buffer.
When nil, the lemmata are offered through `completing-read' and only the
chosen one is shown, though still fetched by offset rather than by a
headword search."
  :type 'boolean
  :group 'classicist-lookup)

(defcustom classicist-lookup-show-analysis t
  "Whether to head a parsed lookup with its morphological analysis.
Non-nil reproduces the application, which prints \"Perseus analysis of X\"
and the lemmata above the dictionary entries."
  :type 'boolean
  :group 'classicist-lookup)

(defvar classicist--lookup-same-window nil
  "When non-nil, show a looked-up entry in the CURRENT window.
`classicist--search-dict' normally opens each entry in a fresh
`*Diogenes Lookup*' buffer and `pop-to-buffer's it, which may split or
reuse another window.  When this variable is non-nil the fresh buffer
is shown in the window that was selected when the lookup was invoked
\(via `pop-to-buffer-same-window'), so a `C-c C-c' chain stays in one
window while the previous entry's buffer remains live (reachable with
the usual buffer/window history).  Bound by `classicist-perseus-action';
nil everywhere else keeps the old behaviour.")

(defun classicist--search-dict (word lang sort-fn key-fn &optional file)
  "Search for a word in a Diogenes dictionary.
The lines in dictionary file must be sorted according to SORT-FN,
while KEY-FN must return the key.

FILE names the dictionary to search, defaulting to LANG\'s own
\(`diogenes--dict-file\').  Another dictionary of the same language may be
passed instead -- `diogenes-gaffiot.el\' passes Gaffiot for Latin -- and
LANG then still says which language the ENTRIES are in, so `C-c C-c\',
the print-dictionary banner and the rest behave as they do for the LSJ
and Lewis & Short.

NB. This finds an entry by where its key SORTS, so it is only as good as
the file\'s order.  The Lewis & Short that comes with Diogenes is ordered
by the i-spelling of its headwords while the `key\' attributes retain the
j-spelling (the entry displayed as `iacio\' has key=\"ja^ci^o\"), so no
j-lemma can be reached this way.  This is `$do_lookup\' in Perseus.pm and
it has the same flaw there; the parse path avoids it by using the byte
offset recorded in the analyses file -- see
`classicist--lookup-dict-offset\'."
  (seq-let (xml-bytes start end exact-hit)
      (classicist--binary-search (or file (diogenes--dict-file lang))
			       sort-fn key-fn word)
    (unless exact-hit (message "No results for %s! Showing nearest entry" word))
    (classicist--show-dict-entry xml-bytes start end lang file)))

(defun classicist--dict-offset (nr)
  "Return NR as a usable dictionary offset, or nil.
NR is the first field of an analyses entry or the second of a lemmata
entry -- a byte offset into the dictionary, as a number or a string.  Zero
is make_latin_lemmata.pl\'s \"no entry\" marker rather than an offset, so it
counts as nil."
  (let ((n (cond ((integerp nr) nr)
		 ((and (stringp nr)
		       (string-match-p "\\`[[:space:]]*[0-9]+[[:space:]]*\\'"
				       nr))
		  (string-to-number nr)))))
    (and n (> n 0) n)))

(defun classicist--lookup-dict-offset (offset lang &optional file)
  "Show the dictionary entry that begins OFFSET bytes into the dictionary.
This is how Diogenes itself reaches an entry after a parse: the offset
comes from the analyses or the lemmata file, so the entry is the one the
morphological data was built against, with no headword to get wrong.
LANG is the language of the entry; FILE defaults to LANG\'s own
dictionary."
  (let ((dict (or file (diogenes--dict-file lang))))
    (seq-let (xml-bytes start end) (classicist--get-dict-line dict offset)
      (unless xml-bytes
	(error "No dictionary entry at offset %d of %s" offset dict))
      (classicist--show-dict-entry xml-bytes start end lang file))))

(defun classicist--show-dict-entry (xml-bytes start end lang &optional file)
  "Show the dictionary entry in XML-BYTES in a fresh lookup buffer.
START and END are its offsets in the dictionary file, as returned by
`classicist--binary-search\' or `classicist--get-dict-line\'; they are what
`classicist-lookup-next\' and `-previous\' walk from.  LANG says which
language the ENTRY is in, FILE which dictionary it came from.

Returns the lookup buffer."
    (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	   (lookup-buffer (diogenes--get-fresh-buffer "lookup"))
	   formatted)
      ;; A fresh buffer either way (the previous entry is never destroyed);
      ;; `classicist--lookup-same-window' only chooses WHERE to show it -- in
      ;; the calling window, or (default) via the usual `pop-to-buffer'.
      ;;
      ;; The gate is whether the optional `diogenes-purpose' module is loaded
      ;; -- NOT whether `purpose-mode' is on.  Spacemacs turns `purpose-mode'
      ;; on for everyone, so keying on that would always fire; the real
      ;; question is whether the user has opted in to giving the Diogenes
      ;; buffers their own window-purposes by loading `diogenes-purpose'.
      ;;
      ;; * `diogenes-purpose' LOADED: set the major mode BEFORE displaying, so
      ;;   purpose (whose action runs at display time and dispatches on the
      ;;   major mode) classifies the buffer as a lookup and gives it the
      ;;   lookup window instead of the browser/edit window.
      ;;
      ;; * `diogenes-purpose' NOT loaded: run the ORIGINAL sequence verbatim --
      ;;   display first, then set the mode.  This is exactly the pre-existing
      ;;   behaviour (reuse an existing window or open a new one from the
      ;;   browser; show in place on a single-window frame), and it holds
      ;;   whether or not `purpose-mode' happens to be on and whether or not
      ;;   `pop-up-frames' is set.
      ;;
      ;; In both, `classicist-lookup-mode' derives from `text-mode' and runs
      ;; `kill-all-local-variables', so the buffer-locals are assigned after.
      ;; And in either case: a frame showing only a startup page is a frame
      ;; with nothing in it, so the entry takes that window rather than
      ;; splitting it or opening a frame beside it.  `diogenes-purpose' had
      ;; this carve-out for the Spacemacs home buffer alone; it belongs here,
      ;; where it holds for Doom's dashboard and Emacs's own splash too, and
      ;; whether or not either display module is loaded.  See
      ;; `classicist--sole-home-window-p'.
      (let ((classicist--lookup-same-window
             (or classicist--lookup-same-window
                 (classicist--sole-home-window-p))))
        ;; `purpose-mode', not `(featurep 'diogenes-purpose)': our own module
        ;; is required from `diogenes.el' and so always present, where the
        ;; question is whether window-purpose is running and will classify
        ;; this buffer as it is displayed.
        (if (bound-and-true-p purpose-mode)
            ;; --- window-purpose running: mode before display ---
            (progn
              (with-current-buffer lookup-buffer
                (classicist-lookup-mode))
              (classicist-display-buffer lookup-buffer
                                        :kind 'lookup
                                        :same-window
                                        classicist--lookup-same-window))
          ;; --- otherwise: the original order, unchanged ---
          (classicist-display-buffer lookup-buffer
                                    :kind 'lookup
                                    :same-window classicist--lookup-same-window)
          (classicist-lookup-mode)))
      (setq classicist--lookup-file (or file (diogenes--dict-file lang))
	    classicist--lookup-bufstart start
	    classicist--lookup-bufend end
	    classicist--lookup-lang lang)
      ;; Paint the window BEFORE parsing.  `classicist--dict-parse-xml' runs
      ;; `xml-parse-region', which is Lisp, over the whole of the entry --
      ;; and an entry can be large: Georges gives 26 KB to `a' as a
      ;; preposition alone.  Emacs is single-threaded, so nothing is redrawn
      ;; while that runs, and on Wayland (`pgtk') a frame that has not been
      ;; redrawn is not merely stale but blank: the frame the reader was
      ;; looking at goes black for as long as the parse takes.  Showing
      ;; something first, and forcing it onto the screen, leaves the
      ;; compositor a painted surface to hold on to.
      (let ((inhibit-read-only t))
	(erase-buffer)
	(insert (propertize "Looking up ...\n" 'font-lock-face 'italic)))
      (redisplay t)
      (setq formatted (classicist--dict-parse-xml xml start end))
      (let ((inhibit-read-only t))
	(erase-buffer))
      (cond (formatted (classicist--lookup-insert-and-format formatted))
	    (t (classicist--lookup-insert-xml xml start end lookup-buffer)))
      ;; Record the first entry's headword (a fallback for the openers) and
      ;; give the entry its own clickable link banner (OLD/TLL for Latin;
      ;; Montanari, CGL, BDAG, Passow, TGL for Greek).  Navigation adds a
      ;; banner per entry too, so links follow you between entries.
      (setq classicist--lookup-headword
	    (classicist--lookup-first-headword))
      (save-excursion
	(goto-char (point-min))
	(classicist--lookup-insert-entry-links lang))
      ;; So that navigation can tell which entry point is in, once more
      ;; than one is on show.
      (classicist--lookup-mark-entry (point-min) (point-max) start end)
      lookup-buffer))

(defun classicist--lookup-insert-entry-links (lang &optional pos)
  "Insert the print-dictionary link banner for the entry at POS (point default).
Resolves that entry's own headword via `classicist--lookup-headword-at-point'
and inserts its links just before the headword, so every entry -- the one
first looked up and each later `classicist-lookup-next' / `-previous' step --
carries links that act on ITS headword.  A no-op when the entry has no
detectable headword."
  (let ((pos (or pos (point))))
    (save-excursion
      (goto-char pos)
      (let ((hw (classicist--lookup-headword-at-point pos)))
	(when hw
	  (classicist--lookup-insert-dict-links hw lang))))))


(defun classicist--lookup-assert-lang (expected dict-name)
  "Abort unless the current lookup entry's language is EXPECTED.
EXPECTED is \"greek\" or \"latin\"; DICT-NAME is the dictionary's
name, used in the error message.  The print dictionaries call this
at the start of their opener commands so that, e.g., a Greek-only
lexicon is not opened on a Latin entry and vice versa.  The check
relies on the buffer-local `classicist--lookup-lang' recorded when
the lookup buffer was built; if the language is unknown, no error
is raised."
  (let ((lang (and (boundp 'classicist--lookup-lang) classicist--lookup-lang)))
    (when (and lang (not (string= lang expected)))
      (user-error "%s is a %s dictionary, but this entry is %s"
                  dict-name
                  (capitalize expected)
                  lang))))

(defface classicist-lookup-link-key
  '((((background light)) :foreground "#a0522d" :weight bold :underline nil
     :inherit nil)
    (((background dark)) :foreground "#f0c674" :weight bold :underline nil
     :inherit nil)
    (t :weight bold :underline nil :inherit nil))
  "Face for the key hint inside a print-dictionary link, the \"t\" of \"[TLL (t)]\".
Deliberately NOT a blue: the link around it is already coloured, and a hint
in a neighbouring shade of the same colour is no hint at all.  A warm
foreground, bold, and no underline set it apart from the link whatever the
theme does with links themselves -- sienna on a light background, a soft
amber on a dark one.

To suit it to your own theme:

  M-x customize-face RET classicist-lookup-link-key RET

or, in your init file,

  (set-face-attribute \\='classicist-lookup-link-key nil
                      :foreground \"orange red\" :weight \\='bold)"
  :group 'classicist-lookup)

(defun classicist--lookup-dict-link (name key action headword help)
  "Return a clickable link reading \"[NAME (KEY)]\" for HEADWORD.
ACTION is the symbol `classicist-perseus-action' dispatches on, HELP a format
string taking the headword, and KEY the key bound to the same command --
shown in parentheses, in `classicist-lookup-link-key', so the binding can be
read off the entry instead of looked up.  KEY may be nil for a link with no
key of its own."
  (let* ((label (if key (format "[%s (%s)]" name key) (format "[%s]" name)))
         (link (propertize label
                           'font-lock-face 'link
                           'keymap classicist-perseus-action-map
                           'action action
                           'headword headword
                           'help-echo (format help headword)
                           'rear-nonsticky t)))
    (when key
      ;; The key sits between "(" and ")]", i.e. two characters from the end.
      (put-text-property (- (length label) 2 (length key))
                         (- (length label) 2)
                         'font-lock-face 'classicist-lookup-link-key
                         link))
    link))

(defvar classicist--lookup-dictionaries nil
  "Every dictionary that may appear in an entry's link banner.
A list of plists, one per dictionary, in the order they are offered.  Built
by `classicist-lookup-register-dictionary', which is how a dictionary module
announces itself: adding a dictionary to Diogenes takes no edit to this
file, and a dictionary whose module is not loaded is simply not registered
and not offered.

Before this existed, three separate places here had to be taught about
each new dictionary -- the two link lists, the per-entry choice among them,
and the action dispatch that ran a link.  A module that forgot one of the
three failed in a different way each time.")

(defcustom classicist-declared-dictionaries nil
  "Dictionaries you use, named by id, whatever their paths say.
A list of symbols: `old', `tll', `montanari', `cambridge', `bdag',
`passow', `tgl', `gaffiot', `gaffiot-pdf', `georges', `georges-pdf',
`pape', `dge', `bailly', `bailly-pdf'.  Order does not matter -- this is a
set, tested with `memq'.

A declared dictionary is offered on every entry of its language, and its
key and its link explain what to set when pressed with nothing configured.
An undeclared one is offered when its paths are set, which is what makes
an installation that declares nothing behave sensibly: configure a
dictionary and it appears.

    (setq classicist-declared-dictionaries \\='(old tll bailly tgl))

Loading a module yourself declares it too -- `(require \\='diogenes-tll)'
before `diogenes.el' loads -- and saying it both ways is harmless.  See
`diogenes--loading-bundle' for why the load-order proviso, and
\\[classicist-list-dictionaries] to see which dictionaries are declared, by
which route, and what their paths are doing."
  :type '(repeat symbol)
  :group 'classicist-lookup)

(defcustom classicist-lookup-keys
  '((classicist-perseus-action        . "RET")
    (classicist-perseus-action        . "C-c C-c")
    (classicist-lookup-in-dictionary  . "C-c C-o")
    (classicist-lookup-next           . "C-c C-n")
    (classicist-lookup-previous       . "C-c C-p")
    (classicist-lookup-open-tll-or-tgl . "t")
    (classicist-lookup-lewis          . "l")
    (diogenes--quit                 . "q"))
  "The keys of a lookup buffer, as (COMMAND . KEY).
Every key the lookup buffer binds for itself is here, so that any of them can
be moved or removed -- nil for a KEY binds nothing.  A command may appear
twice, `classicist-perseus-action\=' being on `RET\=' and `C-c C-c\=' both.

The dictionary letters are NOT here: they belong to the dictionaries, which
come and go with the modules that provide them, and
`classicist-lookup-dictionary-keys\=' answers for those.  `t\=' and `l\=' are here
because they dispatch between two dictionaries rather than naming one.

Consulted when the map is built, so set it before the package loads -- in
`:init\=' with `use-package\=', or in a preset."
  :type '(alist :key-type function
                :value-type (choice key-sequence (const :tag "Unbound" nil)))
  :group 'classicist-lookup)

(defcustom classicist-lookup-dictionary-keys nil
  "Keys for the dictionaries in a lookup buffer, overriding their defaults.
An alist of (ID . KEY), where ID is a dictionary\='s registered identifier --
`old\=', `tll\=', `gaffiot\=', `georges\=', `montanari\=', `cambridge\=', `bdag\=',
`passow\=', `tgl\=', `bailly\=', `pape\=', `dge\=', `lewis\=' -- and KEY a key
description, or nil to bind nothing at all:

    (setq classicist-lookup-dictionary-keys
          \='((old . \"O\") (gaffiot . \"F\") (bdag . nil)))

The letters the package chooses are opinionated and finite, and a reader who
consults the Gaffiot constantly and the BDAG never has better uses for `g\=' and
`b\='.  Nil frees a letter for something of your own.

The BANNER reads this too, so `[OLD (O)]\=' says what the key now is.  A
rebinding the banner did not know about would be worse than none: the offer
printed under an entry is the package telling the reader what to press."
  :type '(alist :key-type symbol
                :value-type (choice key-sequence (const :tag "Unbound" nil)))
  :group 'classicist-lookup)

(defun classicist--lookup-dictionary-key (id default)
  "The key for dictionary ID: what the reader asked for, or DEFAULT.
Returns nil where the reader asked for nil, which means bind nothing -- so a
caller must distinguish `no preference\=' from `no key\=', and consult
`classicist-lookup-dictionary-keys\=' with `assq\=' rather than reading its cdr."
  (let ((cell (assq id classicist-lookup-dictionary-keys)))
    (if cell (cdr cell) default)))

(cl-defun classicist-lookup-register-dictionary
    (id &key name lang key command help (show 'always) buffer-p of
             available-p (order 50) bind declared paths)
  "Register the dictionary ID for the entry link banner.  Idempotent.
Registering an ID already present replaces it, so a module may be reloaded.

ID is the symbol the link carries as its `action' property and the symbol
`classicist-perseus-action' dispatches on; keep it unique.  NAME is the label
shown in brackets, KEY the key bound to the same command -- shown after the
name, so the binding can be read off the entry -- and HELP a format string
taking the headword, for the echo area.  LANG is \"greek\" or \"latin\": the
language of entry the dictionary is offered on.  COMMAND is called with the
headword as its only argument.

SHOW says when the dictionary appears, and is the whole of the arrangement
the banner used to spell out by hand:

  `always'         -- a print dictionary: offered on every entry of its
                     language, so long as AVAILABLE-P says this user has
                     it.
  `unless-current' -- an electronic dictionary: offered except in its own
                     lookup buffer, where the link would lead nowhere.
                     Needs BUFFER-P, a predicate that is non-nil when the
                     current buffer is showing this dictionary.  The way
                     back to a language's own dictionary -- the LSJ, Lewis
                     & Short -- is this with `classicist--lookup-own-dictionary-p'.
  `when-current'   -- offered ONLY inside another dictionary's buffer,
                     named by OF.  This is how a printed companion to an
                     electronic dictionary is reached: Gaffiot's PDF from a
                     Gaffiot entry, Bailly's from a Bailly entry.

AVAILABLE-P, if given, is called with no arguments and must return non-nil
for the dictionary to be offered at all.  This is how a dictionary is
optional: every one of them but the LSJ and Lewis & Short passes a
predicate over its own path options, so a dictionary the user has not got
is silently absent from the banner instead of being offered and then
refusing.  The predicate is asked afresh each time an entry is drawn, so
setting a path -- or building an XML -- takes effect at once, with no
reload; it must therefore be cheap, and it must neither signal nor prompt.
`diogenes--path-usable-p' is the usual way to write one.

A dictionary with both an XML and a printed edition, such as Gaffiot,
Bailly and Georges, is available when EITHER is: its command dispatches on
which, so the one link leads to whichever the user actually has.  Its PDF
companion, registered separately with `when-current', carries the
PDF-only predicate, so the \"[PDF]\" link appears inside the entry only
when there is a PDF behind it.

DECLARED says the user asked for this dictionary by loading its module,
rather than receiving it with the bundle `diogenes.el' loads; a module
computes it at load time with `diogenes--declared-at-load-p'.  A declared
dictionary is offered whatever its paths say, AVAILABLE-P not being
consulted, so that a dictionary you use but have misconfigured explains
itself instead of disappearing.  `classicist-declared-dictionaries' declares
one the other way, by id; either is enough and both together are harmless.

PATHS is the list of option symbols this dictionary reads -- purely so
\\[classicist-list-dictionaries] can report on them.

ORDER sorts the banner, low to high; the shipped dictionaries leave gaps to
sort between.  BIND, if non-nil, binds KEY to COMMAND in
`classicist-lookup-mode-map'.  A key that must serve both languages cannot be
bound this way -- it needs a command that dispatches on
`classicist--lookup-lang', as `diogenes-lookup-pape-or-gaffiot-pdf' does --
so such modules leave BIND nil and bind the key themselves."
  (let ((entry (list :id id :name name :lang lang :key key
                     :command command :help help :show show
                     :buffer-p buffer-p :of of
                     :available-p available-p :order order
                     :bind bind :declared declared :paths paths)))
    (setq classicist--lookup-dictionaries
          (append (cl-remove id classicist--lookup-dictionaries
                             :key (lambda (e) (plist-get e :id)))
                  (list entry)))
    ;; Through the installer rather than by binding here, so that a key two
    ;; dictionaries want gets the command that chooses between them.  Binding
    ;; directly would have given it to whichever registered last.
    (when (and bind command (boundp 'classicist-lookup-mode-map))
      (classicist--lookup-install-registered-keys))
    id))

(defun classicist--lookup-dictionary (id)
  "Return the registration plist of dictionary ID, or nil."
  (cl-find id classicist--lookup-dictionaries
           :key (lambda (e) (plist-get e :id))))

(defun classicist--lookup-install-registered-keys ()
  "Bind the keys of dictionaries registered with a non-nil BIND.
Called once `classicist-lookup-mode-map' exists, for modules that registered
before it did; `classicist-lookup-register-dictionary' binds directly when it
can.  Re-registering is idempotent, so doing both is harmless."
  (let ((by-key nil))
    ;; Gather what wants each key, so that a key wanted by two dictionaries can
    ;; be given a command that chooses between them.
    (dolist (entry classicist--lookup-dictionaries)
      (let* ((id (plist-get entry :id))
             (command (plist-get entry :command))
             (key (classicist--lookup-dictionary-key id (plist-get entry :key))))
        (when (and (plist-get entry :bind) key command)
          (let ((cell (assoc key by-key)))
            (if cell
                (setcdr cell (append (cdr cell) (list entry)))
              (push (cons key (list entry)) by-key))))))
    (dolist (cell by-key)
      (let ((key (car cell))
            (entries (cdr cell)))
        (keymap-set classicist-lookup-mode-map key
                    (if (cdr entries)
                        (classicist--lookup-key-dispatcher entries)
                      (plist-get (car entries) :command)))))))

(defun classicist-lookup-dictionary-here ()
  "The dictionary this buffer is showing, as (ID NAME LANG), or nil.

Asked of the registrations rather than guessed.  Each module says how its own
buffer is recognised -- `:buffer-p' -- and what it is called, so this answers
`Montanari' or `DGE' or `Gaffiot' and not merely `greek' or `latin'.

Wanted because a citation names a dictionary: `LSJ s.v. pe/mpw III.2' is a
reference and `a Greek dictionary, pe/mpw' is not.  The language alone cannot
say which of twelve it was.

The base dictionaries are the fallback, there being no registration for the
LSJ or Lewis & Short themselves -- they are what the others are offered
BESIDE."
  (let ((lang (or (and (boundp 'classicist--lookup-lang) classicist--lookup-lang)
                  "greek")))
    ;; OF THIS LANGUAGE ONLY.  A predicate may answer for any lookup buffer
    ;; -- several ask no more than `am I in a Diogenes lookup?' -- so the
    ;; first registration in the list claimed a Greek entry for a Latin
    ;; dictionary, and an LSJ link said Lewis & Short.  The buffer says which
    ;; language it holds; a dictionary of the other cannot be what is shown.
    (or (cl-loop for entry in classicist--lookup-dictionaries
                 for predicate = (plist-get entry :buffer-p)
                 when (and predicate
                           (equal (plist-get entry :lang) lang)
                           (ignore-errors (funcall predicate)))
                 return (list (plist-get entry :id)
                              (plist-get entry :name)
                              (or (plist-get entry :lang) lang)))
        (if (equal lang "latin")
            (list 'lewis-short "Lewis & Short" "latin")
          (list 'lsj "LSJ" "greek")))))

(defun classicist-lookup-sense-here ()
  "The place in the entry at point: (HEADWORD . SENSE-PATH), or nil.

HEADWORD as the dictionary writes it, in betacode; SENSE-PATH as a reader
cites it, `III.2\=', or nil above the first sense.

The headword is looked for FORWARD as well as at point.  `orth\=' is put on the
entry by the walk, but a buffer may open above the entry element -- a banner,
a blank line -- and there the property is not yet in force."
  (let ((key (or (get-text-property (point) 'entry-key)
                 (get-text-property (point) 'orth)
                 (save-excursion
                   (goto-char (point-min))
                   (let ((match (text-property-search-forward 'entry-key)))
                     (and match (prop-match-value match))))
                 (save-excursion
                   (goto-char (point-min))
                   (let ((match (text-property-search-forward 'orth)))
                     (and match (prop-match-value match)))))))
    (and key (cons key (get-text-property (point) 'sense-path)))))

(defun classicist--lookup-key-dispatcher (entries)
  "A command opening whichever of ENTRIES matches the language being read.
Two dictionaries may want one key, and where they are of different languages
there is no conflict to resolve: `t\=' is the TLL in a Latin entry and the TGL
in a Greek one, and a reader who puts Gaffiot and Bailly both on `g\=' means the
same thing -- the French dictionary of whichever language is in front of them.

The buffer says which language it holds, so the choice needs no prompt.  Where
none of ENTRIES is of that language the first is used, which is what a reader
asking for a dictionary of the other language can only have meant."
  (lambda ()
    (interactive)
    (let* ((lang (or (and (boundp 'classicist--lookup-lang) classicist--lookup-lang)
                     "latin"))
           (match (or (cl-find lang entries
                               :key (lambda (e) (plist-get e :lang))
                               :test #'equal)
                      (car entries))))
      (call-interactively (plist-get match :command)))))

(defun classicist-lookup-install-dictionary-keys ()
  "Apply `classicist-lookup-dictionary-keys\=' to the lookup buffers.
Called for its effect after changing that option in a running Emacs; the
keys are installed at load time without it."
  (interactive)
  (when (boundp 'classicist-lookup-mode-map)
    (classicist--lookup-install-registered-keys)
    (when (called-interactively-p 'interactive)
      (message "Diogenes: dictionary keys installed"))))

(defun classicist--lookup-dict-in-buffer-p (id)
  "Non-nil if the current lookup buffer is showing dictionary ID.
Asks that dictionary's own BUFFER-P predicate, which knows how to
recognise itself -- usually by comparing `classicist--lookup-file' with the
dictionary it converted."
  (let* ((entry (classicist--lookup-dictionary id))
         (predicate (and entry (plist-get entry :buffer-p))))
    (and predicate (funcall predicate) t)))

(defun classicist--lookup-dict-available-p (predicate)
  "Non-nil if the dictionary guarded by PREDICATE is installed here.
PREDICATE is a registration's AVAILABLE-P: nil for a dictionary that needs
no configuration -- the LSJ and Lewis & Short, which come with Diogenes
itself -- and otherwise a function of no arguments that answers whether
this user has the dictionary.

Three ways of not having it are all one answer here:

  the option is unset, so the predicate returns nil;
  the module is not loaded, so the predicate is not even defined;
  the predicate signals, `diogenes-path' itself not being set yet.

None of them is an error to report from inside a redisplay, so all three
mean the same thing: leave that dictionary out of the banner.  The keys
remain bound, and pressing one still explains what to set -- see
`diogenes--require-path'."
  (cond
   ((null predicate) t)
   ((not (functionp predicate)) nil)
   (t (and (ignore-errors (funcall predicate)) t))))

(defun classicist--lookup-dict-declared-p (entry)
  "Non-nil if the user has said ENTRY's dictionary is one they use.
Two ways of saying it, either sufficient and both together harmless:

  its id is in `classicist-declared-dictionaries';
  its module was loaded by the user rather than by the bundle, which the
  module recorded at load time as DECLARED.

The first is a set, so the order it is written in means nothing.  The
second depends on load order -- see `diogenes--loading-bundle' -- which is
why the variable exists."
  (or (plist-get entry :declared)
      (and (memq (plist-get entry :id) classicist-declared-dictionaries) t)))

(defun classicist--lookup-dict-visible-p (entry)
  "Non-nil if ENTRY should be offered on the entry now on screen.
Declared first, configured second: a dictionary the user has said they use
is offered whatever its paths are doing, and one they have not is offered
when its paths are set.  Either way the SHOW rules then decide whether it
belongs on THIS entry -- see `classicist-lookup-register-dictionary'."
  (and (or (classicist--lookup-dict-declared-p entry)
           (classicist--lookup-dict-available-p (plist-get entry :available-p)))
       (pcase (plist-get entry :show)
         ('always t)
         ('unless-current
          (let ((predicate (plist-get entry :buffer-p)))
            (not (and predicate (funcall predicate)))))
         ('when-current
          (classicist--lookup-dict-in-buffer-p (plist-get entry :of)))
         (_ t))))

(defun classicist--lookup-dict-specs (lang)
  "Return (NAME KEY ID HELP) for each dictionary offered on a LANG entry.
Sorted by the registrations' ORDER; `sort' is stable, so dictionaries
sharing an order keep the sequence they were registered in, which is the
order their modules were loaded."
  (let ((entries (seq-filter
                  (lambda (e)
                    (and (equal (plist-get e :lang) lang)
                         (classicist--lookup-dict-visible-p e)))
                  classicist--lookup-dictionaries)))
    (mapcar (lambda (e)
              ;; The key as it IS, not as it was registered: a reader who has
              ;; moved the OLD to `O' must be told `O', the banner being the
              ;; package saying what to press.
              (list (plist-get e :name)
                    (classicist--lookup-dictionary-key (plist-get e :id)
                                                     (plist-get e :key))
                    (plist-get e :id) (plist-get e :help)))
            (sort entries (lambda (a b) (< (plist-get a :order)
                                           (plist-get b :order)))))))

(defun classicist--lookup-register-shipped-dictionaries ()
  "Register the dictionaries that come with Diogenes itself.
That is now only Lewis & Short -- and, from `diogenes-pape.el', the LSJ --
the two dictionaries Diogenes searches by default and so the way back from
any other dictionary of their language.  They need no AVAILABLE-P: their
files ship with Diogenes, and if they are missing nothing in this package
works at all.

Every other dictionary registers itself from its own module, with an
AVAILABLE-P that reports whether this user has it: see
`diogenes-old.el', `diogenes-tll.el', `diogenes-montanari.el',
`diogenes-cambridge.el', `diogenes-bdag.el', `diogenes-passow.el',
`diogenes-tgl.el', `diogenes-gaffiot.el', `diogenes-georges.el',
`diogenes-pape.el', `diogenes-dge.el' and `diogenes-bailly.el'.  A
dictionary whose module is not loaded is not registered, and one whose
paths are unset is registered but not offered, so an installation with no
extra dictionaries at all draws no banner and never mentions a dictionary
it does not have."
  ;; Lewis & Short: the way back to the Latin dictionary Diogenes searches
  ;; by default, so offered in any Latin entry that is not itself one.
  (classicist-lookup-register-dictionary
   'lewis :lang "latin" :name "Lewis & Short" :key "l" :order 70
   :command #'classicist-lookup-lewis
   :show 'unless-current
   :buffer-p #'classicist--lookup-own-dictionary-p
   :help "Show Lewis & Short's entry for \"%s\""))

(defun classicist--lookup-dict-declared-how (entry)
  "How ENTRY's dictionary came to be declared, as a short string."
  (let ((by-module (plist-get entry :declared))
        (by-list (memq (plist-get entry :id) classicist-declared-dictionaries)))
    (cond ((and by-module by-list) "declared (require + list)")
          (by-module               "declared (require)")
          (by-list                 "declared (list)")
          (t                       "auto"))))

(defun classicist--lookup-dict-path-report (entry)
  "What ENTRY's dictionary's own options are doing, as a list of strings.
One line per option: unset, set but not there, or set and readable.  The
middle case is the one worth seeing -- a moved volume or a mistyped path,
which shows the link and fails on being pressed."
  (let ((paths (plist-get entry :paths)))
    (if (null paths)
        (list "no paths (ships with Diogenes)")
      (mapcar
       (lambda (symbol)
         (let ((value (and (boundp symbol) (symbol-value symbol))))
           (cond
            ((not (diogenes--source-set-p value))
             (format "%s: unset" symbol))
            ((consp value)
             (format "%s: set (%d entries)" symbol (length value)))
            ((or (file-readable-p value) (file-directory-p value))
             (format "%s: %s" symbol (abbreviate-file-name value)))
            (t
             (format "%s: %s -- NOT FOUND" symbol
                     (abbreviate-file-name value))))))
       paths))))

(defun classicist-list-dictionaries ()
  "Show every registered dictionary, how it is declared, and its paths.
The answer to \"is this dictionary going to appear, and if not why not\":
each is listed with its language, its key, whether it is declared -- by
`classicist-declared-dictionaries', by having had its module loaded, or not
at all -- and what each of its own options currently holds.

A dictionary appears in an entry's link banner when it is declared, or when
its paths are set; `Offered' says which of those it manages, before the
per-entry rules about the dictionary you happen to be reading.  A module
that is not loaded at all is not here, having never registered."
  (interactive)
  (let ((entries (sort (copy-sequence classicist--lookup-dictionaries)
                       (lambda (a b)
                         (let ((la (or (plist-get a :lang) ""))
                               (lb (or (plist-get b :lang) "")))
                           (if (string= la lb)
                               (< (plist-get a :order) (plist-get b :order))
                             (string< la lb)))))))
    (with-current-buffer (get-buffer-create "*Diogenes Dictionaries*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Diogenes dictionaries\n\n" 'face 'bold))
        (insert (format "classicist-declared-dictionaries: %s\n\n"
                        (if classicist-declared-dictionaries
                            (mapconcat #'symbol-name
                                       classicist-declared-dictionaries " ")
                          "(empty -- every dictionary is path-detected)")))
        (dolist (entry entries)
          (insert (propertize (format "%s (%s)"
                                      (or (plist-get entry :name) "?")
                                      (plist-get entry :id))
                              'face 'bold))
          (insert (format "  %s" (or (plist-get entry :lang) "-")))
          (let ((key (classicist--lookup-dictionary-key (plist-get entry :id)
                                                      (plist-get entry :key))))
            (cond (key (insert (format "  key %s" key)))
                  ((plist-get entry :key)
                   (insert (format "  key %s (unbound by you)"
                                   (plist-get entry :key))))))
          (insert "\n")
          (insert (format "  %s, %s\n"
                          (classicist--lookup-dict-declared-how entry)
                          (if (classicist--lookup-dict-visible-p entry)
                              "offered here"
                            "not offered")))
          (dolist (line (classicist--lookup-dict-path-report entry))
            (insert (format "  %s\n" line)))
          (insert "\n"))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

(defun classicist--lookup-insert-dict-links (headword lang)
  "Insert clickable print-dictionary links for HEADWORD at point.
Each link reads \"[NAME (KEY)]\", the key being the one bound to the same
command in `classicist-lookup-mode-map'.

Which dictionaries those are is not decided here: each is registered by its
own module through `classicist-lookup-register-dictionary', and
`classicist--lookup-dict-specs' picks the ones this entry should offer.  For
Latin that is normally [OLD], [TLL] and [Georges], then either [Gaffiot]
-- an entry in a lookup buffer, not a PDF -- or, when the entry shown IS
Gaffiot, [Lewis & Short] leading back and [PDF] for the same page in
print; for Greek [Montanari], [CGL], [BDAG], [Passow] and [TGL], then
whichever of [Pape], [Bailly] and [LSJ] is not on screen, and [PDF] inside
Bailly.

Clicking a link (or pressing RET on it) opens that dictionary at the page
holding HEADWORD.  The links are inserted AT POINT, so the caller positions
to the top of the entry they belong to; the initial lookup and each
`classicist-lookup-next' / `-previous' step do this once per entry, so every
entry carries its own banner.

Only dictionaries this user actually has are listed: each registration's
AVAILABLE-P reads its own path options (`diogenes-old-pdf-file',
`diogenes-tll-pdf-directory', `diogenes-georges-directory',
`diogenes-georges-file', `diogenes-gaffiot-file',
`diogenes-gaffiot-pdf-file', `diogenes-montanari-pdf-file',
`diogenes-cambridge-pdf-file', `diogenes-bdag-pdf-file',
`diogenes-bailly-file', `diogenes-bailly-pdf-file',
`diogenes-passow-directory', `diogenes-tgl-directory',
`diogenes-pape-file', `diogenes-dge-file'), and an unset one drops out of
the banner rather than being offered and then refusing.  With none of them
set there are no links at all, and the whole banner -- newline included --
is omitted."
  (let ((inhibit-read-only t)
        (specs (classicist--lookup-dict-specs lang)))
    (when specs
      (save-excursion
        (let ((links (mapcar (lambda (spec)
                               (seq-let (name key action help) spec
                                 (classicist--lookup-dict-link name key action
                                                             headword help)))
                             specs))
              ;; Six Greek dictionaries do not fit one line at most widths, and
              ;; letting them run on wraps a link across two lines and pushes
              ;; the entry itself onto the end of the banner.  So break between
              ;; links, never inside one, and close with a newline of its own so
              ;; the headword always starts a line.
              (width (max 20 (or fill-column 70)))
              (column 0))
          (dolist (link links)
            (let ((len (string-width link)))
              (cond ((zerop column))               ; first link on a line
                    ((> (+ column 2 len) width)
                     (insert "\n")
                     (setq column 0))
                    (t (insert "  ")
                       (setq column (+ column 2))))
              (insert link)
              (setq column (+ column len))))
          (insert "\n"))))))

(defun classicist--lookup-first-headword ()
  "Return the first entry headword in the current lookup buffer.
Reads the `orth' text property placed on head elements by
`classicist--dict-handle-elt'.  Returns nil if none is found."
  (save-excursion
    (goto-char (point-min))
    (let ((match (text-property-search-forward 'orth nil
						(lambda (_ v) (and v t)))))
      (and match (prop-match-value match)))))

(defun classicist--lookup-headword-at-point (&optional pos)
  "Return the headword of the entry containing POS (point by default).
A lookup buffer accumulates entries as you navigate with
`classicist-lookup-next' / `classicist-lookup-previous'; each entry's
headword carries the `orth' text property (placed by
`classicist--dict-handle-elt').  The entry POS sits in is the one whose
headword is the NEAREST `orth' at or before POS, so this reads the
`orth' at POS when point is inside a headword, else searches backward;
if POS precedes the first headword, it falls back to the first `orth'
after POS.  Returns nil when the buffer has no `orth' property at all.

This is what makes the print-dictionary keys (o m c b p t) and the
per-entry link banners act on the entry the cursor is in, rather than
the entry the buffer was first opened on."
  (let ((pos (or pos (point))))
    (save-excursion
      (goto-char pos)
      (or (get-text-property pos 'orth)
          (let ((match (text-property-search-backward 'orth nil
                        (lambda (_ v) (and v t)))))
            (if match
                (prop-match-value match)
              (goto-char pos)
              (let ((m (text-property-search-forward 'orth nil
                        (lambda (_ v) (and v t)))))
                (and m (prop-match-value m)))))))))

(defun classicist--lookup-dict (word lang)
  "Search for a word in a Diogenes dictionary. Dispatcher function."
  (pcase lang
    ("greek" (let ((normalized (diogenes--beta-normalize-gravis
		     (diogenes--greek-ensure-beta word))))
	       (classicist--search-dict normalized "greek"
				      #'classicist--beta-sort-function
				      #'classicist--xml-key-fn)))
    ("latin" (classicist--search-dict word "latin"
			 #'classicist--latin-sort-function
			 #'classicist--xml-key-fn))))

(defun classicist--lookup-own-dictionary-p ()
  "Non-nil if this lookup buffer shows the language\'s own Diogenes dictionary.
That is the LSJ for Greek and Lewis & Short for Latin -- what
`classicist--lookup-dict' searches -- as opposed to another dictionary shown
through the same machinery, such as Gaffiot.  Compared by file, since that
is what a lookup buffer records."
  (and (derived-mode-p 'classicist-lookup-mode)
       (boundp 'classicist--lookup-file) classicist--lookup-file
       (boundp 'classicist--lookup-lang) classicist--lookup-lang
       (ignore-errors
         (string= (file-truename classicist--lookup-file)
                  (file-truename (diogenes--dict-file classicist--lookup-lang))))))

(defun classicist--word-at-point-for-lookup ()
  "The word at point, where a word at point could be a word to look up.
Nil in a buffer whose text is not a text: a startup screen, whose words are
English prose about Emacs, and a document viewer, whose buffer holds the bytes
of a PDF and answers `%PDF\='.

`thing-at-point\=' has no opinion about where it is, so a lookup offered
`Welcome\=' or `%PDF\=' as its default -- and a reader who pressed RET at the
prompt got a lookup of that.  A default is a guess at what the reader means,
and in those buffers there is nothing to guess from."
  (unless (or (classicist--home-buffer-p (buffer-name))
              (derived-mode-p 'pdf-view-mode 'doc-view-mode)
              (and (fboundp 'reader-mode) (derived-mode-p 'reader-mode)))
    (or
     ;; A word the text broke across two lines is one word, and looking up
     ;; either half finds nothing: no dictionary has `praeci' or `pitur'.  The
     ;; browser can tell, the citation being a text property it knows to skip,
     ;; so it is asked first.
     (and (derived-mode-p 'classicist-browser-mode)
          (bound-and-true-p classicist-browser-join-broken-words)
          (fboundp 'classicist-browser--word-at-point-joined)
          (classicist-browser--word-at-point-joined))
     (thing-at-point 'word t))))

(defun classicist--lookup-current-headword ()
  "Return the headword of the entry point is in, for the lookup commands."
  (or (classicist--lookup-headword-at-point)
      (get-text-property (point) 'orth)
      (and (boundp 'classicist--lookup-headword) classicist--lookup-headword)
      (classicist--word-at-point-for-lookup)
      (user-error "No headword found at point")))

(defun classicist--language-at-point (&optional pos)
  "The lookup language of the word at POS: \"greek\", \"latin\", or nil.
The rules `C-c C-c\=' goes by, factored out so that a second command need not
guess differently from the first.

The text-property language is only useful when it is actually a lookup
language.  In a Latin (Lewis & Short) entry the definition prose is tagged
\"english\", so a Latin word under point carries lang=\"english\" -- not nil
-- which is why keying on the property alone failed.  Only \"greek\" and
\"latin\" count; otherwise the language of the entry being read is used.

But not blindly.  Where the element says the text is neither Greek nor
Latin -- the German definitions of Pape, the English glosses of the LSJ --
falling back to a Greek entry\='s language would parse a word of prose as
Greek and answer with whatever sorts nearest.  A Greek lemma is written in
Greek letters, so Latin script under the cursor is prose and there is
nothing to look up.  Greek inside that prose is still recognised, tagged or
not.

In the browser there are no text properties to consult and no lookup
buffer: the language is the one the text is being read in.

Before any of that, the script is consulted.  A word written in Greek
letters is Greek whatever the markup says or fails to say -- and it often
fails to say: Gaffiot quotes his Greek untagged, so a Greek word in a
Gaffiot article would otherwise inherit the article\='s Latin and be parsed
as a Latin word that does not exist.  The same holds of the Greek in Lewis
& Short, in Georges, and of a Greek word a reader has typed into a buffer
of their own.  Script is the one piece of evidence that cannot be wrong
about this, so it is taken first."
  (let* ((pos (or pos (point)))
	 (prop-lang (get-text-property pos 'lang))
	 (buf-lang (or (and (boundp 'classicist--lookup-lang)
			    classicist--lookup-lang)
		       (and (boundp 'classicist--browser-language)
			    classicist--browser-language)))
	 (word (classicist--word-at-point-for-lookup)))
    (cond
     ;; Greek letters mean Greek, tagged or not.
     ((and word (string-match-p "\\cg" word)) "greek")
     ((member prop-lang '("greek" "latin")) prop-lang)
     ((and prop-lang (equal buf-lang "greek")) nil)
     (t buf-lang))))

(defun classicist--lookup-choosable-dictionaries (&optional lang)
  "The registered dictionaries a word can be looked up in, for completion.
Returns an alist of (LABEL . ENTRY).  With LANG, only that language\='s
dictionaries and the label is the name alone; without, every language\='s and
the label says which: \"Bailly (greek)\".

Only dictionaries with a `:command\=' and a `:buffer-p\=' are offered -- which
is what distinguishes an electronic dictionary, searchable by headword, from
a print one that can only be opened at a page.  `:show\=' is deliberately NOT
consulted: the point of choosing a dictionary by hand is to reach one the
banner is not offering, whether because the word is not in Lewis & Short at
all or because you are already inside the dictionary the banner would
suggest."
  (cl-loop for entry in classicist--lookup-dictionaries
	   for name = (plist-get entry :name)
	   for entry-lang = (plist-get entry :lang)
	   when (and (plist-get entry :command)
		     (plist-get entry :buffer-p)
		     name entry-lang
		     (or (null lang) (equal lang entry-lang)))
	   collect (cons (if lang name (format "%s (%s)" name entry-lang))
			 entry)))

(defcustom classicist-lookup-always-ask-dictionary nil
  "Whether the language lookup commands always ask which dictionary.
Nil, the default, sends `\\[diogenes-lookup-greek]\=' to the LSJ and
`\\[diogenes-lookup-latin]\=' to Lewis & Short, and a prefix argument asks;
non-nil asks every time and a prefix argument makes no difference.

Worth setting for a reader who works mostly in Bailly, Georges or the DGE
and finds the default an extra keystroke rather than a convenience."
  :type 'boolean
  :group 'classicist-lookup)

(defun classicist--lookup-read-args (lang prompt)
  "Read the arguments for a LANG lookup: (WORD DICTIONARY).
PROMPT is used when the default dictionary is to be searched.  DICTIONARY
is nil unless a choice was asked for, by a prefix argument or by
`classicist-lookup-always-ask-dictionary\=', in which case the prompt names
what was chosen -- so the minibuffer says what it is about to do."
  (let ((dictionary
	 (when (or current-prefix-arg classicist-lookup-always-ask-dictionary)
	   (classicist--read-dictionary lang))))
    (list (read-from-minibuffer
	   (if dictionary
	       (format "Look up in %s: " (plist-get dictionary :name))
	     prompt)
	   (classicist--word-at-point-for-lookup))
	  dictionary)))

(defun classicist--read-dictionary (lang &optional prompt)
  "Ask which of LANG\='s registered dictionaries to use; return its entry.
Signals if none is registered, which is the honest answer to a request that
cannot be met -- better than silently falling back on the default and
leaving the reader to wonder why the choice was ignored."
  (let ((alist (classicist--lookup-choosable-dictionaries lang)))
    (unless alist
      (user-error "No searchable %s dictionary is registered: \
load diogenes-bailly, -gaffiot, -georges, -pape or -dge" lang))
    (cdr (assoc (completing-read (or prompt
				     (format "Which %s dictionary: " lang))
				 alist nil t)
		alist))))

(defun classicist--lookup-word-in-dictionary (word dictionary &optional parse)
  "Show WORD in DICTIONARY, a registry entry; with PARSE, its lemma instead.
The one place that knows how to send a word to a dictionary chosen at
runtime, used by `classicist-lookup-in-dictionary\=' and by the language
commands when they are asked to offer a choice."
  (let* ((lang (plist-get dictionary :lang))
	 (command (plist-get dictionary :command))
	 (word (string-trim (or word "")))
	 (target (if parse (classicist--lookup-lemma-of word lang) word)))
    (when (string-empty-p word)
      (user-error "Nothing to look up"))
    ;; The dictionary commands assert the language of the buffer they are
    ;; called from, so that a Greek lexicon is not opened on a Latin entry.
    ;; Here the language comes from the dictionary that was chosen, which is
    ;; the whole point: let-binding the buffer-local tells the assertion the
    ;; truth about what is being looked up.  And nothing may be inherited
    ;; from the entry we are leaving: a Greek word looked up in Georges must
    ;; not carry the Greek file along with it.
    (let ((classicist--lookup-lang lang)
	  ;; Where the entry appears is NOT decided here.  Each dictionary
	  ;; command decides it -- the five XML dictionaries from their own
	  ;; `...-display-in-same-window', and only when the lookup was made
	  ;; from a lookup buffer -- so a binding made here would be
	  ;; discarded by theirs.  An earlier attempt bound it, which asked
	  ;; "Open the result in this same window?" and then ignored the
	  ;; answer.
	  (classicist--lookup-file nil))
      (unless (equal target word)
	(message "%s: looking up %s" word target))
      (funcall command target))))

(defun classicist-lookup-in-dictionary (&optional word dictionary)
  "Look a word up in a dictionary of your choosing.
Like `C-c C-c\=', but instead of going to Lewis & Short or the LSJ -- the
dictionaries Diogenes searches by default -- it asks which dictionary, of
those registered, and in which language, since the label names both.

For a word that is in neither of the default dictionaries but is in another:
a late or technical word Lewis & Short does not carry, a proper name, a
sense Bailly gives and the LSJ does not.  And for reading a Greek word in
German rather than in English, or a Latin one in French, whatever the
language of the entry you are looking at.

The language is settled the way `C-c C-c\=' settles it, by
`classicist--language-at-point\=': the word\='s own tagging where the markup says
what it is, otherwise the language of the entry or text being read.  Only
that language\='s dictionaries are then offered, since the others could not
answer.  Where the language cannot be told, it is asked for.

WORD defaults to the headword or word at point, and is parsed first, so an
inflected form reaches its lemma.  With a prefix argument, prompt for the
word as well.  DICTIONARY is a registry entry; interactively it is chosen by
completion."
  (interactive
   (let* ((lang (or (classicist--language-at-point)
		    (completing-read "Language: " '("greek" "latin") nil t)))
	  (alist (classicist--lookup-choosable-dictionaries lang))
	  (_ (unless alist
	       (user-error "No searchable %s dictionary is registered: \
load diogenes-bailly, -gaffiot, -georges or -pape" lang)))
	  (choice (completing-read (format "Look this %s word up in: " lang)
				   alist nil t))
	  (entry (cdr (assoc choice alist)))
	  ;; The word under the cursor, and only then the entry's headword.
	  ;; `classicist--lookup-current-headword' answers with the headword of
	  ;; the ARTICLE, which is what the dictionary keys want when the whole
	  ;; article is the subject -- and quite wrong here, where the point of
	  ;; the command is the word you are looking at.  Reading Gaffiot on
	  ;; `dico', it took `dico' rather than the Greek word under point;
	  ;; `dico' read as beta code is δ-ι-ξ-ο, which is how a Greek lookup
	  ;; came to answer with `δίξεστον'.  `C-c C-c' takes the word at point
	  ;; and this must agree with it.
	  (default (or (classicist--word-at-point-for-lookup)
		       (ignore-errors (classicist--lookup-current-headword))
		       "")))
     (list (if (or current-prefix-arg (string-empty-p default))
	       (read-string (if (string-empty-p default)
				(format "Look up in %s: " choice)
			      (format "Look up in %s (%s): " choice default))
			    nil nil default)
	     default)
	   entry)))
  (unless dictionary
    (user-error "No dictionary chosen"))
  (classicist--lookup-word-in-dictionary word dictionary t))

(defun classicist-lookup-lewis (&optional word)
  "Show Lewis & Short's entry for WORD in a lookup buffer.
Interactively, WORD defaults to the headword of the Latin entry at point;
with a prefix argument, prompt for it.  This is the way back from another
Latin dictionary -- Gaffiot, say -- to the one Diogenes searches by
default, and it is what the \"[Lewis & Short]\" link in a Gaffiot entry
runs."
  (interactive
   (progn
     (classicist--lookup-assert-lang "latin" "Lewis & Short")
     ;; `l' is the way BACK from another Latin dictionary; in Lewis & Short
     ;; itself it would look up the entry already on screen.
     (unless (or current-prefix-arg
                 (not (classicist--lookup-own-dictionary-p)))
       (user-error "This entry is Lewis & Short already; `g' opens Gaffiot, \
`C-u l' looks up another word here"))
     (list (if current-prefix-arg
               (read-string "Look up in Lewis & Short: ")
             (classicist--lookup-current-headword)))))
  (let ((word (string-trim (or word (classicist--lookup-current-headword))))
        (classicist--lookup-same-window
         (derived-mode-p 'classicist-lookup-mode)))
    (when (string-empty-p word)
      (user-error "No word given"))
    (classicist--lookup-dict word "latin")))

(defun classicist--lookup-mark-entry (beg end start-offset end-offset)
  "Record on the text from BEG to END which dictionary entry it is.
START-OFFSET and END-OFFSET are the entry\='s offsets in the dictionary
file.  `classicist--lookup-bufstart\=' and `-bufend\=' track only the outermost
pair on show, which is all that is needed to extend the stack at either
edge; navigating from where point happens to be needs to know which of
several stacked entries that is, so each carries its own offsets."
  (let ((inhibit-read-only t))
    (put-text-property beg end 'diogenes-entry
		       (cons start-offset end-offset))))

(defun classicist--lookup-entry-at-point ()
  "The (START . END) dictionary offsets of the entry point is in, or nil.
A separator or a link banner belongs to the entry it follows, so where
point is between entries the one before it answers."
  (or (get-text-property (point) 'diogenes-entry)
      (let ((pos (previous-single-property-change (point) 'diogenes-entry)))
	(and pos (get-text-property (1- pos) 'diogenes-entry)))
      (and (get-text-property (point-min) 'diogenes-entry))))

(defun classicist--lookup-entry-region (offsets)
  "The buffer positions (BEG . END) of the displayed entry whose OFFSETS match."
  (let ((pos (point-min))
	found)
    (while (and pos (not found))
      (let ((here (get-text-property pos 'diogenes-entry)))
	(if (equal here offsets)
	    (setq found (cons pos (or (next-single-property-change
				       pos 'diogenes-entry)
				      (point-max))))
	  (setq pos (next-single-property-change pos 'diogenes-entry)))))
    found))

(defun classicist--lookup-entry-starting-at (offset)
  "The buffer position of a displayed entry whose START offset is OFFSET."
  (let ((pos (point-min))
	found)
    (while (and pos (not found))
      (let ((here (get-text-property pos 'diogenes-entry)))
	(if (and here (= (car here) offset))
	    (setq found pos)
	  (setq pos (next-single-property-change pos 'diogenes-entry)))))
    found))

(defun classicist--lookup-insert-entry (xml-bytes start end position before)
  "Insert the entry in XML-BYTES at POSITION, and return where it begins.
A separator goes between it and what it is joined to: after the entry when
BEFORE is non-nil, since the entry then precedes what is already there, and
before it otherwise.  The inserted text is marked with its offsets by
`classicist--lookup-mark-entry\=', and given its own link banner."
  (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	 (formatted (classicist--dict-parse-xml xml start end))
	 (inhibit-read-only t)
	 (beg (copy-marker position nil))
	 (fin (copy-marker position t)))
    (goto-char position)
    (unless before (classicist--lookup-print-separator))
    (let ((entry-start (point)))
      (if formatted
	  (classicist--lookup-insert-and-format formatted)
	(classicist--lookup-insert-xml xml start end (current-buffer)))
      (goto-char fin)
      (when before (classicist--lookup-print-separator))
      (classicist--lookup-insert-entry-links classicist--lookup-lang entry-start))
    (classicist--lookup-mark-entry beg fin start end)
    (setq classicist--lookup-bufstart (min classicist--lookup-bufstart start)
	  classicist--lookup-bufend (max classicist--lookup-bufend end))
    (marker-position beg)))

(defun classicist-lookup-next (&optional n)
  "Go to the entry after the one point is in, showing it if need be.
With a numerical prefix, move on N entries.

Movement is relative to point, not to the stack: with several entries on
show, this goes to the one after the entry point is in.  Where that entry
is already displayed -- as the next of a stacked pair, or because it was
fetched before -- point simply moves to it and nothing is read; otherwise
it is fetched and inserted directly after the current entry, so that the
buffer keeps the dictionary\='s own order."
  (interactive "p")
  (unless (eq major-mode 'classicist-lookup-mode)
    (error "Not in Diogenes Lookup Mode!"))
  (dotimes (_ (max 1 (or n 1)))
    (let* ((here (or (classicist--lookup-entry-at-point)
		     (cons classicist--lookup-bufstart classicist--lookup-bufend)))
	   (wanted (1+ (cdr here)))
	   (shown (classicist--lookup-entry-starting-at wanted)))
      (if shown
	  (goto-char shown)
	(seq-let (xml-bytes start end)
	    (classicist--get-dict-line classicist--lookup-file wanted)
	  (unless xml-bytes (error "No further entries!"))
	  (goto-char (or (cdr (classicist--lookup-entry-region here))
			 (point-max)))
	  (goto-char (classicist--lookup-insert-entry xml-bytes start end
						    (point) nil)))))))

(defun classicist-lookup-previous (&optional n)
  "Go to the entry before the one point is in, showing it if need be.
With a numerical prefix, move back N entries.  The counterpart of
`classicist-lookup-next\=', and relative to point in the same way."
  (interactive "p")
  (unless (eq major-mode 'classicist-lookup-mode)
    (error "Not in Diogenes Lookup Mode!"))
  (dotimes (_ (max 1 (or n 1)))
    (let* ((here (or (classicist--lookup-entry-at-point)
		     (cons classicist--lookup-bufstart classicist--lookup-bufend)))
	   (wanted (1- (car here))))
      (seq-let (xml-bytes start end)
	  (classicist--get-dict-line classicist--lookup-file wanted)
	(unless xml-bytes (error "No further entries!"))
	(let ((shown (classicist--lookup-entry-starting-at start)))
	  (if shown
	      (goto-char shown)
	    (goto-char (or (car (classicist--lookup-entry-region here))
			   (point-min)))
	    (goto-char (classicist--lookup-insert-entry xml-bytes start end
						      (point) t))))))))

(defun classicist--lookup-parse-bibl-string (str)
  "Parse a DICT bibliography reference string.
Returns a list that classicist--browse-work can be applied to."
  (seq-let (corpus author work-and-passage)
      (split-string (replace-regexp-in-string "^Perseus:abo:" "" str)
		    ",")
    (seq-let (work &rest passage)
	(split-string work-and-passage ":")
      (let ((labels-missing
	     (- (length (diogenes--get-work-labels (list :type corpus)
						   (list author work)))
		(length passage))))
	(cond ((< labels-missing 0) (error "Too many labels! %s" str))
	      ((> labels-missing 0)
	       (setq passage (nconc passage (cl-loop for i from 1 to labels-missing
						     collect "")))))
	(list (list :type corpus)
	      (append (list author work) passage))))))

(defun classicist-lookup-forward-line (&optional N)
  (interactive "p")
  (forward-line N)
  (when (eobp) (classicist-lookup-next)))

(defun classicist-lookup-backward-line (&optional N)
  (interactive "p")
  (forward-line (- N))
  (when (bobp) (classicist-lookup-previous)))

(defun classicist-lookup-beginning-of-buffer (&optional N)
  (interactive "^P")
  (when (and (not N) (bobp))
    (classicist-lookup-previous))
  (beginning-of-buffer N))

(defun classicist-lookup-end-of-buffer (&optional N)
  (interactive "^P")
  (when (and (not N) (eobp))
    (classicist-lookup-next))
  (end-of-buffer N))

(defvar classicist-lookup-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    ;; Overrides of movement keys
    (dolist (cell classicist-lookup-keys)
      (when (cdr cell)
        (keymap-set map (cdr cell) (car cell))))
    (keymap-set map "<remap> <previous-line>"       #'classicist-lookup-backward-line)
    (keymap-set map "<remap> <next-line>"           #'classicist-lookup-forward-line)
    (keymap-set map "<remap> <beginning-of-buffer>" #'classicist-lookup-beginning-of-buffer)
    (keymap-set map "<remap> <end-of-buffer>"       #'classicist-lookup-end-of-buffer)
    ;; Keys that dispatch between two dictionaries, or between the two
    ;; languages, are bound here when the command that does the dispatching
    ;; lives here too: `t' is the TLL in Latin and the TGL in Greek, and
    ;; `l' is Lewis & Short -- redefined by `diogenes-pape--install-keys'
    ;; into the Lewis/LSJ dispatcher once Pape is loaded.  Every other
    ;; dictionary key is bound by the module that owns it, with `:bind t' in
    ;; its registration or by hand -- so a dictionary whose module is not
    ;; loaded leaves its key alone instead of binding it to a command that
    ;; does not exist.
    map)
  "Basic mode map for the Diogenes Lookup Mode.")

(define-derived-mode classicist-lookup-mode text-mode "Diogenes Lookup"
  "Major mode to browse databases."
  (make-local-variable 'classicist--lookup-file)
  (make-local-variable 'classicist--lookup-bufstart)
  (make-local-variable 'classicist--lookup-bufend)
  (make-local-variable 'classicist--lookup-lang)
  (make-local-variable 'classicist--lookup-headword)
  (setq buffer-read-only t))

(let ((cache (make-hash-table :test 'equal)))
  (defun classicist--get-all-analyses (lang)
    "Returns the entirety of an analysis file as a hash table.
This function is cached, so that it actually reads and parses teh
file only at the first call."
    (or (gethash (cons lang 'analyses) cache)
	(setf (gethash (cons lang 'analyses) cache)
	      (classicist--analyses-file-to-hashtable
	       (file-name-concat (diogenes--perseus-path)
				 (concat lang "-analyses.txt"))))))

  (defun classicist--get-analyses-index (lang)
    "Returns the indices of an analysis file written by Diogenes.
 This function is cached, so that it actually reads and parses
the file only at the first call."
    (or (gethash (cons lang 'index) cache)
	(setf (gethash (cons lang 'index) cache)
	      (classicist--read-analyses-index lang))))

  (defun classicist--get-all-lemmata (lang)
    "Returns the entirety of a lemmata file as a hash table.
 This function is cached, so that it actually reads and parses
the file only at the first call."
    (or (gethash (cons lang 'lemmata) cache)
	(setf (gethash (cons lang 'lemmata) cache)
	      (classicist--lemmata-file-to-hashtable
	       (file-name-concat (diogenes--perseus-path)
				 (concat lang "-lemmata.txt")))))))

(defun classicist-perseus-action (char)
  "Callback for the links in Diogenes Lookup and Analysis Mode."
  (interactive "d")
  (let* ((action (get-text-property char 'action))
         ;; A link to a dictionary carries that dictionary's id, and the
         ;; registry knows what to run: one clause instead of the fifteen
         ;; that had to be added to, by hand, whenever a dictionary was.
         (dictionary (classicist--lookup-dictionary action)))
    (if dictionary
        (funcall (plist-get dictionary :command)
                 (get-text-property char 'headword))
      (cl-case action
      (bibl (apply #'classicist--browse-work (classicist--lookup-parse-bibl-string
					    (get-text-property char 'bibl))))
      ;; The `lemma-nr' property is the byte offset of the entry in the
      ;; dictionary -- the first field of the analyses record, or the second
      ;; of a lemmata record, where make_latin_lemmata.pl writes 0 for "no
      ;; entry".  Seek to it when there is one; the headword search is only
      ;; the fallback (see `classicist--search-dict' on why it cannot be
      ;; trusted for Latin j-lemmata).
      (lookup (let ((offset (classicist--dict-offset
			     (get-text-property char 'lemma-nr)))
		    (lang (get-text-property char 'lang)))
		(if offset
		    (classicist--lookup-dict-offset offset lang)
		  (classicist--lookup-dict (get-text-property char 'lemma)
					 lang))))
      (forms (classicist--show-all-forms (get-text-property char 'lemma)
				       (get-text-property char 'lang)))
      (t (let* ((lang (classicist--language-at-point char))
		(word (classicist--word-at-point-for-lookup)))
	   (pcase lang
	     ((or "greek" "latin")
	      ;; Looking up a word opens its dictionary entry.  When we are
	      ;; already in a lookup buffer, offer to show it in THIS window
	      ;; (staying put) rather than popping open another one; either
	      ;; way the entry we came from stays alive.  The choice only
	      ;; matters when there is another window to pop into -- with a
	      ;; single window there is nowhere else to go, so default to
	      ;; reusing it without asking.
	      (let ((classicist--lookup-same-window
		     (and (derived-mode-p 'classicist-lookup-mode)
			  (or (= (count-windows) 1)
			      (y-or-n-p "Open the result in this same window? ")))))
		(classicist--parse-and-lookup (or word (classicist--word-at-point-for-lookup)) lang)))
	     (_ (message "C-c C-c cannot do anything useful here!")))))))))

(provide 'classicist-lookup)

;;; classicist-lookup.el ends here
