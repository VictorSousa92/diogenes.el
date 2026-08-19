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

;; Defined in diogenes-old.el and diogenes-perseus.el, which this module does
;; not require: it is loaded from a Spacemacs user-config hook, possibly before
;; either of them.  Advising a function before it is defined is supported, and
;; the keymap is touched inside `with-eval-after-load'.
(declare-function diogenes-old--display-page-buffer "diogenes-old"
                  (buffer action other-window))
(defvar diogenes-lookup-mode-map)

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

;;;; Focus: moving between the browser, the lookup and the dictionary
;;
;; With three purposed windows on screen -- browser, lookup, dictionary --
;; the question of which one has point becomes a real one.  purpose.el
;; decides WHERE a buffer appears; it has nothing to say about focus.  What
;; follows is a small set of conventions:
;;
;;   * opening a dictionary, or turning it to a new entry, focuses it;
;;   * `Q' in the dictionary returns to the lookup;
;;   * `D' in the lookup goes (back) to the dictionary;
;;   * `Q' in the lookup returns to the browser.
;;
;; A dictionary buffer is an ordinary `pdf-view-mode' (or `doc-view-mode',
;; or `reader-mode') buffer, which as the Commentary above notes is not
;; distinguishable by mode or name.  So this tracks them itself: every
;; buffer Diogenes displays through `diogenes-old--display-page-buffer'
;; gets `diogenes-purpose-dict-mode', a minor mode whose only job is to
;; mark the buffer as a Diogenes dictionary and to carry the `Q' binding.
;; That marker is also what makes `D' able to find the dictionary again.

(defcustom diogenes-purpose-focus-dictionary t
  "Whether opening or turning a dictionary moves point into its window.
Non-nil selects the dictionary window whenever Diogenes displays a page in
it -- opening one, or looking up a new entry while it is already on screen.
Nil leaves point where it was, which is Diogenes' own behaviour."
  :type 'boolean
  :group 'diogenes)

(defvar diogenes-purpose--last-dict-buffer nil
  "The dictionary buffer Diogenes displayed most recently.
Consulted by `diogenes-purpose-focus-dictionary-window' when no window is
currently showing a dictionary.")

(defvar diogenes-purpose-dict-mode-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "Q" #'diogenes-purpose-focus-lookup-window)
    map)
  "Keymap for `diogenes-purpose-dict-mode'.")

(define-minor-mode diogenes-purpose-dict-mode
  "Mark this buffer as a Diogenes print dictionary.
Turned on automatically in any PDF or document buffer Diogenes opens at an
entry's page.  Provides \\<diogenes-purpose-dict-mode-map>\\[diogenes-purpose-focus-lookup-window], \
which returns point to the lookup window, and lets
`diogenes-purpose-focus-dictionary-window' recognise the buffer."
  :lighter " Dio-Dict"
  :keymap diogenes-purpose-dict-mode-map)

(defun diogenes-purpose--window-with (predicate)
  "The most recently used window of this frame whose buffer satisfies PREDICATE.
PREDICATE is called with the window's buffer current."
  (car (sort (cl-remove-if-not
              (lambda (window)
                (with-current-buffer (window-buffer window)
                  (funcall predicate)))
              (window-list nil 'no-minibuffer))
             (lambda (a b) (> (window-use-time a) (window-use-time b))))))

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
        (select-window window)
      (user-error "No Diogenes lookup window on this frame"))))

(defun diogenes-purpose-focus-dictionary-window ()
  "Select the window showing a Diogenes print dictionary.
Bound to \\`D' in a lookup buffer.  When no dictionary is on screen but one
was opened earlier in this session, it is displayed again and selected;
otherwise open one first with `o', `t', `m', `c', `b', `g', `G' or `p'."
  (interactive)
  (let ((window (diogenes-purpose--dict-window)))
    (cond
     (window (select-window window))
     ((buffer-live-p diogenes-purpose--last-dict-buffer)
      (select-window (display-buffer diogenes-purpose--last-dict-buffer)))
     (t (user-error
         "No dictionary open; `o' opens the OLD, `t' the TLL, `g' Gaffiot")))))

(defun diogenes-purpose-focus-browser-window ()
  "Select the window showing the Diogenes browser.
Bound to \\`Q' in a lookup buffer: the way back from the entry to the text
it was looked up from.  Unlike \\`q', nothing is buried or killed."
  (interactive)
  (let ((window (diogenes-purpose--browser-window)))
    (if window
        (select-window window)
      (user-error "No Diogenes browser window on this frame"))))

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
      (let ((window (get-buffer-window buffer)))
        (when window (select-window window)))))
  buffer)

(defun diogenes-purpose--install-focus ()
  "Install the dictionary advice and the `D' and `Q' lookup bindings."
  (advice-add 'diogenes-old--display-page-buffer :filter-return
              #'diogenes-purpose--after-display-page)
  (with-eval-after-load 'diogenes-perseus
    (when (boundp 'diogenes-lookup-mode-map)
      (keymap-set diogenes-lookup-mode-map "D"
                  #'diogenes-purpose-focus-dictionary-window)
      (keymap-set diogenes-lookup-mode-map "Q"
                  #'diogenes-purpose-focus-browser-window))))

(defun diogenes-purpose--uninstall-focus ()
  "Undo `diogenes-purpose--install-focus'."
  (advice-remove 'diogenes-old--display-page-buffer
                 #'diogenes-purpose--after-display-page)
  (when (boundp 'diogenes-lookup-mode-map)
    (keymap-unset diogenes-lookup-mode-map "D" t)
    (keymap-unset diogenes-lookup-mode-map "Q" t)))

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
  (diogenes-purpose--uninstall-focus)
  (when (fboundp 'purpose-compile-user-configuration)
    (purpose-compile-user-configuration))
  t)

;; Apply on load, if purpose is present.
(when (featurep 'window-purpose)
  (diogenes-purpose-install))

(provide 'diogenes-purpose)
;;; diogenes-purpose.el ends here
