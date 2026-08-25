;;; diogenes-doom.el --- Diogenes buffers in frames of their own -*- lexical-binding: t -*-

;; Author: Victor Sousa
;; Keywords: languages, tools

;;; Commentary:

;; Where `diogenes-purpose.el' teaches window-purpose what a Diogenes buffer
;; is, this teaches `display-buffer' to give each kind a FRAME of its own.
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

(defgroup diogenes-doom nil
  "Showing Diogenes buffers in frames of their own."
  :group 'diogenes)

(defcustom diogenes-doom-lookup-regexp
  "\\`\\*\\(?:diogenes-lookup\\|Diogenes Analysis\\|Diogenes Forms\\)"
  "Buffers that share the lookup frame.
Lookups, morphological analyses and the form lists belong together: they
are all answers about a word, and one replaces another.  Every entry gets
its own buffer -- `*diogenes-lookup*', `*diogenes-lookup<2>*' and so on --
so this matches a prefix rather than a name."
  :type 'regexp
  :group 'diogenes-doom)

(defcustom diogenes-doom-browser-regexp
  "\\`\\*diogenes-browser"
  "Buffers that get the browser frame.
A frame of its own, so that looking a word up never covers the text the
word was read in."
  :type 'regexp
  :group 'diogenes-doom)

(defcustom diogenes-doom-dictionary-regexps nil
  "Names of dictionary PDFs to gather into one frame of their own.
A list of regexps.  Nothing is here by default because a dictionary PDF is
an ordinary `pdf-view-mode' buffer named after its file, and only you know
what your files are called:

    (setq diogenes-doom-dictionary-regexps
          \\='(\"Oxford Latin Dictionary\\\\.pdf\" \"Montanari\\\\.pdf\"))

Single-file dictionaries have predictable names; the directory-based ones
\\(the TLL, Passow, the TGL) open one file per volume, so theirs vary --
match the directory's name if they share a prefix."
  :type '(repeat regexp)
  :group 'diogenes-doom)

(defcustom diogenes-doom-frame-parameters
  '((width . 90) (height . 45) (name . "Diogenes"))
  "Parameters for a frame made for a Diogenes buffer.
The name is worth keeping: it is what a tiling window manager can match on
to place these frames by rule."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'diogenes-doom)

(defcustom diogenes-doom-reuse-frames t
  "Whether a second buffer of a kind reuses the frame the first is in.
Non-nil is the point of the module: one lookup frame, reused, however many
entries you open.  Nil gives a frame per buffer, which is `pop-up-frames'
without the gathering, and buries the screen."
  :type 'boolean
  :group 'diogenes-doom)

(defvar diogenes-doom--rules nil
  "The entries this module has put into `display-buffer-alist'.
Kept so that `diogenes-doom-uninstall' can remove exactly those.")


;;; Finding the frame a kind of buffer already lives in

(defun diogenes-doom--role (buffer)
  "Which frame BUFFER belongs in: `lookup', `browser', `dictionary', or nil."
  (let ((name (buffer-name (get-buffer buffer))))
    (cond
     ((null name) nil)
     ((string-match-p diogenes-doom-lookup-regexp name) 'lookup)
     ((string-match-p diogenes-doom-browser-regexp name) 'browser)
     ((cl-some (lambda (re) (string-match-p re name))
               diogenes-doom-dictionary-regexps)
      'dictionary))))

(defun diogenes-doom--window-of-role (role)
  "A window, on any visible frame, showing a buffer whose role is ROLE."
  (catch 'found
    (dolist (frame (frame-list))
      (when (frame-visible-p frame)
        (dolist (window (window-list frame 'no-minibuffer))
          (when (eq role (diogenes-doom--role (window-buffer window)))
            (throw 'found window)))))))

(defun diogenes-doom-display-in-role-frame (buffer alist)
  "Show BUFFER in the frame its kind already occupies, if there is one.
A `display-buffer' action function.  `display-buffer-reuse-window' cannot
do this: it looks for a window showing THE SAME buffer, and every entry
here is a new buffer.  What is wanted is a window showing a SIBLING -- any
other lookup -- which is the frame-shaped version of what a shared
window-purpose does.

Returns nil when there is no such frame, so the actions after this one in
the list get their turn: normally `display-buffer-pop-up-frame'."
  (and diogenes-doom-reuse-frames
       (let* ((role (diogenes-doom--role buffer))
              (window (and role (diogenes-doom--window-of-role role))))
         (when window
           (window--display-buffer buffer window 'reuse alist)))))


;;; Installing and removing the rules

(defun diogenes-doom--rule (regexp)
  "The `display-buffer-alist' entry for buffers matching REGEXP."
  `(,regexp
    (diogenes-doom-display-in-role-frame
     display-buffer-pop-up-frame)
    (inhibit-same-window . t)
    (reusable-frames . visible)
    (pop-up-frame-parameters . ,diogenes-doom-frame-parameters)))

;;;###autoload
(defun diogenes-doom-install ()
  "Give the Diogenes buffers frames of their own.  Idempotent.
The rules are PREPENDED to `display-buffer-alist', which is what keeps them
ahead of Doom's popup rules -- `display-buffer' uses the first entry that
matches, so a Diogenes buffer never reaches the popup manager and there is
nothing to tell Doom to ignore."
  (interactive)
  (diogenes-doom-uninstall)
  (let ((regexps (append (list diogenes-doom-lookup-regexp
                               diogenes-doom-browser-regexp)
                         diogenes-doom-dictionary-regexps)))
    (dolist (regexp (reverse regexps))
      (let ((rule (diogenes-doom--rule regexp)))
        (push rule diogenes-doom--rules)
        (push rule display-buffer-alist))))
  (when (called-interactively-p 'interactive)
    (message "Diogenes buffers will open in frames of their own")))

;;;###autoload
(defun diogenes-doom-uninstall ()
  "Take this module's rules out of `display-buffer-alist'.
Only its own: a rule you added yourself, for the same buffers, is left
alone."
  (interactive)
  (dolist (rule diogenes-doom--rules)
    (setq display-buffer-alist (delq rule display-buffer-alist)))
  (setq diogenes-doom--rules nil))


;;; Getting to a frame that is already open

(defun diogenes-doom--focus (role what)
  "Raise and select the frame holding a buffer of role ROLE.
WHAT names the kind, for the message when there is none."
  (let ((window (diogenes-doom--window-of-role role)))
    (if (not window)
        (message "No %s frame open" what)
      (let ((frame (window-frame window)))
        (select-frame-set-input-focus frame)
        (select-window window)))))

;;;###autoload
(defun diogenes-doom-focus-lookup-frame ()
  "Raise the frame showing a dictionary entry or an analysis."
  (interactive)
  (diogenes-doom--focus 'lookup "lookup"))

;;;###autoload
(defun diogenes-doom-focus-browser-frame ()
  "Raise the frame showing the corpus browser."
  (interactive)
  (diogenes-doom--focus 'browser "browser"))

;;;###autoload
(defun diogenes-doom-focus-dictionary-frame ()
  "Raise the frame showing a dictionary PDF.
Only finds one if `diogenes-doom-dictionary-regexps' names it."
  (interactive)
  (diogenes-doom--focus 'dictionary "dictionary"))

;;;###autoload
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
