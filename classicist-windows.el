;;; classicist-windows.el --- where a classicist's buffers go -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; THE ONE PLACE THAT DECIDES WHERE A BUFFER GOES, for every family in the
;; suite: a text in the Diogenes browser, an entry in a lexicon, a hit list
;; from Diorisis, a tree from the treebank, a TEI edition.  Nineteen
;; `pop-to-buffer' and `set-window-buffer' calls answered that question
;; separately before this existed, and the ones that answered it by hand were
;; where the faults were.
;;
;; It lived in `diogenes-lisp-utils.el', which was the wrong house for it
;; twice over: the layer is not a lisp utility, and it is not Diogenes'
;; alone.  `tei-diorisis.el' has called `diogenes--display-buffer' from
;; outside Diogenes since it was written, which is what settled the question.
;;
;; A BUFFER HAS A ROLE -- `browser', `lookup', `morphology', `dictionary',
;; `search' -- found from its name first and its major mode second, in that
;; order because a name is settled when the buffer is created where a mode may
;; be set after it is displayed.  `classicist-role-regexps' is a defcustom, so
;; a module may register its own buffers by name; the roles themselves are
;; still a closed set, which is the next thing here that wants opening.
;;
;; THE NAMES CHANGED with the move, and the old ones are aliased in
;; `diogenes-lisp-utils.el' rather than here, so that a file requiring
;; Diogenes and not the suite still finds them.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; `classicist--role-modes' was a defconst, and is a defcustom under its
;; public name.  Aliased because it was reachable, and a table of modes is
;; exactly the thing somebody will have added to by hand.
(define-obsolete-variable-alias 'classicist--role-modes
                                'classicist-role-modes "0.1")

(require 'classicist-groups)

(defgroup classicist-windows nil
  "Where a classicist's buffers go."
  :group 'classicist)

(defcustom classicist-role-modes
  '((diogenes-lookup-mode . lookup)
    ;; `morphology', not `lookup'.  The name regexps got this right and this
    ;; table did not, so a buffer classified by NAME went to the analysis frame
    ;; and the same buffer classified by MODE went to the entry's -- and which
    ;; happened depended on whether the mode was set before it was displayed.
    (classicist-analysis-mode . morphology)
    (diogenes-select-forms-mode . morphology)
    (classicist-browser-mode . browser)
    (diogenes-search-mode . search)
    (pdf-view-mode . dictionary)
    (doc-view-mode . dictionary)
    (reader-mode . dictionary))
  "Major modes and the role each belongs to.
Consulted after `classicist-role-regexps\=', for a buffer already in its mode
-- which a document buffer is, `find-file\=' having set it before display.

A DEFCUSTOM, and it was a defconst: the roles are not Diogenes\=' alone.  A
module adds its own modes the way it already adds its own names to
`classicist-role-regexps\=', and gives the role somewhere to be placed with
`classicist-display-actions\=' or `classicist-window-behaviour\=':

    (add-to-list \='classicist-role-modes
                 \='(diorisis-results-mode . diorisis-results))
    (add-to-list \='classicist-window-behaviour
                 \='(diorisis-results . split))

A role this does not mention, and no regexp matches, is nil -- and a buffer
of no role is placed by whatever is installed, as before."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'classicist-windows)

(defcustom classicist-display-actions nil
  "Roles and the `display-buffer\=' action each takes.
An alist, and the place a role added by a module says where it goes:

    (add-to-list \='classicist-display-actions
                 \='(diorisis-results . ((display-buffer-below-selected)
                                       (window-height . 12))))

Consulted BEFORE `classicist-lookup-display-action\=' and its three fellows,
which stay and still win where they are set -- they were four options for
four roles, which is no way to hold a set a module may add to, and no reason
to break a setting either."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'classicist-windows)


;;; The options

;; BEFORE THE FUNCTIONS THAT READ THEM, which source order did not
;; manage: two of these were defined below their readers and the
;; compiler said so -- quietly, and only when nothing happened to
;; load this file before compiling it.

(defcustom classicist-lookup-display-action nil
  "Where a dictionary entry or an analysis appears.
A `display-buffer\=' ACTION, or nil to leave the choice to Emacs -- which
means `display-buffer-alist\=', `pop-up-frames\=' and whatever the reader has
configured, and is the default because it is the answer that respects what
they configured.

    ;; entries share one window, replacing each other
    (setq classicist-lookup-display-action
          \='((display-buffer-reuse-mode-window display-buffer-same-window)
            (mode . (diogenes-lookup-mode classicist-analysis-mode))))

Set, this takes precedence over `diogenes-purpose' and `diogenes-doom'.
Both modules would otherwise win -- purpose through an overriding action,
Doom through `display-buffer-alist', and Emacs consults both before the
action a caller passes -- so an answer given here is given first refusal
instead.  If it declines, they have their say after all.

Two things this does NOT decide.  A lookup made from a frame holding only a
startup page takes that window whatever is set here -- there is a window
going spare and using it is never wrong.  And a `C-c C-c\=' chain stays in
one window, that being what the reader asked for by pressing the key in an
entry rather than a request about layout.  See `classicist-display-buffer\='."
  :type 'sexp
  :group 'classicist-windows)

(defcustom classicist-browser-display-action nil
  "Where a passage from the corpora appears.
A `display-buffer\=' ACTION, or nil for Emacs\='s own choice.  A browser buffer
is the text being read, so it wants a window of its own and a lookup should
not displace it -- which is what `classicist-lookup-display-action\=' is for,
this being the other half of that arrangement."
  :type 'sexp
  :group 'classicist-windows)

(defcustom classicist-dictionary-display-action nil
  "Where a scanned dictionary\='s page appears.
A `display-buffer\=' ACTION, or nil for Emacs\='s own choice.  Distinct from
the other two because a dictionary is consulted and closed where an entry is
read: `diogenes-old-pdf-display-action\=' is the value the print dictionaries
use today, and this is where it is heading."
  :type 'sexp
  :group 'classicist-windows)

(defcustom classicist-gather-frames 'auto
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

`classicist-lookup-display-action\=' and its two companions still take
precedence: an answer given there is given first refusal."
  :type '(choice (const :tag "Follow pop-up-frames" auto)
                 (const :tag "Always" t)
                 (const :tag "Never" nil))
  :group 'classicist-windows)

(defcustom classicist-frame-parameters
  '((name . "Diogenes"))
  "Parameters for a frame made to hold a Diogenes buffer.
The name is worth keeping: it is what a tiling window manager matches on to
place these frames by rule.  A width and a height are deliberately NOT here
-- a tiling manager assigns the space, and a frame that asks for a size it
cannot have leaves part of its tile empty."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'classicist-windows)

(defcustom classicist-role-regexps
  '(("\\`\\*diogenes-lookup" . lookup)
    ("\\`\\*Diogenes \\(?:Analysis\\|Forms\\)" . morphology)
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

    (add-to-list \='classicist-role-regexps
                 \='(\\\\`Oxford Latin Dictionary\\\\.pdf . dictionary))"
  :type '(alist :key-type regexp :value-type symbol)
  :group 'classicist-windows)

(defcustom classicist-companion-roles
  '((morphology . lookup))
  "Which role a kind should be shown beside, rather than beside the reader.
An alist of (KIND . ROLE): a buffer of KIND is displayed by splitting a window
already showing a buffer of ROLE, wherever the reader happens to be.

`morphology\=' is beside `lookup\=' because the two are the same sort of
consultation and belong in one column.  NOT because an analysis is of the entry
showing there: one may analyse a form while another word\='s entry is open, and
the pairing says where they go rather than what they are about.

And it is the LOOKUP window rather than the selected one: `ml\=' may be pressed
while reading a passage in the browser, and splitting the browser would put the
analysis in the middle of the text.  With no lookup window on the screen there
is nothing to be beside, and the ordinary rules apply.

Read in BOTH directions.  One pair answers for two arrangements: an analysis
divides the entry\='s window, and -- where an analysis is on the screen and no
entry is -- an entry divides the analysis\='s.  Whichever of the two arrives
second joins the first, which is what belonging together means.

The value may also be `selected\=', which is not a role: it means the window the
command was given from, whatever is in it.

    (setq classicist-companion-roles \='((morphology . selected)))

That is the arrangement for a reader who wants an analysis under whatever they
are looking at rather than beside the entry -- and it is deliberately not the
default, since `ml\=' from a passage would then divide the passage.  Being
`selected\=' rather than a role, it is not read in reverse: an entry is not put
beside `selected\=' by it.

Other roles work as well: `(morphology . browser)\=' puts an analysis beside the
text, and `(morphology . dictionary)\=' beside a scanned page.  Set it to nil and
an analysis takes a window by the ordinary rules."
  :type '(alist :key-type symbol
                :value-type (choice (const :tag "The entry" lookup)
                                    (const :tag "The text" browser)
                                    (const :tag "A scanned page" dictionary)
                                    (const :tag "An analysis" morphology)
                                    (const :tag "Whichever window I am in" selected)))
  :group 'classicist-windows)

(defcustom classicist-companion-direction 'below
  "Which way the companion window is divided; see
`classicist-display-beside-companion\='.
`below\=' puts the analysis under the entry, which is what reading one against
the other wants: they share the column the entry had, and the frame gains no
third column."
  :type '(choice (const :tag "Below" below) (const :tag "Above" above)
                 (const :tag "To the right" right) (const :tag "To the left" left))
  :group 'classicist-windows)

(defcustom classicist-window-behaviour 'defer
  "Where Diogenes buffers go, said in one word.
A shorthand for the three actions below, and consulted only where the action
for a kind of buffer is nil -- so setting
`classicist-lookup-display-action\=' keeps its own answer for lookups while the
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
    (setq classicist-window-behaviour
          \='((browser . defer) (lookup . split)
            (dictionary . frames) (morphology . split)))

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
  :group 'classicist-windows)

(defcustom classicist-split-direction nil
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
  :group 'classicist-windows)

(defcustom classicist-split-size nil
  "How much of the divided window the new one takes, or nil for half.
A number of lines or columns, or a float between 0 and 1 for a fraction of
what is being divided.  Applied in whichever direction the split went.

An ALIST answers per kind, as `classicist-window-behaviour\=' does:

    (setq classicist-split-size \='((lookup . 0.4) (dictionary . 0.55)))

A kind the alist does not mention gets half, which is what Emacs does unasked.

It governs the split that MAKES a window and nothing after.  Where a kind
REUSES another\='s window -- a scanned page taking the entry\='s, a second entry
taking the first\='s -- there is no split and no size of its own: one window has
one size, and the buffer that arrives second inherits it.  So a size for a
kind that never gets a window of its own has nothing to act on."
  :type '(choice (const :tag "Half" nil)
                 (number :tag "Lines, columns, or a fraction")
                 (alist :key-type symbol :value-type number))
  :group 'classicist-windows)

(defcustom classicist-split-from 'selected
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
  :group 'classicist-windows)

(defcustom classicist-morphology-display-action nil
  "Where an analysis or a list of forms appears, or nil for the shorthand.
A `display-buffer\=' action, as `classicist-lookup-display-action\=' is.

These buffers -- `*Diogenes Analysis*\=' and `*Diogenes Forms*\=' -- used to be
displayed as lookups, and so replaced whatever entry one was reading.  They are
a different thing: an entry is what a dictionary says about a word, and an
analysis is what the morphology says about a form, and a reader consulting one
about the other wants both on the screen at once."
  :type '(choice (const :tag "Follow classicist-window-behaviour" nil)
                 (sexp :tag "A display-buffer action"))
  :group 'classicist-windows)

(defcustom classicist-claim-buffers t
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
  :group 'classicist-windows)

(defcustom classicist-claim-buffer-function 'auto
  "How a Diogenes buffer is claimed by the current perspective.
  `auto\=' -- the default -- looks for what is installed and uses it, or does
nothing where nothing is.  persp-mode and perspective.el are both found this
way: they share the name `persp-add-buffer\=' and both accept a buffer, which
is all that is wanted here.

A function of one argument to do it yourself, for a workspace package this
does not know -- eyebrowse, bufler, something local.  Nil never claims, the
same as `classicist-claim-buffers\=' nil.

Tab-bar tabs need nothing: a tab holds a window configuration rather than a
set of buffers, so a buffer is reachable from any of them."
  :type '(choice (const :tag "Detect what is installed" auto)
                 (const :tag "Never" nil)
                 function)
  :group 'classicist-windows)

(defcustom classicist-display-debug nil
  "When non-nil, record every decision `classicist-display-buffer\=' makes.
Each call appends a paragraph to `*diogenes-display-log*\=': which of the four
branches was taken, what was in force when it was taken, the windows before
and after, and the window returned.

Here because one symptom -- a lookup taking the window of the text it was
looked up from, on one configuration and not the others -- took a day of
probing and was not explained.  Every component measured correctly in
isolation while the whole measured wrong, which is the signature of a
decision being made where nobody is looking.  A log of the decision itself
answers in one keypress what the probing did not.

    (setq classicist-display-debug t)

then do the thing that misbehaves, and read the buffer."
  :type 'boolean
  :group 'classicist-windows)

(defcustom classicist-home-buffer-names
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
  :group 'classicist-windows)





(defun classicist--buffer-role (buffer)
  "Which frame BUFFER belongs in, or nil.
By name first and by major mode second -- see `classicist-role-regexps\=' and
`classicist-role-modes\=', either of which a module may add to.

BUFFER may be a buffer or a name, but it has to EXIST: a name for a buffer that
has not been created answers nil."
  (when-let* ((buffer (get-buffer buffer))
              (name (buffer-name buffer)))
    (or (cdr (cl-find-if (lambda (rule) (string-match-p (car rule) name))
                         classicist-role-regexps))
        (cdr (assq (buffer-local-value 'major-mode buffer)
                   classicist-role-modes)))))


(defun classicist--remember-role (window role)
  "Note on WINDOW that it has held a buffer of ROLE.
A window keeps a list, most recent first, so a window that held an entry and now
holds a scanned page still answers to `lookup\='.

Which is the point of it.  A scan REPLACES the entry by default, and the window
then shows a PDF: the next entry looked for a window showing a lookup buffer,
found none, and split -- so a reader who consulted the print and then looked up
another word got a third window instead of the entry\='s own back.  The window
had
held an entry a moment before and nothing said so."
  (when (window-live-p window)
    (let ((held (window-parameter window 'diogenes-roles)))
      (set-window-parameter window 'diogenes-roles
                            (cons role (delq role (copy-sequence held)))))))


(defun classicist--window-that-held (role)
  "A window on a visible frame that holds, or has held, a buffer of ROLE.
Windows showing that kind NOW come first: a second entry belongs beside the
first, not in the window where a scan happens to have displaced one.

For PLACEMENT only.  The keys for going between windows use
`classicist--windows-of-role\=', which asks what a window shows and not what it
once showed -- `C-c C-l\=' should take a reader to an entry, and a window
holding
a page of the OLD is not an entry however lately it was."
  (or (classicist--window-of-role role)
      (catch 'found
        (dolist (frame (frame-list))
          (when (frame-visible-p frame)
            (dolist (window (window-list frame 'no-minibuffer))
              (when (memq role (window-parameter window 'diogenes-roles))
                (throw 'found window))))))))


(defun classicist--windows-of-role (role)
  "Every window on a visible frame showing a buffer whose role is ROLE.
In a settled order -- the frame list, and within a frame the window list -- so
that going from one to the next lands somewhere predictable rather than
wherever the last command happened to leave things."
  (let (found)
    (dolist (frame (frame-list))
      (when (frame-visible-p frame)
        (dolist (window (window-list frame 'no-minibuffer))
          (when (eq role (classicist--buffer-role (window-buffer window)))
            (push window found)))))
    (nreverse found)))


(defun classicist--window-of-role (role)
  "A window on any visible frame showing a buffer whose role is ROLE.
The first of `classicist--windows-of-role\=', for callers that want somewhere to
put a buffer rather than somewhere to go."
  (car (classicist--windows-of-role role)))


(defun classicist--companion-role (kind)
  "The role KIND belongs beside, from `classicist-companion-roles\=', or nil.
Read in BOTH directions, the relation being between the two and not from one to
the other: an entry and its analysis belong together, so whichever arrives
second joins the first.  With an analysis on the screen and no entry, an entry
divides the analysis\='s window, exactly as an analysis divides an entry\='s.

So one pair, `(morphology . lookup)\=', answers for both."
  (or (cdr (assq kind classicist-companion-roles))
      ;; Reversed only for a real ROLE.  `(morphology . selected)' says where an
      ;; analysis goes and nothing about where an entry goes, so reading it
      ;; backwards -- and concluding that an entry belongs beside `morphology' --
      ;; would be inventing an instruction the reader did not give.
      (let ((pair (rassq kind classicist-companion-roles)))
        (and pair (not (eq (cdr pair) 'selected)) (car pair)))))


(defun classicist-display-beside-companion (buffer alist)
  "Show BUFFER by splitting the window of the role it belongs beside.
A `display-buffer\=' action function, consulting
`classicist-companion-roles\='.  Returns nil where there is no such window --
so the actions after it get their turn, and a first analysis with no entry
open behaves like anything else.

The split goes downward by default, an entry and its analysis reading as one
column; `classicist-companion-direction\=' says otherwise."
  (when-let* ((kind (classicist--buffer-role buffer))
              (beside (classicist--companion-role kind))
              ;; `selected' is not a role but the window in hand: a reader who
              ;; wants an analysis under whatever they are reading, rather than
              ;; in the lookup window's column.
              (window (if (eq beside 'selected)
                          (selected-window)
                        (classicist--window-of-role beside))))
    ;; Not `split-window-sensibly\=': the thresholds would refuse a window that
    ;; is merely half a frame, which is what an entry\='s window usually is.
    (let ((new (ignore-errors
                 (split-window window nil classicist-companion-direction))))
      (when (window-live-p new)
        (window--display-buffer buffer new 'window alist)))))


(defun classicist-display-in-role-frame (buffer alist)
  "Show BUFFER in the frame its kind already occupies, if there is one.
A `display-buffer\=' action function.  `display-buffer-reuse-window\=' cannot
do this: it looks for a window showing the SAME buffer, and every entry is a
new buffer.  What is wanted is a window showing a SIBLING -- any other
lookup -- so that the second entry replaces the first instead of opening
another frame beside it.

Returns nil where there is no such frame, so the actions after it get their
turn: normally `display-buffer-pop-up-frame\='."
  (when-let* ((role (classicist--buffer-role buffer))
              (window (classicist--window-that-held role)))
    (window--display-buffer buffer window 'reuse alist)))


(defun classicist--gathering-p ()
  "Whether Diogenes buffers are being gathered into frames at the moment.
Asked at display time, so `pop-up-frames\=' may be set or unset in a running
Emacs and the answer changes with it."
  (pcase classicist-gather-frames
    ('auto (or (memq 'frames
                     (if (and (consp classicist-window-behaviour)
                              (consp (car classicist-window-behaviour)))
                         (mapcar #'cdr classicist-window-behaviour)
                       (list classicist-window-behaviour)))
               (and pop-up-frames t)))
    (value (and value t))))


(defun classicist--gathering-action ()
  "The action that keeps each kind of Diogenes buffer in one frame."
  `((classicist-display-in-role-frame display-buffer-pop-up-frame)
    (inhibit-same-window . t)
    (reusable-frames . visible)
    (pop-up-frame-parameters . ,classicist-frame-parameters)))


(defun classicist--split-size-for (kind)
  "What `classicist-split-size\=' says about KIND, or nil for half."
  (if (and (consp classicist-split-size)
           (consp (car classicist-split-size)))
      (cdr (assq kind classicist-split-size))
    classicist-split-size))


(defun classicist--split-alist (&optional kind)
  "The `display-buffer\=' alist entries describing how to divide a window.
KIND selects the size, `classicist-split-size\=' being answerable per kind."
  (append
   (when classicist-split-direction
     (list (cons 'direction classicist-split-direction)))
   (let ((size (classicist--split-size-for kind)))
     (when size
       (list (cons (if (memq classicist-split-direction '(right left))
                       'window-width
                     'window-height)
                   size))))
   (pcase classicist-split-from
     ('main '((window . main)))
     ('root '((window . root)))
     (_ nil))))


(defun classicist--split-functions ()
  "The functions that make a new window, in the order to try them.
`display-buffer-in-direction\=' when a direction was asked for, because
`display-buffer-pop-up-window\=' has none to give it; then the ordinary
pop-up; then `classicist--display-split-anyway\=', which does not ask."
  (append
   (when classicist-split-direction '(display-buffer-in-direction))
   (when (eq classicist-split-from 'largest)
     '(display-buffer-use-least-recent-window))
   '(display-buffer-pop-up-window
     classicist--display-split-anyway)))


(defun classicist--behaviour-action (behaviour &optional kind)
  "The `display-buffer\=' action BEHAVIOUR stands for, for a buffer of KIND.
Built rather than looked up, because `classicist-split-direction\=',
`classicist-split-size\=' and `classicist-split-from\=' have a say in three of the
four and a table could not hold them.

`classicist-display-in-role-frame\=' leads all of them: a second entry belongs
where the first is, whether that is a window or a frame, and only a first
entry needs somewhere new."
  (pcase behaviour
    ('reuse `((classicist-display-in-role-frame display-buffer-same-window)
              (inhibit-same-window . nil)))
    ('split `(,(append
                (list 'classicist-display-in-role-frame)
                ;; A kind with a COMPANION is shown beside that companion
                ;; rather than beside the reader: an analysis belongs in the
                ;; lookup window's column, wherever `ml' was pressed from.  Tried
                ;; after the role frame -- a second analysis joins the first --
                ;; and before the ordinary splitting, which is what happens
                ;; when there is no entry on the screen to be beside.
                ;; Either member of a companion pair, the relation being
                ;; symmetric: an analysis divides the entry's window, and an
                ;; entry divides the analysis's where there is no entry yet.
                (when (and kind (classicist--companion-role kind))
                  (list 'classicist-display-beside-companion))
                ;; No KIND: this function has none to take -- the per-kind
                ;; SPLIT DIRECTION was reverted deliberately, and only the
                ;; size is answerable per kind.
                (classicist--split-functions))
              ,@(classicist--split-alist kind)))
    ('frames `((classicist-display-in-role-frame
                display-buffer-pop-up-frame
                ,@(classicist--split-functions))
               (inhibit-same-window . t)
               (reusable-frames . visible)
               (pop-up-frame-parameters . ,classicist-frame-parameters)
               ,@(classicist--split-alist kind)))
    (_ nil)))


(defun classicist--behaviour-for (kind)
  "What `classicist-window-behaviour\=' says about KIND.
Diogenes\=' own roles are `browser\=', `lookup\=', `dictionary\=' and
`morphology\=' -- a passage, an entry, a scanned page, and an analysis or list
of forms -- and a module may register others: see `classicist-role-modes\='.

A word applies to every kind; an alist answers per kind, and a kind it does
not mention gets `defer\='."
  (if (and (consp classicist-window-behaviour)
           (consp (car classicist-window-behaviour)))
      (or (cdr (assq kind classicist-window-behaviour)) 'defer)
    classicist-window-behaviour))


(defun classicist--display-split-anyway (buffer alist)
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
  (let* ((horizontal (memq classicist-split-direction '(right left)))
         (side (pcase classicist-split-direction
                 ('above 'above) ('left 'left)
                 (_ nil)))
         ;; The size the ACTION carries, which is the one for this kind:
         ;; `classicist--split-alist' put it there.  Reading
         ;; `classicist-split-size' here instead would ignore a per-kind
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


(defun classicist--display-action (kind)
  "The `display-buffer\=' action for a Diogenes buffer of KIND.
KIND is a role -- see `classicist-role-modes\=' -- and nil for none.

The action set for that kind if there is one, and otherwise whatever
`classicist-window-behaviour\=' says -- in that order, so that naming an action
for lookups leaves the browser and the dictionaries on the shorthand.  A
reader who wants one thing arranged specially should not have to spell out
the other two."
  (or (pcase kind
        ;; The four that had an option each, and they still win: a reader who
        ;; set one should not find it overruled by a default.
        ('lookup classicist-lookup-display-action)
        ('browser classicist-browser-display-action)
        ('dictionary classicist-dictionary-display-action)
        ('morphology classicist-morphology-display-action)
        (_ nil))
      ;; And any role at all, including one a module registered.
      (cdr (assq kind classicist-display-actions))
      ;; `defer' yields nil, there being nothing for it to be: it means that
      ;; no action of ours is passed at all.
      (classicist--behaviour-action (classicist--behaviour-for kind) kind)))


(defun classicist--claim-buffer (buffer)
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
  (when (and classicist-claim-buffers buffer)
    (save-window-excursion
      (save-current-buffer
        (pcase classicist-claim-buffer-function
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


(defvar classicist--display-log-before nil)

(defvar classicist--display-log-branch nil)

(defvar classicist--display-log-detail nil)


(defun classicist--display-log (buffer window)
  "Append what `classicist-display-buffer\=' just decided about BUFFER."
  (when classicist-display-debug
    (with-current-buffer (get-buffer-create "*diogenes-display-log*")
      (goto-char (point-max))
      (insert (format "%s  %s\n  branch  %s\n  detail  %S\n\
  before  %S\n  after   %S\n  window  %s (%s)\n\n"
                      (format-time-string "%H:%M:%S")
                      (buffer-name (get-buffer buffer))
                      (or classicist--display-log-branch "?")
                      classicist--display-log-detail
                      classicist--display-log-before
                      (mapcar (lambda (w) (buffer-name (window-buffer w)))
                              (window-list))
                      window
                      (if (window-live-p window)
                          (buffer-name (window-buffer window))
                        "dead"))))))


(defmacro classicist--with-our-answer (&rest body)
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


(cl-defun classicist-display-buffer (buffer &key kind same-window action
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

KIND selects the action -- see `classicist--display-action\=' -- and ACTION
overrides it, for a caller that has computed one.

FALLBACK is an action for when nothing else has an opinion: after what the
reader asked for, and after the gathering.  A module with a display
arrangement of its own passes it there rather than as ACTION, so that
`classicist-window-behaviour\=' and `classicist-gather-frames\=' can still
answer --
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
See `classicist--sole-home-window-p\='.

The window is SELECTED unless NO-SELECT, because that is what the calls
this replaced did.  `pop-to-buffer\=' displays AND selects; `display-buffer\='
only displays -- and a reader left in the buffer they came from, looking at
an entry in another window, finds that the keys they expect are undefined,
because the buffer they are in is not the entry.  The distinction is easy to
miss and was missed here."
  ;; Claimed BEFORE it is displayed, so that whatever watches the display --
  ;; a perspective, a workspace -- sees a buffer that already belongs.
  (classicist--claim-buffer buffer)
  (let* ((classicist--display-log-before
          (and classicist-display-debug
               (mapcar (lambda (w) (buffer-name (window-buffer w)))
                       (window-list))))
         (classicist--display-log-branch nil)
         (classicist--display-log-detail nil)
         (chosen (or action (classicist--display-action kind)))
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
       ((or (classicist--sole-home-window-p) same-window)
        (setq classicist--display-log-branch "intent: same-window or lone home"
              classicist--display-log-detail
              (list :same-window same-window
                    :sole-home (classicist--sole-home-window-p)))
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
              (classicist--with-our-answer (display-buffer buffer))
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
        (setq classicist--display-log-branch "action set by the reader"
              classicist--display-log-detail (list :action chosen))
        (let ((display-buffer-overriding-action chosen))
          (classicist--with-our-answer (display-buffer buffer))))
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
       ((classicist--gathering-p)
        (setq classicist--display-log-branch "gathering into frames"
              classicist--display-log-detail
              (list :pop-up-frames pop-up-frames))
        (let ((display-buffer-overriding-action (classicist--gathering-action)))
          (classicist--with-our-answer (display-buffer buffer))))
       ;; A module's own arrangement, where it has one and nothing above had
       ;; an opinion.
           (fallback
            (setq classicist--display-log-branch "the module's own action"
                  classicist--display-log-detail (list :fallback fallback))
            (classicist--with-our-answer (display-buffer buffer fallback)))
       ;; Nothing set and no frames: whatever is installed decides --
       ;; `window-purpose' under Spacemacs, a popup manager under Doom, plain
       ;; `display-buffer' elsewhere.
           (t
            (setq classicist--display-log-branch "deferred to what is installed"
                  classicist--display-log-detail
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
      ;; enough of this package depends on it -- `classicist--browse-work'
      ;; sets the major mode in whatever buffer is current after displaying,
      ;; and `diogenes--show-dict-entry' recenters -- that leaving it to
      ;; follow from `select-window' is not good enough.
      (set-buffer (window-buffer window)))
    ;; What this window has held, so a window whose entry a scan replaced is
    ;; still the place the next entry belongs.  Recorded from the KIND asked
    ;; for rather than from the buffer's role: they agree, and the kind is what
    ;; the caller meant.
    (when (and (window-live-p window) kind)
      (classicist--remember-role window kind))
    (classicist--display-log buffer window)
    window))


(defun classicist--home-buffer-p (name)
  "Non-nil if NAME is a startup or home buffer.
`classicist-home-buffer-names' plus whatever the distribution calls its own,
asked of the variables the distributions define: this way a renamed or
localised home buffer is still recognised."
  (and name
       (or (member name classicist-home-buffer-names)
           (cl-some (lambda (symbol)
                      (and (boundp symbol)
                           (equal name (symbol-value symbol))))
                    '(spacemacs-buffer-name
                      +doom-dashboard-name
                      dashboard-buffer-name))
           nil)))


(defun classicist--sole-home-window-p ()
  "Non-nil if the selected frame shows a home buffer and nothing else.
The question a display rule needs to ask before it splits or pops: there
is a window here, and what it holds is not worth keeping."
  (and (one-window-p)
       (classicist--home-buffer-p (buffer-name (window-buffer (selected-window))))))

;;; Going from one window to another

;; LEFT BEHIND BY THE FIRST EXTRACTION, on the strength of a closure walk that
;; reported `--focus-role' reaching every dictionary module.  It does not: the
;; reach was through `diogenes-old-visit-dictionary', named in the DOCSTRING of
;; the dictionary command.  Prose, not a call.
;;
;; Asked for the direct edge instead, this group calls one thing outside
;; itself -- `classicist--windows-of-role', which is here -- so here is where
;; it belongs.

(defun classicist--focus-role (role what)
  "Go to a window holding a buffer of role ROLE, raising its frame if need be.
WHAT names the kind, for the message when there is none.

With ONE such window this simply goes there.  With several -- which `frames\='
makes ordinary, a scan of the OLD beside a scan of the TLL -- pressing the key
again goes to the next, and past the last comes back to the first.  So a reader
who wants a particular one presses until they arrive, and a reader with only one
of a kind never notices there was a choice.

Where point is already in a window of that role, the NEXT one is chosen; where
it is not, the first.  A reader pressing the key means `take me there\=', and
answering `you are there\=' would be true and useless."
  (let ((windows (classicist--windows-of-role role)))
    (cond
     ((null windows) (message "No %s window open" what))
     (t
      (let* ((here (selected-window))
             (position (cl-position here windows))
             (target (if position
                         (nth (mod (1+ position) (length windows)) windows)
                       (car windows))))
        (unless (eq (window-frame target) (selected-frame))
          (select-frame-set-input-focus (window-frame target)))
        (select-window target)
        (when (and position (> (length windows) 1))
          (message "%s %d of %d" (capitalize what)
                   (1+ (mod (1+ position) (length windows)))
                   (length windows))))))))

(defun classicist-focus-lookup ()
  "Go to the entry -- raising its frame if it is in one."
  (interactive)
  (classicist--focus-role 'lookup "lookup"))

(defun classicist-focus-browser ()
  "Go to the corpus browser -- raising its frame if it is in one."
  (interactive)
  (classicist--focus-role 'browser "browser"))

(defun classicist-focus-dictionary ()
  "Go to the scanned dictionary -- raising its frame if it is in one.
Bound to nothing by default, and that is deliberate: `C-c C-e\=' reaches the
scans, `diogenes-old-visit-dictionary\=' preferring the page opened from the
entry one is reading and calling this when there is none.  One key for the whole
of it.  Bind this where the plain behaviour is wanted, or call it from a
function of your own."
  (interactive)
  (classicist--focus-role 'dictionary "dictionary"))

(defun classicist-focus-morphology ()
  "Go to the analysis -- raising its frame if it is in one."
  (interactive)
  (classicist--focus-role 'morphology "analysis"))

(defcustom classicist-focus-keys
  '((classicist-focus-browser    . "C-c C-b")
    (classicist-focus-lookup     . "C-c C-l")
    (classicist-focus-morphology . "C-c C-a")
    ;; The scanned page has no key here: `C-c C-e' is
    ;; `diogenes-old-visit-dictionary', which prefers the page opened from the
    ;; entry one is reading, falls back on this command, and cycles through this
    ;; command when pressed inside a scan.  One key doing the whole of it beats
    ;; two that differ in a way nobody can remember.  Give this command a key of
    ;; its own if the plain behaviour is wanted.
    (classicist-focus-dictionary . nil))
  "Keys for going from one Diogenes window to another, as (COMMAND . KEY).
Bound in the Diogenes buffers themselves -- an entry, a passage, an analysis, a
scanned page -- since going from one to another is something one does while in
one of them.  Nil for a key binds nothing.

`C-c\=' and a letter is reserved for the user by the Emacs conventions, and
`C-c C-<letter>\=' belongs to the major mode; these are major-mode maps, so
these are ours to take.  Under evil the read-only buffers are in Emacs state,
so the chords work there without further arrangement.

The SCANNED page is reached by `C-c C-e\=', which is
`diogenes-old-visit-dictionary-key\=' and not set here: that command prefers the
page opened from the entry one is reading, falls back on
`classicist-focus-dictionary\=', and CYCLES through it when pressed inside a
scan.
So one key does the whole of it, and this table leaves that command unbound
rather than offering a second key that differs in a way nobody can remember.

`diogenes-purpose\=' bound `C-c C-b\=' and `C-c C-l\=' to commands of its own
before these existed.  It no longer does: the keys are the same and the commands
are in the core, so they work whether purpose is loaded or not.

These matter most when the kinds are in FRAMES, where there is no window to move
to with `C-x o\=' -- but they work within a frame as well, which is why they are
bound whatever `diogenes-window-behaviour\=' says.

Set to nil to bind none of them.  The commands remain, and the `diogenes\='
menu offers them under `w\='."
  :type '(choice (const :tag "Bind none" nil)
                 (alist :key-type function
                        :value-type (choice key-sequence
                                            (const :tag "Unbound" nil))))
  :group 'classicist-windows)

(defvar classicist--focus-maps
  '(diogenes-lookup-mode-map
    classicist-analysis-mode-map
    classicist-browser-mode-map
    diogenes-search-mode-map
    diogenes-select-forms-mode-map
    diogenes-corpus-mode-map
    ;; A minor mode of OURS for the scanned pages, and not
    ;; `pdf-view-mode-map': that map belongs to pdf-tools, and binding into it
    ;; would take these keys from every PDF a reader opens.
    ;; `diogenes-pdf-search-mode' is enabled on the configured dictionaries and
    ;; nowhere else, which is the same reasoning that gave `L' a minor mode
    ;; rather than a viewer binding.
    diogenes-pdf-search-mode-map)
  "The maps the focus keys are bound in.
Every buffer one might be reading FROM: our own modes, and the scanned pages
through our own minor mode -- a scan being where one is most likely to want the
entry back.")

(defun classicist-install-focus-keys ()
  "Bind `classicist-focus-keys\=' in the Diogenes buffers.
Called for its effect at load, and again after changing the option.  A key the
option no longer names is left alone rather than hunted down: unbinding by hand
is `keymap-unset\=', and guessing at what a reader may have bound themselves is
worse than leaving one key too many."
  (interactive)
  (dolist (map-symbol classicist--focus-maps)
    (when (boundp map-symbol)
      (let ((map (symbol-value map-symbol)))
        (dolist (cell classicist-focus-keys)
          (when (and (cdr cell) (keymapp map))
            (condition-case nil
                (keymap-set map (cdr cell) (car cell))
              ;; A viewer may have made its map something `keymap-set' will not
              ;; take; that is its business, and one map refusing is no reason
              ;; to leave the others unbound.
              (error nil))))))))

;;;###autoload
(defun classicist-focus (role)
  "Go to a window holding a buffer of ROLE.
FOR ANY ROLE, including one a module registered.  The four commands above
are the roles Diogenes ships and the ones with keys; a Diorisis hit list or a
treebank tree has a role too -- see `classicist-role-modes\=' -- and had no
way to be reached until this existed.

Interactively, completes on the roles `classicist-role-modes\=' knows."
  (interactive
   (list (intern (completing-read
                  "Role: "
                  (delete-dups (mapcar #'cdr classicist-role-modes))
                  nil t))))
  (classicist--focus-role role (symbol-name role)))

(provide 'classicist-windows)

;;; classicist-windows.el ends here
