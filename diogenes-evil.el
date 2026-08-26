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

(require 'cl-lib)                        ; cl-pushnew

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

(defcustom diogenes-evil-normal-state-key "<escape>"
  "Key that leaves Emacs state for normal state in a Diogenes buffer.
`<escape>\=' by default, which is the key one already presses to get to normal
state from anywhere else -- and which in Emacs state does nothing.

The point is to have all three states available in a buffer that starts in
the third.  Emacs state is where the dictionaries live: `o\=' is the OLD, `g\='
is Gaffiot, `B\=' is Bailly, and evil\='s own meanings for those letters are out
of reach while it lasts.  Normal state is where evil\='s keyboard lives -- the
motions, the searches, `C-w\=' for windows, the leader on `SPC\='.  Both are
wanted, at different moments, and neither wants rebuilding inside the other.

`C-z\=' already returns from Emacs state, but to whatever state came before it,
which is usually insert; this goes to normal state whatever came before.  Nil
binds nothing."
  :type '(choice key-sequence (const :tag "Do not bind" nil))
  :group 'diogenes-evil)

(defconst diogenes-evil--maps
  '(diogenes-lookup-mode-map
    diogenes-analysis-mode-map
    diogenes-select-forms-mode-map
    diogenes-search-mode-map
    diogenes-corpus-mode-map)
  "The mode maps that Emacs state applies to.")

(defun diogenes-evil-bind-normal-state-key ()
  "Bind `diogenes-evil-normal-state-key\=' in the Diogenes maps.
Bound in the MODE maps, which is what Emacs state consults -- so it works
there and is invisible in normal state, where escape has its own meaning and
should keep it.

Nothing already bound on that key is disturbed."
  (when (and diogenes-evil-normal-state-key
             (featurep 'evil)
             (fboundp 'evil-normal-state))
    (dolist (map-symbol diogenes-evil--maps)
      (when (and (boundp map-symbol) (keymapp (symbol-value map-symbol)))
        (let ((map (symbol-value map-symbol))
              (key (kbd diogenes-evil-normal-state-key)))
          (unless (lookup-key map key)
            (keymap-set map diogenes-evil-normal-state-key
                        #'evil-normal-state)))))))

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
    ;; And a way out of Emacs state into normal state, for the moment one
    ;; wants evil's keyboard rather than the dictionaries.  After the maps
    ;; exist: they live in files this one does not require.
    (dolist (feature '(diogenes-perseus diogenes-forms diogenes-search
                                        diogenes-corpora))
      (with-eval-after-load feature (diogenes-evil-bind-normal-state-key)))
    (when (called-interactively-p 'interactive)
      (message "Diogenes buffers start in Emacs state; %s for normal state"
               (or diogenes-evil-normal-state-key "C-z")))))

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
