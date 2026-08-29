;;; diogenes-cheatsheet.el --- A floating key cheatsheet -*- lexical-binding: t -*-

;;; Commentary:

;; `diogenes-cheatsheet' pops up a floating panel listing the keys of
;; whichever Diogenes buffer you are in -- lookup, browser or print
;; dictionary -- and dismisses it on the next keystroke.
;;
;; No external tool is involved.  Emacs has had child frames since 26, and a
;; child frame IS an overlay: a real frame, undecorated, positioned over its
;; parent, outside the window layout, so nothing is split, resized or
;; buried.  `notify-send' and friends would be worse here, not better --
;; they truncate, they cannot be dismissed on a keystroke, they lose the
;; faces, and on Wayland they queue behind whatever the notification daemon
;; is doing.  On a terminal frame, where there are no child frames, this
;; falls back to an ordinary help window.
;;
;; The listing is GENERATED from the live keymaps rather than written out
;; here, so it cannot drift: the print-dictionary keys each module registers
;; through `diogenes-lookup-register-dictionary', and the keys for going from
;; one Diogenes window or frame to another, appear because they are in the maps,
;; not because this file knows about them.

;;; Code:

(require 'cl-lib)

;; Defined by `diogenes-perseus.el', which this module does not require: the
;; cheatsheet reads whatever keymaps and registry happen to be loaded and
;; says nothing about the rest, so it guards every use with `fboundp' or
;; `boundp' rather than pulling the lookup machinery in.  Declared only to
;; keep the byte-compiler quiet about the reference.
(declare-function diogenes--lookup-dict-available-p "diogenes-perseus"
                  (predicate))

(defvar diogenes-lookup-mode-map)
(defvar diogenes-analysis-mode-map)
(defvar diogenes--lookup-dictionaries)
(defvar diogenes-browser-mode-map)
(defvar diogenes-purpose-dict-mode-map)

(defgroup diogenes-cheatsheet nil
  "A floating cheatsheet of Diogenes keys."
  :group 'diogenes)

(defcustom diogenes-cheatsheet-command-prefixes
  '("diogenes-lookup-open-" "diogenes-lookup-" "diogenes-browser-"
    "diogenes-focus-" "diogenes-old-" "diogenes-tgl-" "diogenes-pdf-"
    "diogenes-purpose-focus-" "diogenes-purpose-" "diogenes--" "diogenes-")
  "Prefixes stripped from a command name to label it, longest first.
`diogenes-lookup-open-montanari' becomes \"montanari\"."
  :type '(repeat string)
  :group 'diogenes-cheatsheet)

(defcustom diogenes-cheatsheet-max-height 0.8
  "How tall the cheatsheet panel may grow.
A number of lines, or a fraction of the frame\='s height.  Sections that do
not fit are moved into further columns rather than being cut off, so this
governs the shape of the panel more than how much of it you see."
  :type '(choice natnum float)
  :group 'diogenes-cheatsheet)

(defcustom diogenes-cheatsheet-column-gap 3
  "Spaces between the columns of the cheatsheet panel."
  :type 'natnum
  :group 'diogenes-cheatsheet)

(defface diogenes-cheatsheet-title
  '((t :inherit shr-h2))
  "Face for the cheatsheet's section titles."
  :group 'diogenes-cheatsheet)

(defface diogenes-cheatsheet-key
  '((t :inherit help-key-binding))
  "Face for the keys listed in the cheatsheet."
  :group 'diogenes-cheatsheet)

(defface diogenes-cheatsheet-group
  '((t :inherit font-lock-comment-face))
  "Face for the cheatsheet's group headings within a section."
  :group 'diogenes-cheatsheet)

(defface diogenes-cheatsheet-border
  '((t :inherit shadow))
  "Face supplying the child frame's border colour."
  :group 'diogenes-cheatsheet)


;;;; Gathering the keys

(defcustom diogenes-cheatsheet-labels
  '((diogenes-old-visit-dictionary . "the scanned page")
    (diogenes-focus-browser        . "the text")
    (diogenes-focus-lookup         . "the entry")
    (diogenes-focus-morphology     . "the analysis")
    (diogenes-focus-dictionary     . "the scanned page")
    (diogenes-pdf-search           . "look a word up")
    (diogenes-tgl-open-index-here  . "the index, around this word")
    (diogenes-browser-remove-hyphenation  . "join divided words")
    (diogenes-browser-reinsert-hyphenation . "divide them again")
    (diogenes-evil-normal-state    . "normal state"))
  "Labels to use instead of the one made from a command's name.
An alist of (COMMAND . LABEL).  Stripping the prefixes off
`diogenes-old-visit-dictionary\=' leaves `old visit dictionary\=', which says
what the function is called and not what pressing the key does -- and in a
section headed `Going between the windows and frames\=' the useful label is `the
scanned page\='.

Only for the names that read badly.  Most do not need an entry:
`diogenes-lookup-open-montanari\=' becomes `montanari\=', which is exactly right."
  :type '(alist :key-type function :value-type string)
  :group 'diogenes-cheatsheet)

(defun diogenes-cheatsheet--label (command)
  "A short human label for COMMAND."
  (or
   (cdr (assq command diogenes-cheatsheet-labels))
   (let ((name (symbol-name command)))
    (cl-loop for prefix in diogenes-cheatsheet-command-prefixes
	     when (string-prefix-p prefix name)
	     do (setq name (substring name (length prefix)))
	     and return nil)
     (replace-regexp-in-string "-" " " name))))

(defcustom diogenes-cheatsheet-uninteresting-commands
  '(self-insert-command undefined digit-argument negative-argument
    ignore mouse-drag-region mouse-set-point mouse-set-region
    newline indent-for-tab-command)
  "Commands never listed, however they are bound.
Editing and mouse commands a reader has no need to be told about; the
browser is a `text-mode' buffer and inherits a good many of them."
  :type '(repeat symbol)
  :group 'diogenes-cheatsheet)

(defun diogenes-cheatsheet--interesting-p (event definition)
  "Whether EVENT bound to DEFINITION belongs in the cheatsheet."
  (and (symbolp definition)
       (commandp definition)
       (not (memq definition diogenes-cheatsheet-uninteresting-commands))
       (not (eq event 'remap))
       (not (eq event 'menu-bar))
       (not (eq event 'tool-bar))
       ;; A cons EVENT is a range of characters -- the whole printable
       ;; alphabet bound to `self-insert-command', and the like.
       (not (consp event))
       (let ((description (key-description (vector event))))
	 (not (string-match-p "\\`<\\(mouse\\|down-mouse\\|drag-mouse\\|menu\\)"
			      description)))))

(defun diogenes-cheatsheet--walk (keymap &optional prefix)
  "The (KEY-DESCRIPTION . COMMAND) pairs of KEYMAP, PREFIX prepended.
Recurses into prefix keymaps, which is the whole point: the browser keeps
its commands under `C-c C-', and a walk that stopped at the first level
would report the prefix and none of what it leads to."
  (let ((prefix (or prefix []))
	out)
    (map-keymap
     (lambda (event definition)
       (let ((keys (vconcat prefix (vector event))))
	 (cond
	  ;; `remap' is not a prefix but a pseudo-keymap: a binding under it
	  ;; says "wherever COMMAND would run, run this instead", so the key is
	  ;; whatever the user has bound COMMAND to.  Descending into it yields
	  ;; rows like `<remap> <scroll-up-command>', which name no key at all;
	  ;; the remapped command is already listed under its real key.
	  ((memq event '(remap menu-bar tool-bar)) nil)
	  ;; A prefix: descend.  `keymapp' covers both a keymap and a symbol
	  ;; whose function definition is one.
	  ((and (keymapp definition) (not (consp event)))
	   (setq out (nconc out (diogenes-cheatsheet--walk definition keys))))
	  ((diogenes-cheatsheet--interesting-p event definition)
	   (setq out (nconc out (list (cons (key-description keys)
					    definition))))))))
     keymap)
    out))

(defun diogenes-cheatsheet--bindings (keymap)
  "The (KEY-DESCRIPTION . COMMAND) pairs KEYMAP itself provides.
The parent is dropped first.  `map-keymap' walks inherited bindings as
well, so for `diogenes-browser-mode-map', whose parent is `text-mode-map',
the listing would otherwise be mostly Emacs and hardly Diogenes at all."
  (let ((own (copy-keymap keymap)))
    (set-keymap-parent own nil)
    (cl-delete-duplicates (diogenes-cheatsheet--walk own)
			  :key #'cdr :from-end t)))

(defcustom diogenes-cheatsheet-navigation-commands
  '(diogenes-lookup-next diogenes-lookup-previous
    diogenes-lookup-forward-entry diogenes-lookup-backward-entry
    diogenes-lookup-headword diogenes-lookup-first-headword
    diogenes-browser-forward diogenes-browser-backward
    scroll-up-command scroll-down-command
    beginning-of-buffer end-of-buffer)
  "Commands counted as navigation rather than as anything else.
Moving about within an entry, or from one entry to the next.  Consulted
before the dictionary registry, so a command listed here is never taken for
a dictionary opener."
  :type '(repeat function)
  :group 'diogenes-cheatsheet)

(defun diogenes-cheatsheet--dictionary-entry (command)
  "The registry entry whose `:command' is COMMAND, or nil."
  (cl-find-if (lambda (entry) (eq (plist-get entry :command) command))
	      (and (boundp 'diogenes--lookup-dictionaries)
		   diogenes--lookup-dictionaries)))

(defun diogenes-cheatsheet--dictionary-title (entry)
  "The group heading a dictionary ENTRY belongs under.
Language first, since a reader of Latin has no use for the Greek keys, and
`:lang' is in the registry already.  Within a language, a print dictionary
\(`:show' `always') is separated from the electronic ones."
  (let ((lang (pcase (plist-get entry :lang)
		("latin" "Latin")
		("greek" "Greek")
		(_ nil)))
	(kind (if (eq (plist-get entry :show) 'always)
		  "print dictionaries"
		"dictionaries")))
    (if lang
	(format "%s %s" lang kind)
      (capitalize kind))))

(defun diogenes-cheatsheet--dictionary-by-id (id)
  "The registry entry whose `:id' is ID, or nil."
  (and id
       (cl-find-if (lambda (entry) (eq (plist-get entry :id) id))
		   (and (boundp 'diogenes--lookup-dictionaries)
			diogenes--lookup-dictionaries))))

(defun diogenes-cheatsheet--companions (entry)
  "The registry entries that are companions of ENTRY sharing its key.
A PDF registers as `:name \"PDF\" :of bailly', and the Bailly's PDF goes
further: it shares `B' with the dictionary and binds nothing itself,
because one command dispatches on which of the two you are looking at.
Listing them as separate rows would print `B' twice and be wrong about
both, so ENTRY's row names them together instead."
  (let ((key (plist-get entry :key))
	(id (plist-get entry :id)))
    (cl-remove-if-not
     (lambda (other)
       (and (not (eq other entry))
	    (eq (plist-get other :of) id)
	    (equal (plist-get other :key) key)))
     (and (boundp 'diogenes--lookup-dictionaries)
	  diogenes--lookup-dictionaries))))

(defun diogenes-cheatsheet--dictionary-label (entry)
  "The label for a dictionary ENTRY: its name, its parent, its companions.
A companion offered under the same key is named in the same row, with the
buffer it is reached from -- `Bailly, or PDF in Bailly' -- since that is
what pressing the key actually does.  A companion with a key of its own
gets its own row, labelled with the dictionary it belongs to: `Gaffiot:
PDF' rather than a bare `PDF' adrift in the list."
  (let* ((name (or (plist-get entry :name) ""))
	 (parent-entry (diogenes-cheatsheet--dictionary-by-id
			(plist-get entry :of)))
	 (parent-name (or (and parent-entry (plist-get parent-entry :name))
			  (and (plist-get entry :of)
			       (capitalize (symbol-name (plist-get entry :of))))))
	 (shared (diogenes-cheatsheet--companions entry)))
    (cond
     ;; A companion with its own key.  `when-current' means the registry
     ;; offers it ONLY inside the buffer of the dictionary named by `:of',
     ;; so the key does something else everywhere else -- Gaffiot\='s PDF and
     ;; Pape both answer to `P\=' -- and a label that did not say so would be
     ;; telling the reader to press a key that will not work.
     ((and parent-name (not (diogenes-cheatsheet--shares-parent-key-p entry)))
      (if (eq (plist-get entry :show) 'when-current)
	  (format "%s: %s (in %s only)" parent-name name parent-name)
	(format "%s: %s" parent-name name)))
     ;; A dictionary one of whose companions shares its key.
     (shared
      (format "%s, or %s in %s"
	      name
	      (mapconcat (lambda (other) (or (plist-get other :name) "?"))
			 shared "/")
	      name))
     ;; `unless-current' -- an electronic dictionary withheld in its own
     ;; buffer -- is deliberately NOT annotated: it covers five of the
     ;; dictionaries, and "Gaffiot (not in Gaffiot)" on every row would say
     ;; the obvious at the cost of the ones worth reading.
     (t name))))

(defun diogenes-cheatsheet--shares-parent-key-p (entry)
  "Whether ENTRY is a companion offered under its parent's own key.
Such an entry needs no row of its own: the parent's row names it."
  (let ((parent (diogenes-cheatsheet--dictionary-by-id (plist-get entry :of))))
    (and parent (equal (plist-get entry :key) (plist-get parent :key)))))

(defconst diogenes-cheatsheet--group-order
  '("Navigation"
    "Latin print dictionaries" "Latin dictionaries"
    "Greek print dictionaries" "Greek dictionaries"
    "Print dictionaries" "Dictionaries"
    ;; `Windows' was the old name and is kept, harmlessly, for anyone whose
    ;; configuration still produces it; the rule now says the longer thing,
    ;; which is what a reader needs to see.
    "Going between the windows and frames" "Windows"
    "Other")
  "The order the groups appear in, whichever of them turn out to be used.")

(defun diogenes-cheatsheet--configured-p (binding)
  "Whether BINDING should be shown, given what this user has installed.
A key that opens a dictionary is worth listing only when the dictionary is
there: the registry's own availability test decides, the same one that
keeps an unconfigured dictionary out of an entry's link banner, so the
cheatsheet and the banner never disagree.  A key that is not a dictionary
opener at all -- navigation, windows, quitting -- is always shown.

Keys shared between two dictionaries are shown as long as either of them
is available: `t' is worth listing for a reader who has the TLL and not the
TGL, and the command dispatches on the language anyway."
  (let* ((command (cdr binding))
         (entries (cl-remove-if-not
                   (lambda (entry) (eq (plist-get entry :command) command))
                   (and (boundp 'diogenes--lookup-dictionaries)
                        diogenes--lookup-dictionaries))))
    (or (null entries)
        (not (fboundp 'diogenes--lookup-dict-available-p))
        (cl-some (lambda (entry)
                   (diogenes--lookup-dict-available-p
                    (plist-get entry :available-p)))
                 entries))))

(defun diogenes-cheatsheet--classify (bindings)
  "Group BINDINGS into (GROUP-TITLE . LINES) pairs, in a fixed order.
Each line is (KEY . LABEL).  A dictionary is grouped by language and kind
from its registry entry, and a PDF companion is labelled with the
dictionary it belongs to; everything else is sorted by what its command
does."
  (let ((groups (mapcar #'list diogenes-cheatsheet--group-order)))
    (dolist (binding bindings)
      (let* ((key (car binding))
	     (command (cdr binding))
	     (name (symbol-name command))
	     (entry (diogenes-cheatsheet--dictionary-entry command))
	     (title
	      (cond
	       ((memq command diogenes-cheatsheet-navigation-commands)
		"Navigation")
	       (entry (diogenes-cheatsheet--dictionary-title entry))
	       ;; Going from one window or FRAME to another.  Both spellings:
	       ;; `diogenes-focus-*\=' is where these live now, and
	       ;; `diogenes-purpose-focus-*\=' is what they were called when only
	       ;; window-purpose had them -- a reader may still have one bound.
	       ((or (string-prefix-p "diogenes-focus-" name)
		    (string-prefix-p "diogenes-purpose-focus-" name)
		    (eq command 'diogenes-old-visit-dictionary))
		"Going between the windows and frames")
	       ;; Fallbacks: a dictionary that registered no :command, or a
	       ;; key bound before the registry existed.
	       ((string-prefix-p "diogenes-lookup-open-" name)
		"Print dictionaries")
	       ((string-match-p "\\(next\\|previous\\|forward\\|backward\\|scroll\\)"
				name)
		"Navigation")
	       (t "Other")))
	     (label (if entry
			(diogenes-cheatsheet--dictionary-label entry)
		      (diogenes-cheatsheet--label command)))
	     (cell (or (assoc title groups)
		       (car (push (list title) groups)))))
	(push (cons key label) (cdr cell))))
    (cl-loop for title in (append diogenes-cheatsheet--group-order
				  (mapcar #'car groups))
	     for cell = (assoc title groups)
	     when (and cell (cdr cell))
	     collect (prog1 (cons title (nreverse (cdr cell)))
		       (setcdr cell nil)))))

(defun diogenes-cheatsheet--sections ()
  "The sections to show, as a list of (TITLE . BINDINGS).
Only maps that exist are included, and the map of the current buffer comes
first, so the panel answers \"what can I press HERE\" before anything else."
  (let* ((here (cond ((derived-mode-p 'diogenes-lookup-mode) 'lookup)
		     ((derived-mode-p 'diogenes-analysis-mode) 'analysis)
		     ((derived-mode-p 'diogenes-browser-mode) 'browser)
		     ((bound-and-true-p diogenes-purpose-dict-mode) 'dict)))
	 (all
	  (delq
	   nil
	   (list
	    (when (boundp 'diogenes-lookup-mode-map)
	      (list 'lookup "Lookup" diogenes-lookup-mode-map))
	    (when (boundp 'diogenes-browser-mode-map)
	      (list 'browser "Browser" diogenes-browser-mode-map))
	    (when (boundp 'diogenes-analysis-mode-map)
	      (list 'analysis "Analysis" diogenes-analysis-mode-map))
	    (when (boundp 'diogenes-purpose-dict-mode-map)
	      (list 'dict "Print dictionary" diogenes-purpose-dict-mode-map))))))
    (cl-loop for (tag title map) in (append
				     (cl-remove-if-not
				      (lambda (s) (eq (car s) here)) all)
				     (cl-remove-if
				      (lambda (s) (eq (car s) here)) all))
	     for bindings = (cl-remove-if-not
			     #'diogenes-cheatsheet--configured-p
			     (diogenes-cheatsheet--bindings map))
	     when bindings
	     collect (cons (if (eq tag here) (concat title "  (here)") title)
			   bindings)
	     into out
	     finally return
	     (let ((out (diogenes-cheatsheet--lift-common out))
		   (entry (diogenes-cheatsheet--entry-points))
		   ;; The prefixed variants, which the maps cannot supply: `C-u L'
		   ;; is `L' given an argument, and no keymap holds it.
		   (prefixed (diogenes-cheatsheet--prefixed)))
	       (append out
		       (when prefixed (list (cons "With a prefix" prefixed)))
		       (when entry (list (cons "Getting in" entry))))))))

(defcustom diogenes-cheatsheet-prefixed
  '((diogenes-pdf-search "L" "the word under point, or one you type")
    (diogenes-pdf-search "C-u L"
                         "its ROOT, for a badly-OCR\u2019d word -- and in tomes I-IV \
of the TGL, an index reference such as `t.3 c.746\'")
    ;; One rule, said once: a prefixed letter looks a word up IN that
    ;; dictionary, the XML where there is one.  Bare, the letter does that too
    ;; -- except inside that dictionary's own entry, where it reaches the print.
    (diogenes-lookup-bailly "C-u <letter>"
                            "look a word up in that dictionary -- the XML where \
it has one")
    (diogenes-lookup-bailly "B, g, G"
                            "inside that dictionary's own entry, the printed page")
    (diogenes-browser-forward "C-c C-n" "the next page of the passage")
    (diogenes-browser-forward "C-u 5 C-c C-n" "five pages on")
    (diogenes-browser-backward "C-u 5 C-c C-p" "five pages back"))
  "Commands whose behaviour changes with a prefix argument.
A list of (COMMAND KEY DESCRIPTION), shown under \"With a prefix\".

Written out rather than read from the keymaps, and it has to be: a prefix
argument is not a binding.  `C-u L\=' is `L\=' given an argument, so no map has
anything to say about it, and a cheatsheet built from the maps alone can never
mention the second half of what these keys do.

`C-u\=' is Emacs\='s `universal-argument\=' and not ours to move.  Where a
distribution has taken `C-u\=' for scrolling the argument is on the leader --
`SPC u\=' under Doom and Spacemacs -- and `M-1\=' serves anywhere; the commands
ask only whether they were given an argument, not how.

WHAT THE PREFIX MEANS is the same for every dictionary letter: `ask me which
word\='.  It does NOT switch between a dictionary's XML and its print.  What does
that is pressing the letter again INSIDE that dictionary's own entry -- `g\=' in a
Gaffiot entry opens Gaffiot's printed page, and `C-u g\=' there looks another word
up in the XML instead.  Bailly, Gaffiot and Georges are the three with both.

For a print-only dictionary -- the OLD, Montanari, the CGL, the BDAG, Passow,
the TGL -- the letter opens the scan and the prefix asks which word to open it
at.  `C-u L\=' inside a scan is the exception that does more, and it is listed
above.

A command absent from this installation is left out, as elsewhere."
  :type '(repeat (list function string string))
  :group 'diogenes-cheatsheet)

(defun diogenes-cheatsheet--lift-common (sections)
  "SECTIONS with the bindings common to all of them in a section of their own.
A binding is common when the SAME KEY runs the SAME COMMAND in every Diogenes
buffer -- the keys for going between the windows, `q\=', and whatever else is
bound everywhere.  Listed once under `Everywhere\=' and taken out of the rest.

Both halves of that test are needed.  The same key doing different things is
not common but a coincidence: `i\=' opens the TGL index in a TGL volume and is
`evil-insert-state\=' elsewhere, and listing it once would say something false
about both.  So the pair is compared, not the key.

Where there is only one section there is nothing to have in common, and it is
returned untouched -- a reader with one Diogenes buffer open wants its keys, not
a separate panel saying they are also available in it."
  (if (< (length sections) 2)
      sections
    (let* ((first (cdr (car sections)))
           (common
            (cl-remove-if-not
             (lambda (pair)
               (cl-every (lambda (section)
                           (cl-find pair (cdr section)
                                    :test (lambda (a b)
                                            (and (equal (car a) (car b))
                                                 (eq (cdr a) (cdr b))))))
                         (cdr sections)))
             first)))
      (if (null common)
          sections
        (append
         (list (cons "Everywhere" common))
         (cl-loop for section in sections
                  for rest = (cl-remove-if
                              (lambda (pair)
                                (cl-find pair common
                                         :test (lambda (a b)
                                                 (and (equal (car a) (car b))
                                                      (eq (cdr a) (cdr b))))))
                              (cdr section))
                  when rest collect (cons (car section) rest)))))))

(defun diogenes-cheatsheet--prefixed ()
  "The (KEY . DESCRIPTION) pairs for `diogenes-cheatsheet-prefixed\='."
  (cl-loop for (command key description) in diogenes-cheatsheet-prefixed
	   when (fboundp command)
	   collect (cons key description)))

(defcustom diogenes-cheatsheet-entry-points
  '(diogenes
    diogenes-lookup-lewis diogenes-lookup-lsj
    diogenes-parse-latin diogenes-parse-greek
    diogenes-browse-latin diogenes-browse-greek
    diogenes-search-latin diogenes-search-greek
    diogenes-lookup-search-entries
    diogenes-cheatsheet)
  "Commands listed under \"Getting in\", wherever they happen to be bound.
These are reached from outside a Diogenes buffer, so they are in no mode
map: each is shown with its global key if it has one, otherwise as
\\`M-x\\='.  Commands that do not exist in this installation are left out."
  :type '(repeat function)
  :group 'diogenes-cheatsheet)

(defun diogenes-cheatsheet--entry-points ()
  "The (KEY-OR-M-x . COMMAND) pairs for `diogenes-cheatsheet-entry-points'."
  (cl-loop for command in diogenes-cheatsheet-entry-points
	   when (fboundp command)
	   collect (cons (let ((keys (where-is-internal command nil t)))
			   (if keys (key-description keys) "M-x"))
			 command)))

(defun diogenes-cheatsheet--blocks ()
  "The cheatsheet as a list of blocks, each block a list of lines.
One block per section, kept whole: a section is never split down the middle
by a column break."
  (let ((sections (diogenes-cheatsheet--sections)))
    (unless sections
      (user-error "No Diogenes keymaps are loaded"))
    (cl-loop
     for section in sections
     collect
     (cons (propertize (car section) 'face 'diogenes-cheatsheet-title)
	   ;; The prefixed section carries STRINGS where the others carry
	   ;; commands, its entries being descriptions of what an argument does
	   ;; rather than bindings -- so it goes round `--classify', which reads a
	   ;; command's name to decide the group and would fail on a string.
	   (if (equal (car section) "With a prefix")
	       (cl-loop for (key . label) in (cdr section)
			collect (format "  %s  %s"
					(propertize (format "%-11s" key)
						    'face 'diogenes-cheatsheet-key)
					label))
	   (cl-loop
	    for group in (diogenes-cheatsheet--classify (cdr section))
	    append (cons (propertize (format " %s" (car group))
				     'face 'diogenes-cheatsheet-group)
			 (cl-loop for (key . label) in (cdr group)
				  collect (format "  %s  %s"
						  (propertize (format "%-11s" key)
							      'face
							      'diogenes-cheatsheet-key)
						  label)))))))))

(defun diogenes-cheatsheet--group-start-p (line)
  "Whether LINE begins a group within a section.
A group heading has one leading space and a key line two, which is how the
lines are built a few forms above.  Read from the shape rather than from the
face, so that a section rendering its own way -- `With a prefix\=' does -- is
treated as one group and not cut up."
  (and (stringp line)
       (> (length line) 1)
       (eq (aref line 0) ?\s)
       (not (eq (aref line 1) ?\s))))

(defun diogenes-cheatsheet--split-block (block height)
  "BLOCK as a list of blocks, none taller than HEIGHT.
Cut at GROUP boundaries, so a section too tall for the panel continues in the
next column with its groups intact.  The parts after the first are titled
`... (continued)\=', or a reader meets a column of keys belonging to nothing
they can see.

A block was previously allowed to overflow, on the reasoning that a panel
running long is better than a section cut in half.  It does not run long: the
frame is clamped to the parent, so the overflow is simply not shown -- the
Lookup section, with a group for each language and each kind of dictionary, lost
its last lines mid-word.

Where a single GROUP is taller than the room, there is nothing to cut at and it
is cut at the height; that is a section with thirty dictionaries in it, and
half of it visible beats none."
  (if (or (null height) (<= (length block) height))
      (list block)
    (let* ((title (car block))
           (continued (concat title "  (continued)"))
           (parts nil)
           (current nil)
           (used 1)                     ; the title line
           (first t))
      (dolist (line (cdr block))
        (when (and (>= (1+ used) height)
                   ;; Cut before a group where there is one to cut before, and
                   ;; at the height where there is not.
                   (or (diogenes-cheatsheet--group-start-p line)
                       (>= used height)))
          (push (cons (if first title continued) (nreverse current)) parts)
          (setq current nil used 1 first nil))
        (push line current)
        (setq used (1+ used)))
      (when current
        (push (cons (if first title continued) (nreverse current)) parts))
      (nreverse parts))))

(defun diogenes-cheatsheet--columnate (blocks height)
  "Distribute BLOCKS into columns no taller than HEIGHT.
A block taller than HEIGHT is split at its group boundaries and continues in
the next column -- see `diogenes-cheatsheet--split-block\='.  It used to be
allowed a column of its own and to overflow, which meant being clipped, the
frame being clamped to the parent's size."
  (let (columns current (used 0))
    (dolist (block (cl-mapcan (lambda (b)
                                (diogenes-cheatsheet--split-block b height))
                              blocks))
      (let ((size (1+ (length block))))	; a blank line between blocks
	(when (and current (> (+ used size) height))
	  (push (nreverse current) columns)
	  (setq current nil used 0))
	(setq current (append (list block) current)
	      used (+ used size))))
    (when current (push (nreverse current) columns))
    (nreverse columns)))

(defun diogenes-cheatsheet--paste (columns)
  "Join COLUMNS side by side.  Returns (TEXT WIDTH HEIGHT)."
  (let* ((gap (make-string diogenes-cheatsheet-column-gap ?\s))
	 (texts (mapcar (lambda (column)
			  (let ((lines nil))
			    (dolist (block column)
			      (setq lines (append lines block '(""))))
			    lines))
			columns))
	 (widths (mapcar (lambda (lines)
			   (apply #'max 1 (mapcar #'string-width lines)))
			 texts))
	 (height (apply #'max 1 (mapcar #'length texts))))
    (list
     (cl-loop
      for row below height
      concat (concat
	      (cl-loop
	       for lines in texts
	       for width in widths
	       for first = (eq lines (car texts))
	       concat (concat (unless first gap)
			      (let ((line (or (nth row lines) "")))
				(concat line
					(make-string
					 (max 0 (- width (string-width line)))
					 ?\s)))))
	      "\n"))
     (+ (apply #'+ widths)
	(* diogenes-cheatsheet-column-gap (max 0 (1- (length widths)))))
     height)))

(defun diogenes-cheatsheet--render (&optional available-height available-width)
  "The cheatsheet laid out in columns.  Returns (TEXT WIDTH HEIGHT).
AVAILABLE-HEIGHT is how many lines there is room for and AVAILABLE-WIDTH how
many columns of characters; between them they decide how the sections are
spread.

The WIDTH is the part that was missing, and it is what made the panel crop.
Columns were packed to fit the height alone, the frame was then clamped to the
parent's width, and whatever did not fit was simply not shown -- a section
missing altogether, with nothing to say it was there.  So: pack, measure, and
where the result is too wide, pack again with a taller allowance, which puts
more into each column and so uses fewer of them.  Repeated until it fits or
until the columns are as tall as the blocks themselves, at which point one
column is all there is and the panel scrolls instead."
  (let* ((blocks (diogenes-cheatsheet--blocks))
	 (height (or available-height 40))
	 (width (or available-width 80))
	 (tallest (apply #'max 1 (mapcar #'length blocks)))
	 (result (diogenes-cheatsheet--paste
		  (diogenes-cheatsheet--columnate blocks height))))
    ;; AND NOTHING MORE.  An earlier version, finding the result too wide, packed
    ;; again with a taller allowance -- fewer columns, less width.  Which works,
    ;; and trades a horizontal crop for a vertical one: the height is the room
    ;; the frame has, so a column taller than it is cut off the bottom, which is
    ;; exactly what a reader reported.  Growing the height to fix the width is
    ;; robbing one to pay the other.
    ;;
    ;; So the layout keeps to the height it was given, and the CALLER decides
    ;; what to do when the result will not fit -- `diogenes-cheatsheet' shows it
    ;; in a help window, which scrolls, rather than in a panel that cannot.
    (ignore tallest)
    result))


;;;; Showing it

(defvar diogenes-cheatsheet--frame nil
  "The child frame currently showing the cheatsheet, if any.")

(defconst diogenes-cheatsheet--buffer-name " *diogenes-cheatsheet*")

(defun diogenes-cheatsheet--buffer (text)
  "A buffer holding TEXT, prepared for display in the panel."
  (with-current-buffer (get-buffer-create diogenes-cheatsheet--buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert text))
    (setq-local mode-line-format nil
		header-line-format nil
		cursor-type nil
		truncate-lines t
		show-trailing-whitespace nil)
    (setq buffer-read-only t)
    (goto-char (point-min))
    (current-buffer)))

(defun diogenes-cheatsheet--delete-frame ()
  "Take the cheatsheet down."
  (when (frame-live-p diogenes-cheatsheet--frame)
    (delete-frame diogenes-cheatsheet--frame))
  (setq diogenes-cheatsheet--frame nil))

(defun diogenes-cheatsheet--show-child-frame (buffer width height)
  "Show BUFFER, WIDTH by HEIGHT, in a child frame over the selected frame.
The panel is transient and shows one buffer, so the frame is made with
everything that would otherwise decide what a new frame displays turned
off.  `initial-buffer-choice' is the one that matters: a configuration
which sets it -- Spacemacs sets it to a function returning its home buffer
-- has that buffer pulled into a window as the frame comes up, and it is
the window BEHIND the panel that is left showing it.  The reported symptom
was the home screen appearing in place of a dictionary entry on pressing
the cheatsheet key.

`after-make-frame-functions' is bound away for the same reason, a hook
there being free to display whatever it likes; `display-buffer-alist' so
that no display rule, and no `window-purpose' redirection, has a say; and
the parent's own window is put back if something got past all three."
  (let* ((parent (selected-frame))
	 (parent-window (selected-window))
	 (parent-buffer (window-buffer parent-window))
	 (char-w (frame-char-width parent))
	 (char-h (frame-char-height parent))
	 (left (max 0 (/ (- (frame-pixel-width parent) (* width char-w)) 2)))
	 (top (max 0 (/ (- (frame-pixel-height parent) (* height char-h)) 3)))
	 (frame
	  (let ((initial-buffer-choice nil)
		(inhibit-startup-screen t)
		(after-make-frame-functions nil)
		(display-buffer-alist nil))
	    (make-frame
	     `((parent-frame . ,parent)
	       (minibuffer . nil)
	       (undecorated . t)
	       (no-accept-focus . t)
	       (no-focus-on-map . t)
	       (min-width . 1) (min-height . 1)
	       (width . ,width) (height . ,height)
	       (left . ,left) (top . ,top)
	       (internal-border-width . 12)
	       (child-frame-border-width . 1)
	       (left-fringe . 0) (right-fringe . 0)
	       (vertical-scroll-bars . nil)
	       (horizontal-scroll-bars . nil)
	       (menu-bar-lines . 0) (tool-bar-lines . 0)
	       (tab-bar-lines . 0)
	       (line-spacing . 0)
	       (unsplittable . t)
	       (no-other-frame . t)
	       (cursor-type . nil)
	       (desktop-dont-save . t))))))
    (set-face-background 'child-frame-border
			 (face-foreground 'diogenes-cheatsheet-border nil t)
			 frame)
    (let ((window (frame-root-window frame)))
      (set-window-buffer window buffer)
      (set-window-dedicated-p window t)
      (set-window-parameter window 'mode-line-format 'none))
    ;; Whatever the frame did on its way up, the window the reader was
    ;; looking at should still hold what it held.
    (when (and (window-live-p parent-window)
	       (buffer-live-p parent-buffer)
	       (not (eq (window-buffer parent-window) parent-buffer)))
      (set-window-buffer parent-window parent-buffer))
    (setq diogenes-cheatsheet--frame frame)))

;;;###autoload
(defun diogenes-cheatsheet ()
  "Show the Diogenes keys in a floating panel, until the next keystroke.
The keys of the current Diogenes buffer come first, then those of the other
Diogenes buffers, then the commands that get you into one.  The listing is
read from the live keymaps, so registered print dictionaries and the keys for
going between the windows appear of their own accord.

The sections are laid out in as many columns as the frame has room for, so
nothing is cut off.  On a terminal frame, where there are no child frames,
this falls back to an ordinary help window."
  (interactive)
  (let* ((parent (selected-frame))
	 (room (max 8 (- (if (floatp diogenes-cheatsheet-max-height)
			     (round (* diogenes-cheatsheet-max-height
				       (frame-height parent)))
			   diogenes-cheatsheet-max-height)
			 2))))
    (seq-let (text width height)
	(diogenes-cheatsheet--render room (- (frame-width parent) 4))
      (if (or (not (display-graphic-p))
	      ;; TOO BIG FOR A PANEL, in either direction: a child frame is
	      ;; clamped to its parent and shows nothing of what falls outside,
	      ;; so a reader loses whole sections and is not told.  A help window
	      ;; scrolls, which is the honest answer to more content than room --
	      ;; and it is the same fallback a terminal frame already takes.
	      (> width (- (frame-width parent) 4))
	      (> height room))
	  (with-help-window (help-buffer) (princ text))
	(diogenes-cheatsheet--delete-frame)
	(diogenes-cheatsheet--show-child-frame
	 (diogenes-cheatsheet--buffer text)
	 (min width (- (frame-width parent) 4))
	 (min height (- (frame-height parent) 2)))
	(unwind-protect
	    ;; Any event takes the panel down, and is then replayed, so the key
	    ;; that dismissed it still does its job.
	    (let ((event (read-event)))
	      (when event
		(setq unread-command-events
		      (append (listify-key-sequence (vector event))
			      unread-command-events))))
	  (diogenes-cheatsheet--delete-frame))))))

(provide 'diogenes-cheatsheet)
;;; diogenes-cheatsheet.el ends here
