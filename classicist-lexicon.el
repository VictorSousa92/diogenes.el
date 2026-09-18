;;; classicist-lexicon.el --- reading a dictionary file -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology

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

;; READING A DICTIONARY FILE.  A binary search over a sorted index, the file
;; offsets an entry lies between, the beta code the keys are written in, and
;; the XML of an entry turned into something a reader can look at.
;;
;; NINE-TENTHS PRIVATE: twenty-seven of twenty-nine forms are internal, and
;; the rest of what was perseus calls seventeen of them.  Which is the shape
;; of a layer nobody needs to reach into -- you ask it for an entry and it
;; reads the file.
;;
;; IT CALLS NOTHING ABOVE IT except by declaration.
;; `classicist-perseus-action-map' is here, because the XML renderer puts it
;; on every link it makes and the analysis links use it too; the command it
;; names is the dispatcher, which reads a text property and asks the
;; dictionary registry what to run, and that is `classicist-lookup\='s
;; business.  A keymap naming a command it does not define resolves at a
;; keypress, by which time everything is loaded.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'diogenes-perl-interface)      ; --perl-script, perl-executable
(require 'classicist-groups)
(require 'classicist-variants)

;; DEFINED IN `classicist-lookup.el', WHICH REQUIRES THIS FILE.  The map
;; below names it; nothing here calls it.
(declare-function classicist-perseus-action "classicist-lookup" (char))

(defvar classicist--dict-sense-stack nil
  "The sense labels in force, outermost first, as an entry is walked.

A stack and not a tree, because the senses of an entry are FLAT: the LSJ
writes them as siblings and says how deep each is with a `level' attribute.
Bound afresh for each entry by the `let' in its caller -- see
`classicist--dict-process-elt', which pushes onto it.")

;; IN diogenes.el, THE ENTRY POINT, so declared rather than required:
;; requiring the entry point from a layer it loads is the circle this suite
;; exists to avoid.  Upstream patch 5 moved this one down into a
;; diogenes-lemmata.el; it was not ported here because perseus was going to be
;; cut, and this is the cut.  It wants a home in one of the four.
(declare-function diogenes--perseus-path "diogenes" ())

(defgroup classicist-lexicon nil
  "Reading a dictionary file: its index, its offsets, and its XML."
  :group 'classicist)

(defsubst classicist--perseus-ensure-utf8 (str lang)
  (if (string= lang "greek")
      (diogenes--perseus-beta-to-utf8 str)
    (diogenes--replace-regexes-in-string str
      ("_" "\N{COMBINING MACRON}")
      ("\\^" "\N{COMBINING BREVE}"))))


(defconst classicist-perseus-action-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "RET" #'classicist-perseus-action)
    (keymap-set map "<double-mouse-1>" #'classicist-perseus-action)
    (keymap-set map "<mouse-2>" #'classicist-perseus-action)
    map)
  "Keymap that calls the perseus-action-command on certain
words.")


(defvar-local classicist--lookup-headword nil
  "Headword of the entry currently shown in a lookup buffer.
Used by `diogenes-lookup-open-old' to find the corresponding page
of the Oxford Latin Dictionary PDF.")

(defun classicist--read-forward-until-newline (file file-pos bufsize)
  "Try to read forward from a file until the next newline."
  (when file-pos
    (cl-loop for newline = (re-search-forward "\n" nil t)
	     when newline return (list newline file-pos)
	     for chars-read = (progn (goto-char (point-max))
				     (cadr (insert-file-contents-literally
					    file nil
					    file-pos (+ file-pos bufsize))))
	     when (zerop chars-read) return nil
	     do (cl-incf file-pos chars-read))))


(defun classicist--read-backward-until-newline (file file-pos bufsize)
  "Try to read backward from a file untilg the next newline."
  (when file-pos
    (cl-loop for newline = (re-search-backward "\n" nil t)
	     when newline return (list (1+ newline) file-pos)
	     when (cl-minusp file-pos) do (error "No further entries!")
	     for chars-read = (progn (goto-char (point-min))
				     (cadr (insert-file-contents-literally
					    file nil
					    (let ((start (- file-pos bufsize)))
					      (if (> start 0) start 0))
					    file-pos)))
	     when (zerop chars-read) return (list 1 0)
	     do (forward-char chars-read)
	     do (cl-decf file-pos chars-read))))


(defun classicist--get-dict-line (file pos &optional file-length)
  "Jump at POS into a FILE, and returns the next complete line.
It returns additionally the start and end offsets of the line.
If file-length is not supplied, it will be determined."
  (setq file-length (or file-length
			(file-attribute-size (file-attributes file))))
  (let ((bufsize 5000)
	(buf-start 0)
	(line-start 1)
	line-end)
    (with-temp-buffer
      (unless (zerop pos)
	(seq-setq (line-start buf-start)
		  (classicist--read-backward-until-newline file pos bufsize))
	(goto-char (point-max)))
      (seq-setq (line-end)
		(classicist--read-forward-until-newline file pos bufsize))
      (when (and line-start line-end)
	(cl-decf line-end)		; Chop off newline
	(list (buffer-substring line-start line-end)
	      (+ buf-start (1- line-start))
	      (+ buf-start (1- line-end)))))))

(defun classicist--ascii-sort-function (a b)
  (let ((word-a (downcase (diogenes--ascii-alpha-only a)))
	(word-b (downcase (diogenes--ascii-alpha-only b))))
    (cond ((string-greaterp word-a word-b) 'a)
	  ((string-greaterp word-b word-a) 'b)
	  (t nil))))

(defun classicist--c-sort-function (a b)
  "Compare A and B as `LC_ALL=C sort' ordered them: by character code.
The comparator a binary search is given must agree with the order of the
file it walks, and for the analyses and lemmata files that order is over
the RAW beta-code keys, in which `)', `(' and `/' precede every letter:

    o)mi/xlh   o)mi/xlhn   o)mi/xlhs   o)mi/xlh|   o)mi/xlh|sin

`classicist--ascii-sort-function' cannot be used on them, because it
compares `diogenes--ascii-alpha-only' -- accents and breathings thrown
away -- and the two orders disagree wherever one key accents an earlier
syllable than another: the file puts `o)mi/xlh' before `o)mikro/n', while
letters-only makes `omikron' the lesser of the two.  A search then walks
into the wrong half and reports no hit, so a form that IS in the file
fails to parse and the caller falls back to searching the dictionary for
the inflected form itself -- which lands on whatever sorts nearest, one
entry or so away from the word wanted.

The failure is per-bucket, which is what makes it look arbitrary: the
three-character bucket `lo/\=' holds keys accented alike and parses
correctly, while `o)m\=' holds `o)mi/xl-\=', `o)mikr-\=', `o)mo/-\=' and
`o)moi-\=' together and had 55 inversions under the wrong comparator.

These keys are pure ASCII, so `string>' is byte order."
  (cond ((string> a b) 'a)
        ((string> b a) 'b)
        (t nil)))


(defun classicist--latin-sort-function (a b)
  "Compare two Lewis & Short keys as the dictionary itself orders them.
`classicist--ascii-sort-function' with `classicist-latin-fold-letters' applied
to both sides; see that variable for why the Latin dictionary needs it."
  (let ((word-a (classicist--latin-fold-key a))
	(word-b (classicist--latin-fold-key b)))
    (cond ((string-greaterp word-a word-b) 'a)
	  ((string-greaterp word-b word-a) 'b)
	  (t nil))))


(defconst classicist--beta-code-alphabet
  [?0 ?a ?b ?g ?d ?e ?v ?z ?h ?q
      ?i ?k ?l ?m ?n ?c ?o ?p
      ?r ?s ?t ?u ?f ?x ?y ?w]
  "The greek alphabet in beta code.")

(defun classicist--beta-sort-function (a b)
  (let ((a (downcase (diogenes--ascii-alpha-only a)))
	(b (downcase (diogenes--ascii-alpha-only b))))
    (cl-case
	(cl-loop for i from 0 to (1- (min (length a) (length b)))
		 for pos-char-a = (cl-position (elt a i)
					       classicist--beta-code-alphabet)
		 for pos-char-b = (cl-position (elt b i)
					       classicist--beta-code-alphabet)
		 do (cond ((not pos-char-a)
			   (error "Illegal character %c" (elt a i)))
			  ((not pos-char-b)
			   (error "Illegal character %c" (elt b i))))
		 if (> pos-char-a pos-char-b) return 'a
		 if (> pos-char-b pos-char-a) return 'b)
      (a 'a)
      (b 'b)
      (t (cond ((> (length a) (length b)) 'a)
	       ((> (length b) (length a)) 'b)
	       (t nil))))))

(defun classicist--tab-key-fn (buf)
  (let ((split (string-match "\t" buf)))
    (when split (list (substring buf 0 split)
		      (substring buf (1+ split))))))


(defun classicist--xml-key-fn (buf)
  (if (string-match "key\\s-*=\\s-*\"\\([^\"]*\\)\""
		    buf)
      (list (match-string-no-properties 1 buf)
	    buf)
    (error "Could not find key in str:\n %s" buf)))

(defun classicist--binary-search (dict-file comp-fn key-fn word &optional start stop)
  "A binary search for finding entries in the lexicographical files.
Upon success, it returns a list containing the entry, its start
and end offsets, and the symbol t to indicate success. Otherwise,
the nearest entry and its offsets are returned."
  (cl-loop with size = (file-attribute-size (file-attributes dict-file))
	   with left = (or start 0)
	   with right = (or stop size)
	   unless (< left right) return (list buf buf-start buf-end)
	   for mid = (floor (+ left right) 2)
	   for (buf buf-start buf-end)
	   = (classicist--get-dict-line dict-file mid size)
	   for (key _value) = (funcall key-fn buf)
	   for comp-result = (funcall comp-fn key word)
	   unless comp-result return (list buf buf-start buf-end t)
	   do (cond ((eq comp-result 'a) (setq right (1- buf-start)))
		    ((eq comp-result 'b) (setq left (1+ buf-end))))))

(defun classicist--analyses-file-to-hashtable (file)
  "Loads a whole analyses file as a hashtable into memory."
  (message "Parsing %s, this may take a while..." file)
  (prog1
      (with-temp-buffer
	(insert-file-contents-literally file)
	(cl-loop with analyses = (make-hash-table :test 'equal :size 950000)
		 with begin = 1
		 for tab = (re-search-forward "\t" nil t)
		 unless tab return analyses
		 for key = (buffer-substring begin (1- tab))
		 for newline = (or (re-search-forward "\n" nil t)
				   (point-max))
		 do (setf (gethash key analyses)
			  (buffer-substring begin (1- newline)))
		 do (setf begin newline)))
    (message "Parsed.")))


(defun classicist--lemmata-file-to-hashtable (file)
  "Loads a whole lemmata file into memory."
  (message "Parsing %s, this may take a while..." file)
  (with-temp-buffer
    (insert-file-contents-literally file)
    (prog1
	(cl-loop with lemmata = (make-hash-table :test 'equal :size 950000)
		 ;; with numbers = (make-hash-table :test 'equal :size 950000)
		 with begin = 1
		 for tab-1 = (re-search-forward "\t" nil t)
		 for tab-2 = (re-search-forward "\t" nil t)
		 ;; unless tab-2 return (cons lemmata numbers)
		 unless tab-2 return lemmata
		 for full-lemma = (buffer-substring begin (1- tab-1))
		 for lemma = (if (string-match "[0-9]$" full-lemma)
				 (substring full-lemma 0 (match-beginning 0))
			       full-lemma)
		 for nr  = (string-to-number (buffer-substring tab-1 (1- tab-2)))
		 for newline = (or (re-search-forward "\n" nil t)
				   (point-max))
		 for entries = (split-string (buffer-substring tab-2 (1- newline))
					     "\t")
		 for record = (nconc (list full-lemma nr) entries)
		 do (push record (gethash lemma lemmata))
		 ;; do (setf (gethash nr numbers)  record)
		 do (setf begin newline))
      (message "Parsed."))))

(defun classicist--read-analyses-index-script (file)
  (diogenes--perl-script
   "sub quote {"
   "  local $_ = shift;"
   "  s/\\\\/\\\\\\\\/g;"
   "  s/\\\"/\\\\\\\"/gr"
   "}"
   "my (%index_start, %index_end, $index_max);"
   (format "open my $fh, '<', '%s' or die $!;" file)
   "eval do { undef local $/; <$fh> };"
   "print '(:index-start (';"
   "while ( my ($k, $v) = each %index_start ) { printf '(\"%s\" . %s)', quote($k), $v }"
   "print ') :index-end (';"
   "while ( my ($k, $v) = each %index_end   ) { printf '(\"%s\" . %s)', quote($k), $v }"
   "print qq') :index-max $index_max)';"))


(defun classicist--read-analyses-index (lang)
  (let ((file (concat (diogenes--perseus-path) "/" lang "-analyses.idt")))
    (unless (file-exists-p file)
      (error "Cannot find %s idt file %s" lang file))
    (unless (file-readable-p file)
      (error "Cannot read %s idt file %s" lang file))
    (read
     (with-temp-buffer
       (unless (zerop (call-process
		       diogenes-perl-executable
		       nil '(t nil) nil
		       "-e" (classicist--read-analyses-index-script file)))
	 (error "Perl exited with errors, no data received!"))
       (buffer-string)))))

(defun classicist--lookup-insert-and-format (str)
  (let ((start (point))
	(inhibit-read-only t))
    (insert str)
    (fill-region start (point))
    (recenter -1)
    (goto-char start)))


(defun classicist--lookup-print-separator ()
  "Print a separator line between entries"
  (insert "\n\n")
  (cl-loop repeat fill-column do (insert "—"))
  (insert "\n\n"))

(defun classicist--dict-parse-xml (str begin end)
  "Try to parse a string containing the XML of a dictionary entry."
  (let ((parsed (with-temp-buffer (insert (classicist--try-correct-xml str))
				  (ignore-errors (car (xml-parse-region))))))
    (when parsed
      ;; The enclosing entry element carries a `key' attribute holding
      ;; the canonical, hyphen-free lemma (e.g. "tamquam" for the entry
      ;; displayed as "tam-quam").  Seed it into the properties so the
      ;; `head' handler can prefer it as the headword for OLD/TLL.
      (let ((entry-key (cdr (assq 'key (cadr parsed))))
	    ;; ONE ENTRY, ONE STACK.  Otherwise the senses of the last entry
	    ;; shown would still be in force at the top of the next.
	    (classicist--dict-sense-stack nil))
	(classicist--dict-process-elt
	 parsed (list 'begin begin 'end end 'entry-key entry-key))))))


(defun classicist--element-text (elt)
  "Return the concatenated text of a parsed XML element ELT.
ELT is a node as produced by `xml-parse-region': a string, or a
list (TAG ATTRS . CHILDREN).  All descendant text is joined in
document order; markup is ignored.  Used to recover a full
headword such as \"tam-quam\" that is split across child nodes."
  (cl-typecase elt
    (string elt)
    (list (mapconcat #'classicist--element-text (cddr elt) ""))
    (t "")))




(defun classicist--dict-sense-path (label level)
  "The path to a sense of LEVEL labelled LABEL, or nil where it has none.

Kept in `classicist--dict-sense-stack\='.  A sense of level n replaces everything
at n and deeper, that being what makes it a new branch rather than a
continuation, and the path is what remains joined by stops.

A sense with no label of its own takes no place on the stack -- Gaffiot and
Georges write bare senses, and a path with an empty level in it names
nothing -- but it does close the levels below it, a new sense being a new
sense whether it is numbered or not."
  (let ((depth (max 1 level)))
    ;; BY LEVEL, AND NOT BY POSITION.  The stack holds (LEVEL . LABEL) pairs
    ;; because an UNLABELLED sense takes no place on it -- the LSJ writes
    ;; level-1 senses with no number, as mere paragraph breaks -- and after
    ;; one of those the nth entry is no longer the nth level.  Truncating by
    ;; position then kept a sibling as a parent, and two level-2 senses came
    ;; out `II\=' and `II.III\=' where `II\=' and `III\=' were meant.
    (setq classicist--dict-sense-stack
          (seq-remove (lambda (pair) (>= (car pair) depth))
                      classicist--dict-sense-stack))
    (unless (string-empty-p label)
      (setq classicist--dict-sense-stack
            (append classicist--dict-sense-stack (list (cons depth label)))))
    (and classicist--dict-sense-stack
         (string-join (mapcar #'cdr classicist--dict-sense-stack) "."))))


(defun classicist--dict-process-elt (elt properties)
  "Process a parsed XML element of a dictionary entry recursively.
The properties list is an accumulator that holds all properties
of the active element."
  (cl-typecase elt
    (string (apply #'propertize elt properties))
    (list (let ((p (append (classicist--dict-handle-elt elt properties)
			   properties)))
	    (mapconcat (lambda (e) (classicist--dict-process-elt e p))
		       (cddr elt))))))


(defun classicist--try-correct-xml (xml)
  "Try to hotfix invalid xml in the greek LSJ files."
  (diogenes--replace-regexes-in-string xml
    ("<\\([[:multibyte:][:space:]]+\\)>" "&lt;\\1&gt;")))


(defvar classicist--dict-xml-handlers-extra
  '(
    ;;(author . '(font-lock-face bold))
    ;;(title . '(font-lock-face italic))
    (i . (font-lock-face warning))
    (b . (font-lock-face bold)))
  "An alist of property lists to be applied to a simple tag in a dictionary.")


(defun classicist--dict-handle-elt (elt &optional properties)
  "Handle the more complicated tags of a Diogenes dictionary file.
Each element is a list whose car is the element, whose cadr is an
a-list containing all the properties, and whose cddr is the
actual contents of the list. This function selects an approriate
handler based on the car and returns a property list that
represents the properties of the element. It may also manipulate
the contents of the element (cddr). Elements that only require
special formatting are handled by th
classicist--dict-xml-handlers-extra variable.
PROPERTIES is the accumulator from `classicist--dict-process-elt';
it may carry an `entry-key' (the canonical lemma of the entry)."
  (let ((tag (car elt))
	(lang (or (alist-get 'lang (cadr elt))
		  "english")))
    (nconc
     (list 'lang lang)
     (cl-case tag
       (div2
	;; THE HEADWORD OVER THE WHOLE ENTRY.  The `head' handler puts `orth'
	;; on the head text, which is where the headword is printed -- but a
	;; reader standing in the middle of an article is not standing on it,
	;; and a command that wants to know which entry this is had to search
	;; the buffer backwards to find out.
	;;
	;; The entry element carries the key, so it can be put on everything
	;; the entry renders to and read at point.  Betacode, as the
	;; dictionaries write it.
	(let ((key (cdr (assoc 'key (cadr elt)))))
	  (and key (list 'entry-key key))))
       (head (let* ((entry-key (plist-get properties 'entry-key))
		    (orth-orig (cdr (assoc 'orth_orig (cadr elt))))
		    ;; The headword shown as "tam-quam" is the compound
		    ;; "tamquam"; a lookup must use the whole word.  Prefer
		    ;; the entry's canonical `key' (hyphen-free, exactly
		    ;; what the dictionary sorts on), then the full head
		    ;; text, then orth_orig, then the first child.
		    (full (string-trim (classicist--element-text elt)))
		    (hw (cond ((and entry-key (> (length entry-key) 0)) entry-key)
			      ((> (length full) 0) full)
			      (orth-orig orth-orig)
			      ((stringp (caddr elt)) (caddr elt)))))
	       (when orth-orig
		 (setf (cddr elt) (list orth-orig)))
	       ;; Tag the head text with an `orth' property carrying this
	       ;; entry's headword, so `diogenes-lookup-open-old' /
	       ;; `diogenes-lookup-open-tll' can find the right page from
	       ;; any point inside the entry.
	       (list 'font-lock-face 'shr-h1
		     'orth hw)))
       (sense
	;; THE PLACE IN THE ENTRY, and not only the label.  A reader citing a
	;; dictionary cites `LSJ s.v. pe/mpw III.2', not the whole of a long
	;; article: the sense is the citation.
	;;
	;; Built without knowing the tree, because it need not be known.
	;; `classicist--dict-process-elt' hands each handler the properties of
	;; its ANCESTORS and passes what comes back down to the children, so
	;; a sense has only to read the path it inherited and add its own
	;; label.  The nesting takes care of itself.
	;;
	;; A sense with no `n' adds nothing and passes its parent's path on
	;; unchanged -- Gaffiot and Georges have bare <sense> elements, and a
	;; path with an empty level in it would name nothing.
	;; FLAT, AND DEEP BY ATTRIBUTE.  The senses of an LSJ entry are
	;; siblings -- every one closes before the next opens -- and their
	;; depth is the `level' attribute, not the nesting.  So a sense
	;; cannot read its place from its ancestors: it has none, and
	;; inheriting from them gave `2' where `III.2' was wanted.
	;;
	;; What is kept instead is a stack, one label to a level, as the
	;; senses are met in order.  A sense of level n throws away
	;; everything at n and deeper -- that is what makes it a new branch
	;; -- and puts its own label at n.  The path is the stack joined.
	(let* ((label (string-trim (or (cdr (assoc 'n (cadr elt))) "")))
	       (level (string-to-number
		       (or (cdr (assoc 'level (cadr elt))) "1")))
	       (path (classicist--dict-sense-path label level)))
	  (push (concat "\n\n"
			(propertize label 'font-lock-face 'success)
			" ")
		(cddr elt))
	  (and path (list 'sense-path path))))
       (bibl (let ((reference (cdr (assoc 'n (cadr elt)))))
	       (list 'font-lock-face 'link
		     'keymap classicist-perseus-action-map
		     'action 'bibl
		     'bibl reference
		     'help-echo reference
		     'rear-nonsticky t)))
       (quote (when (stringp (caddr elt))
		(setf (caddr elt) (concat (caddr elt) " ")))
	      nil)
       (t (or (cdr (assoc tag classicist--dict-xml-handlers-extra))))))))

(provide 'classicist-lexicon)

;;; classicist-lexicon.el ends here
