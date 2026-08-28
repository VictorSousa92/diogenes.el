;;; diogenes-lisp-utils.el --- Lisp utilities for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This file contains some lisp utilites needed by diogenes.el

;;; Code:
(require 'cl-lib)
(require 'transient)             ; transient-scope
(require 'seq)
(require 'ucs-normalize)                ; diogenes--ascii-alpha-only folds NFD

(defmacro diogenes--replace-regexes-in-string (str &rest subst-lists)
  "Apply a list of regex-substitutions to a string in sequence.
Each SUBST-LIST contains the REGEXP REP, followed optionaleval
parameters of `replace-regexp-in-string', FIXEDCASE LITERAL SUBEXP
START. Alternativly, SUBST-LIST can be a string or a list of one
element, in which case this is taken as the REGEXP and all of its
matches are deleted. 

Returns the resulting string."
  (declare (indent 1))
  (let ((result str))
    (dolist (subst subst-lists result)
      (setf result
	    (cl-typecase subst
	      (list (let ((regex (car subst))
			  (rep (or (cadr subst) ""))
			  (rest  (cddr subst)))
		      `(replace-regexp-in-string ,regex ,rep ,result
						 ,@rest)))
	      (string `(replace-regexp-in-string ,subst "" ,result))
	      (t (error "%s must be either a list or a string!"
			subst)))))))

(defun diogenes--plist-keys (plist)
  "Traverse a plist and extract its keys"
  (unless (plistp plist) (error "Not a plist!"))
  (cl-loop for key in plist by #'cddr
	   collect key))

(defun diogenes--plist-values (plist)
  "Traverse a plist and extract its values"
  (unless (plistp plist) (error "Not a plist!"))
  (cl-loop for key in (cdr plist) by #'cddr
	   collect key))

(defun diogenes--plist-keyword-keys-p (plist)
  "Check if all keys of a plist are keywords"
  (cond ((not (plistp plist)) nil)
	((cdr plist) (and (keywordp (car plist))
			  (diogenes--plist-keyword-keys-p (cddr plist))))
	(t t)))

(defun diogenes--assoc-cadr (key alist)
  "Return non-nil if KEY is equal to the cadr of an element of ALIST.
The value is actually the first element of ALIST whose car equals KEY."
  (cl-find-if (lambda (e) (equal key (cadr e)))
	      alist))

(defun diogenes--keyword->string (kw)
  (unless (keywordp kw) (error "Not a keyword: %s" kw))
  (substring (symbol-name kw) 1))

(defun diogenes--string->keyword (s)
  (intern (concat ":" s)))

(defun diogenes--hash-to-alist (hash-table)
  (cl-loop for k being the hash-keys of hash-table
	   using (hash-values v)
	   collect (cons k v)))

(defun diogenes--split-once (regexp str)
  "Split a string once on regexp and return the substrings as a list."
  (save-match-data
    (if (string-match regexp str)
	(list (substring str 0 (match-beginning 0))
	      (substring str (match-end 0)))
      (list str))))

(defun diogenes--get-text-prop-boundaries (pos property)
  "Get the boundaries of the region where property does not change."
  (let* ((end (or (next-single-char-property-change pos property)
	    (point-max)))
	 (start (or (previous-single-char-property-change end property)
		    (point-min))))
    (list start end)))

(defvar diogenes--loading-bundle nil
  "Non-nil while `diogenes.el' loads the dictionary modules it ships with.
This is how a module tells apart the two ways it can come to be loaded:

  the user asked for it -- `(require \\='diogenes-tll)' in an init file --
  which is a declaration that this dictionary is wanted;

  `diogenes.el' loaded it along with everything else, which says nothing
  about whether the user has it.

A module reads this AT LOAD TIME, through `diogenes--declared-at-load-p',
and passes the answer to `diogenes-lookup-register-dictionary' as
DECLARED.  Read at load time rather than at registration because
registration is deferred through `with-eval-after-load' and would
otherwise run inside the bundle's own binding.

`diogenes-declared-dictionaries' is the other way to declare one, and the
one that does not depend on load order.")

(defun diogenes--declared-at-load-p ()
  "Whether the file now being loaded was asked for, rather than bundled.
Call at the top level of a dictionary module, never from a function: the
answer is about the moment the file is read.  See
`diogenes--loading-bundle'."
  (not (bound-and-true-p diogenes--loading-bundle)))

(defcustom diogenes-lookup-display-action nil
  "Where a dictionary entry or an analysis appears.
A `display-buffer\=' ACTION, or nil to leave the choice to Emacs -- which
means `display-buffer-alist\=', `pop-up-frames\=' and whatever the reader has
configured, and is the default because it is the answer that respects what
they configured.

    ;; entries share one window, replacing each other
    (setq diogenes-lookup-display-action
          \='((display-buffer-reuse-mode-window display-buffer-same-window)
            (mode . (diogenes-lookup-mode diogenes-analysis-mode))))

Set, this takes precedence over `diogenes-purpose' and `diogenes-doom'.
Both modules would otherwise win -- purpose through an overriding action,
Doom through `display-buffer-alist', and Emacs consults both before the
action a caller passes -- so an answer given here is given first refusal
instead.  If it declines, they have their say after all.

Two things this does NOT decide.  A lookup made from a frame holding only a
startup page takes that window whatever is set here -- there is a window
going spare and using it is never wrong.  And a `C-c C-c\=' chain stays in
one window, that being what the reader asked for by pressing the key in an
entry rather than a request about layout.  See `diogenes--display-buffer\='."
  :type 'sexp
  :group 'diogenes)

(defcustom diogenes-browser-display-action nil
  "Where a passage from the corpora appears.
A `display-buffer\=' ACTION, or nil for Emacs\='s own choice.  A browser buffer
is the text being read, so it wants a window of its own and a lookup should
not displace it -- which is what `diogenes-lookup-display-action\=' is for,
this being the other half of that arrangement."
  :type 'sexp
  :group 'diogenes)

(defcustom diogenes-dictionary-display-action nil
  "Where a scanned dictionary\='s page appears.
A `display-buffer\=' ACTION, or nil for Emacs\='s own choice.  Distinct from
the other two because a dictionary is consulted and closed where an entry is
read: `diogenes-old-pdf-display-action\=' is the value the print dictionaries
use today, and this is where it is heading."
  :type 'sexp
  :group 'diogenes)

(defcustom diogenes-gather-frames 'auto
  "Whether Diogenes buffers of a kind share a frame.
  `auto\=' -- the default -- follows `pop-up-frames\='.  Gathering only means
anything where a buffer would otherwise get a frame to itself, so with
`pop-up-frames\=' nil this does nothing and Emacs, `window-purpose\=' or
whatever else is installed decides as before.  Set `pop-up-frames\=' and the
gathering begins, with no reload: the question is asked each time a buffer is
displayed.

This is where Doom and Spacemacs come to the same behaviour.  Both put a
mechanism of their own between a buffer and its window -- Doom a popup
manager and `display-buffer-alist\=', Spacemacs `window-purpose\=' and window
dedication -- and with frames in play neither is answering the question the
reader asked.  So with `pop-up-frames\=' set this answers it for both, and
the second entry replaces the first in its frame on either.

  t gathers regardless, for a setup that wants Diogenes buffers kept
together in windows.  nil never gathers.

`diogenes-lookup-display-action\=' and its two companions still take
precedence: an answer given there is given first refusal."
  :type '(choice (const :tag "Follow pop-up-frames" auto)
                 (const :tag "Always" t)
                 (const :tag "Never" nil))
  :group 'diogenes)

(defcustom diogenes-frame-parameters
  '((name . "Diogenes"))
  "Parameters for a frame made to hold a Diogenes buffer.
The name is worth keeping: it is what a tiling window manager matches on to
place these frames by rule.  A width and a height are deliberately NOT here
-- a tiling manager assigns the space, and a frame that asks for a size it
cannot have leaves part of its tile empty."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'diogenes)

(defcustom diogenes-role-regexps
  '(("\\`\\*\\(?:diogenes-lookup\\|Diogenes Analysis\\|Diogenes Forms\\)" . lookup)
    ("\\`\\*diogenes-browser" . browser)
    ("\\`\\*diogenes-search" . search))
  "Buffer names and the kind of frame each belongs in.
Matched before major modes, and that order matters: a buffer's NAME is
settled when it is created, where `diogenes--search-dict\=' sets the major
mode after the buffer has been displayed.  A rule dispatching on the mode
alone would see `fundamental-mode\=' and miss.

Add a dictionary PDF here to give the scans a frame of their own -- they are
ordinary `pdf-view-mode\=' buffers named after their files, so only you know
what they are called:

    (add-to-list \='diogenes-role-regexps
                 \='(\\\\`Oxford Latin Dictionary\\\\.pdf . dictionary))"
  :type '(alist :key-type regexp :value-type symbol)
  :group 'diogenes)

(defconst diogenes--role-modes
  '((diogenes-lookup-mode . lookup)
    (diogenes-analysis-mode . lookup)
    (diogenes-select-forms-mode . lookup)
    (diogenes-browser-mode . browser)
    (diogenes-search-mode . search)
    (pdf-view-mode . dictionary)
    (doc-view-mode . dictionary)
    (reader-mode . dictionary))
  "Major modes and the kind of frame each belongs in.
Consulted after `diogenes-role-regexps\=', for a buffer already in its mode
-- which a document buffer is, `find-file\=' having set it before display.")

(defun diogenes--buffer-role (buffer)
  "Which frame BUFFER belongs in: `lookup\=', `browser\=', `dictionary\=' or nil.
By name first and by major mode second: see `diogenes-role-regexps\='."
  (when-let* ((buffer (get-buffer buffer))
              (name (buffer-name buffer)))
    (or (cdr (cl-find-if (lambda (rule) (string-match-p (car rule) name))
                         diogenes-role-regexps))
        (cdr (assq (buffer-local-value 'major-mode buffer)
                   diogenes--role-modes)))))

(defun diogenes--window-of-role (role)
  "A window on any visible frame showing a buffer whose role is ROLE."
  (catch 'found
    (dolist (frame (frame-list))
      (when (frame-visible-p frame)
        (dolist (window (window-list frame 'no-minibuffer))
          (when (eq role (diogenes--buffer-role (window-buffer window)))
            (throw 'found window)))))))

(defun diogenes-display-in-role-frame (buffer alist)
  "Show BUFFER in the frame its kind already occupies, if there is one.
A `display-buffer\=' action function.  `display-buffer-reuse-window\=' cannot
do this: it looks for a window showing the SAME buffer, and every entry is a
new buffer.  What is wanted is a window showing a SIBLING -- any other
lookup -- so that the second entry replaces the first instead of opening
another frame beside it.

Returns nil where there is no such frame, so the actions after it get their
turn: normally `display-buffer-pop-up-frame\='."
  (when-let* ((role (diogenes--buffer-role buffer))
              (window (diogenes--window-of-role role)))
    (window--display-buffer buffer window 'reuse alist)))

(defun diogenes--gathering-p ()
  "Whether Diogenes buffers are being gathered into frames at the moment.
Asked at display time, so `pop-up-frames\=' may be set or unset in a running
Emacs and the answer changes with it."
  (pcase diogenes-gather-frames
    ('auto (or (memq 'frames
                     (if (and (consp diogenes-window-behaviour)
                              (consp (car diogenes-window-behaviour)))
                         (mapcar #'cdr diogenes-window-behaviour)
                       (list diogenes-window-behaviour)))
               (and pop-up-frames t)))
    (value (and value t))))

(defun diogenes--gathering-action ()
  "The action that keeps each kind of Diogenes buffer in one frame."
  `((diogenes-display-in-role-frame display-buffer-pop-up-frame)
    (inhibit-same-window . t)
    (reusable-frames . visible)
    (pop-up-frame-parameters . ,diogenes-frame-parameters)))

(defcustom diogenes-window-behaviour 'defer
  "Where Diogenes buffers go, said in one word.
A shorthand for the three actions below, and consulted only where the action
for a kind of buffer is nil -- so setting
`diogenes-lookup-display-action\=' keeps its own answer for lookups while the
browser and the dictionaries follow this.

  `defer\='   -- the default, and what the package did before this existed:
             whatever is installed decides.  `window-purpose\=' where it is
             loaded, a popup manager under Doom, plain `display-buffer\='
             elsewhere.  A reader who has arranged their windows to their
             liking wants this.

  `reuse\='   -- one window for entries, each replacing the last.  Nothing is
             split and nothing is covered but the previous entry.

  `split\='   -- an entry gets a window of its own beside the text, and later
             entries share it.  A window the first time, reuse after that:
             the alternative -- splitting again for every entry -- fills the
             frame with the same word.

  `frames\='  -- each kind of buffer in a frame of its own, entries gathered
             into the lookup frame.  This sets the gathering; whether a new
             buffer gets a frame at all is `pop-up-frames\=', which is yours
             to set, since it governs the whole of Emacs and not just this.

MIXED, by giving an alist rather than a word.  The three kinds are different
things and there is no reason they should agree:

    ;; the text stays where it is, entries share a window beside it,
    ;; and a scan gets a frame of its own
    (setq diogenes-window-behaviour
          \='((browser . defer) (lookup . split) (dictionary . frames)))

A kind the alist does not mention falls back to `defer\='.  `frames\=' for any
kind switches the gathering on for all of them, the gathering being about
which frame a buffer joins rather than about one kind.

None of the four can override two things, both being statements about what
was asked rather than about layout: a `C-c C-c\=' chain stays in the window it
was pressed in, and a frame holding only a startup page yields its window."
  :type '(choice
          (const :tag "Let what is installed decide" defer)
          (const :tag "One window, entries replacing each other" reuse)
          (const :tag "A window of its own, then shared" split)
          (const :tag "A frame of its own, gathered" frames)
          (alist :tag "A different answer for each kind"
                 :key-type (choice (const lookup) (const browser)
                                   (const dictionary))
                 :value-type (choice (const defer) (const reuse)
                                     (const split) (const frames))))
  :group 'diogenes)

(defcustom diogenes-split-direction nil
  "Which way `split\=' and the window fallbacks divide a window.
Nil lets Emacs choose, which means `split-window-sensibly\=' and its
thresholds -- below if the window is tall enough, beside it if it is wide
enough, and neither if a distribution has set the thresholds against you.

  `below\=', `above\=', `right\=', `left\=' say which, and say it regardless of the
thresholds: an entry beside a text reads better on a wide screen, and under
it on a tall one, and that is a judgement about the screen rather than
something Emacs can infer."
  :type '(choice (const :tag "Let Emacs choose" nil)
                 (const :tag "Below the text" below)
                 (const :tag "Above the text" above)
                 (const :tag "To the right" right)
                 (const :tag "To the left" left))
  :group 'diogenes)

(defcustom diogenes-split-size nil
  "How much of the divided window the new one takes, or nil for half.
A number of lines or columns, or a float between 0 and 1 for a fraction of
what is being divided.  Applied in whichever direction the split went.

An ALIST answers per kind, as `diogenes-window-behaviour\=' does:

    (setq diogenes-split-size \='((lookup . 0.4) (dictionary . 0.55)))

A kind the alist does not mention gets half, which is what Emacs does unasked.

It governs the split that MAKES a window and nothing after.  Where a kind
REUSES another\='s window -- a scanned page taking the entry\='s, a second entry
taking the first\='s -- there is no split and no size of its own: one window has
one size, and the buffer that arrives second inherits it.  So a size for a
kind that never gets a window of its own has nothing to act on."
  :type '(choice (const :tag "Half" nil)
                 (number :tag "Lines, columns, or a fraction")
                 (alist :key-type symbol :value-type number))
  :group 'diogenes)

(defun diogenes--split-size-for (kind)
  "What `diogenes-split-size\=' says about KIND, or nil for half."
  (if (and (consp diogenes-split-size)
           (consp (car diogenes-split-size)))
      (cdr (assq kind diogenes-split-size))
    diogenes-split-size))

(defcustom diogenes-split-from 'selected
  "Which window is divided when a new one is wanted.
  `selected\=' -- the one you are in, which is where you were looking;
  `main\=' -- the frame\='s main window, ignoring side windows a popup manager
  or a file tree may have put at the edges;
  `root\=' -- the frame as a whole, so the new window spans its full width or
  height rather than dividing whichever window happens to be selected;
  `largest\=' -- whichever has the most room, which is the least surprising
  choice when the frame is already divided several ways."
  :type '(choice (const :tag "The window I am in" selected)
                 (const :tag "The frame's main window" main)
                 (const :tag "The whole frame" root)
                 (const :tag "Whichever is largest" largest))
  :group 'diogenes)

(defun diogenes--split-alist (&optional kind)
  "The `display-buffer\=' alist entries describing how to divide a window.
KIND selects the size, `diogenes-split-size\=' being answerable per kind."
  (append
   (when diogenes-split-direction
     (list (cons 'direction diogenes-split-direction)))
   (let ((size (diogenes--split-size-for kind)))
     (when size
       (list (cons (if (memq diogenes-split-direction '(right left))
                       'window-width
                     'window-height)
                   size))))
   (pcase diogenes-split-from
     ('main '((window . main)))
     ('root '((window . root)))
     (_ nil))))

(defun diogenes--split-functions ()
  "The functions that make a new window, in the order to try them.
`display-buffer-in-direction\=' when a direction was asked for, because
`display-buffer-pop-up-window\=' has none to give it; then the ordinary
pop-up; then `diogenes--display-split-anyway\=', which does not ask."
  (append
   (when diogenes-split-direction '(display-buffer-in-direction))
   (when (eq diogenes-split-from 'largest)
     '(display-buffer-use-least-recent-window))
   '(display-buffer-pop-up-window
     diogenes--display-split-anyway)))

(defun diogenes--behaviour-action (behaviour &optional kind)
  "The `display-buffer\=' action BEHAVIOUR stands for, for a buffer of KIND.
Built rather than looked up, because `diogenes-split-direction\=',
`diogenes-split-size\=' and `diogenes-split-from\=' have a say in three of the
four and a table could not hold them.

`diogenes-display-in-role-frame\=' leads all of them: a second entry belongs
where the first is, whether that is a window or a frame, and only a first
entry needs somewhere new."
  (pcase behaviour
    ('reuse `((diogenes-display-in-role-frame display-buffer-same-window)
              (inhibit-same-window . nil)))
    ('split `(,(cons 'diogenes-display-in-role-frame
                     (diogenes--split-functions))
              ,@(diogenes--split-alist kind)))
    ('frames `((diogenes-display-in-role-frame
                display-buffer-pop-up-frame
                ,@(diogenes--split-functions))
               (inhibit-same-window . t)
               (reusable-frames . visible)
               (pop-up-frame-parameters . ,diogenes-frame-parameters)
               ,@(diogenes--split-alist kind)))
    (_ nil)))

(defun diogenes--behaviour-for (kind)
  "What `diogenes-window-behaviour\=' says about KIND.
A word applies to every kind; an alist answers per kind, and a kind it does
not mention gets `defer\='."
  (if (and (consp diogenes-window-behaviour)
           (consp (car diogenes-window-behaviour)))
      (or (cdr (assq kind diogenes-window-behaviour)) 'defer)
    diogenes-window-behaviour))

(defun diogenes--display-split-anyway (buffer alist)
  "Split the selected window and show BUFFER there, whatever the thresholds say.
The last resort of every behaviour but `defer\=', and needed because
`display-buffer-pop-up-window\=' asks `split-window-sensibly\=' for
permission -- which consults `split-height-threshold\=' and
`split-width-threshold\=', and a distribution may set those so that no frame
the reader actually has can be split.  Spacemacs ships 80 against a frame of
68 lines.

So `split\=' would quietly become `reuse\=', and the entry would take the
window holding the text it was looked up from: the one outcome every one of
these behaviours exists to prevent."
  (let* ((horizontal (memq diogenes-split-direction '(right left)))
         (side (pcase diogenes-split-direction
                 ('above 'above) ('left 'left)
                 (_ nil)))
         ;; The size the ACTION carries, which is the one for this kind:
         ;; `diogenes--split-alist' put it there.  Reading
         ;; `diogenes-split-size' here instead would ignore a per-kind
         ;; setting, this function being the last resort of every behaviour.
         (size (let ((n (or (cdr (assq 'window-width alist))
                            (cdr (assq 'window-height alist)))))
                 (and (numberp n)
                      (if (floatp n)
                          (round (* n (if horizontal
                                          (window-total-width)
                                        (window-total-height))))
                        n))))
         (window
          (or (ignore-errors
                (split-window (selected-window) size
                              (or side (if horizontal 'right 'below))))
              ;; Whichever way was asked for may be impossible; the other way
              ;; is better than not splitting, which would mean taking the
              ;; window the reader is in.
              (ignore-errors
                (split-window (selected-window) size
                              (if horizontal 'below 'right))))))
    (when (window-live-p window)
      (window--display-buffer buffer window 'window alist))))

(defun diogenes--display-action (kind)
  "The `display-buffer\=' action for a Diogenes buffer of KIND.
KIND is `lookup\=', `browser\=', `dictionary\=', or anything else for none.

The action set for that kind if there is one, and otherwise whatever
`diogenes-window-behaviour\=' says -- in that order, so that naming an action
for lookups leaves the browser and the dictionaries on the shorthand.  A
reader who wants one thing arranged specially should not have to spell out
the other two."
  (or (pcase kind
        ('lookup diogenes-lookup-display-action)
        ('browser diogenes-browser-display-action)
        ('dictionary diogenes-dictionary-display-action)
        (_ nil))
      ;; `defer' yields nil, there being nothing for it to be: it means that
      ;; no action of ours is passed at all.
      (diogenes--behaviour-action (diogenes--behaviour-for kind) kind)))

(defcustom diogenes-claim-buffers t
  "Whether a Diogenes buffer is claimed by the perspective it appears in.
Non-nil adds it, so that `previous-buffer\=', `next-buffer\=' and the
perspective\='s own buffer list can reach it.  Nil leaves it out, where
`switch-to-buffer\=' by name is the only way back to it.

Wanted because these buffers are made rather than visited.  persp-mode and
perspective.el both decide what a perspective contains by watching
`find-file\=' and `switch-to-buffer\='; a buffer created by a program and
displayed by `display-buffer\=' is seen by neither, so it exists, is on the
window\='s own history, and is still invisible to the keys that walk it --
which is a confusing state, and was reported as a buffer being killed."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-claim-buffer-function 'auto
  "How a Diogenes buffer is claimed by the current perspective.
  `auto\=' -- the default -- looks for what is installed and uses it, or does
nothing where nothing is.  persp-mode and perspective.el are both found this
way: they share the name `persp-add-buffer\=' and both accept a buffer, which
is all that is wanted here.

A function of one argument to do it yourself, for a workspace package this
does not know -- eyebrowse, bufler, something local.  Nil never claims, the
same as `diogenes-claim-buffers\=' nil.

Tab-bar tabs need nothing: a tab holds a window configuration rather than a
set of buffers, so a buffer is reachable from any of them."
  :type '(choice (const :tag "Detect what is installed" auto)
                 (const :tag "Never" nil)
                 function)
  :group 'diogenes)

(defun diogenes--claim-buffer (buffer)
  "Add BUFFER to the current perspective, if there is one to add it to.
Called for every Diogenes buffer as it is displayed -- which is one place,
where the Doom module did it from six mode hooks and so missed any buffer
whose mode was not among them.

WITHOUT DISPLAYING IT, which took a day to notice.  `persp-add-buffer\='
SWITCHES TO the buffer it is given, so claiming an entry put it in the window
the reader was in -- before the display path had decided anything, so the
display then found it already there and correctly reused it.  Every
explanation offered for that reuse was wrong, and had to be: the window was
gone before any of the machinery blamed for it was consulted.

`save-window-excursion\=' puts the configuration back, and
`save-current-buffer\=' the buffer, so a claim is a claim and nothing else,
whatever the perspective package does inside it."
  (when (and diogenes-claim-buffers buffer)
    (save-window-excursion
      (save-current-buffer
        (pcase diogenes-claim-buffer-function
          ('nil nil)
          ('auto
           ;; persp-mode and perspective.el: different packages, same
           ;; minor-mode name and the same function, and either takes a
           ;; buffer.
           (when (and (bound-and-true-p persp-mode)
                      (fboundp 'persp-add-buffer))
             (ignore-errors (persp-add-buffer buffer))))
          ((and (pred functionp) fn)
           (ignore-errors (funcall fn buffer))))))))

(defcustom diogenes-display-debug nil
  "When non-nil, record every decision `diogenes--display-buffer\=' makes.
Each call appends a paragraph to `*diogenes-display-log*\=': which of the four
branches was taken, what was in force when it was taken, the windows before
and after, and the window returned.

Here because one symptom -- a lookup taking the window of the text it was
looked up from, on one configuration and not the others -- took a day of
probing and was not explained.  Every component measured correctly in
isolation while the whole measured wrong, which is the signature of a
decision being made where nobody is looking.  A log of the decision itself
answers in one keypress what the probing did not.

    (setq diogenes-display-debug t)

then do the thing that misbehaves, and read the buffer."
  :type 'boolean
  :group 'diogenes)

(defvar diogenes--display-log-before nil)
(defvar diogenes--display-log-branch nil)
(defvar diogenes--display-log-detail nil)

(defun diogenes--display-log (buffer window)
  "Append what `diogenes--display-buffer\=' just decided about BUFFER."
  (when diogenes-display-debug
    (with-current-buffer (get-buffer-create "*diogenes-display-log*")
      (goto-char (point-max))
      (insert (format "%s  %s\n  branch  %s\n  detail  %S\n\
  before  %S\n  after   %S\n  window  %s (%s)\n\n"
                      (format-time-string "%H:%M:%S")
                      (buffer-name (get-buffer buffer))
                      (or diogenes--display-log-branch "?")
                      diogenes--display-log-detail
                      diogenes--display-log-before
                      (mapcar (lambda (w) (buffer-name (window-buffer w)))
                              (window-list))
                      window
                      (if (window-live-p window)
                          (buffer-name (window-buffer window))
                        "dead"))))))

(defmacro diogenes--with-our-answer (&rest body)
  "Run BODY.  Kept as a no-op, and here is what it was for.
An earlier commit had this bind `purpose-action-function\=' to `ignore\=', on
the belief that window-purpose\='s advice on `display-buffer\=' consulted it and
would therefore stand aside.  No such variable exists: `(boundp
\='purpose-action-function)\=' is nil with purpose loaded, so the binding did
nothing, and a test asserting it passed while asserting a fiction.

The reuse it was meant to fix had another cause entirely, and one closer to
home -- `diogenes-purpose.el\=' installing itself as
`display-buffer-overriding-action\=' and calling `purpose--action-function\='
from inside purpose\='s own advice.  Twice through that function is a reuse
where once is a split.  See the commentary in that file.

Left in place, doing nothing, only so that a compiled caller from the
intervening commits does not break.  Callers should be plain
`display-buffer\=' calls."
  (declare (indent 0) (debug t))
  `(progn ,@body))

(cl-defun diogenes--display-buffer (buffer &key kind same-window action
                                          fallback no-select)
  "Show BUFFER and return the window it is in.
The one place that decides where a Diogenes buffer goes, so that a reader
who wants to change it has one thing to change and the package has one
thing to get right.  Nineteen `pop-to-buffer\=' and `set-window-buffer\='
calls answered this separately before, and the ones that answered it by
hand were where the faults were: a `set-window-buffer\=' records no window
history, so `q\=' had nowhere to go back to, and a bare `pop-to-buffer\='
consults no rule, so a startup page kept its window while the text opened
beside it.

KIND selects the action -- see `diogenes--display-action\=' -- and ACTION
overrides it, for a caller that has computed one.

FALLBACK is an action for when nothing else has an opinion: after what the
reader asked for, and after the gathering.  A module with a display
arrangement of its own passes it there rather than as ACTION, so that
`diogenes-window-behaviour\=' and `diogenes-gather-frames\=' can still answer --
an arrangement the package chose is not a decision the reader made, and
should not outrank one.

SAME-WINDOW puts BUFFER where we are.  Not a preference but a statement
about what was asked: pressing a key inside an entry to see another entry
is staying in one place, and no display rule should overrule it.  It goes
through `display-buffer\=' all the same, rather than `set-window-buffer\=',
so that dedication and the rest are handled properly -- but NOT because that
records the window history, which it does not.  Getting back to what was
displaced is `diogenes-old--return-buffer''s business, and the key bound
beside it.

A frame holding only a startup page is the exception to everything: there
is a window going spare, and taking it is right whatever is configured.
See `diogenes--sole-home-window-p\='.

The window is SELECTED unless NO-SELECT, because that is what the calls
this replaced did.  `pop-to-buffer\=' displays AND selects; `display-buffer\='
only displays -- and a reader left in the buffer they came from, looking at
an entry in another window, finds that the keys they expect are undefined,
because the buffer they are in is not the entry.  The distinction is easy to
miss and was missed here."
  ;; Claimed BEFORE it is displayed, so that whatever watches the display --
  ;; a perspective, a workspace -- sees a buffer that already belongs.
  (diogenes--claim-buffer buffer)
  (let* ((diogenes--display-log-before
          (and diogenes-display-debug
               (mapcar (lambda (w) (buffer-name (window-buffer w)))
                       (window-list))))
         (diogenes--display-log-branch nil)
         (diogenes--display-log-detail nil)
         (chosen (or action (diogenes--display-action kind)))
         ;; The window `display-buffer' RETURNS, not one found afterwards by
         ;; searching.  An earlier version re-derived it with
         ;; `(get-buffer-window buffer t)', which looks on every frame and
         ;; can find a different, older window showing the same buffer: the
         ;; selection then went there, the current buffer and the selected
         ;; window fell out of step, and `diogenes--show-dict-entry' met
         ;; "`recenter'ing a window that does not display current-buffer".
         (window
          (cond
       ;; Intent, not layout: both of these are what the reader asked for by
       ;; pressing the key they pressed, and both go through
       ;; `display-buffer-overriding-action' so that they hold under
       ;; `diogenes-purpose', which uses an overriding action of its own, and
       ;; under `diogenes-doom', whose rules are in `display-buffer-alist'.
       ((or (diogenes--sole-home-window-p) same-window)
        (setq diogenes--display-log-branch "intent: same-window or lone home"
              diogenes--display-log-detail
              (list :same-window same-window
                    :sole-home (diogenes--sole-home-window-p)))
        ;; A DEDICATED window declines, and `display-buffer' then puts the
        ;; buffer somewhere else entirely -- which is not "somewhere else"
        ;; but a refusal of what was asked.  window-purpose dedicates the
        ;; lookup and browser windows to their purposes, so this is the
        ;; ordinary case under it and not an edge one;
        ;; `diogenes-old--display-in-this-window' has always undedicated for
        ;; the same reason.  Put back afterwards, so purpose's arrangement
        ;; survives our one exception to it.
        (let* ((here (selected-window))
               (dedicated (window-dedicated-p here))
               (display-buffer-overriding-action
                '(display-buffer-same-window (inhibit-same-window . nil))))
          (when dedicated (set-window-dedicated-p here nil))
          (unwind-protect
              (diogenes--with-our-answer (display-buffer buffer))
            (when (and dedicated
                       (window-live-p here)
                       (eq (window-buffer here) buffer))
              ;; Only if what we asked for is what landed here: otherwise the
              ;; window holds someone else's buffer, and dedicating it to
              ;; that would be worse than leaving it undedicated.
              (set-window-dedicated-p here dedicated)))))
       ;; An action the reader has set gets FIRST REFUSAL -- ahead of
       ;; `diogenes-purpose' and of `diogenes-doom', both of which would
       ;; otherwise win by where they put themselves.  A setting that loses to
       ;; the module it was meant to override is not a setting.  Should it
       ;; decline -- every function in it returning nil -- `display-buffer'
       ;; carries on to the alist and the modules have their say after all.
       (chosen
        (setq diogenes--display-log-branch "action set by the reader"
              diogenes--display-log-detail (list :action chosen))
        (let ((display-buffer-overriding-action chosen))
          (diogenes--with-our-answer (display-buffer buffer))))
       ;; Frames are in play, and nothing more specific was asked for.  This
       ;; is where Doom and Spacemacs come to the same behaviour: both put a
       ;; mechanism between a buffer and its window -- a popup manager and
       ;; `display-buffer-alist' there, `window-purpose' and window dedication
       ;; here -- and with `pop-up-frames' set neither is answering the
       ;; question the reader asked.  So it is answered here, for both, and
       ;; the second entry replaces the first in its frame on either.
       ;;
       ;; Through the overriding action for that reason: an action passed the
       ;; ordinary way would lose to purpose, which uses an overriding action
       ;; of its own, and to Doom, whose rules are in the alist.
       ((diogenes--gathering-p)
        (setq diogenes--display-log-branch "gathering into frames"
              diogenes--display-log-detail
              (list :pop-up-frames pop-up-frames))
        (let ((display-buffer-overriding-action (diogenes--gathering-action)))
          (diogenes--with-our-answer (display-buffer buffer))))
       ;; A module's own arrangement, where it has one and nothing above had
       ;; an opinion.
           (fallback
            (setq diogenes--display-log-branch "the module's own action"
                  diogenes--display-log-detail (list :fallback fallback))
            (diogenes--with-our-answer (display-buffer buffer fallback)))
       ;; Nothing set and no frames: whatever is installed decides --
       ;; `window-purpose' under Spacemacs, a popup manager under Doom, plain
       ;; `display-buffer' elsewhere.
           (t
            (setq diogenes--display-log-branch "deferred to what is installed"
                  diogenes--display-log-detail
                  (list :overriding display-buffer-overriding-action
                        :alist (mapcar #'car display-buffer-alist)
                        :advice (let (fs)
                                  (advice-mapc (lambda (f _) (push f fs))
                                               'display-buffer)
                                  fs)))
            (display-buffer buffer)))))
    (when (and (window-live-p window) (not no-select))
      ;; On another frame, the frame has to be raised as well, which is the
      ;; other half of what `pop-to-buffer' did for us.
      (unless (eq (window-frame window) (selected-frame))
        (select-frame-set-input-focus (window-frame window)))
      (select-window window)
      ;; And the buffer made CURRENT.  `pop-to-buffer' did that too, and
      ;; enough of this package depends on it -- `diogenes--browse-work'
      ;; sets the major mode in whatever buffer is current after displaying,
      ;; and `diogenes--show-dict-entry' recenters -- that leaving it to
      ;; follow from `select-window' is not good enough.
      (set-buffer (window-buffer window)))
    (diogenes--display-log buffer window)
    window))

(defun diogenes--path-set-p (value)
  "Non-nil if VALUE is a path the user has actually named.
Set-ness only: whether anything is there is not asked.  A dictionary whose
path is set is one the user means to have, so its link is offered and the
command explains what is wrong with the path -- a moved volume or a typo
being a thing to report rather than a reason to make the dictionary
disappear.  `diogenes--path-usable-p' is the stricter question, for when
something is about to be read."
  (and (stringp value) (not (string-empty-p value)) t))

(defun diogenes--source-set-p (value)
  "Non-nil if VALUE names TEI source material, without checking it is there.
As `diogenes--path-set-p', but for the `...-source-file' options, which
take a file, a directory of files, or a list of either."
  (cond
   ((consp value) (seq-some #'diogenes--source-set-p value))
   (t (diogenes--path-set-p value))))

(defcustom diogenes-home-buffer-names
  '("*spacemacs*" "*doom*" "*doom-dashboard*" "*dashboard*"
    "*GNU Emacs*" "*About GNU Emacs*")
  "Buffer names treated as a startup or home page.
A frame showing one of these and nothing else is a frame with nothing in
it: splitting it, or opening another frame beside it, wastes the screen
where reusing the window is what a reader wants.  Every distribution has
its own -- `*spacemacs*\=', Doom\='s `*doom*\=' (and `*doom-dashboard*\=', which
some configurations use instead), the dashboard package\='s `*dashboard*\=', and
Emacs\='s own splash -- and the name is looked for at the moment of display, so
nothing here depends on which is installed.

These names have a second use, in
`diogenes--word-at-point-for-lookup\=': a word at point in a startup page is not
a word to look up, a dashboard being prose about Emacs.  `*scratch*\=' is
deliberately NOT here -- it would be reasonable for that second purpose and
wrong for this one, since a frame showing scratch is a frame the reader may be
using."
  :type '(repeat string)
  :group 'diogenes)

(defun diogenes--home-buffer-p (name)
  "Non-nil if NAME is a startup or home buffer.
`diogenes-home-buffer-names' plus whatever the distribution calls its own,
asked of the variables the distributions define: this way a renamed or
localised home buffer is still recognised."
  (and name
       (or (member name diogenes-home-buffer-names)
           (cl-some (lambda (symbol)
                      (and (boundp symbol)
                           (equal name (symbol-value symbol))))
                    '(spacemacs-buffer-name
                      +doom-dashboard-name
                      dashboard-buffer-name))
           nil)))

(defun diogenes--sole-home-window-p ()
  "Non-nil if the selected frame shows a home buffer and nothing else.
The question a display rule needs to ask before it splits or pops: there
is a window here, and what it holds is not worth keeping."
  (and (one-window-p)
       (diogenes--home-buffer-p (buffer-name (window-buffer (selected-window))))))

(defun diogenes--path-usable-p (value kind)
  "Non-nil if VALUE names an existing file or readable directory.
KIND is `file' or `directory'.  VALUE is what a dictionary's path option
currently holds: nil, the empty string, or a path that does not exist all
count as unusable.

This is the half of the pair that ASKS, and it must stay cheap, silent and
free of side effects: the link banner calls it for every dictionary each
time it draws itself, so it may neither signal nor prompt.
`diogenes--require-path' is the half that TELLS -- called by a command once
the user has actually pressed a key, and which explains what to set."
  (and (stringp value)
       (not (string-empty-p value))
       (if (eq kind 'directory)
           (file-directory-p value)
         (file-readable-p value))
       t))

(defun diogenes--source-usable-p (value)
  "Non-nil if VALUE names TEI source material that is actually there.
The `...-source-file' options each take any of three things -- a single XML
file, a directory of them, or an explicit list -- so this accepts all
three: a list is usable when any of its members is, a string when it names
either a readable file or an existing directory.

Asked when deciding whether to offer a dictionary that has not been
converted yet: a source that is present means \\[diogenes-lookup-pape] and
its kind can offer to build the dictionary, so the link leads somewhere
after all.  Like `diogenes--path-usable-p', it neither signals nor
prompts."
  (cond
   ((consp value) (seq-some #'diogenes--source-usable-p value))
   (t (or (diogenes--path-usable-p value 'file)
          (diogenes--path-usable-p value 'directory)))))

(defun diogenes--require-path (value variable dictionary kind)
  "Return VALUE, or explain how to set VARIABLE if it will not serve.
The dictionaries each need a path from the user, and a missing one should
say what to set and how rather than failing somewhere downstream.  VALUE is
what the option currently holds, VARIABLE its symbol, DICTIONARY the name to
call it by in the message, and KIND either `file' or `directory'.

Set as an ordinary variable, before Diogenes loads, or through Customize;
either way the value survives the `defcustom'."
  (let ((name (symbol-name variable)))
    (cond
     ((or (null value) (and (stringp value) (string-empty-p value)))
      (user-error "%s is not set up yet: `%s' must name %s.  \
Put (setq %s \"/path/to/%s\") in your init file before Diogenes loads, or \
run M-x customize-variable RET %s RET"
                  dictionary name
                  (if (eq kind 'directory) "a directory" "a file")
                  name
                  (if (eq kind 'directory) "folder/" "file.pdf")
                  name))
     ((eq kind 'directory)
      (unless (file-directory-p value)
        (user-error "%s: `%s' is %s, which is not an existing directory"
                    dictionary name value))
      value)
     (t
      (unless (file-readable-p value)
        (user-error "%s: `%s' is %s, which cannot be read"
                    dictionary name value))
      value))))

(defun diogenes--ascii-alpha-p (letter)
  (or (<= 65 letter 90)
      (<= 97 letter 122)))

(defun diogenes--ascii-alpha-only (str)
  "Return the ASCII letters of STR, accented letters folded to their base.
Decomposes to NFD first, so a letter that carries a mark contributes the
letter: `desîmus' gives `desimus', not `desmus'.

That distinction is the whole point of the decomposition.  Everything but
ASCII letters is then discarded, and an accented letter that had NOT been
decomposed would be discarded with it -- so a Latin form printed with a
quantity or a contraction mark, as the PHI texts print `desîmus', lost the
marked letter altogether.  The comparators built on this then placed it
past the end of its own letter block (`desmus' sorts after `desivare'), and
a lookup landed on whatever entry happened to be there.

Ligatures are not spelt out here: NFD leaves æ alone, there being no
canonical decomposition for it.  A dictionary whose headwords use them
handles them in its own key function -- see `diogenes-gaffiot--key'."
  (cl-remove-if-not #'diogenes--ascii-alpha-p
                    (ucs-normalize-NFD-string (or str ""))))

(defun diogenes--string-equal-letters-only (str-a str-b)
  "Compare two string, making them equal if they contain the same letters"
  (string-equal (replace-regexp-in-string "[^[:alpha:]]" "" str-a)
		(replace-regexp-in-string "[^[:alpha:]]" "" str-b)))

(defun diogenes--first-line-p ()
  "Return non-nil if on the first line in buffer."
  (save-excursion (beginning-of-line) (bobp)))

(defun diogenes--last-line-p ()
  "Return non-nil if on the last line in buffer."
  (save-excursion (end-of-line) (eobp)))

(cl-defun diogenes--filter-in-minibuffer (list prompt
					       &key
					       initial-selection
					       remove-prompt
					       all-string
					       remove-string
					       regexp-string
					       commit-string)
  "Filter a list interactively in minibuffer, with initial-selection preselected.
When supplied, the keyword arguments add additional strings with a special meaning:

- :all-string adds all values and toggles the other input mode (add <-> remove)
- :regexp-string causes the next input to be read in as a regexp
- :remove-string switches input mode to `remove'"
  (setq list (cl-copy-list list))
  (setq remove-prompt (or remove-prompt prompt))
  (let ((max-mini-window-height 0.8))
    (cl-loop
     with list-length = (length list)
     with current-list = (cl-set-difference list initial-selection)
     with remove = nil
     with results = (nreverse initial-selection)
     for collection = (append (if remove results current-list)
			      (when regexp-string
				(list regexp-string))
			      (when (and remove-string
					 results
					 (not remove)) 
				(list remove-string))
			      (when (and all-string
					 (or remove
					     (< (length results)
						list-length)))
				(list all-string))
			      (when commit-string (list commit-string)))
     for inp = (completing-read (concat
				 (if results (format "%s\n" results) "")
				 (if remove remove-prompt prompt))
				collection)
     if (or (string-blank-p inp)
	    (equal inp commit-string))
     return (nreverse results)
     for matcher = (cond ((string= inp regexp-string)
			  (setq inp "")
			  (let ((regexp (read-regexp "Regexp: ")))
			    (lambda (str) (string-match regexp str))))
			 (t (lambda (str) (string-equal inp str))))
     do
     (cond ((not (or (string-blank-p inp)
		     (member inp collection)))
	    (message "Invalid input!")
	    (sit-for 1))
	   ((string= inp remove-string)
	    (setq remove t))
	   ((and remove (string= inp all-string))
	    (setq remove nil
		  current-list (cl-copy-list list)
		  results nil))
	   ((string= inp all-string)
	    (setq current-list nil
		  results (cl-copy-list list)))
	   (remove
	    (let ((matches (cl-remove-if-not matcher results)))
	      (setq remove nil
		    current-list (nconc matches current-list)
		    results (cl-delete-if matcher results))))
	   (t
	    (let ((matches (cl-remove-if-not matcher current-list)))
	      (setq results (nconc matches results)
		    current-list (cl-delete-if matcher current-list))))))))

(defun diogenes-undo ()
  "Undo also when buffer is readonly."
  (interactive)
  (let ((inhibit-read-only t))
    (undo)))

(defun diogenes--quit ()
  (interactive) (kill-buffer))

(defun diogenes--ask-and-quit ()
  (interactive)
  (when (y-or-n-p "Discard edits and quit?")
    (kill-buffer)))

;;; Transient scope accessors
(defsubst diogenes--tr--type () (plist-get (transient-scope) :type))
(defsubst diogenes--tr--callback () (plist-get (transient-scope) :callback))
(defsubst diogenes--tr--no-ask () (plist-get (transient-scope) :no-ask))

(provide 'diogenes-lisp-utils)

;;; diogenes-lisp-utils.el ends here
