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
;; through `diogenes-lookup-register-dictionary', and the focus keys
;; `diogenes-purpose' adds when it is loaded, appear because they are in the
;; maps, not because this file knows about them.

;;; Code:

(require 'cl-lib)

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

(defun diogenes-cheatsheet--label (command)
  "A short human label for COMMAND."
  (let ((name (symbol-name command)))
    (cl-loop for prefix in diogenes-cheatsheet-command-prefixes
	     when (string-prefix-p prefix name)
	     do (setq name (substring name (length prefix)))
	     and return nil)
    (replace-regexp-in-string "-" " " name)))

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
    "Windows" "Other")
  "The order the groups appear in, whichever of them turn out to be used.")

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
	       ((string-prefix-p "diogenes-purpose-focus-" name) "Windows")
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
	     for bindings = (diogenes-cheatsheet--bindings map)
	     when bindings
	     collect (cons (if (eq tag here) (concat title "  (here)") title)
			   bindings)
	     into out
	     finally return (let ((entry (diogenes-cheatsheet--entry-points)))
			      (if entry
				  (append out (list (cons "Getting in" entry)))
				out)))))

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
	   (cl-loop
	    for group in (diogenes-cheatsheet--classify (cdr section))
	    append (cons (propertize (format " %s" (car group))
				     'face 'diogenes-cheatsheet-group)
			 (cl-loop for (key . label) in (cdr group)
				  collect (format "  %s  %s"
						  (propertize (format "%-11s" key)
							      'face
							      'diogenes-cheatsheet-key)
						  label))))))))

(defun diogenes-cheatsheet--columnate (blocks height)
  "Distribute BLOCKS into columns no taller than HEIGHT where possible.
A block taller than HEIGHT takes a column of its own and sets the height:
better a panel that runs long than a section cut in half."
  (let (columns current (used 0))
    (dolist (block blocks)
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

(defun diogenes-cheatsheet--render (&optional available-height)
  "The cheatsheet laid out in columns.  Returns (TEXT WIDTH HEIGHT).
AVAILABLE-HEIGHT is how many lines there is room for; it decides how many
columns the sections are spread over."
  (let* ((blocks (diogenes-cheatsheet--blocks))
	 (height (or available-height 40)))
    (diogenes-cheatsheet--paste
     (diogenes-cheatsheet--columnate blocks height))))


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
  "Show BUFFER, WIDTH by HEIGHT, in a child frame over the selected frame."
  (let* ((parent (selected-frame))
	 (char-w (frame-char-width parent))
	 (char-h (frame-char-height parent))
	 (left (max 0 (/ (- (frame-pixel-width parent) (* width char-w)) 2)))
	 (top (max 0 (/ (- (frame-pixel-height parent) (* height char-h)) 3)))
	 (frame
	  (make-frame
	   `((parent-frame . ,parent)
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
	     (desktop-dont-save . t)))))
    (set-face-background 'child-frame-border
			 (face-foreground 'diogenes-cheatsheet-border nil t)
			 frame)
    (let ((window (frame-root-window frame)))
      (set-window-buffer window buffer)
      (set-window-dedicated-p window t)
      (set-window-parameter window 'mode-line-format 'none))
    (setq diogenes-cheatsheet--frame frame)))

;;;###autoload
(defun diogenes-cheatsheet ()
  "Show the Diogenes keys in a floating panel, until the next keystroke.
The keys of the current Diogenes buffer come first, then those of the other
Diogenes buffers, then the commands that get you into one.  The listing is
read from the live keymaps, so registered print dictionaries and the
`diogenes-purpose\=' focus keys appear of their own accord.

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
    (seq-let (text width height) (diogenes-cheatsheet--render room)
      (if (not (display-graphic-p))
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
