;;; diogenes-evil.el --- Diogenes under evil-mode -*- lexical-binding: t -*-

;; Author: Victor Sousa
;; Keywords: languages, tools

;;; Commentary:

;; The dictionary keys are single letters -- `o' for the OLD, `g' for
;; Gaffiot, `B' for Bailly -- and under evil those letters belong to evil.
;; Every Diogenes mode derives from `text-mode', so evil starts them in
;; normal state, where `o' opens a line, `d' deletes, `p' pastes, `b' moves
;; back a word and `q' records a macro.  Evil's state maps come before the
;; major mode's, so none of the dictionary keys is reached; the buffers being
;; read-only, the letters do nothing useful in their place.
;;
;; Nothing here changes a key.  It says instead that the buffers where all
;; the letters mean something are Emacs-state buffers -- they are read-only
;; views, and evil's editing commands have nothing in them to act on.  `C-z'
;; still puts you into normal state for a moment if you want its motions.
;;
;; This file does nothing at all when evil is not loaded, and nothing to a
;; mode whose initial state the user has already chosen: an explicit
;; `evil-set-initial-state' in an init file is an answer, and this is only
;; for the modes nobody has answered for.
;;
;; Two modes are deliberately left in normal state, both of them arguable --
;; see `diogenes-evil-emacs-state-modes'.

;;; Code:

(require 'cl-lib)                        ; cl-pushnew, cl-some

(defgroup diogenes-evil nil
  "Diogenes under evil-mode."
  :group 'diogenes)

(defcustom diogenes-evil-emacs-state-modes
  '(diogenes-lookup-mode
    diogenes-analysis-mode
    diogenes-search-mode
    diogenes-select-forms-mode
    diogenes-corpus-mode)
  "Diogenes modes to start in evil's Emacs state.
Each is a read-only view whose keys are single letters: the lookup and
analysis buffers carry the eleven dictionary keys, and the search, forms and
corpus buffers a dozen more between them.  In normal state evil has all of
those, and the buffer has nothing for evil to edit.

Two modes are NOT here, on purpose, and either can be added:

  `diogenes-browser-mode' -- its only single-letter key is `q', so normal
  state costs almost nothing and buys evil's motions in a text one is
  reading.  Almost: the browser loads the next page when you move past the
  last line, which it does by remapping `next-line', and evil's `j' is
  `evil-next-line' rather than `next-line'.  So the arrow keys page and `j'
  does not.  Add the mode here if you would rather have the paging.

  `diogenes-corpus-edit-mode' -- the one Diogenes buffer meant to be typed
  in, where normal state is the point of using evil at all."
  :type '(repeat symbol)
  :group 'diogenes-evil)

(defcustom diogenes-evil-manage-initial-states t
  "Whether to put `diogenes-evil-emacs-state-modes' into Emacs state.
Nil leaves evil's own defaults alone, for a reader who would rather bind the
dictionary keys into normal state by hand -- which costs `o', `d', `p', `b',
`t', `g' and `G' inside dictionary buffers, and keeps `j' and `k'."
  :type 'boolean
  :group 'diogenes-evil)

(defvar diogenes-evil--set nil
  "The modes this file has set an initial state for.
So that `diogenes-evil-uninstall' can undo exactly those, and no more.")

(defun diogenes-evil--spoken-for-p (mode)
  "Whether MODE's initial evil state has already been decided by someone else."
  (and (boundp 'evil-initial-state-alist)
       (assq mode evil-initial-state-alist)
       (not (memq mode diogenes-evil--set))))

(defcustom diogenes-evil-restore-keys t
  "Whether evil\='s motions and the leader are put back in Emacs state.
Emacs state hands the single letters to the dictionaries, which is what it is
for -- but it takes away the rest of the keyboard with them, and the rest of
the keyboard is how one moves about.  An entry is a long text to be read and
searched, so `j\=', `k\=', `C-d\=', `gg\=', `/\=' and `n\=' are the keys that matter most
in it, and `C-w h\=' and its family are how one gets to another window.

So they come back, on the keys they already have, except where a dictionary
has claimed the key -- see `diogenes-evil-restored-keys\='.  Nil leaves Emacs
state bare, which is what it was."
  :type 'boolean
  :group 'diogenes-evil)

(defcustom diogenes-evil-restored-keys
  '(;; --- moving within the entry ---
    ("j" . evil-next-line)
    ("k" . evil-previous-line)
    ("C-d" . evil-scroll-down)
    ("C-u" . evil-scroll-up)
    ("C-f" . evil-scroll-page-down)
    ("C-b" . evil-scroll-page-up)
    ("}" . evil-forward-paragraph)
    ("{" . evil-backward-paragraph)
    ("w" . evil-forward-word-begin)
    ("e" . evil-forward-word-end)
    ("0" . evil-beginning-of-line)
    ("$" . evil-end-of-line)
    ("^" . evil-first-non-blank)
    ("%" . evil-jump-item)
    ;; --- searching it ---
    ("/" . evil-ex-search-forward)
    ("?" . evil-ex-search-backward)
    ("n" . evil-ex-search-next)
    ("N" . evil-ex-search-previous)
    ("*" . evil-ex-search-word-forward)
    ;; --- getting back to where one was ---
    ("C-o" . evil-jump-backward)
    ("C-i" . evil-jump-forward)
    ;; --- and to another window ---
    ("C-w" . evil-window-map))
  "Keys to put back in the Diogenes buffers, and what to put on them.
An alist of (KEY . COMMAND); COMMAND may be a keymap, which is how `C-w\='
comes back as evil\='s whole window map.

The dictionaries\=' own keys are NOT here and must not be: `d\=', `c\=', `p\=' and
`P\=' would take Bailly, Cambridge, Passow and Pape, and `b\=' and `l\=' would take
BDAG and Lewis & Short.  Their loss is small -- three of them are operators
with nothing to operate on in a read-only buffer -- and the dictionaries are
the reason for being here.

`h\=' and `l\=' are likewise absent: `l\=' is Lewis & Short, and `h\=' alone would be
odd.  The arrow keys work, and both are remapped by the lookup buffer anyway
to keep the entry\='s links in view."
  :type '(alist :key-type key-sequence :value-type sexp)
  :group 'diogenes-evil)

(defcustom diogenes-evil-leader-key "SPC"
  "Where the distribution\='s leader map goes in a Diogenes buffer.
`SPC\=' by default, and free for the taking: in Emacs state it is
`self-insert-command\=', and these buffers are read-only, so it does nothing
but complain.

Doom\='s `doom-leader-map\=' and Spacemacs\='s `spacemacs-default-map\=' are both
found; nil binds nothing.  Without this, choosing Emacs state took away the
key a Doom or Spacemacs reader reaches for most, which was not a trade
anybody agreed to."
  :type '(choice key-sequence (const :tag "Do not bind" nil))
  :group 'diogenes-evil)

(defconst diogenes-evil--maps
  '(diogenes-lookup-mode-map
    diogenes-analysis-mode-map
    diogenes-select-forms-mode-map
    diogenes-search-mode-map
    diogenes-corpus-mode-map)
  "The mode maps that Emacs state applies to, and so want their keys back.")

(defun diogenes-evil--leader-map ()
  "The leader map of whatever distribution this is, or nil."
  (cl-some (lambda (symbol)
             (and (boundp symbol)
                  (keymapp (symbol-value symbol))
                  (symbol-value symbol)))
           '(doom-leader-map spacemacs-default-map)))

(defun diogenes-evil-restore-keys ()
  "Put evil\='s motions and the leader back into the Diogenes maps.
Each key is bound only if the map has nothing on it already, so a dictionary
key is never taken and neither is anything a reader has bound themselves."
  (when (and diogenes-evil-restore-keys (featurep 'evil))
    (dolist (map-symbol diogenes-evil--maps)
      (when (and (boundp map-symbol) (keymapp (symbol-value map-symbol)))
        (let ((map (symbol-value map-symbol)))
          (dolist (entry diogenes-evil-restored-keys)
            (let* ((key (kbd (car entry)))
                   (command (cdr entry))
                   (value (if (and (symbolp command) (boundp command)
                                   (keymapp (symbol-value command)))
                              (symbol-value command)
                            command)))
              ;; Nothing already bound HERE is disturbed: the dictionaries
              ;; got there first, and so did the reader.
              (unless (lookup-key map key)
                (when (or (keymapp value) (fboundp value))
                  (keymap-set map (car entry) value)))))
          (when-let* ((key diogenes-evil-leader-key)
                      (leader (diogenes-evil--leader-map)))
            (unless (lookup-key map (kbd key))
              (keymap-set map key leader))))))))

;;;###autoload
(defun diogenes-evil-install ()
  "Start the read-only Diogenes buffers in evil's Emacs state.  Idempotent.
Does nothing without evil, and nothing to a mode whose state has been set
elsewhere -- `evil-set-initial-state' in an init file wins."
  (interactive)
  (when (fboundp 'evil-set-initial-state)
    (dolist (mode diogenes-evil-emacs-state-modes)
      (unless (diogenes-evil--spoken-for-p mode)
        (evil-set-initial-state mode 'emacs)
        (cl-pushnew mode diogenes-evil--set)))
    ;; And the keys Emacs state took away, minus the ones the dictionaries
    ;; want.  After the maps exist: they are defined in files this one does
    ;; not require.
    (with-eval-after-load 'diogenes-perseus (diogenes-evil-restore-keys))
    (with-eval-after-load 'diogenes-forms (diogenes-evil-restore-keys))
    (with-eval-after-load 'diogenes-search (diogenes-evil-restore-keys))
    (with-eval-after-load 'diogenes-corpora (diogenes-evil-restore-keys))
    (when (called-interactively-p 'interactive)
      (message "Diogenes buffers: Emacs state, with the motions and %s kept"
               (or diogenes-evil-leader-key "no leader")))))

;;;###autoload
(defun diogenes-evil-uninstall ()
  "Give the Diogenes modes back to evil's own defaults.
Only the ones this file set."
  (interactive)
  (when (boundp 'evil-initial-state-alist)
    (dolist (mode diogenes-evil--set)
      (setq evil-initial-state-alist
            (assq-delete-all mode evil-initial-state-alist)))
    (setq diogenes-evil--set nil)))

;; Either order: evil already loaded, or loaded later.
(when diogenes-evil-manage-initial-states
  (if (featurep 'evil)
      (diogenes-evil-install)
    (with-eval-after-load 'evil
      (when diogenes-evil-manage-initial-states
        (diogenes-evil-install)))))

(provide 'diogenes-evil)
;;; diogenes-evil.el ends here
