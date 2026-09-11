;;; diogenes-org.el --- org links to passages and dictionary entries -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Victor Sousa

;; Author: Victor Sousa
;; URL: https://github.com/VictorSousa92/org-integration
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: classics, greek, latin, org, hypermedia

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Org links to what Diogenes shows: a passage of a text, an entry in a
;; dictionary, a page of a scanned one.  `C-c l' in a Diogenes buffer stores a
;; link; `C-c C-o' on it in an org file opens the thing again.
;;
;;     [[diogenes:passage:tlg:0086:025:1053a.15-1053a.18][Arist. Metaph. 1053a15-18]]
;;     [[diogenes:entry:greek:le/gw][λέγω, LSJ]]
;;     [[diogenes:page:old:1283][OLD p. 1283]]
;;
;; ONE LINK TYPE with a discriminator, rather than three types.  A reader
;; writing an org file has one thing to remember, and the second field says what
;; kind of thing is meant.
;;
;; THE TARGET IS NOT THE DESCRIPTION.  A citation as a scholar writes it --
;; `1053a15', the Bekker page running into the line -- cannot be read back:
;; nothing in the string says where the page ends, and knowing would mean
;; knowing the work's levels before parsing the citation that identifies the
;; work.  So the target carries `1053a.15', a stop between every level, and the
;; description carries the conventional form.  The part that must function does
;; not depend on any convention.
;;
;; REQUIRES the fork at https://github.com/VictorSousa92/diogenes.el, branch
;; `org-integration'.  `diogenes-browser-reference', `diogenes-open-passage' and
;; the abbreviation table are not in the upstream package; this is built on
;; them, and on nothing private -- `diogenes--browse-work' has two hyphens and
;; is none of our business.

;;; Code:

(require 'org)

;; NOT `(require \='diogenes)\='.  Loading the whole package runs its startup
;; check, which signals `diogenes-path is not set!\=' -- right for a reader who
;; has not configured it, and fatal to a batch compile, which has no
;; configuration at all.
;;
;; Nothing here needs Diogenes at compile time either: every function used is
;; declared below and called at run time, when a reader is in a Diogenes buffer
;; and Diogenes is therefore loaded.  The `eval-when-compile\=' is for the macros
;; and the mode symbols only.
(eval-when-compile (require 'cl-lib))
(require 'seq)

;; Diogenes' own, called at run time.  Declared rather than required, so this
;; file compiles without a configured Diogenes and fails only where it should:
;; at the point a reader asks for something Diogenes has to answer.
(declare-function diogenes-browser-reference "diogenes-browser" ())
(declare-function diogenes-reference-to-string "diogenes-browser" (reference))
(declare-function diogenes-open-passage "diogenes-browser"
                  (corpus author work &optional passage))
(declare-function diogenes-citation-interval-from-key "diogenes-browser" (key))
(declare-function diogenes-lookup-greek "diogenes-perseus" (word))
(declare-function diogenes-lookup-latin "diogenes-perseus" (word))

(defvar diogenes-browser-mode-hook)
(defvar diogenes-lookup-mode-hook)

(defgroup diogenes-org nil
  "Org links to Diogenes' passages, entries and scanned pages."
  :group 'diogenes
  :prefix "diogenes-org-")

(defcustom diogenes-org-link-type "diogenes"
  "The name of the link type, before the colon.
One type for all three kinds, the kind being the field after it.  Changing this
after links are written makes those links unfollowable, org resolving a link by
its type."
  :type 'string
  :group 'diogenes-org)

(defcustom diogenes-org-reuse-browser nil
  "Whether following a passage link reuses a browser rather than making one.
Each browse starts a Perl process and a buffer of its own, so following the same
link ten times leaves ten browsers.  Set this and a browser already reading that
work is shown instead.

OFF, because a browser already open is at whatever passage its reader left it,
and reuse CANNOT page it to the one the link names: paging is the Perl process's
business and there is no route to it from outside.  So a link followed into a
reused browser shows the wrong lines and reports that the ones it named are not
in view -- which is exactly what it did, and is not what a link is for.

A link should take a reader where it points.  Buffers accumulating is the lesser
evil, and `q' closes one."
  :type 'boolean
  :group 'diogenes-org)

;;; Reading and writing the link

(defun diogenes-org--encode (parts)
  "PARTS as the tail of a link, colon-separated.
Colons are the separator, so a part containing one is escaped.  Nothing
Diogenes produces does -- corpus, author and work are numbers and a citation is
digits and stops -- but an entry key comes from a dictionary and betacode has
its own punctuation."
  (mapconcat (lambda (part)
               (replace-regexp-in-string ":" "%3A" (format "%s" part)))
             parts ":"))

(defun diogenes-org--decode (path)
  "The link PATH as its parts, unescaped."
  (mapcar (lambda (part) (replace-regexp-in-string "%3A" ":" part))
          (split-string path ":")))

;;; Storing

(defun diogenes-org--store-passage ()
  "A link to the passage in this browser buffer, or nil."
  (let ((reference (diogenes-browser-reference)))
    (when (and reference (plist-get reference :key))
      (org-link-store-props
       :type diogenes-org-link-type
       :link (concat diogenes-org-link-type ":"
                     (diogenes-org--encode
                      (list "passage"
                            (plist-get reference :corpus)
                            (plist-get reference :author)
                            (plist-get reference :work)
                            (plist-get reference :key))))
       :description (diogenes-reference-to-string reference))
      t)))

(defun diogenes-org--store-entry ()
  "A link to the dictionary entry in this lookup buffer, or nil.
The entry's key and language are text properties the lookup put there, so an
entry can be reopened by name -- which is what makes a link to one possible at
all."
  (let ((key (get-text-property (point) 'entry-key))
        (language (get-text-property (point) 'lang)))
    (when (and key language)
      (org-link-store-props
       :type diogenes-org-link-type
       :link (concat diogenes-org-link-type ":"
                     (diogenes-org--encode (list "entry" language key)))
       :description (format "%s, %s" key
                            (if (equal language "greek") "LSJ" "Lewis & Short")))
      t)))

(defun diogenes-org--store-page ()
  "A link to the scanned page in this document buffer, or nil.
The file and the page, which is all a scan is.  The file rather than the
dictionary's name: a reader may have the OLD where another has it elsewhere, and
a path is what `diogenes-old--show-page' takes."
  (when (and (derived-mode-p 'pdf-view-mode 'doc-view-mode)
             buffer-file-name)
    ;; `pdf-view-current-page' is a MACRO, so `fboundp' answers t and calling it
    ;; signals `Invalid function'.  `funcall' cannot call a macro either.  What
    ;; both viewers do have is a variable, and pdf-tools' expands to exactly
    ;; this one -- so the variable is what to read, and no dispatch is needed.
    (let ((page (cond ((and (derived-mode-p 'pdf-view-mode)
                            (fboundp 'image-mode-window-get))
                       ;; What `pdf-view-current-page' expands to: the page is a
                       ;; window property, image-mode's rather than
                       ;; pdf-tools' own.
                       (image-mode-window-get 'page))
                      ((and (derived-mode-p 'doc-view-mode)
                            (boundp 'doc-view-current-page))
                       (symbol-value 'doc-view-current-page))
                      (t nil))))
      (when page
        (org-link-store-props
         :type diogenes-org-link-type
         :link (concat diogenes-org-link-type ":"
                       (diogenes-org--encode
                        (list "page" (abbreviate-file-name buffer-file-name)
                              page)))
         :description (format "%s p. %s"
                              (file-name-base buffer-file-name) page))
        t))))

;;;###autoload
(defun diogenes-org-store-link ()
  "Store a link to whatever this Diogenes buffer is showing.
A passage in the browser, an entry in a lookup, a page in a scan.  Nil in any
other buffer, so `org-store-link' goes on to ask whoever else is interested."
  (cond ((derived-mode-p 'diogenes-browser-mode) (diogenes-org--store-passage))
        ((derived-mode-p 'diogenes-lookup-mode) (diogenes-org--store-entry))
        ((derived-mode-p 'pdf-view-mode 'doc-view-mode)
         (diogenes-org--store-page))))

;;; Following

(defcustom diogenes-org-highlight t
  "Whether following a link marks the lines it names.
A link says which lines, and a browser that opens at them without saying which
leaves a reader to count.  The marking fades: it answers `where?\=' and then gets
out of the way of reading.

Nil to open the passage and mark nothing."
  :type 'boolean
  :group 'diogenes-org)

(defcustom diogenes-org-highlight-style 'colour
  "How the lines a link named are marked.

`colour\=' colours the TEXT and leaves the background alone, which over several
lines reads better than a block: the words stay words.

`overlay\=' puts a background on them, `diogenes-org-highlight-background-face\=',
which inherits `highlight\=' -- a face every theme styles deliberately because so
much depends on it.

`pulse\=' fades the marking in and out with `pulse.el\='.  Prettier where it shows,
and it often does not: `pulse-highlight-start-face\=' is a face most themes leave
alone, so its background is whatever the default happens to be -- Catppuccin
leaves it at #45475a, a background shade, and the pulse is then invisible
against the buffer.  Which is how this came to be an option: the marking worked
from the first and could not be seen."
  :type '(choice (const :tag "The text coloured, until dismissed" colour)
                 (const :tag "A background, until dismissed" overlay)
                 (const :tag "A pulse, where the theme styles one" pulse))
  :group 'diogenes-org)

(defcustom diogenes-org-highlight-seconds nil
  "How long a marking stays, or nil to leave it until dismissed.
A number of seconds where a marking should go by itself.  Nil is the default: a
reader following a link to a passage is going to read the passage, and a marking
that vanishes while they are still finding their place has answered nothing.

`q\=' takes it off with the buffer, and `diogenes-org-unhighlight\=' takes it off
without."
  :type '(choice (const :tag "Until dismissed" nil) number)
  :group 'diogenes-org)

(defface diogenes-org-highlight-face
  '((t :inherit warning))
  "Face for the lines a link named, colouring the TEXT.
`warning\=' because every theme styles it deliberately and none styles it
alarmingly: an orange or a yellow, legible as text, which is the point of
colouring the words rather than the background.

Not `highlight\=': that is a BACKGROUND face, and a block of it over several lines
sits on the reading rather than pointing at it."
  :group 'diogenes-org)

(defface diogenes-org-highlight-background-face
  '((t :inherit highlight :extend t))
  "Face for the lines a link named, where a background is wanted.
Used when `diogenes-org-highlight-style\=' is `overlay\='.  `:extend\=' so a marked
line is marked to the window\='s edge rather than to the end of its text, several
lines otherwise making a ragged block."
  :group 'diogenes-org)

(defun diogenes-org-unhighlight ()
  "Take off the marking a followed link left, in this buffer.
The marking stays until it is dismissed, a reader following a link to a passage
being about to read the passage.  This is how to dismiss it without leaving the
buffer.

Only ours: an overlay carrying `diogenes-org\=', so a marking left by anything
else -- isearch, an occur, hi-lock -- is not swept up with it."
  (interactive)
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (overlay-get overlay 'diogenes-org)
      (delete-overlay overlay))))

(defun diogenes-org--citation-region (from to)
  "The bounds of the lines from citation FROM to citation TO, or nil.
Both are lists of strings, as a link carries them.  TO may be nil, and then one
line is meant.

Matched against the `cit\=' property, which every line of a passage carries and
which holds a list of numbers and symbols -- `(1053a 15)\=' -- where a link holds
strings.  So the comparison is of printed forms: `(format \"%s\" ...)\=' on each
element, which is what `diogenes-citation-to-key\=' does when it writes the link
in the first place."
  (let ((wanted (lambda (citation)
                  (and citation
                       (mapcar (lambda (element) (format "%s" element))
                               citation))))
        start end)
    (save-excursion
      (goto-char (point-min))
      (let ((match nil))
        (while (and (not end)
                    (setq match (text-property-search-forward 'cit)))
          (let ((here (funcall wanted (prop-match-value match))))
            (cond ((and (not start) (equal here from))
                   (setq start (prop-match-beginning match))
                   ;; One line where no second citation was given.
                   (unless to (setq end (prop-match-end match))))
                  ((and start to (equal here to))
                   (setq end (prop-match-end match))))))))
    (and start end (cons start end))))

(defcustom diogenes-org-highlight-tries 40
  "How many times to look for the lines before giving up.
A tenth of a second apart, so forty is four seconds.

Waiting is necessary and waiting on the PROCESS does not work.  A browser's Perl
process is a SERVER: it stays running to page the text forward and back, so it
never exits and a sentinel on it never fires -- which is why the first version of
this marked nothing at all.  What arrives is TEXT, and the thing to wait for is
the citation appearing in the buffer."
  :type 'integer
  :group 'diogenes-org)

(defun diogenes-org--highlight (buffer from to)
  "Mark the lines FROM to TO in BUFFER, once they are there.
Nothing is there when a link is followed: `diogenes--browse-work\=' starts a Perl
process and the text arrives afterwards, a filter inserting it as it comes.  So
this waits on the PROCESS and marks when it has finished.

The sentinel is added rather than replacing what is there -- the default one, on
a fresh browser -- and it calls that first, so anything Diogenes comes to do on
exit still happens."
  (when (and diogenes-org-highlight (buffer-live-p buffer))
    (diogenes-org--highlight-when-there buffer from to
                                        diogenes-org-highlight-tries)))

(defun diogenes-org--highlight-when-there (buffer from to tries)
  "Mark the lines FROM to TO in BUFFER as soon as they are in it.
Looks again every tenth of a second, TRIES times.  Stops the moment it succeeds,
so the ordinary case costs one look and the timer is never set."
  (when (buffer-live-p buffer)
    (unless (diogenes-org--highlight-now buffer from to (> tries 0))
      (when (> tries 0)
        (run-with-timer
         0.1 nil
         (lambda ()
           (diogenes-org--highlight-when-there buffer from to (1- tries))))))))

(defun diogenes-org--highlight-now (buffer from to &optional quietly)
  "Mark the lines FROM to TO in BUFFER.  Non-nil where they were found.
QUIETLY says nothing where they are not there, the caller meaning to look
again."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((bounds (diogenes-org--citation-region from to)))
        (if (not bounds)
            ;; The passage may have opened elsewhere than the link asked -- a
            ;; citation Diogenes rounds to the nearest it has -- and saying so
            ;; beats marking the wrong lines.
            (unless quietly
              (message "Opened, but the lines %s are not in view"
                       (mapconcat #'identity (or to from) ".")))
          (goto-char (car bounds))
          ;; Only where a window shows this buffer.  `recenter' signals
          ;; otherwise -- `recentering a window that does not display
          ;; current-buffer' -- and a link may well be followed into a buffer
          ;; that is not on the screen yet, the marking running from a timer
          ;; after the text arrived.
          (when (eq (window-buffer (selected-window)) (current-buffer))
            (recenter))
          ;; One marking at a time: a reader following a second link to the
          ;; same passage should see where THIS one points, not two.
          (diogenes-org-unhighlight)
          (if (and (eq diogenes-org-highlight-style 'pulse)
                   (require 'pulse nil t)
                   (fboundp 'pulse-momentary-highlight-region))
              (let ((pulse-delay 0.06) (pulse-iterations 14))
                (pulse-momentary-highlight-region (car bounds) (cdr bounds)))
            (let ((overlay (make-overlay (car bounds) (cdr bounds))))
              (overlay-put overlay 'face
                           (if (eq diogenes-org-highlight-style 'overlay)
                               'diogenes-org-highlight-background-face
                             'diogenes-org-highlight-face))
              (overlay-put overlay 'diogenes-org t)
              ;; `evaporate' so the marking goes when the text under it does --
              ;; paging replaces the buffer's contents, and an overlay left over
              ;; that would mark whatever arrived in its place.
              (overlay-put overlay 'evaporate t)
              (when (numberp diogenes-org-highlight-seconds)
                (run-with-timer
                 diogenes-org-highlight-seconds nil
                 (lambda () (when (overlayp overlay)
                              (delete-overlay overlay)))))))
          ;; Found, which is what the caller wants to know.
          t)))))

(defun diogenes-org--browser-showing (corpus author work)
  "A browser buffer already reading WORK of AUTHOR in CORPUS, or nil.
Asked through `diogenes-browser-reference\=', which is public, rather than by
reading `diogenes--browser-corpus\=' and its fellows.  Those have two hyphens: a
package outside Diogenes reading them would break on a rename as surely as one
calling a private function, and the boundary is worth keeping on both sides."
  (seq-find (lambda (buffer)
              (with-current-buffer buffer
                (and (derived-mode-p 'diogenes-browser-mode)
                     (let ((reference (diogenes-browser-reference)))
                       (and reference
                            (equal (plist-get reference :corpus) corpus)
                            (equal (plist-get reference :author) author)
                            (equal (plist-get reference :work) work))))))
            (buffer-list)))

(defun diogenes-org--follow-passage (parts)
  "Open the passage PARTS names: (CORPUS AUTHOR WORK KEY)."
  (let* ((corpus (nth 0 parts))
         (author (nth 1 parts))
         (work (nth 2 parts))
         (key (nth 3 parts))
         (interval (and key (diogenes-citation-interval-from-key key)))
         (existing (and diogenes-org-reuse-browser
                        (diogenes-org--browser-showing corpus author work))))
    (if existing
        ;; Already reading this work: show it rather than start another Perl
        ;; process.  It may be at another passage -- the buffer cannot be paged
        ;; from outside, that being the process's business -- so a reader who
        ;; wants the exact lines follows the link with a prefix.
        (progn
          (pop-to-buffer existing)
          ;; And say plainly what has happened, rather than marking whatever
          ;; this browser is showing.  It is at the passage its reader left it
          ;; at, and there is no paging it from here.
          (unless (diogenes-org--highlight-now existing (car interval)
                                               (cdr interval) t)
            (message (concat "Reusing the browser already reading %s %s/%s, "
                             "which is not at %s\n"
                             "Set diogenes-org-reuse-browser to nil to open "
                             "the passage afresh")
                     corpus author work (or key "the passage named"))))
      (let ((buffer (diogenes-open-passage corpus author work (car interval))))
        ;; And mark what the link named, when the text has arrived.
        (when (bufferp buffer)
          (diogenes-org--highlight buffer (car interval) (cdr interval)))
        buffer))))

(defun diogenes-org--follow-entry (parts)
  "Open the dictionary entry PARTS names: (LANGUAGE KEY)."
  (let ((language (nth 0 parts))
        (key (nth 1 parts)))
    (cond ((equal language "greek") (diogenes-lookup-greek key))
          ((equal language "latin") (diogenes-lookup-latin key))
          (t (user-error "No dictionary for language `%s'" language)))))

(defun diogenes-org--follow-page (parts)
  "Open the scanned page PARTS names: (FILE PAGE)."
  (let ((file (expand-file-name (nth 0 parts)))
        (page (string-to-number (or (nth 1 parts) "1"))))
    (unless (file-exists-p file)
      (user-error "No such file: %s" file))
    (find-file file)
    (cond ((fboundp 'pdf-view-goto-page) (pdf-view-goto-page page))
          ((fboundp 'doc-view-goto-page) (doc-view-goto-page page)))))

;;;###autoload
(defun diogenes-org-follow-link (path &optional _prefix)
  "Open what the link PATH names.
The first part says which kind, the rest belongs to that kind."
  (let* ((parts (diogenes-org--decode path))
         (kind (car parts))
         (rest (cdr parts)))
    (pcase kind
      ("passage" (diogenes-org--follow-passage rest))
      ("entry" (diogenes-org--follow-entry rest))
      ("page" (diogenes-org--follow-page rest))
      (_ (user-error "Unknown kind of Diogenes link: `%s'" kind)))))

;;; Exporting

(defun diogenes-org-export-link (path description backend)
  "PATH and DESCRIPTION as BACKEND wants them.
A link to a text on one's own disc means nothing to a reader of the export, so
what is exported is the CITATION -- which is what a footnote wants in any case.
`Arist. Metaph. 1053a15' is the whole of the information; the link was only ever
a convenience for the writer."
  (let ((text (or description
                  (let ((parts (diogenes-org--decode path)))
                    (mapconcat #'identity (cdr parts) " ")))))
    (pcase backend
      ('html (format "<span class=\"diogenes-citation\">%s</span>" text))
      ('latex (format "\\textit{%s}" text))
      (_ text))))

;;; Registering

;;;###autoload
(defun diogenes-org-setup ()
  "Teach org about Diogenes links.
Called at load; called again after changing `diogenes-org-link-type\\='."
  (org-link-set-parameters
   diogenes-org-link-type
   :follow #'diogenes-org-follow-link
   :store #'diogenes-org-store-link
   :export #'diogenes-org-export-link))

;;;###autoload
(eval-after-load 'org '(diogenes-org-setup))

(diogenes-org-setup)

;;;; --------------------------------------------------------------------
;;;; THE NOTES ON A PASSAGE
;;;; --------------------------------------------------------------------

;; THE OTHER DIRECTION.  Everything above goes from a note to the text: a link
;; stored, followed, the passage opened and marked.  What follows goes the
;; other way -- from the text to the notes -- which is the question a reader
;; puts far more often: `has anything been said about what I am looking at?'
;;
;; The join is the link itself.  A note keeps the passage it was made on in
;; `ROAM_REFS', in the same form the links use, so org-roam can be asked which
;; notes bear on a stretch of text and nothing new has to be invented or kept
;; in step.
;;
;; A NOTE BELONGS TO A PASSAGE, not to a page of a book, which is why none of
;; this uses `org-noter'.  That anchors a note to a location in a document --
;; `:NOTER_PAGE: 114' -- and such a note means nothing without the PDF it was
;; taken against, and nothing at all if one reads Slings instead of Burnet.
;; `1048a27' does not move.

(declare-function org-roam-db-query "org-roam-db" (sql &rest args))
(declare-function org-roam-node-open "org-roam-node" (node &optional cmd))
(declare-function org-roam-node-from-id "org-roam-node" (id))
(declare-function org-roam-node-create "org-roam-node" (&rest args))
(declare-function org-roam-capture- "org-roam-capture"
                  (&key goto keys node info props templates))
(declare-function diogenes-browser-citation-at "diogenes-browser"
                  (&optional position))
(declare-function diogenes-citation-to-key "diogenes-utils" (citation))
(declare-function diogenes--get-works-list "diogenes-perl-interface"
                  (options author))
(declare-function diogenes--assoc-cadr "diogenes-lisp-utils" (key alist))

(defcustom diogenes-org-near 0
  "How far outside a note's own span it is still counted as covering a passage.

In the smallest unit the citation names -- lines, where a work is cited by
them.  Nought is exact: a note on 1048a27-1048b16 covers 1048a27 and not
1048a26.

Raised where a reader takes notes on a stretch and then wants them from a
little before it, a line or two being neither here nor there in a note on a
paragraph."
  :type 'integer
  :group 'diogenes-org)

(defcustom diogenes-org-title-by-name t
  "Whether a note is titled with the work's own name.

Non-nil asks the corpus what the work is called: `Metaphysica 1048a27'.  The
corpora give the Latin titles the editions use -- Metaphysica, Ethica Eudemia,
De Anima -- which is how a classicist refers to them.

Nil uses `diogenes-reference-to-string', which gives the dictionaries' own
abbreviations: `Arist. Metaph. 1048a27'.  Shorter, and what one writes in a
footnote.

Asking the corpus is a call into Perl, so the answer is remembered: once per
author for as long as Emacs runs."
  :type 'boolean
  :group 'diogenes-org)

(defcustom diogenes-org-capture-template nil
  "The org-roam template a new note is made from, or nil for the built-in."
  :type '(choice (const :tag "The built-in" nil) sexp)
  :group 'diogenes-org)


;;; What a reference says

(defun diogenes-org--passage-parts (path)
  "PATH as (CORPUS AUTHOR WORK FROM TO), or nil where it names no passage.

The links carry their kind first -- `passage', `entry', `page' -- so a
reference to a dictionary entry is not mistaken for one to a text.  TO is nil
where the reference names a single place rather than a stretch."
  (let* ((path (replace-regexp-in-string
                (concat "\\\\`" (regexp-quote diogenes-org-link-type) ":")
                "" (or path "")))
         (parts (diogenes-org--decode path)))
    (when (and (>= (length parts) 5) (equal (nth 0 parts) "passage"))
      (let ((ends (split-string (nth 4 parts) "-" t)))
        (list (nth 1 parts) (nth 2 parts) (nth 3 parts)
              (car ends) (cadr ends))))))

(defun diogenes-org--levels (key)
  "KEY, a citation with stops in it, as a list of numbers.

`1048a.27' is (10480 27) -- the page and its column as one number, the line as
another -- so that two citations can be compared as NUMBERS rather than as
strings.  Which is what lets a note made on a stretch be found from inside it:
`1048a.27' is less than `1048b.16' by arithmetic and not by spelling."
  (let (out)
    (dolist (level (split-string (or key "") "[.]" t))
      (if (string-match "\\\\`\\\\([0-9]+\\\\)\\\\([a-e]\\\\)\\\\'" level)
          ;; A PAGE AND ITS COLUMN, which the corpora write as one level:
          ;; times ten and the letter's place, so `1048b' is above `1048a'
          ;; and below `1049a'.
          (push (+ (* 10 (string-to-number (match-string 1 level)))
                   (- (aref (match-string 2 level) 0) ?a))
                out)
        (push (string-to-number
               (if (string-match "\\\\([0-9]+\\\\)" level)
                   (match-string 1 level)
                 "0"))
              out)))
    (nreverse out)))

(defun diogenes-org--before-p (a b)
  "Whether citation A is at or before citation B, level by level.
A citation with fewer levels is taken to begin where the other does:
`1048a' is at or before `1048a.27', the column beginning at its first line."
  (catch 'done
    (cl-loop for x in a
             for y in b
             do (cond ((< x y) (throw 'done t))
                      ((> x y) (throw 'done nil))))
    t))

(defun diogenes-org--same-work-p (a b)
  "Whether references A and B are of one work of one author in one corpus."
  (and a b
       (equal (nth 0 a) (nth 0 b))
       (equal (nth 1 a) (nth 1 b))
       (equal (nth 2 a) (nth 2 b))))

(defun diogenes-org--covers-p (reference here)
  "Whether REFERENCE's span holds the single place HERE."
  (let ((r (diogenes-org--passage-parts reference))
        (h (diogenes-org--passage-parts here)))
    (when (diogenes-org--same-work-p r h)
      (let ((place (diogenes-org--levels (nth 3 h)))
            (start (diogenes-org--levels (nth 3 r)))
            (end (diogenes-org--levels (or (nth 4 r) (nth 3 r)))))
        (when (and place start)
          (when (> diogenes-org-near 0)
            (setq start (append (butlast start)
                                (list (- (car (last start))
                                         diogenes-org-near)))
                  end (append (butlast end)
                              (list (+ (car (last end))
                                       diogenes-org-near)))))
          (and (diogenes-org--before-p start place)
               (diogenes-org--before-p place end)))))))

(defun diogenes-org--overlaps-p (reference from to)
  "Whether REFERENCE's span MEETS the stretch FROM to TO.

Meets, and not merely falls within.  A note made on a paragraph that begins
before this page and ends on it bears on the page as much as one made wholly
inside it, and a reader turning to the page wants both."
  (let ((r (diogenes-org--passage-parts reference))
        (a (diogenes-org--passage-parts from))
        (b (diogenes-org--passage-parts to)))
    (when (diogenes-org--same-work-p r a)
      (let ((r-start (diogenes-org--levels (nth 3 r)))
            (r-end (diogenes-org--levels (or (nth 4 r) (nth 3 r))))
            (p-start (diogenes-org--levels (nth 3 a)))
            (p-end (diogenes-org--levels (or (and b (or (nth 4 b) (nth 3 b)))
                                             (nth 3 a)))))
        (and r-start p-start
             ;; Two spans meet where neither ends before the other begins.
             (diogenes-org--before-p r-start p-end)
             (diogenes-org--before-p p-start r-end))))))


;;; Where the browser is

(defun diogenes-org--reference-string (&optional it)
  "The passage in hand as a link path, or nil."
  (let ((it (or it (diogenes-browser-reference))))
    (when (and it (plist-get it :key))
      (diogenes-org--encode
       (list "passage"
             (plist-get it :corpus)
             (plist-get it :author)
             (plist-get it :work)
             (plist-get it :key))))))

(defun diogenes-org--page-span ()
  "What the browser is showing, as (FROM . TO) link paths, or nil.

THE WHOLE PAGE, and not the line at point.  A reader looking for notes wants
whatever bears on what is in front of them, and a note two lines above the
cursor is as much to the point as one on it.

The buffer keeps no record of where it is -- paging is the Perl process's
business -- but every line carries its citation as a text property, so the
extent is read off the first and last lines of the text itself.

FORWARD for the first, backward for the last.
`diogenes-browser-citation-at' searches backward where the line it is given
has none of its own, a citation belonging to the lines that follow it; asked
at the very first line it had nothing behind it and answered nil, which is
every browser buffer there is."
  (when (derived-mode-p 'diogenes-browser-mode)
    (let* ((it (diogenes-browser-reference))
           (first (save-excursion
                    (goto-char (point-min))
                    (or (diogenes-browser-citation-at)
                        (let ((match (text-property-search-forward 'cit)))
                          (and match (prop-match-value match))))))
           (last (save-excursion
                   (goto-char (max (point-min) (1- (point-max))))
                   (diogenes-browser-citation-at))))
      (when (and it first)
        (let ((make (lambda (citation)
                      (diogenes-org--encode
                       (list "passage"
                             (plist-get it :corpus)
                             (plist-get it :author)
                             (plist-get it :work)
                             (diogenes-citation-to-key citation))))))
          (cons (funcall make first)
                (funcall make (or last first))))))))


;;; What a note is called

(defvar diogenes-org--work-names (make-hash-table :test 'equal)
  "What the corpus calls each work, keyed by (CORPUS AUTHOR).
A call into Perl is dear enough to be worth making once.")

(defun diogenes-org--work-name (corpus author work)
  "What CORPUS calls WORK of AUTHOR, or nil.
The corpus's own name -- `Metaphysica', `Ethica Eudemia' -- and not the number
the database files it under."
  (when (and corpus author work)
    (let* ((key (list corpus author))
           (map (or (gethash key diogenes-org--work-names)
                    (puthash key
                             (condition-case nil
                                 (or (diogenes--get-works-list
                                      (list :type corpus) author)
                                     'none)
                               ;; NO CORPUS, NO NAME.  A reader without the
                               ;; databases should get a note titled by
                               ;; number rather than an error.
                               (error 'none))
                             diogenes-org--work-names))))
      (unless (eq map 'none)
        (car (diogenes--assoc-cadr work map))))))

(defun diogenes-org--title (it)
  "The passage in IT as a scholar writes it, for the title of a note."
  (or (and diogenes-org-title-by-name
           (let ((name (diogenes-org--work-name
                        (plist-get it :corpus)
                        (plist-get it :author)
                        (plist-get it :work)))
                 (text (plist-get it :text)))
             (and name text (format "%s %s" name text))))
      (let ((said (and (fboundp 'diogenes-reference-to-string)
                       (diogenes-reference-to-string it))))
        (and said (not (string-empty-p said)) said))
      (plist-get it :text)
      "a passage"))

(defun diogenes-org--where (path)
  "PATH's own citation, as a reader writes it.

The levels alone -- `1048a.27-1048b.16' -- the corpus, the author and the work
being the same for every note offered and so worth none of the line.  Which is
what a reader chooses by: not the title of the note but the passage it is on."
  (let ((r (diogenes-org--passage-parts path)))
    (if r
        (concat (nth 3 r) (and (nth 4 r) (concat "-" (nth 4 r))))
      path)))


;;; Asking org-roam

(defun diogenes-org--refs ()
  "Every (PATH NODE-ID TITLE) org-roam knows that names a passage.

Asked of roam's database rather than of the files: it is what the database is
for, and a reader with three thousand notes should not wait while they are
read."
  (unless (require 'org-roam nil t)
    (user-error "This wants org-roam"))
  (let (out)
    (dolist (row (org-roam-db-query
                  [:select [refs:ref nodes:id nodes:title]
                   :from refs
                   :join nodes :on (= refs:node-id nodes:id)]))
      (let ((ref (nth 0 row)))
        (when (and ref (diogenes-org--passage-parts ref))
          (push (list ref (nth 1 row) (nth 2 row)) out))))
    (nreverse out)))

;;;###autoload
(defun diogenes-org-notes (&optional all)
  "The notes on what the browser is showing.

A NOTE IS OFFERED BY ITS PASSAGE -- `1048a.27' and then its title -- and
offered even where there is only one, so that a reader sees WHICH lines it was
made on before opening it.  A note found is not always the note wanted, and
the citation is how one can tell.

Opening one puts the reader in the note; the link inside it leads back to the
passage, and marks it.

With ALL, every note on this WORK rather than on this page, which is what one
wants on arriving at a dialogue rather than at a line."
  (interactive "P")
  (let* ((span (diogenes-org--page-span))
         (here (diogenes-org--reference-string)))
    (unless (or span here)
      (user-error "Not in a browser, so there is no passage to look for"))
    (let* ((mine (diogenes-org--passage-parts (or (car span) here)))
           (found
            (cl-remove-if-not
             (lambda (row)
               (if all
                   (diogenes-org--same-work-p
                    (diogenes-org--passage-parts (nth 0 row)) mine)
                 (and span
                      (diogenes-org--overlaps-p (nth 0 row)
                                                (car span) (cdr span)))))
             (diogenes-org--refs))))
      (if (null found)
          (message "No notes on %s%s"
                   (if all
                       (or (plist-get (diogenes-browser-reference) :work)
                           "this work")
                     (diogenes-org--where (car span)))
                   (if all "" " -- C-u for the whole work"))
        ;; SORTED BY PASSAGE, so the list runs down the page as the text does
        ;; rather than in whatever order the database answered.
        (setq found
              (sort found
                    (lambda (a b)
                      (diogenes-org--before-p
                       (diogenes-org--levels
                        (nth 3 (diogenes-org--passage-parts (nth 0 a))))
                       (diogenes-org--levels
                        (nth 3 (diogenes-org--passage-parts (nth 0 b))))))))
        (let* ((choices
                (mapcar (lambda (row)
                          (cons (format "%-24s %s"
                                        (diogenes-org--where (nth 0 row))
                                        (or (nth 2 row) ""))
                                row))
                        found))
               (picked (completing-read
                        (format "%d note%s: " (length found)
                                (if (= (length found) 1) "" "s"))
                        choices nil t)))
          (org-roam-node-open
           (org-roam-node-from-id (nth 1 (cdr (assoc picked choices))))))))))


;;; Making one

(defun diogenes-org--template ()
  "The template a new note is captured from."
  (or diogenes-org-capture-template
      '(("d" "a passage" plain "%?"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n")
         :unnarrowed t))))

;;;###autoload
(defun diogenes-org-note ()
  "Make a note on the passage in hand, or on the stretch that is marked.

The citation goes into `ROAM_REFS' in the same form the links use, which is
how the note is found again and how it leads back."
  (interactive)
  (unless (require 'org-roam nil t)
    (user-error "This wants org-roam"))
  (let* ((it (diogenes-browser-reference))
         (path (diogenes-org--reference-string it)))
    (unless path
      (user-error "Not in a browser, so there is no passage to note"))
    (org-roam-capture-
     :node (org-roam-node-create :title (diogenes-org--title it))
     :info (list :ref (concat diogenes-org-link-type ":" path))
     :props (list :immediate-finish nil)
     :templates (diogenes-org--template)
     :keys "d")))


;;; Back to the text

;; FROM ANYWHERE IN THE NOTE, and not from a link in it.  A note's `ROAM_REFS'
;; already says which passage it is on -- it is what the note was found by --
;; so a reader in a note has no business hunting for a link to click, and a
;; note written before there were links has none to hunt for.
;;
;; The reference is looked for outwards from point: this heading's, then its
;; parent's, then the file's.  Which is what a reader means by `the passage
;; this is about' in a file of notes on a dozen passages -- the nearest one
;; that says.

(defun diogenes-org--ref-at-point ()
  "The passage reference governing point, or nil.

Outwards from point: the entry\='s own `ROAM_REFS\=', then those of the headings
above it, then the file\='s.  The first that names a passage wins, an inner
note being about a narrower thing than its parent."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (catch 'found
        ;; Every heading from here outwards, and then the file itself.
        (let ((looking t))
          (while looking
            (dolist (ref (append
                          (org-entry-get-multivalued-property
                           (point) "ROAM_REFS")
                          nil))
              (when (diogenes-org--passage-parts ref)
                (throw 'found ref)))
            ;; A property drawer may hold the refs unsplit, where they were
            ;; written by hand rather than by org-roam.
            (let ((raw (org-entry-get (point) "ROAM_REFS")))
              (when raw
                (dolist (ref (split-string raw "[ \t]+" t))
                  (when (diogenes-org--passage-parts ref)
                    (throw 'found ref)))))
            (setq looking (ignore-errors (org-up-heading-safe)))))
        ;; And the file\='s own keyword, for a note that is one file.
        (let ((raw (cadr (assoc "ROAM_REFS"
                                (org-collect-keywords '("ROAM_REFS"))))))
          (when raw
            (dolist (ref (split-string raw "[ \t]+" t))
              (when (diogenes-org--passage-parts ref)
                (throw 'found ref)))))
        nil))))

;;;###autoload
(defun diogenes-org-goto-passage ()
  "Open the passage this note is about.

Read from the note\='s own `ROAM_REFS\=', so it works anywhere in the note and
in notes written before there were links to click.

The browser already reading the work is reused where there is one -- see
`diogenes-org-reuse-browser\=' -- and the lines the note was made on are
marked."
  (interactive)
  (let ((ref (diogenes-org--ref-at-point)))
    (unless ref
      (user-error
       "This note says no passage: no ROAM_REFS naming one, here or above"))
    (diogenes-org-follow-link
     (replace-regexp-in-string
      (concat "\\`" (regexp-quote diogenes-org-link-type) ":") "" ref))))

(defcustom diogenes-org-goto-key "C-c C-d"
  "Key in an org buffer for opening the passage a note is about.
Nil binds nothing.  `C-c C-d\=' for Diogenes; it is `org-deadline\=' by default,
so a reader who wants that should choose another."
  :type '(choice (const :tag "Bind nothing" nil) string)
  :group 'diogenes-org)


;;; Keys

(defcustom diogenes-org-notes-key "C-c C-o"
  "Key in the browser for the notes on what it is showing.  Nil binds nothing."
  :type '(choice (const :tag "Bind nothing" nil) string)
  :group 'diogenes-org)

(defcustom diogenes-org-note-key "C-c C-w"
  "Key in the browser for making a note.  Nil binds nothing."
  :type '(choice (const :tag "Bind nothing" nil) string)
  :group 'diogenes-org)

;;;###autoload
(defun diogenes-org-install-keys ()
  "Put the note keys in the browser.  Idempotent.
A key already taken is left alone and said so, another module's binding being
its own business."
  (when (boundp 'diogenes-browser-mode-map)
    (dolist (pair (list (cons diogenes-org-notes-key #'diogenes-org-notes)
                        (cons diogenes-org-note-key #'diogenes-org-note)))
      (let* ((key (car pair))
             (command (cdr pair))
             (taken (and key (keymap-lookup diogenes-browser-mode-map key))))
        (cond
         ((null key))
         ((eq taken command))
         ((and taken (not (numberp taken)))
          (message "Diogenes: %s is already %s, so %s is unbound"
                   key taken command))
         (t (keymap-set diogenes-browser-mode-map key command))))))
  ;; AND IN ORG, for the way back.  `C-c C-d' is `org-deadline' out of the
  ;; box, so a binding already there is left alone and said so.
  (when (and diogenes-org-goto-key (boundp 'org-mode-map))
    (let ((taken (keymap-lookup org-mode-map diogenes-org-goto-key)))
      (cond
       ((eq taken #'diogenes-org-goto-passage))
       ((and taken (not (numberp taken)))
        (message "Diogenes: %s in org is already %s, so %s is unbound"
                 diogenes-org-goto-key taken 'diogenes-org-goto-passage))
       (t (keymap-set org-mode-map diogenes-org-goto-key
                      #'diogenes-org-goto-passage))))))

;;;###autoload
(with-eval-after-load 'diogenes-browser
  (diogenes-org-install-keys))

;;;###autoload
(with-eval-after-load 'org
  (diogenes-org-install-keys))

(provide 'diogenes-org)
;;; diogenes-org.el ends here
