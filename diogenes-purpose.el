;;; diogenes-purpose.el --- Give Diogenes buffers their own window-purpose -*- lexical-binding: t -*-

;;; Commentary:

;; window-purpose (purpose.el) is an ordinary package: Spacemacs enables it
;; for everyone, which is how most people meet it, but anyone may load it and
;; the two cases are the same.  Its action runs before
;; Emacs's normal `display-buffer' machinery -- so it, not `pop-up-frames'
;; or `display-buffer-alist', decides where a buffer is shown.  Out of the
;; box every Diogenes buffer (the browser AND every lookup) has the purpose
;; `edit', the same purpose as ordinary text/code windows.  Because purpose
;; shows a buffer in a window that already carries its purpose, a lookup
;; launched from the browser is placed in the browser's own `edit' window:
;; the lookup appears to "take over" the browser and never opens a window
;; of its own.
;;
;; This module fixes that the purpose-native way, by giving the Diogenes
;; buffers purposes of their OWN, keyed on their major mode:
;;
;;   * dictionary entries        -> purpose `diogenes-lookup'
;;   * analyses and form lists   -> purpose `diogenes-morphology'
;;   * the corpus browser        -> purpose `diogenes-browser'
;;
;; With distinct purposes, purpose keeps each family in its own window: entries
;; share one, analyses another, and the browser keeps its own, so none of the
;; three lands on top of another.  This needs no change to Diogenes.
;;
;; Dictionary PDFs are intentionally NOT purposed here.  purpose.el (at
;; least this Spacemacs version) offers no per-buffer purpose setter and
;; matches only by major mode or buffer name; a dictionary PDF is an
;; ordinary `pdf-view-mode' buffer whose name is just the file's base name,
;; with nothing to distinguish a Diogenes dictionary from any other PDF
;; without listing exact file names.  If you want the dictionary PDFs
;; purposed too, add their buffer-name entries yourself via
;; `diogenes-purpose-extra-name-purposes' (single-file dictionaries have a
;; predictable base name, e.g. "Montanari.pdf").
;;
;; Nothing to load: `diogenes.el' requires this, and it installs itself when
;; window-purpose appears, in either order.  `diogenes-purpose-manage-purposes'
;; turns that off.  The older way still works, if a configuration does it:
;;
;;   (with-eval-after-load 'window-purpose
;;     (require 'diogenes-purpose))
;;
;; It is idempotent; re-applying is safe.

;;; Code:

(require 'cl-lib)

(declare-function purpose-compile-user-configuration "window-purpose-configuration" ())
(defvar purpose-user-mode-purposes)
(defvar purpose-user-name-purposes)

;; `diogenes--home-buffer-p' and the list behind it: shared with the core,
;; so that Doom's dashboard and Emacs's splash are recognised here too.
(require 'diogenes-lisp-utils)

;; Defined in diogenes-old.el and diogenes-perseus.el, which this module does
;; not require: it is loaded from a Spacemacs user-config hook, possibly before
;; either of them.  Advising a function before it is defined is supported, and
;; the keymap is touched inside `with-eval-after-load'.
(declare-function diogenes-old--display-page-buffer "diogenes-old"
                  (buffer action other-window))
(defvar diogenes-lookup-mode-map)

(defcustom diogenes-purpose-mode-purposes
  '((diogenes-lookup-mode   . diogenes-lookup)
    (diogenes-analysis-mode . diogenes-morphology)
    (diogenes-browser-mode  . diogenes-browser))
  "Alist mapping Diogenes major modes to window-purposes.
Three families, each keeping its own window: entries, morphological analyses,
and the corpus browser.  Each entry is (MAJOR-MODE . PURPOSE).

The analyses had `diogenes-lookup' with the entries, so an analysis replaced
the entry a reader had just looked up -- which is the entry they wanted the
analysis beside.  An entry is what a dictionary says about a word and an
analysis is what the morphology says about a form; they are consulted
together."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'diogenes)

(defcustom diogenes-purpose-regexp-purposes
  '(("\\`\\*diogenes-lookup" . diogenes-lookup)
    ;; A purpose of their own, for the same reason they are a display kind of
    ;; their own: an analysis and an entry are consulted together, so purpose
    ;; must not file them in one window.
    ("\\`\\*Diogenes Analysis" . diogenes-morphology)
    ("\\`\\*Diogenes Forms" . diogenes-morphology)
    ("\\`\\*diogenes-browser" . diogenes-browser))
  "Buffer-name regexps and the window-purpose each names.
The MODE table below says the same thing and cannot be relied on, which is
why this exists: a lookup buffer is created, displayed, and only then put
into `diogenes-lookup-mode\=', so at the moment purpose classifies it the mode
is `fundamental-mode\=' and the mode table has nothing to say.  Purpose then
files the entry under `general\=' and shows it in the window the reader was
reading in.

A name is settled when the buffer is made, so this cannot be consulted too
early.  Regexps rather than plain names because every entry gets a buffer of
its own -- `*diogenes-lookup<2>*\=' and upwards."
  :type '(alist :key-type regexp :value-type symbol)
  :group 'diogenes)

(defcustom diogenes-purpose-extra-name-purposes nil
  "Extra (BUFFER-NAME . PURPOSE) pairs to add to `purpose-user-name-purposes'.
Handy for purposing dictionary PDF buffers, which are named after
their file, e.g. \\='((\"Montanari.pdf\" . diogenes-dict)
                     (\"Oxford Latin Dictionary.pdf\" . diogenes-dict))."
  :type '(alist :key-type string :value-type symbol)
  :group 'diogenes)

(defun diogenes-purpose--merge (extra alist)
  "Return ALIST with EXTRA entries added, EXTRA taking precedence.
Existing entries for a key EXTRA also defines are dropped so EXTRA
wins; unrelated entries are preserved.  Neither argument is mutated."
  (append extra
          (cl-remove-if (lambda (cell) (assoc (car cell) extra))
                        alist)))

(defcustom diogenes-purpose-reuse-home-window t
  "When non-nil, show a Diogenes buffer in the startup/home window if it is alone.
With window-purpose active, a browse or lookup normally opens in its
own purpose window.  But when the only window in the frame is the
Spacemacs startup buffer (`spacemacs-buffer-name', usually
\"*spacemacs*\"), it is nicer to reuse that single window rather than
split it or pop a new one.  This option enables that carve-out; it
takes effect only while `diogenes-purpose' is installed."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-purpose-home-buffer-names nil
  "Further buffer names to treat as a startup or home page.
Added to `diogenes-home-buffer-names', which the whole package consults and
which already covers Spacemacs, Doom, the dashboard package and Emacs's own
splash.  Used by `diogenes-purpose-reuse-home-window'."
  :type '(repeat string)
  :group 'diogenes)

(defun diogenes-purpose--home-buffer-name-p (name)
  "Non-nil if NAME is one of the recognised startup/home buffer names.
`diogenes-home-buffer-names' is the list the whole package uses -- Doom's
dashboard and Emacs's own splash as well as Spacemacs's -- and
`diogenes-purpose-home-buffer-names' adds to it, for a home buffer only
this module needs to know about."
  (and name
       (or (diogenes--home-buffer-p name)
           (member name diogenes-purpose-home-buffer-names))))

(define-obsolete-function-alias 'diogenes-purpose--overriding-action
  'purpose--action-function "modular-customizable"
  "The wrapper is gone; see below.")

;; WHAT WAS HERE, AND WHY IT WENT.
;;
;; This module used to install itself as `display-buffer-overriding-action',
;; wrapping `purpose--action-function' so that a Diogenes buffer could reuse
;; the sole startup window before purpose had its say.  purpose ADVISES
;; `display-buffer', so the wrapper ran from inside that advice -- and then
;; called `purpose--action-function' itself, a second time, from within
;; purpose's own machinery.  Once was a split; twice was a reuse.  Which is
;; why a lookup made from the browser took the browser's window on Spacemacs
;; and nowhere else, and why nothing else touched it: not the display action,
;; not `display-buffer-alist', not the thresholds, not the purposes.  None of
;; them was reached.
;;
;; The carve-out it existed for is `diogenes--sole-home-window-p' now, applied
;; by `diogenes--display-buffer' to every Diogenes buffer whether purpose is
;; loaded or not.  So the wrapper had nothing left to do but the harm.
;;
;; What remains of this module is telling purpose what our buffers ARE.  That
;; is all it should ever have done: purpose decides where a buffer goes, and
;; does it well, given the truth about the buffer.

;;;; Focus: moving between the browser, the lookup and the dictionary
;;
;; With the browser, the lookup and the dictionary each in its own window --
;; and, as Diogenes is meant to be used, the dictionary in a frame of its
;; own -- which of them has the input focus becomes a real question.
;; purpose.el decides WHERE a buffer appears; it has nothing to say about
;; focus, and across frames focus is the window manager's business rather
;; than Emacs's.  What follows is a small set of conventions, each of which
;; raises and focuses the target frame when the target is not on this one:
;;
;;   * opening a dictionary, or turning it to a new entry, focuses it;
;;   * `C-c C-e' goes to the dictionary Entry;
;;   * `C-c C-l' goes to the Lookup;
;;   * `C-c C-b' goes to the Browser.
;;
;; One key per destination, the same in all three buffers, rather than a
;; different letter according to where you happen to be: `C-c C-l' means the
;; lookup whether pressed in the browser or in a dictionary, and a key
;; pressed in the buffer it names does nothing but stay put.  Three keys and
;; three places are easier to hold than six pairings.
;;
;; Prefixed rather than bare letters because `diogenes-browser-mode' derives
;; from `text-mode' and the browser is writable -- a bare `D' there would
;; insert a D -- and because the prefixed form matches the keys the browser
;; already has: `C-c C-c' to look a word up, `C-c C-q' to quit, `C-c C-n'
;; and `C-c C-p' to page.  Note that `C-c C-c' MAKES a lookup, where
;; `C-c C-l' returns to one that exists.
;;
;; `C-c C-e' for the entry, and not the `C-c C-d' the mnemonic would
;; suggest: KDE Plasma takes `Ctrl-D' for its own window management, so that
;; sequence never reaches Emacs at all on that desktop.
;;
;; A dictionary buffer is an ordinary `pdf-view-mode' (or `doc-view-mode',
;; or `reader-mode') buffer, which as the Commentary above notes is not
;; distinguishable by mode or name.  So this tracks them itself: every
;; buffer Diogenes displays through `diogenes-old--display-page-buffer'
;; gets `diogenes-purpose-dict-mode', a minor mode whose only job is to
;; mark the buffer as a Diogenes dictionary and to carry the `Q' binding.
;; That marker is also what makes `D' able to find the dictionary again.

(defcustom diogenes-purpose-focus-dictionary t
  "Whether opening or turning a dictionary moves the focus to it.
Non-nil selects the dictionary window whenever Diogenes displays a page in
it -- opening one, or looking up a new entry while it is already on screen
-- raising and focusing its frame when, as is usual, the dictionary has a
frame to itself.  Nil leaves the focus where it was, which is Diogenes' own
behaviour."
  :type 'boolean
  :group 'diogenes)

(defvar diogenes-purpose--last-dict-buffer nil
  "The dictionary buffer Diogenes displayed most recently.
Consulted by `diogenes-purpose-focus-dictionary-window' when no window is
currently showing a dictionary.")

(defvar diogenes-purpose-dict-mode-map
  (make-sparse-keymap)
  "Keymap for `diogenes-purpose-dict-mode'.
EMPTY, and that is the point of it now: the mode still exists so that a
dictionary buffer can be recognised, and the keys it used to carry --
`C-c C-l', `C-c C-b', `C-c C-e' -- are in the core, bound by
`diogenes-focus-keys' and `diogenes-old-visit-dictionary-key' in every Diogenes
buffer including this one.

Leaving them here did more than duplicate: the cheatsheet lifts into
`Everywhere' the bindings that are the same in every section, comparing the key
AND the command, and a scan running `diogenes-purpose-focus-browser-window'
where an entry runs `diogenes-focus-browser' has the same key doing two things.
So nothing was common, nothing was lifted, and the four keys went on being
listed four times over.")

(define-minor-mode diogenes-purpose-dict-mode
  "Mark this buffer as a Diogenes print dictionary.
Turned on automatically in any PDF or document buffer Diogenes opens at an
entry's page.  Carries the focus keys -- \\<diogenes-purpose-dict-mode-map>\\[diogenes-purpose-focus-lookup-window] for the lookup \
and \\[diogenes-purpose-focus-browser-window] for the browser -- and lets
`diogenes-purpose-focus-dictionary-window' recognise the buffer as one."
  :lighter " Dio-Dict"
  :keymap diogenes-purpose-dict-mode-map)

(defun diogenes-purpose--window-with (predicate)
  "The most recently used window showing a buffer that satisfies PREDICATE.
Every visible frame is searched, not just the selected one: Diogenes is
meant to be used with the dictionary in a frame of its own, so the window
wanted is usually not on this frame at all.  PREDICATE is called with the
window's buffer current."
  (car (sort (cl-remove-if-not
              (lambda (window)
                (with-current-buffer (window-buffer window)
                  (funcall predicate)))
              (cl-loop for frame in (visible-frame-list)
                       append (window-list frame 'no-minibuffer)))
             (lambda (a b) (> (window-use-time a) (window-use-time b))))))

(defun diogenes-purpose--focus (window)
  "Give WINDOW the input focus, raising and focusing its frame if need be.
`select-window' alone is not enough across frames: it makes WINDOW current
for Lisp but leaves the window manager pointing at whatever frame had focus
before, so keys keep going to the old frame.  `select-frame-set-input-focus'
raises the frame and asks the window manager to focus it."
  (let ((frame (window-frame window)))
    (unless (eq frame (selected-frame))
      (select-frame-set-input-focus frame))
    (select-window window)
    window))

(defun diogenes-purpose--lookup-window ()
  "A window showing a Diogenes lookup or analysis buffer, or nil."
  (diogenes-purpose--window-with
   (lambda () (derived-mode-p 'diogenes-lookup-mode 'diogenes-analysis-mode))))

(defun diogenes-purpose--browser-window ()
  "A window showing the Diogenes browser, or nil."
  (diogenes-purpose--window-with
   (lambda () (derived-mode-p 'diogenes-browser-mode))))

(defun diogenes-purpose--dict-window ()
  "A window showing a Diogenes print dictionary, or nil."
  (diogenes-purpose--window-with
   (lambda () (bound-and-true-p diogenes-purpose-dict-mode))))

(defun diogenes-purpose-focus-lookup-window ()
  "Select the window showing the Diogenes lookup.
Bound to \\`Q' in a dictionary buffer: the way back from the page to the
entry it was opened from."
  (interactive)
  (let ((window (diogenes-purpose--lookup-window)))
    (if window
        (diogenes-purpose--focus window)
      (user-error "No Diogenes lookup window on any visible frame"))))

(defun diogenes-purpose-focus-dictionary-window ()
  "Select the window showing a Diogenes print dictionary.
Bound to \\`D' in a lookup buffer.  When no dictionary is on screen but one
was opened earlier in this session, it is displayed again and selected;
otherwise open one first with `o', `t', `m', `c', `b', `g', `G' or `p'."
  (interactive)
  (let ((window (diogenes-purpose--dict-window)))
    (cond
     (window (diogenes-purpose--focus window))
     ((buffer-live-p diogenes-purpose--last-dict-buffer)
      ;; Gone from the screen but still alive -- an iconified or closed
      ;; dictionary frame.  Displaying it again brings it back wherever the
      ;; configuration puts dictionaries, and then it gets the focus.
      (diogenes-purpose--focus
       (display-buffer diogenes-purpose--last-dict-buffer)))
     (t (user-error
         "No dictionary open; `o' opens the OLD, `t' the TLL, `g' Gaffiot")))))

(defun diogenes-purpose-focus-browser-window ()
  "Select the window showing the Diogenes browser.
Bound to \\`Q' in a lookup buffer: the way back from the entry to the text
it was looked up from.  Unlike \\`q', nothing is buried or killed."
  (interactive)
  (let ((window (diogenes-purpose--browser-window)))
    (if window
        (diogenes-purpose--focus window)
      (user-error "No Diogenes browser window on any visible frame"))))

(defun diogenes-purpose--after-display-page (buffer &rest _)
  "Mark BUFFER as a dictionary and, optionally, select its window.
`:filter-return' advice on `diogenes-old--display-page-buffer', which every
forward opener funnels through and which returns the buffer it displayed."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (unless (bound-and-true-p diogenes-purpose-dict-mode)
        (diogenes-purpose-dict-mode 1)))
    (setq diogenes-purpose--last-dict-buffer buffer)
    (when diogenes-purpose-focus-dictionary
      ;; t: look on every frame, since the dictionary usually has its own.
      (let ((window (get-buffer-window buffer t)))
        (when window (diogenes-purpose--focus window)))))
  buffer)

(defun diogenes-purpose--install-focus ()
  "Install the dictionary advice and the focus bindings.
Bare letters in the lookup and the dictionary, which are read-only; the
browser\='s under its own `C-c C-\=' prefix, since it derives from `text-mode\='
and is writable."
  (advice-add 'diogenes-old--display-page-buffer :filter-return
              #'diogenes-purpose--after-display-page)
  (dolist (spec '((diogenes-perseus . diogenes-lookup-mode-map)
                  (diogenes-perseus . diogenes-analysis-mode-map)
                  (diogenes-browser . diogenes-browser-mode-map)))
    (let ((feature (car spec))
          (map (cdr spec)))
      ;; The KEYS are no longer bound here.  `diogenes-focus-keys' binds
      ;; `C-c C-b', `C-c C-l', `C-c C-a' and `C-c C-s' in the core, to commands
      ;; that raise a window or a frame whichever this module is doing -- so a
      ;; reader has the same four keys with purpose and without it, which is
      ;; what they should have had from the start.  The commands below remain
      ;; for anyone who bound them.
      (ignore feature map))))

(defun diogenes-purpose--uninstall-focus ()
  "Undo `diogenes-purpose--install-focus'."
  (advice-remove 'diogenes-old--display-page-buffer
                 #'diogenes-purpose--after-display-page)
  (dolist (map '(diogenes-lookup-mode-map
                 diogenes-analysis-mode-map
                 diogenes-browser-mode-map))
    (when (boundp map)
      (dolist (key '("C-c C-e" "C-c C-l" "C-c C-b"))
        (keymap-unset (symbol-value map) key t)))))

;;;###autoload
(defun diogenes-purpose-install ()
  "Give Diogenes buffers their own window-purposes and recompile.
Adds this module's mode entries (and any
`diogenes-purpose-extra-name-purposes') to the `purpose-user-*-purposes'
variables -- Diogenes entries take precedence over an existing entry for
the same key, unrelated user entries are left untouched -- then calls
`purpose-compile-user-configuration' so the change takes effect at once.
Idempotent."
  (interactive)
  (unless (featurep 'window-purpose)
    (user-error "window-purpose (purpose.el) is not loaded"))
  (setq purpose-user-mode-purposes
        (diogenes-purpose--merge diogenes-purpose-mode-purposes
                                 (and (boundp 'purpose-user-mode-purposes)
                                      purpose-user-mode-purposes)))
  (when diogenes-purpose-extra-name-purposes
    (setq purpose-user-name-purposes
          (diogenes-purpose--merge diogenes-purpose-extra-name-purposes
                                   (and (boundp 'purpose-user-name-purposes)
                                        purpose-user-name-purposes))))
  ;; BY NAME as well as by mode, and the names are what actually work.  A
  ;; lookup buffer is created, displayed, and only then put into
  ;; `diogenes-lookup-mode' -- so at the moment purpose classifies it the mode
  ;; is `fundamental-mode', the mode table says nothing, and purpose files it
  ;; under `general' and shows it in the window we were reading in.  Measured:
  ;; `purpose-buffer-purpose' on a fresh `*diogenes-lookup*' returned
  ;; `general' where the browser correctly returned `diogenes-browser'.
  ;;
  ;; A name is settled when the buffer is made, so a regexp cannot be too
  ;; early.  Regexps rather than names because every entry gets its own
  ;; buffer -- `*diogenes-lookup<2>*' and upwards.
  (when (boundp 'purpose-user-regexp-purposes)
    (setq purpose-user-regexp-purposes
          (diogenes-purpose--merge diogenes-purpose-regexp-purposes
                                   purpose-user-regexp-purposes)))
  (purpose-compile-user-configuration)
  ;; Focus conventions between the three purposed windows.
  (diogenes-purpose--install-focus)
  t)

;;;###autoload
(defun diogenes-purpose-uninstall ()
  "Remove Diogenes purposes from the `purpose-user-*-purposes' variables.
Recompiles the configuration afterwards, and restores window-purpose's
own `display-buffer-overriding-action' if this module had wrapped it.
Only the entries this module added are removed; unrelated user entries
stay."
  (interactive)
  ;; An older version of this module put itself in
  ;; `display-buffer-overriding-action'.  Undo that if it is still there.
  (when (equal display-buffer-overriding-action
               '(diogenes-purpose--overriding-action))
    (setq display-buffer-overriding-action
          (if (fboundp 'purpose--action-function)
              '(purpose--action-function)
            nil)))
  (when (boundp 'purpose-user-regexp-purposes)
    (setq purpose-user-regexp-purposes
          (cl-remove-if (lambda (cell)
                          (assoc (car cell) diogenes-purpose-regexp-purposes))
                        purpose-user-regexp-purposes)))
  (when (boundp 'purpose-user-mode-purposes)
    (setq purpose-user-mode-purposes
          (cl-remove-if (lambda (cell)
                          (assq (car cell) diogenes-purpose-mode-purposes))
                        purpose-user-mode-purposes)))
  (when (and diogenes-purpose-extra-name-purposes
             (boundp 'purpose-user-name-purposes))
    (let ((names (mapcar #'car diogenes-purpose-extra-name-purposes)))
      (setq purpose-user-name-purposes
            (cl-remove-if (lambda (cell) (member (car cell) names))
                          purpose-user-name-purposes))))
  (diogenes-purpose--uninstall-focus)
  (when (fboundp 'purpose-compile-user-configuration)
    (purpose-compile-user-configuration))
  t)

(defcustom diogenes-purpose-manage-purposes t
  "Whether Diogenes teaches window-purpose what its buffers are.
Non-nil installs the purposes as soon as `window-purpose' is loaded, in
either order -- this file first or that one.

On by default, and required from `diogenes.el' rather than left to an init
file, for the same reason as `diogenes-evil.el': without it purpose has no
entry for a lookup buffer, files it under the generic `edit' purpose, and
shows an entry in whatever window already holds that purpose -- which is the
window you were reading in.  That is not a layout preference anyone would
choose; it is purpose lacking a fact about buffers only this package knows.

Nil leaves purpose's own configuration alone, for a reader who has written
their own entries and wants them untouched."
  :type 'boolean
  :group 'diogenes)

;; Either order: purpose already loaded, or loaded later.  window-purpose is
;; an ordinary package -- Spacemacs enables it, but anyone may -- so nothing
;; here waits for a distribution.
(when diogenes-purpose-manage-purposes
  (if (featurep 'window-purpose)
      (diogenes-purpose-install)
    (with-eval-after-load 'window-purpose
      (when diogenes-purpose-manage-purposes
        (diogenes-purpose-install)))))

(provide 'diogenes-purpose)
;;; diogenes-purpose.el ends here
