;;; diogenes-doom.el --- Diogenes buffers in frames of their own -*- lexical-binding: t -*-

;; Author: Victor Sousa
;; Keywords: languages, tools

;;; Commentary:

;; Where `diogenes-purpose.el' teaches window-purpose what a Diogenes buffer
;; is, this teaches `display-buffer' to keep each kind together -- in a frame
;; of its own where frames are what you use, in a window where they are not.
;; It gathers, and only where gathering means anything: with `pop-up-frames'
;; nil it stands aside altogether and Emacs displays a lookup as it displays
;; anything else.  `diogenes-doom-gather' overrides that either way.
;;
;; One thing it does unconditionally, `pop-up-frames' or not: a frame showing
;; only a startup page -- `*doom*', `*spacemacs*', Emacs's own splash -- has a
;; window going spare, and a lookup uses it rather than opening another frame
;; beside it.
;; It is the module to load when frames are how you work -- a tiling window
;; manager, or `pop-up-frames' in vanilla Emacs, or Doom Emacs with its popup
;; module out of the way.  The two modules do the same job by different means
;; and are mutually exclusive: load one.
;;
;; Written for Doom, and named for it, but it asks nothing of Doom.  Doom's
;; popup manager keeps its rules in `display-buffer-alist' like everyone
;; else, and `display-buffer' takes the FIRST matching entry, so the rules
;; here are prepended and Doom's never see a Diogenes buffer.  No
;; `set-popup-rule!', no `after!', nothing to arrange in the right order --
;; and the same file works on plain Emacs.
;;
;; What it arranges:
;;
;;   * A lookup or an analysis goes to the frame that already holds one, or
;;     to a new frame.  So the second entry replaces the first rather than
;;     covering your text, which is what the shared `diogenes-lookup' purpose
;;     does under window-purpose.
;;   * The browser keeps a frame of its own, so a lookup never displaces the
;;     text being read.
;;   * A dictionary PDF likewise, once you have named it -- see
;;     `diogenes-doom-dictionary-regexps'.
;;
;; Matching is by BUFFER NAME, deliberately.  A buffer's name is settled when
;; it is created, where its major mode is not: `diogenes--search-dict'
;; displays the buffer and then puts it in `diogenes-lookup-mode', so a rule
;; dispatching on the mode would see `fundamental-mode' and miss.  That
;; ordering is reversed only when `diogenes-purpose' is loaded, and this
;; module is the alternative to loading it.
;;
;; Loading is the switch, as with `diogenes-purpose': the rules are installed
;; at load and `diogenes-doom-uninstall' takes them out again.

;;; Code:

(require 'cl-lib)
(require 'diogenes-lisp-utils)          ; diogenes--sole-home-window-p

(defgroup diogenes-doom nil
  "Showing Diogenes buffers in frames of their own."
  :group 'diogenes)

;; The three options that named the buffers, and the switch for reusing a
;; frame, are the core's now.  A configuration that set them still works:
;; `diogenes-role-regexps' is the list of name-to-role rules, and adding a
;; dictionary PDF to it is what `diogenes-doom-dictionary-regexps' was for.

(defun diogenes-doom--claim-dictionary-regexps ()
  "Fold any `diogenes-doom-dictionary-regexps' into `diogenes-role-regexps'.
For a configuration written against the older option: naming a dictionary
PDF there gave the scans a frame of their own, and it still does."
  (dolist (regexp (bound-and-true-p diogenes-doom-dictionary-regexps))
    (add-to-list 'diogenes-role-regexps (cons regexp 'dictionary))))

(defvar diogenes-doom-dictionary-regexps nil
  "Obsolete; add to `diogenes-role-regexps' instead.
Kept because a configuration may set it, and
`diogenes-doom--claim-dictionary-regexps' still reads it.")

(defvar diogenes-doom--rules nil
  "The entries this module has put into `display-buffer-alist'.
Kept so that `diogenes-doom-uninstall' can remove exactly those.")


;;; Finding the frame a kind of buffer already lives in

;; This was the module's own, and is now the core's: `diogenes--buffer-role',
;; `diogenes--window-of-role' and `diogenes-display-in-role-frame' live in
;; `diogenes-lisp-utils.el', and `diogenes--display-buffer' applies them
;; whenever `pop-up-frames' is set -- under Doom, under Spacemacs, under
;; plain Emacs alike.  Which is the point: the gathering was never
;; Doom-specific, and having it here meant Spacemacs did something else with
;; the same request.
;;
;; What is left below is what only this module can do: adding a buffer to the
;; workspace it was created in, and the focus commands.  The options that
;; belonged to the gathering now name their core counterparts, so a
;; configuration that set them keeps working.

(define-obsolete-variable-alias 'diogenes-doom-frame-parameters
  'diogenes-frame-parameters "modular-customizable"
  "The gathering moved to the core; so did its frame parameters.")

(define-obsolete-variable-alias 'diogenes-doom-gather
  'diogenes-gather-frames "modular-customizable"
  "The gathering moved to the core; so did the switch for it.")

(define-obsolete-function-alias 'diogenes-doom-display-in-role-frame
  'diogenes-display-in-role-frame "modular-customizable")

(define-obsolete-function-alias 'diogenes-doom-gathering-p
  'diogenes--gathering-p "modular-customizable")

(defun diogenes-doom--role (buffer)
  "Which frame BUFFER belongs in.  See `diogenes--buffer-role'."
  (diogenes--buffer-role buffer))

(defun diogenes-doom--window-of-role (role)
  "A window showing a buffer of role ROLE.  See `diogenes--window-of-role'."
  (diogenes--window-of-role role))

;;; Workspaces

;; This was the module's own too, and is now the core's.  persp-mode is not
;; Doom's -- it is a package, and perspective.el poses the same problem with
;; the same function name -- so a buffer being invisible to `previous-buffer'
;; was never a Doom fault, only a Doom-shaped one.  `diogenes--claim-buffer'
;; does it for anyone, from `diogenes--display-buffer', which is one place
;; where this module used six mode hooks and so missed any buffer whose mode
;; was not among them.

(define-obsolete-variable-alias 'diogenes-doom-claim-buffers
  'diogenes-claim-buffers "modular-customizable"
  "The claiming moved to the core, persp-mode not being Doom's.")

(define-obsolete-function-alias 'diogenes-doom-claim-buffer
  'diogenes--claim-buffer "modular-customizable")

;;;###autoload
(defun diogenes-doom-install ()
  "Fold any older Doom-specific settings into their core counterparts.
Nothing else: the rules this used to put in `display-buffer-alist' are gone,
the gathering being the core's and done through an overriding action, and so
are the mode hooks that claimed a buffer for the workspace."
  (interactive)
  (diogenes-doom--claim-dictionary-regexps)
  (when (called-interactively-p 'interactive)
    (message "Diogenes: nothing left to install here -- the core does it")))

;;;###autoload
(defun diogenes-doom-uninstall ()
  "Remove anything an older version of this module left behind."
  (interactive)
  (dolist (rule diogenes-doom--rules)
    (setq display-buffer-alist (delq rule display-buffer-alist)))
  (setq diogenes-doom--rules nil))

;;; Getting to a frame that is already open

(defun diogenes-doom--focus (role what)
  "Raise and select the frame holding a buffer of role ROLE.
WHAT names the kind, for the message when there is none.

Kept for anyone who bound it: the work is `diogenes--focus-role\=' in the core
now, nothing about going from one window to another being particular to Doom."
  (diogenes--focus-role role what))

;;;###autoload
(defalias 'diogenes-doom-focus-lookup-frame #'diogenes-focus-lookup
  "Renamed: `diogenes-focus-lookup\=', and available in any Emacs.")

;;;###autoload
(defalias 'diogenes-doom-focus-browser-frame #'diogenes-focus-browser
  "Renamed: `diogenes-focus-browser\=', and available in any Emacs.")

;;;###autoload
(defalias 'diogenes-doom-focus-dictionary-frame #'diogenes-focus-dictionary
  "Renamed: `diogenes-focus-dictionary\=', and available in any Emacs.")

(defun diogenes-doom-delete-frames ()
  "Close every frame whose buffer is a Diogenes buffer.
The way back from a screenful of entries.  A frame showing anything else as
well is left alone -- closing it would take that with it."
  (interactive)
  (let ((closed 0))
    (dolist (frame (frame-list))
      (when (and (frame-visible-p frame)
                 (not (eq frame (selected-frame)))
                 (cl-every (lambda (window)
                             (diogenes-doom--role (window-buffer window)))
                           (window-list frame 'no-minibuffer)))
        (delete-frame frame)
        (cl-incf closed)))
    (message "Closed %d Diogenes frame%s" closed (if (= closed 1) "" "s"))))

(diogenes-doom-install)

(provide 'diogenes-doom)
;;; diogenes-doom.el ends here
