;;; diogenes-books.el --- open a work at one of its books -*- lexical-binding: t; -*-

;; Keywords: classics, greek, latin
;; Package-Requires: ((emacs "28.1"))

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>

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

;; A WORK OPENED AT A BOOK, by the letter a classicist uses: `Theta' for the
;; ninth book of the Metaphysics, and not `1045b27'.
;;
;; The corpora do not know books.  Aristotle's works declare two levels apiece
;; -- `Bekker page' and `line' -- and there is no third for the book, so
;; `diogenes-browser-goto-passage' cannot be asked for one.  What the corpora
;; DO carry is the book's title, in the text, in braces:
;;
;;     {ΑΡΙΣΤΟΤΕΛΟΥΣ
;;                     ΤΩΝ ΜΕΤΑ ΤΑ ΦΥΣΙΚΑ Α}
;;     {Α ΕΛΑΤΤΟΝ}
;;     {Β}
;;     {Γ}
;;
;; So the books can be found by reading the work and noting where each title
;; falls.  Which is what this does, once per work, and remembers.
;;
;; THE NUMBERING IS THE TEXT'S OWN.  `2' is the second title the work carries,
;; whatever that is -- and in the Metaphysics it is Alpha Minor, a book between
;; Alpha and Beta which the tradition does not number.  A reader who says `2'
;; and means Beta would be off by one from there on, so the completion shows
;; every book with its letter, its number and its page, and a reader chooses by
;; looking rather than by counting.

;;; Code:

(require 'cl-lib)
(require 'seq)

(declare-function diogenes--dump-work "diogenes-browser" (options passage))
(declare-function diogenes-open-passage "diogenes-browser"
                  (corpus author work &optional passage))
(declare-function classicist-browser-reference "classicist-citation" ())
(declare-function diogenes--get-author-list "diogenes-perl-interface" (options &optional author-regex))
(declare-function diogenes--get-works-list "diogenes-perl-interface"
                  (options author))
(declare-function diogenes--assoc-cadr "diogenes-lisp-utils" (key alist))

(defgroup diogenes-books nil
  "Opening a work at one of its books."
  :group 'diogenes
  :prefix "diogenes-books-")

(defcustom diogenes-books-cache-file
  (expand-file-name "diogenes-books.eld" user-emacs-directory)
  "Where the books found in each work are remembered, or nil for memory only.

Finding them means reading the whole work: the titles are in the text, so
there is no index to consult and no way to know where the second book begins
without passing the first.  For the Metaphysics that is some two hundred
pages, which is a few seconds and not worth repeating.

Nil remembers them for the session only."
  :type '(choice (const :tag "Memory only" nil) file)
  :group 'diogenes-books)


;;;; --------------------------------------------------------------------
;;;; WHAT A READER MAY TYPE
;;;; --------------------------------------------------------------------

(defconst diogenes-books--greek
  '((?Α . 1) (?Β . 2) (?Γ . 3) (?Δ . 4) (?Ε . 5) (?Ζ . 6) (?Η . 7)
    (?Θ . 8) (?Ι . 9) (?Κ . 10) (?Λ . 11) (?Μ . 12) (?Ν . 13) (?Ξ . 14)
    (?Ο . 15) (?Π . 16) (?Ρ . 17) (?Σ . 18) (?Τ . 19) (?Υ . 20))
  "The Greek letters in their order, for a book named by one.

THE ALPHABET'S ORDER, and not the work's.  A reader who types `Θ\\=' means the
book the tradition calls Theta, which is the book whose TITLE is Theta -- and
that is looked for among the titles, not counted to.  This is only for saying
which letter was meant where the title is longer than a letter.")

(defconst diogenes-books--roman
  '(("i" . 1) ("ii" . 2) ("iii" . 3) ("iv" . 4) ("v" . 5) ("vi" . 6)
    ("vii" . 7) ("viii" . 8) ("ix" . 9) ("x" . 10) ("xi" . 11)
    ("xii" . 12) ("xiii" . 13) ("xiv" . 14) ("xv" . 15) ("xvi" . 16)
    ("xvii" . 17) ("xviii" . 18) ("xix" . 19) ("xx" . 20))
  "The roman numerals a reader might type, to twenty.
Written out rather than computed: twenty is more books than any work of
Aristotle has, and a table cannot mis-parse `iiii\\='.")

(defun diogenes-books--as-number (said)
  "SAID as a position among the books, or nil.

Arabic, roman or a Greek letter, and case does not matter in the roman.  Nil
where it is none of those -- a reader typing a word means a title, and that is
matched against the titles themselves."
  (let ((said (string-trim said)))
    (cond
     ((string-match-p "\\`[0-9]+\\'" said) (string-to-number said))
     ((cdr (assoc (downcase said) diogenes-books--roman)))
     ((and (= (length said) 1)
           (cdr (assq (upcase (aref said 0)) diogenes-books--greek))))
     (t nil))))

(defun diogenes-books--greek-letter (title)
  "The Greek letter TITLE is named by, or nil.
The FIRST Greek capital in it: a title reads `Α ΕΛΑΤΤΟΝ\\=' or
`ΤΩΝ ΜΕΤΑ ΤΑ ΦΥΣΙΚΑ Α\\=', and in either the book is Alpha."
  (let ((found nil))
    (seq-doseq (char title)
      (when (and (not found) (assq char diogenes-books--greek))
        ;; NOT ANY GREEK CAPITAL.  `ΤΩΝ ΜΕΤΑ ΤΑ ΦΥΣΙΚΑ Α' begins with Tau,
        ;; which is a letter of the alphabet but not the name of this book.
        ;; The name is the letter that stands ALONE -- the last word of the
        ;; title where that word is one character long.
        (setq found nil)))
    (let* ((words (split-string title "[ \t\n]+" t))
           (last (car (last words))))
      (and last (= (length last) 1)
           (assq (aref last 0) diogenes-books--greek)
           (aref last 0)))))


;;;; --------------------------------------------------------------------
;;;; FINDING THEM
;;;; --------------------------------------------------------------------

(defcustom diogenes-books-declared
  '(;; PLATO, whose books are not in the corpus either and cannot be found by
    ;; reading it: the Republic and the Laws print no titles between their
    ;; books, the division being editorial and carried by the Stephanus pages
    ;; alone.  So they are said here, from the Oxford text's own contents.
    (("tlg" "0059" "030")
     ("Respublica I" "327a") ("Respublica II" "357a")
     ("Respublica III" "386a") ("Respublica IV" "419a")
     ("Respublica V" "449a") ("Respublica VI" "484a")
     ("Respublica VII" "514a") ("Respublica VIII" "543a")
     ("Respublica IX" "571a") ("Respublica X" "595a"))
    (("tlg" "0059" "034")
     ("Leges I" "624a") ("Leges II" "652a") ("Leges III" "676a")
     ("Leges IV" "704a") ("Leges V" "726a") ("Leges VI" "751a")
     ("Leges VII" "788a") ("Leges VIII" "828a") ("Leges IX" "853a")
     ("Leges X" "884a") ("Leges XI" "913a") ("Leges XII" "941a"))
    (("tlg" "0059" "036")
     ("Epistola I" "309a") ("Epistola II" "310b")
     ("Epistola III" "315a") ("Epistola IV" "320a")
     ("Epistola V" "321c") ("Epistola VI" "322c")
     ("Epistola VII" "323d") ("Epistola VIII" "352b")
     ("Epistola IX" "357d") ("Epistola X" "358b")
     ("Epistola XI" "358d") ("Epistola XII" "359c")
     ("Epistola XIII" "360a")))
  "Books said outright, for works whose text does not name them.

Keyed by (CORPUS AUTHOR WORK), each a list of (TITLE CITATION) in the order
the work prints them.  Consulted BEFORE the text is read, so a work declared
here costs nothing and a work not declared is looked for.

WHY SOME MUST BE SAID.  Aristotle's books carry titles -- `{Θ}\=' in the text,
which can be found by reading -- and Plato's do not: the division of the
Republic into ten books is the editors\=' and is carried by the Stephanus pages,
which say nothing about where a book begins.  Nothing in the corpus marks it,
so nothing can be read off.

The citations are from the Oxford text\='s contents, and are the pages a reader
will find in any edition: Republic V at 449a, Laws VII at 788a.  A work may be
added here without touching any code, and one declared wrongly is corrected in
one place."
  :type '(alist :key-type (list string string string)
                :value-type (repeat (list string string)))
  :group 'diogenes-books)

(defcustom diogenes-books-read-the-text '("0086")
  "Whose works may be found by READING them, as a list of author numbers.

Reading a work to find its books means dumping the whole of it, which takes
seconds and prints beyond the end of the work asked for.  It is worth it where
the titles are there to be found, and Aristotle -- `0086\=' -- is where they
are.

For anyone else the books must be in `diogenes-books-declared\=', and a work
that is in neither says so rather than spending a minute discovering that its
text names nothing.

Nil reads nothing; t reads anything."
  :type '(choice (const :tag "Nobody" nil)
                 (const :tag "Anybody" t)
                 (repeat string))
  :group 'diogenes-books)

(defvar diogenes-books--known nil
  "The books found in each work, keyed by (CORPUS AUTHOR WORK).
Each is a list of (TITLE CITATION), in the order the work prints them.")

(defun diogenes-books--load ()
  "Read what was remembered, once."
  (when (and diogenes-books-cache-file
             (null diogenes-books--known)
             (file-readable-p diogenes-books-cache-file))
    (setq diogenes-books--known
          (ignore-errors
            (with-temp-buffer
              (insert-file-contents diogenes-books-cache-file)
              (goto-char (point-min))
              (read (current-buffer)))))))

(defun diogenes-books--save ()
  "Remember what has been found."
  (when diogenes-books-cache-file
    (ignore-errors
      (with-temp-file diogenes-books-cache-file
        (insert ";; The books of each work, as its text names them.\n")
        (insert ";; Written by diogenes-books.el; delete it to have them\n")
        (insert ";; found again.\n")
        (prin1 diogenes-books--known (current-buffer))
        (insert "\n")))))

(defun diogenes-books--scan-buffer ()
  "The books in the dump in this buffer, as (TITLE CITATION).

A title is a braced run, which is how the corpora mark one, and the book
begins at the first citation AFTER it -- the citations being printed every few
lines, so this is the first that the text prints and not always the very first
line of the book.  Near enough to open at: a reader asking for Theta wants to
be looking at the beginning of Theta, not at a particular word of it."
  (let ((found nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "{\\([^}]*\\)}" nil t)
        (let ((title (string-trim
                      (replace-regexp-in-string "[ \t\n]+" " "
                                                (match-string 1))))
              (citation
               (save-excursion
                 ;; `980a.25' at the start of a line, as the dump prints it.
                 (and (re-search-forward
                       "^[ \t]*\\([0-9]+[a-z]?\\(?:\\.[0-9a-z]+\\)*\\)[ \t]"
                       nil t)
                      (match-string 1)))))
          (when (and (> (length title) 0) citation)
            (push (list title citation) found)))))
    (diogenes-books--own-work (nreverse found))))

(defun diogenes-books--page (citation)
  "The page number in CITATION, as a number.
The first run of digits: `1045b.27\=' is 1045, and `338a.25\=' is 338."
  (if (string-match "\\([0-9]+\\)" citation)
      (string-to-number (match-string 1 citation))
    0))

(defun diogenes-books--own-work (books)
  "BOOKS up to the point where another work begins.

THE DUMP RUNS PAST THE END.  Diogenes prints some lines beyond the work asked
for -- the package\='s own README says so -- and for the Metaphysics that is the
beginning of the Meteorologica, whose first book is also called Alpha and whose
title was taken for a fifteenth book.

It is known by its pages.  A work\='s citations rise: the Metaphysics runs from
980a to 1087a, and a title at 338a is not a later book of it but the first book
of something else.  So the list is cut where the page falls away -- by more than
a little, a book beginning slightly before the last citation of the one before
being ordinary enough."
  (let ((out nil)
        (highest 0))
    (catch 'done
      (dolist (book books)
        (let ((page (diogenes-books--page (cadr book))))
          (when (and (> highest 0) (< page (- highest 100)))
            ;; Far below anything seen: another work.
            (throw 'done nil))
          (setq highest (max highest page))
          (push book out))))
    (nreverse out)))

(defun diogenes-books--find (corpus author work then)
  "Find the books of WORK and call THEN with them.

Reads the whole work, there being no other way: the titles are in the text.
Asynchronous, the dump being a Perl process that answers in its own time, so
THEN is called when it has finished."
  (diogenes-books--load)
  (let* ((key (list corpus author work))
         ;; SAID OUTRIGHT FIRST.  A declared work needs no reading, and a
         ;; declaration is what a reader edits when a citation is wrong --
         ;; whereas what was read is a cache, and would be read again.
         (declared (cdr (assoc key diogenes-books-declared)))
         (known (or declared (cdr (assoc key diogenes-books--known)))))
    (if known
        (funcall then known)
      (unless (or (eq diogenes-books-read-the-text t)
                  (member author diogenes-books-read-the-text))
        (user-error
         (concat "The books of %s %s/%s are not declared, and reading the "
                 "text to find them is only done for %s -- see "
                 "diogenes-books-declared and diogenes-books-read-the-text")
         corpus author work
         (if diogenes-books-read-the-text
             (mapconcat #'identity diogenes-books-read-the-text ", ")
           "nobody")))
      (message "Reading %s %s/%s to find its books..." corpus author work)
      (let* ((started (diogenes--dump-work (list :type corpus)
                                           (list author work)))
             ;; A PROCESS OR A BUFFER.  `diogenes--start-perl' ends in
             ;; `make-process', which answers with the PROCESS -- so asking
             ;; for a buffer got nil, and the dump ran while nothing waited
             ;; for it.  Either is taken, and the buffer had from the process
             ;; where that is what came back.
             (buffer (cond ((bufferp started) started)
                           ((processp started) (process-buffer started))
                           (t nil))))
        (unless (buffer-live-p buffer)
          (user-error "The dump did not start, or has no buffer"))
        (diogenes-books--when-done
         buffer
         (lambda ()
           (let ((books (with-current-buffer buffer
                          (diogenes-books--scan-buffer))))
             (unless books
               (user-error
                (concat "No books found in %s %s/%s: %d characters dumped, "
                        "%d braced titles in them.  "
                        "M-: (diogenes-books--scan-buffer) in %s to see why")
                corpus author work
                (buffer-size buffer)
                (with-current-buffer buffer
                  (save-excursion
                    (goto-char (point-min))
                    (let ((n 0))
                      (while (re-search-forward "{[^}]*}" nil t)
                        (setq n (1+ n)))
                      n)))
                (buffer-name buffer)))
             (push (cons key books) diogenes-books--known)
             (diogenes-books--save)
             (message "%d books found" (length books))
             (funcall then books))))))))

(defcustom diogenes-books-tries 600
  "How many times to look for the dump to finish before giving up.
A tenth of a second apart, so six hundred is a minute.  A whole work is a good
deal of text and the Perl takes its time over it."
  :type 'integer
  :group 'diogenes-books)

(defun diogenes-books--when-done (buffer then &optional tries)
  "Call THEN when the dump in BUFFER has stopped growing.

WAITED ON THE TEXT, not on the process.  A dump\\='s Perl is finished when it
exits -- but the sentinel Diogenes installs is its own, and replacing it would
take away the post-processing it does.  So this watches the buffer instead: two
looks a tenth of a second apart with no new text is a dump that has finished."
  (let ((tries (or tries diogenes-books-tries))
        (size (buffer-size buffer)))
    (run-with-timer
     0.1 nil
     (lambda ()
       (cond
        ((not (buffer-live-p buffer)))
        ((<= tries 0)
         (message "The dump is taking too long; giving up"))
        ;; THE PROCESS, WHERE THERE IS ONE.  Watching the buffer alone was
        ;; too eager: a Perl reading a whole work pauses -- it is reading
        ;; from a disc and writing in blocks -- and a pause of a tenth of a
        ;; second looked exactly like an ending.  The scan then ran on a
        ;; buffer holding the first block only, which has the title of the
        ;; first book and no citation after it, and so found nothing.
        ;;
        ;; A process that is still live is still dumping, whatever the
        ;; buffer is doing.  The buffer is watched only as a fallback, for a
        ;; process that has gone while its text is still being inserted.
        ((let ((process (get-buffer-process buffer)))
           (and process (process-live-p process)))
         (diogenes-books--when-done buffer then (1- tries)))
        ((and (= (buffer-size buffer) size) (> size 0))
         (funcall then))
        (t (diogenes-books--when-done buffer then (1- tries))))))))


;;;; --------------------------------------------------------------------
;;;; THE COMMAND
;;;; --------------------------------------------------------------------

(defun diogenes-books--choose (books said)
  "The book in BOOKS that SAID names, or nil.

BY ITS NAME FIRST, and by its place only after.  A reader who types `Θ\\=' means
the book called Theta, and the Metaphysics has fourteen books of which Theta is
the ninth title but the eighth letter -- Alpha Minor coming between Alpha and
Beta without a letter of its own.  Counting would find the wrong one; looking
at the titles finds the right one.

A word matches a title containing it, so `ΕΛΑΤΤΟΝ\\=' finds Alpha Minor."
  (let* ((said (string-trim said))
         (letter (and (= (length said) 1) (upcase (aref said 0))))
         (by-name
          (and letter
               (seq-find (lambda (book)
                           (eq (diogenes-books--greek-letter (car book))
                               letter))
                         books)))
         (by-word
          (and (not by-name) (> (length said) 1)
               (seq-find (lambda (book)
                           (string-match-p (regexp-quote (upcase said))
                                           (upcase (car book))))
                         books)))
         (number (and (not by-name) (not by-word)
                      (diogenes-books--as-number said))))
    (or by-name by-word
        (and number (> number 0) (<= number (length books))
             (nth (1- number) books)))))

(defun diogenes-books--label (book n)
  "BOOK, the Nth, as the completion shows it."
  (let ((letter (diogenes-books--greek-letter (car book))))
    (format "%-28s %s%s"
            (car book)
            (if letter (format "%c = " letter) "")
            (format "%d, at %s" n (cadr book)))))

;;;###autoload
(defun diogenes-open-book (&optional said)
  "Open the work in hand at one of its books.

SAID may be the Greek letter the book is called by -- `Θ\\=' -- or a roman or
arabic numeral, or a word from its title.  The letter is the surest: the
numbers count the titles the work prints, and the Metaphysics prints Alpha
Minor between Alpha and Beta, so `2\\=' is that and not Beta.

Called from a browser, the work is the one being read.  Elsewhere it asks.

The books are found by reading the whole work, the corpora having no level for
them -- Aristotle is cited by Bekker page and line and by nothing else -- and
are remembered afterwards in `diogenes-books-cache-file\\='."
  (interactive)
  (let* ((reference (and (derived-mode-p 'diogenes-browser-mode)
                         (classicist-browser-reference)))
         (corpus (or (plist-get reference :corpus) "tlg"))
         (author (plist-get reference :author))
         (work (plist-get reference :work)))
    (unless (and author work)
      (user-error
       "Not in a browser: open the work first, then ask for a book of it"))
    (diogenes-books--find
     corpus author work
     (lambda (books)
       (let* ((labels
               (let ((n 0))
                 (mapcar (lambda (book)
                           (setq n (1+ n))
                           (cons (diogenes-books--label book n) book))
                         books)))
              ;; SHOWN AND NOT COUNTED.  Every book with its letter, its
              ;; number and the page it starts at, so a reader chooses by
              ;; looking -- which is the only way to be right about a work
              ;; whose numbering and whose letters disagree.
              (choice
               (or said
                   (completing-read
                    "Book: "
                    ;; IN THE WORK'S ORDER, not the alphabet's.  Completion
                    ;; sorts what it is given, and sorted alphabetically the
                    ;; list read Α ΕΛΑΤΤΟΝ, Β, Ε, Η, Γ -- which is no order
                    ;; at all to choose a book from.  `identity' as the sort
                    ;; leaves them as they were built, which is the order the
                    ;; work prints them in.
                    (lambda (string predicate action)
                      (if (eq action 'metadata)
                          '(metadata
                            (display-sort-function . identity)
                            (cycle-sort-function . identity))
                        (complete-with-action action labels
                                              string predicate)))
                    nil t)))
              ;; THE LABEL WHOLE, and not a title cut out of it.  The label
              ;; was built here and is the key of `labels', so it is looked up
              ;; as it stands.  Cutting the title back out went wrong the
              ;; moment a title ran past the column the format pads to: the
              ;; books of the Metaphysics are headed `ΑΡΙΣΤΟΤΕΛΟΥΣ ΤΩΝ ΜΕΤΑ
              ;; ΤΑ ΦΥΣΙΚΑ Ζ', which is longer than the padding, so `%-28s'
              ;; added nothing, no two spaces were left to split on, and the
              ;; whole label was taken for a title -- which answers to no
              ;; book.
              ;;
              ;; `diogenes-books--choose' still answers for SAID, a caller
              ;; naming a book outright rather than picking one from the list.
              (book (or (cdr (assoc choice labels))
                        (diogenes-books--choose books choice))))
         (unless book
           (user-error "No book of this work answers to `%s'" choice))
         (message "%s, at %s" (car book) (cadr book))
         (diogenes-open-passage corpus author work
                                (split-string (cadr book) "[.]" t)))))))

(provide 'diogenes-books)
;;; diogenes-books.el ends here
