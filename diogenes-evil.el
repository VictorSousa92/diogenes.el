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
    (when (called-interactively-p 'interactive)
      (message "Diogenes buffers will start in Emacs state (C-z for normal)"))))

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
