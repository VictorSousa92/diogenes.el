;;; diogenes-purpose.el --- Give Diogenes buffers their own window-purpose -*- lexical-binding: t -*-

;;; Commentary:

;; Spacemacs enables window-purpose (purpose.el), whose action runs before
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
;;   * lookup / analysis buffers -> purpose `diogenes-lookup'
;;   * the corpus browser         -> purpose `diogenes-browser'
;;
;; With distinct purposes, purpose keeps each family in its own window: all
;; lookups share one `diogenes-lookup' window, and the browser keeps its own
;; `diogenes-browser' window, so a lookup no longer lands on top of the
;; browser.  This needs no change to Diogenes.
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
;; Load it after purpose is up (in Spacemacs, from `dotspacemacs/user-config'):
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

(defcustom diogenes-purpose-mode-purposes
  '((diogenes-lookup-mode   . diogenes-lookup)
    (diogenes-analysis-mode . diogenes-lookup)
    (diogenes-browser-mode  . diogenes-browser))
  "Alist mapping Diogenes major modes to window-purposes.
Lookups and morphological analyses share the `diogenes-lookup'
purpose so they reuse one window; the corpus browser gets its own
`diogenes-browser' purpose so a lookup never displaces it.  Each
entry is (MAJOR-MODE . PURPOSE)."
  :type '(alist :key-type symbol :value-type symbol)
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

(defcustom diogenes-purpose-home-buffer-names '("*spacemacs*" "*dashboard*" "*GNU Emacs*")
  "Buffer names treated as the startup/home page for window reuse.
If `spacemacs-buffer-name' is bound, its value is added automatically.
Used by `diogenes-purpose-reuse-home-window'."
  :type '(repeat string)
  :group 'diogenes)

(defun diogenes-purpose--home-buffer-name-p (name)
  "Non-nil if NAME is one of the recognised startup/home buffer names."
  (and name
       (or (member name diogenes-purpose-home-buffer-names)
           (and (boundp 'spacemacs-buffer-name)
                (equal name spacemacs-buffer-name)))))

(defun diogenes-purpose--diogenes-buffer-p (buffer)
  "Non-nil if BUFFER is a Diogenes buffer this module gives a purpose.
Recognised by major mode (the keys of `diogenes-purpose-mode-purposes')
or by a lookup-family buffer name (`*diogenes-lookup*', analysis, forms)."
  (let ((buffer (get-buffer buffer)))
    (and buffer
         (or (assq (buffer-local-value 'major-mode buffer)
                   diogenes-purpose-mode-purposes)
             (let ((n (buffer-name buffer)))
               (and n (string-match-p
                       "\\`\\*\\(?:[Dd]iogenes[ -][Ll]ookup\\|Diogenes Analysis\\|Diogenes Forms\\|diogenes-browser\\)"
                       n)))))))

(defun diogenes-purpose--sole-home-window-p ()
  "Non-nil if the selected frame has ONE window showing a home buffer."
  (and (one-window-p)
       (diogenes-purpose--home-buffer-name-p
        (buffer-name (window-buffer (selected-window))))))

(defun diogenes-purpose--overriding-action (buffer alist)
  "`display-buffer' overriding action wrapping window-purpose's own.
When `diogenes-purpose-reuse-home-window' is on, BUFFER is a Diogenes
buffer, and the frame's only window shows the startup/home buffer,
display BUFFER in that window (reusing it, no split, no pop).
Otherwise fall through to window-purpose's normal action
\(`purpose--action-function')."
  (if (and diogenes-purpose-reuse-home-window
           (diogenes-purpose--diogenes-buffer-p buffer)
           (diogenes-purpose--sole-home-window-p))
      (window--display-buffer buffer (selected-window) 'reuse alist)
    (when (fboundp 'purpose--action-function)
      (purpose--action-function buffer alist))))

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
  (purpose-compile-user-configuration)
  ;; Wrap window-purpose's overriding action so a Diogenes buffer reuses the
  ;; sole startup/home window when appropriate.  Only do this when purpose's
  ;; own action is the current override (so we compose with it, not clobber
  ;; something else), and not twice.
  (when (and (equal display-buffer-overriding-action
                    '(purpose--action-function))
             (fboundp 'purpose--action-function))
    (setq display-buffer-overriding-action
          '(diogenes-purpose--overriding-action)))
  t)

;;;###autoload
(defun diogenes-purpose-uninstall ()
  "Remove Diogenes purposes from the `purpose-user-*-purposes' variables.
Recompiles the configuration afterwards, and restores window-purpose's
own `display-buffer-overriding-action' if this module had wrapped it.
Only the entries this module added are removed; unrelated user entries
stay."
  (interactive)
  ;; Restore purpose's overriding action if we had wrapped it.
  (when (equal display-buffer-overriding-action
               '(diogenes-purpose--overriding-action))
    (setq display-buffer-overriding-action
          (if (fboundp 'purpose--action-function)
              '(purpose--action-function)
            nil)))
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
  (when (fboundp 'purpose-compile-user-configuration)
    (purpose-compile-user-configuration))
  t)

;; Apply on load, if purpose is present.
(when (featurep 'window-purpose)
  (diogenes-purpose-install))

(provide 'diogenes-purpose)
;;; diogenes-purpose.el ends here
