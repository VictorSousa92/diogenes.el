;;; diogenes-org.el --- Notes joined to passages -*- lexical-binding: t; -*-

;; Keywords: classics, philology, org, roam
;; Package-Requires: ((emacs "28.1") (org "9.6"))

;;; Commentary:

;; A NOTE BELONGS TO A PASSAGE, not to a page of a book.
;;
;; Which is why this does not use `org-noter'.  That anchors a note to a
;; location in a document -- `:NOTER_PAGE: 114' -- and such a note means
;; nothing without the PDF it was taken against, and nothing at all if one
;; changes from Burnet to Slings.  A citation does not move: `tlg0059:030:327a'
;; is the same passage in every edition there has ever been, and will be the
;; same when the scan is lost.
;;
;; So the citation is the anchor, and it is kept in `ROAM_REFS', which is
;; org-roam's own way of saying what a note is about.  Nothing here is needed
;; to read the notes afterwards: the reference is a string one can grep, and a
;; link falls back to its description, so `[[diogenes:...][Rep. 327a5]]' reads
;; as `Rep. 327a5' in any Emacs and as plain text in none.
;;
;; WHAT IT GIVES
;;
;;   A `diogenes:' link type.  `org-store-link' in a browser names the passage
;;   in hand; following the link opens it again.
;;
;;   `diogenes-org-notes' -- the notes on the passage in hand, found by
;;   comparing citations and not by matching strings, so a note made on
;;   327a5-327b4 is found from anywhere inside it.
;;
;;   `diogenes-org-note' -- a note on the passage in hand, or on the marked
;;   stretch of it, captured with the citation already filled in.
;;
;; THE FORM OF A REFERENCE
;;
;;     diogenes:tlg0059:030:327a.5-327b.4
;;             corpus author:work:from    -to
;;
;; The corpus and the author's number are there so that a note on Republic
;; 327a cannot be confused with a note on anyone else's 327a, which a bare
;; `327a' would invite.  The citation itself is `:key' as the browser gives
;; it: every level separated by a stop, which is the only form that reads
;; back.

;;; Code:

(require 'cl-lib)
(require 'org)

(declare-function org-roam-db-query "org-roam-db" (sql &rest args))
(declare-function org-roam-node-open "org-roam-node" (node &optional cmd))
(declare-function org-roam-node-from-id "org-roam-node" (id))
(declare-function org-roam-capture- "org-roam-capture"
                  (&key goto keys node info props templates))
(declare-function org-roam-node-create "org-roam-node" (&rest args))
(declare-function diogenes-browser-reference "diogenes-browser" ())
(declare-function diogenes-reference-to-string "diogenes-browser" (reference))
(declare-function diogenes--get-works-list "diogenes-perl-interface"
                  (options author))
(declare-function diogenes--assoc-cadr "diogenes-lisp-utils" (key alist))
(declare-function diogenes-browser-citation-at "diogenes-browser"
                  (&optional position))
(declare-function diogenes-citation-to-key "diogenes-utils" (citation))
(declare-function diogenes-citation-to-string "diogenes-utils"
                  (citation labels))
(declare-function diogenes-open-passage "diogenes"
                  (corpus author work passage))
(declare-function diogenes-citation-to-key "diogenes-utils" (citation))
(defvar diogenes--browser-labels)

(defgroup diogenes-org nil
  "Notes joined to passages."
  :group 'diogenes
  :prefix "diogenes-org-")

(defcustom diogenes-org-near 0
  "How far outside a note's own span it is still counted as covering a passage.

In the smallest unit the citation names -- lines, where a work is cited by
them.  Nought is exact: a note on 327a5-327b4 covers 327a5 and not 327a4.

Raised where a reader takes notes on a stretch and then wants them from a
little before it, a line or two being neither here nor there in a note on a
paragraph."
  :type 'integer
  :group 'diogenes-org)

(defcustom diogenes-org-capture-template nil
  "The org-roam template a new note is made from, or nil for the built-in.

Nil captures a heading whose title is the passage as a reader writes it and
whose `ROAM_REFS' is the passage as a machine reads it -- which is all the
joining that is wanted, and leaves the body to the reader."
  :type '(choice (const :tag "The built-in" nil) sexp)
  :group 'diogenes-org)


;;;; --------------------------------------------------------------------
;;;; A REFERENCE
;;;; --------------------------------------------------------------------

;; TWO FORMS, as the browser itself keeps two.  `tlg0059:030:327a.5' reads
;; back and is what a lookup matches on; `Plato, Republic 327a5' is what a
;; reader sees.  Neither can do the other's work, so a link carries both: the
;; first as its path and the second as its description.

(defun diogenes-org--reference (&optional plist)
  "The passage in hand as a reference, or nil.

PLIST as `diogenes-browser-reference\\=' gives it, or that of the current
buffer."
  (let* ((it (or plist (diogenes-browser-reference))))
    (when (and it (plist-get it :key))
      (format "%s:%s:%s:%s"
              (or (plist-get it :corpus) "tlg")
              (diogenes-org--digits (plist-get it :author))
              (diogenes-org--digits (plist-get it :work))
              (plist-get it :key)))))

(defun diogenes-org--digits (value)
  "VALUE's digits, as the corpora number their authors and works.
`tlg0059\\=' and `0059\\=' and 59 are one author, and a reference that wrote
them differently would not find its own notes."
  (let ((text (format "%s" (or value ""))))
    (if (string-match "\\([0-9]+\\)" text) (match-string 1 text) text)))

(defun diogenes-org--parse (path)
  "PATH as (CORPUS AUTHOR WORK FROM TO), or nil.
TO is nil where the reference names a single place rather than a stretch."
  (let ((parts (split-string (or path "") ":")))
    (when (>= (length parts) 4)
      (let* ((span (nth 3 parts))
             (ends (split-string span "-" t)))
        (list (nth 0 parts) (nth 1 parts) (nth 2 parts)
              (car ends) (cadr ends))))))

(defun diogenes-org--levels (key)
  "KEY, a citation with stops in it, as a list of numbers.

`327a.5\\=' is (3270 5) -- the page and its section as one number, the line as
another -- so that two citations can be compared as numbers rather than as
strings.  Which is what lets a note made on a stretch be found from inside it:
`327a.5\\=' is less than `327b.4\\=' by arithmetic and not by spelling."
  (let (out)
    (dolist (level (split-string (or key "") "[.]" t))
      (if (string-match "\\`\\([0-9]+\\)\\([a-e]\\)\\'" level)
          ;; A PAGE AND ITS SECTION, which the corpora write as one level:
          ;; times ten and the letter's place, as the index does it, so `327b'
          ;; is above `327a' and below `328a'.
          (push (+ (* 10 (string-to-number (match-string 1 level)))
                   (- (aref (match-string 2 level) 0) ?a))
                out)
        (push (string-to-number
               (if (string-match "\\([0-9]+\\)" level)
                   (match-string 1 level)
                 "0"))
              out)))
    (nreverse out)))

(defun diogenes-org--before-p (a b)
  "Whether citation A is at or before citation B, level by level.
A citation with fewer levels than the other is taken to begin where the other
does: `327a\\=' is at or before `327a.5\\=', the section beginning at its first
line."
  (catch 'done
    (cl-loop for x in a
             for y in b
             do (cond ((< x y) (throw 'done t))
                      ((> x y) (throw 'done nil))))
    t))

(defun diogenes-org--covers-p (reference here)
  "Whether REFERENCE's span holds HERE.

Both are references as `diogenes-org--reference\\=' makes them.  The corpus,
the author and the work must be the same, and the place must fall within the
reference's span -- which is the whole point: a note is made on a stretch and
wanted from anywhere in it."
  (let ((r (diogenes-org--parse reference))
        (h (diogenes-org--parse here)))
    (when (and r h
               (equal (nth 0 r) (nth 0 h))
               (equal (nth 1 r) (nth 1 h))
               (equal (nth 2 r) (nth 2 h)))
      (let* ((slack diogenes-org-near)
             (place (diogenes-org--levels (nth 3 h)))
             (start (diogenes-org--levels (nth 3 r)))
             (end (diogenes-org--levels (or (nth 4 r) (nth 3 r)))))
        (when (and place start)
          ;; SLACK ON THE SMALLEST UNIT, which is the line where there is one.
          (when (> slack 0)
            (setq start (append (butlast start)
                                (list (- (car (last start)) slack)))
                  end (append (butlast end)
                              (list (+ (car (last end)) slack)))))
          (and (diogenes-org--before-p start place)
               (diogenes-org--before-p place end)))))))


;;;; --------------------------------------------------------------------
;;;; THE LINK
;;;; --------------------------------------------------------------------

;;;###autoload
(defun diogenes-org-open (path &optional _)
  "Open the passage PATH names."
  (let ((parts (diogenes-org--parse path)))
    (unless parts (user-error "Not a passage: %s" path))
    (diogenes-open-passage (nth 0 parts) (nth 1 parts) (nth 2 parts)
                           (split-string (nth 3 parts) "[.]" t))))

;;;###autoload
(defun diogenes-org-store ()
  "Store a link to the passage in hand.
For `org-store-link\\=', which is what `C-c l\\=' calls."
  (let ((it (diogenes-browser-reference)))
    (when it
      (let ((path (diogenes-org--reference it)))
        (when path
          (org-link-store-props
           :type "diogenes"
           :link (concat "diogenes:" path)
           ;; THE DESCRIPTION IS FOR A READER, and is what the note shows
           ;; where this package is not loaded -- which is the point of
           ;; keeping notes this way.
           :description (diogenes-org--label it)))))))

(defcustom diogenes-org-title-by-name t
  "Whether a note is titled with the work\='s own name.

Non-nil asks the corpus what the work is called and titles the note with it:
`Aristotle, Metaphysica 1048a27\='.  The corpora give the Latin titles the
manuscripts and editions use -- Metaphysica, Ethica Eudemia, De Anima -- which
is how a classicist refers to them and what a reader wants to see in a list of
notes a year hence.

Nil uses the dictionaries\=' abbreviations instead, `Arist. Metaph. 1048a27\=',
which are shorter and are what one writes in a footnote.

Asking the corpus means a call into Perl, so the answer is remembered: once
per author for as long as Emacs runs."
  :type 'boolean
  :group 'diogenes-org)

(defvar diogenes-org--work-names (make-hash-table :test 'equal)
  "What the corpus calls each work, keyed by (CORPUS AUTHOR).
A call into Perl is dear enough to be worth making once.")

(defun diogenes-org--work-name (corpus author work)
  "What CORPUS calls WORK of AUTHOR, or nil.

The corpus\='s own name -- `Metaphysica\=', `Ethica Eudemia\=' -- which is the
Latin title the editions use, and not the number the database files it under."
  (when (and corpus author work)
    (let* ((key (list corpus author))
           (map (if (gethash key diogenes-org--work-names)
                    (gethash key diogenes-org--work-names)
                  (puthash key
                           (condition-case nil
                               (or (diogenes--get-works-list
                                    (list :type corpus) author)
                                   'none)
                             ;; NO CORPUS, NO NAME.  A reader without the
                             ;; databases installed should still get a note,
                             ;; titled by number, rather than an error.
                             (error 'none))
                           diogenes-org--work-names))))
      (unless (eq map 'none)
        (car (diogenes--assoc-cadr work map))))))

(defun diogenes-org--label (it)
  "The passage in IT as a SCHOLAR writes it.

`Arist. Metaph. 1048a27\=', and not `025 1048a27\='.  The work\='s number is what
the corpus calls it and is no use as the title of a note: a reader looking down
a list of notes a year hence should see which text each is on.

`diogenes-reference-to-string\=' does the naming, and falls back by degrees --
the work\='s abbreviation where the dictionaries have one, the author\='s alone
where they name him but not it, and the numbers where they name neither.  So a
text no lexicographer quoted still gets a title, and an unambiguous one."
  (or (and diogenes-org-title-by-name
           (let ((name (diogenes-org--work-name
                        (plist-get it :corpus)
                        (diogenes-org--digits (plist-get it :author))
                        (diogenes-org--digits (plist-get it :work))))
                 (text (plist-get it :text)))
             (and name text (format "%s %s" name text))))
      (and (fboundp 'diogenes-reference-to-string)
           (let ((said (diogenes-reference-to-string it)))
             (and said (not (string-empty-p said)) said)))
      (let ((text (plist-get it :text))
            (work (plist-get it :work)))
        (cond ((and text work) (format "%s %s" work text))
              (text text)
              (t "a passage")))))

;;;###autoload
(with-eval-after-load 'org
  (org-link-set-parameters "diogenes"
                           :follow #'diogenes-org-open
                           :store #'diogenes-org-store
                           ;; EXPORTED AS ITS DESCRIPTION.  A citation in a
                           ;; paper is a citation, not a link to a program
                           ;; nobody reading it has.
                           :export (lambda (_path desc _format _info)
                                     (or desc "a passage"))))


;;;; --------------------------------------------------------------------
;;;; THE NOTES ON THIS PASSAGE
;;;; --------------------------------------------------------------------

(defun diogenes-org--page-span ()
  "What the browser is showing, as (FROM . TO) references, or nil.

THE WHOLE PAGE, and not the line at point.  A reader looking for notes is
looking for whatever bears on what is in front of them: asking only about the
line the cursor happens to rest on found nothing nine times in ten, and the
note two lines up went unmentioned.

The buffer keeps no record of where it is -- paging is the Perl process\='s
business -- but every line carries its citation as a text property, so the
extent is read off the first and last lines of the text itself."
  (when (derived-mode-p 'diogenes-browser-mode)
    (let* ((it (diogenes-browser-reference))
           ;; FORWARD FOR THE FIRST, backward for the last.
           ;; `diogenes-browser-citation-at' searches BACKWARD where the line
           ;; it is given has no citation of its own -- a citation belonging
           ;; to the lines that follow it -- so asked at the very first line
           ;; of the buffer it had nothing behind it and answered nil, which
           ;; is every browser buffer there is.
           (first (save-excursion
                    (goto-char (point-min))
                    (or (diogenes-browser-citation-at)
                        (let ((match (text-property-search-forward 'cit)))
                          (and match (prop-match-value match))))))
           (last (save-excursion
                   (goto-char (max (point-min) (1- (point-max))))
                   (diogenes-browser-citation-at))))
      (when (and it first)
        (let ((base (format "%s:%s:%s:"
                            (or (plist-get it :corpus) "tlg")
                            (diogenes-org--digits (plist-get it :author))
                            (diogenes-org--digits (plist-get it :work)))))
          (cons (concat base (diogenes-citation-to-key first))
                (concat base (diogenes-citation-to-key (or last first)))))))))

(defun diogenes-org--overlaps-p (reference from to)
  "Whether REFERENCE\='s span meets the stretch FROM to TO.

MEETS, and not merely falls within.  A note made on a paragraph that begins
before this page and ends on it bears on the page as much as one made wholly
inside it, and a reader turning to the page wants both."
  (let ((r (diogenes-org--parse reference))
        (a (diogenes-org--parse from))
        (b (diogenes-org--parse to)))
    (when (and r a b
               (equal (nth 0 r) (nth 0 a))
               (equal (nth 1 r) (nth 1 a))
               (equal (nth 2 r) (nth 2 a)))
      (let ((r-start (diogenes-org--levels (nth 3 r)))
            (r-end (diogenes-org--levels (or (nth 4 r) (nth 3 r))))
            (p-start (diogenes-org--levels (nth 3 a)))
            (p-end (diogenes-org--levels (or (nth 4 b) (nth 3 b)))))
        (and r-start p-start
             ;; Two spans meet where neither ends before the other begins.
             (diogenes-org--before-p r-start p-end)
             (diogenes-org--before-p p-start r-end))))))

(defun diogenes-org--where (reference)
  "REFERENCE\='s own citation, as a reader writes it.

The levels alone -- `327a.5-327b.4\=' -- the corpus, the author and the work
being the same for every note offered and so worth none of the line.  Which is
what a reader chooses by: not the title of the note but the passage it is on."
  (let ((r (diogenes-org--parse reference)))
    (if r
        (concat (nth 3 r) (and (nth 4 r) (concat "-" (nth 4 r))))
      reference)))

(defun diogenes-org--refs ()
  "Every (REFERENCE NODE-ID TITLE) org-roam knows, for our own references.

Asked of roam's database rather than of the files: it is what roam keeps the
database for, and a reader with three thousand notes should not wait while
they are read."
  (unless (require 'org-roam nil t)
    (user-error "This wants org-roam"))
  (let (out)
    (dolist (row (org-roam-db-query
                  [:select [refs:ref nodes:id nodes:title]
                   :from refs
                   :join nodes :on (= refs:node-id nodes:id)]))
      (let ((ref (nth 0 row)))
        (when (and ref (string-match "\\`\\(diogenes:\\)?\\([a-z]+:[0-9]+:\\)"
                                     ref))
          (push (list (replace-regexp-in-string "\\`diogenes:" "" ref)
                      (nth 1 row) (nth 2 row))
                out))))
    (nreverse out)))

;;;###autoload
(defun diogenes-org-notes (&optional all)
  "The notes on what the browser is showing.

THE WHOLE PAGE is looked at, and not the line at point: a reader wants
whatever bears on what is in front of them, and a note two lines above the
cursor is as much to the point as one on it.

A NOTE IS OFFERED BY ITS PASSAGE -- `327a.5-327b.4\=' and then its title -- and
offered even where there is only one, so that a reader sees WHICH line it was
made on before opening it.  A note found is not always the note wanted, and
the citation is how one can tell.

With ALL, every note on this WORK rather than on this page, which is what one
wants on arriving at a dialogue rather than at a line."
  (interactive "P")
  (let* ((span (diogenes-org--page-span))
         (here (diogenes-org--reference)))
    (unless (or span here)
      (user-error "Not in a browser, so there is no passage to look for"))
    (let* ((parts (diogenes-org--parse (or (car span) here)))
           (found
            (cl-remove-if-not
             (lambda (row)
               (if all
                   (let ((r (diogenes-org--parse (nth 0 row))))
                     (and r
                          (equal (nth 0 r) (nth 0 parts))
                          (equal (nth 1 r) (nth 1 parts))
                          (equal (nth 2 r) (nth 2 parts))))
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
                        (nth 3 (diogenes-org--parse (nth 0 a))))
                       (diogenes-org--levels
                        (nth 3 (diogenes-org--parse (nth 0 b))))))))
        (let* ((choices
                (mapcar (lambda (row)
                          (cons (format "%-22s %s"
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

;;;; --------------------------------------------------------------------
;;;; A NOTE ON THIS PASSAGE
;;;; --------------------------------------------------------------------

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

The citation goes into `ROAM_REFS\\=', which is how the note is found again,
and the passage as a reader writes it becomes the title -- so a note is
legible in the list of notes and not merely findable by a program."
  (interactive)
  (unless (require 'org-roam nil t)
    (user-error "This wants org-roam"))
  (let* ((it (diogenes-browser-reference))
         (here (diogenes-org--reference it)))
    (unless here
      (user-error "Not in a browser, so there is no passage to note"))
    (org-roam-capture-
     :node (org-roam-node-create :title (diogenes-org--label it))
     :info (list :ref (concat "diogenes:" here))
     :props (list :immediate-finish nil)
     :templates (diogenes-org--template)
     :keys "d")))


;;;; --------------------------------------------------------------------
;;;; THE KEYS
;;;; --------------------------------------------------------------------

(defcustom diogenes-org-notes-key "C-c C-o"
  "Key in the browser for the notes on the passage in hand.
Nil binds nothing."
  :type '(choice (const :tag "Bind nothing" nil) string)
  :group 'diogenes-org)

(defcustom diogenes-org-note-key "C-c C-w"
  "Key in the browser for making a note on the passage in hand.
Nil binds nothing.  `C-c C-w\\=' for `writing\\='."
  :type '(choice (const :tag "Bind nothing" nil) string)
  :group 'diogenes-org)

;;;###autoload
(defun diogenes-org-install-keys ()
  "Put the note keys in the browser.  Idempotent.
A key already taken is left alone and said so, another module\\='s binding
being its own business."
  (when (boundp 'diogenes-browser-mode-map)
    (dolist (pair (list (cons diogenes-org-notes-key #'diogenes-org-notes)
                        (cons diogenes-org-note-key #'diogenes-org-note)))
      (let* ((key (car pair))
             (command (cdr pair))
             (existing (and key (keymap-lookup diogenes-browser-mode-map key))))
        (cond
         ((null key))
         ((eq existing command))
         ((and existing (not (numberp existing)))
          (message "Diogenes: %s is already %s, so %s is unbound"
                   key existing command))
         (t (keymap-set diogenes-browser-mode-map key command)))))))

;;;###autoload
(with-eval-after-load 'diogenes-browser
  (diogenes-org-install-keys))

(provide 'diogenes-org)
;;; diogenes-org.el ends here
