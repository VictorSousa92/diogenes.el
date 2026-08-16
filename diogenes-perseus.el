;;; diogenes-perseus.el --- Morphological analysis and dictionary lookup for diogenes.el -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This file contains functions that can can use the lexica and morphological analyses that come with Diogenes

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'shr)                          ; for the shr-h1/h2/h3 faces used below
(require 'diogenes-lisp-utils)
(require 'diogenes-utils)
(require 'diogenes-perl-interface)

(declare-function diogenes-perseus-action nil)
(declare-function diogenes-lookup-open-old "diogenes-old" (&optional word))
(declare-function diogenes-lookup-open-tll "diogenes-tll" (&optional word))
(declare-function diogenes-lookup-open-montanari "diogenes-montanari" (&optional word))
(declare-function diogenes-lookup-open-cambridge "diogenes-cambridge" (&optional word))
(declare-function diogenes-lookup-open-bdag "diogenes-bdag" (&optional word))
(declare-function diogenes-lookup-open-passow "diogenes-passow" (&optional word))
(declare-function diogenes-lookup-open-tgl "diogenes-tgl" (&optional word))

;;;; --------------------------------------------------------------------
;;;; UTILITIES
;;;; --------------------------------------------------------------------
(defsubst diogenes--perseus-ensure-utf8 (str lang)
  (if (string= lang "greek")
      (diogenes--perseus-beta-to-utf8 str)
    (diogenes--replace-regexes-in-string str
      ("_" "\N{COMBINING MACRON}")
      ("\\^" "\N{COMBINING BREVE}"))))

(defconst diogenes-perseus-action-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "RET" #'diogenes-perseus-action)
    (keymap-set map "C-c C-c" #'diogenes-perseus-action)
    (keymap-set map "<double-mouse-1>" #'diogenes-perseus-action)
    (keymap-set map "<mouse-2>" #'diogenes-perseus-action)
    map)
  "Keymap that calls the perseus-action-command on certain
words.")

(defvar-local diogenes--lookup-headword nil
  "Headword of the entry currently shown in a lookup buffer.
Used by `diogenes-lookup-open-old' to find the corresponding page
of the Oxford Latin Dictionary PDF.")



;;;; --------------------------------------------------------------------
;;;; Low LEVEL INTERFACE
;;;; --------------------------------------------------------------------

;;; "Readline"
(defun diogenes--read-forward-until-newline (file file-pos bufsize)
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

(defun diogenes--read-backward-until-newline (file file-pos bufsize)
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

(defun diogenes--get-dict-line (file pos &optional file-length)
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
		  (diogenes--read-backward-until-newline file pos bufsize))
	(goto-char (point-max)))
      (seq-setq (line-end)
		(diogenes--read-forward-until-newline file pos bufsize))
      (when (and line-start line-end)
	(cl-decf line-end)		; Chop off newline
	(list (buffer-substring line-start line-end)
	      (+ buf-start (1- line-start))
	      (+ buf-start (1- line-end)))))))

;;; Binary search
;; Sort functions
;; ASCII
(defun diogenes--ascii-sort-function (a b)
  (let ((word-a (downcase (diogenes--ascii-alpha-only a)))
	(word-b (downcase (diogenes--ascii-alpha-only b))))
    (cond ((string-greaterp word-a word-b) 'a)
	  ((string-greaterp word-b word-a) 'b)
	  (t nil))))

(defconst diogenes--beta-code-alphabet
  [?0 ?a ?b ?g ?d ?e ?v ?z ?h ?q
      ?i ?k ?l ?m ?n ?c ?o ?p
      ?r ?s ?t ?u ?f ?x ?y ?w]
  "The greek alphabet in beta code.")

;;; BETA CODE
(defun diogenes--beta-sort-function (a b)
  (let ((a (downcase (diogenes--ascii-alpha-only a)))
	(b (downcase (diogenes--ascii-alpha-only b))))
    (cl-case
	(cl-loop for i from 0 to (1- (min (length a) (length b)))
		 for pos-char-a = (cl-position (elt a i)
					       diogenes--beta-code-alphabet)
		 for pos-char-b = (cl-position (elt b i)
					       diogenes--beta-code-alphabet)
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

;; Key function
(defun diogenes--tab-key-fn (buf)
  (let ((split (string-match "\t" buf)))
    (when split (list (substring buf 0 split)
		      (substring buf (1+ split))))))

(defun diogenes--xml-key-fn (buf)
  (if (string-match "key\\s-*=\\s-*\"\\([^\"]*\\)\""
		    buf)
      (list (match-string-no-properties 1 buf)
	    buf)
    (error "Could not find key in str:\n %s" buf)))

;; The actual search function
(defun diogenes--binary-search (dict-file comp-fn key-fn word &optional start stop)
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
	   = (diogenes--get-dict-line dict-file mid size)
	   for (key value) = (funcall key-fn buf)
	   for comp-result = (funcall comp-fn key word)
	   unless comp-result return (list buf buf-start buf-end t)
	   do (cond ((eq comp-result 'a) (setq right (1- buf-start)))
		    ((eq comp-result 'b) (setq left (1+ buf-end))))))



;;; Parse whole files and load them into memory
(defun diogenes--analyses-file-to-hashtable (file)
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

(defun diogenes--lemmata-file-to-hashtable (file)
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

;;; Get file indices
(defun diogenes--read-analyses-index-script (file)
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

(defun diogenes--read-analyses-index (lang)
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
		       "-e" (diogenes--read-analyses-index-script file)))
	 (error "Perl exited with errors, no data received!"))
       (buffer-string)))))




;;;; --------------------------------------------------------------------
;;;; PERSEUS DICTIONARY LOOKUP
;;;; --------------------------------------------------------------------

;;; Format and insert contents
(defun diogenes--lookup-insert-and-format (str)
  (let ((start (point))
	(inhibit-read-only t))
    (insert str)
    (fill-region start (point))
    (recenter -1)
    (goto-char start)))

(defun diogenes--lookup-print-separator ()
  "Print a separator line between entries"
  (insert "\n\n")
  (cl-loop repeat fill-column do (insert "—"))
  (insert "\n\n"))

;;; Parse XML
(defun diogenes--dict-parse-xml (str begin end)
  "Try to parse a string containing the XML of a dictionary entry."
  (let ((parsed (with-temp-buffer (insert (diogenes--try-correct-xml str))
				  (ignore-errors (car (xml-parse-region))))))
    (when parsed
      ;; The enclosing entry element carries a `key' attribute holding
      ;; the canonical, hyphen-free lemma (e.g. "tamquam" for the entry
      ;; displayed as "tam-quam").  Seed it into the properties so the
      ;; `head' handler can prefer it as the headword for OLD/TLL.
      (let ((entry-key (cdr (assq 'key (cadr parsed)))))
	(diogenes--dict-process-elt
	 parsed (list 'begin begin 'end end 'entry-key entry-key))))))

(defun diogenes--element-text (elt)
  "Return the concatenated text of a parsed XML element ELT.
ELT is a node as produced by `xml-parse-region': a string, or a
list (TAG ATTRS . CHILDREN).  All descendant text is joined in
document order; markup is ignored.  Used to recover a full
headword such as \"tam-quam\" that is split across child nodes."
  (cl-typecase elt
    (string elt)
    (list (mapconcat #'diogenes--element-text (cddr elt) ""))
    (t "")))

(defun diogenes--dict-process-elt (elt properties)
  "Process a parsed XML element of a dictionary entry recursively.
The properties list is an accumulator that holds all properties
of the active element."
  (cl-typecase elt
    (string (apply #'propertize elt properties))
    (list (let ((p (append (diogenes--dict-handle-elt elt properties)
			   properties)))
	    (mapconcat (lambda (e) (diogenes--dict-process-elt e p))
		       (cddr elt))))))

(defun diogenes--try-correct-xml (xml)
  "Try to hotfix invalid xml in the greek LSJ files."
  (diogenes--replace-regexes-in-string xml
    ("<\\([[:multibyte:][:space:]]+\\)>" "&lt;\\1&gt;")))

(defvar diogenes--dict-xml-handlers-extra
  '(
    ;;(author . '(font-lock-face bold))
    ;;(title . '(font-lock-face italic))
    (i . (font-lock-face warning))
    (b . (font-lock-face bold)))
  "An alist of property lists to be applied to a simple tag in a dictionary.")

(defun diogenes--dict-handle-elt (elt &optional properties)
  "Handle the more complicated tags of a Diogenes dictionary file.
Each element is a list whose car is the element, whose cadr is an
a-list containing all the properties, and whose cddr is the
actual contents of the list. This function selects an approriate
handler based on the car and returns a property list that
represents the properties of the element. It may also manipulate
the contents of the element (cddr). Elements that only require
special formatting are handled by th
diogenes--dict-xml-handlers-extra variable.
PROPERTIES is the accumulator from `diogenes--dict-process-elt';
it may carry an `entry-key' (the canonical lemma of the entry)."
  (let ((tag (car elt))
	(lang (or (alist-get 'lang (cadr elt))
		  "english")))
    (nconc
     (list 'lang lang)
     (cl-case tag
       (head (let* ((entry-key (plist-get properties 'entry-key))
		    (orth-orig (cdr (assoc 'orth_orig (cadr elt))))
		    ;; The headword shown as "tam-quam" is the compound
		    ;; "tamquam"; a lookup must use the whole word.  Prefer
		    ;; the entry's canonical `key' (hyphen-free, exactly
		    ;; what the dictionary sorts on), then the full head
		    ;; text, then orth_orig, then the first child.
		    (full (string-trim (diogenes--element-text elt)))
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
       (sense (push (concat "\n\n"
			    (propertize (or (cdr (assoc 'n (cadr elt))) "")
					'font-lock-face 'success)
			    " ")
		    (cddr elt))
	      nil)
       (bibl (let ((reference (cdr (assoc 'n (cadr elt)))))
	       (list 'font-lock-face 'link
		     'keymap diogenes-perseus-action-map
		     'action 'bibl
		     'bibl reference
		     'help-echo reference
		     'rear-nonsticky t)))
       (quote (when (stringp (caddr elt))
		(setf (caddr elt) (concat (caddr elt) " ")))
	      nil)
       (t (or (cdr (assoc tag diogenes--dict-xml-handlers-extra))))))))



;;; Let the user handle corrupt XML
;;; ... in the lookup mode
(let ((numeric-id 0))
  (defun diogenes--lookup-insert-xml (xml start end buffer)
    "Give the user the change to fix invalid XML in the dictionaries."
    (let* ((key (and (string-match "key=\"\\([^\"]+\\)\"" xml)
		     (match-string 1 xml)))
	   (id (or key (cl-incf numeric-id)))
	   (inhibit-read-only t))
      (message "Invalid xml in entry: Showing entry!")
      (insert (propertize (diogenes--fontify-nxml xml)
			  'invalid-xml id
			  'inhibit-read-only t
			  'keymap (let ((map (make-sparse-keymap)))
				    (keymap-set map "q" #'self-insert-command)
				    map)
			  'begin start
			  'end end))
      (setq diogenes--lookup-buffer buffer
	    diogenes--lookup-entry-id id
	    diogenes--lookup-bufstart start
	    diogenes--lookup-bufend end))))

(defun diogenes--lookup-xml-validate ()
  "Try to validate, parse, format and insert a corrected dictionary entry."
  (interactive)
  (let* ((id (or (get-text-property (point) 'invalid-xml)
	         (error "No XML here to validate!")))
	 (line-start (get-text-property (point) 'begin))
	 (line-end (get-text-property (point) 'end))
	 (prop-boundaries (diogenes--get-text-prop-boundaries (point)
							      'invalid-xml))
	 (xml (apply #'buffer-substring prop-boundaries))
	 (parsed (diogenes--dict-parse-xml xml line-start line-end))
	 (inhibit-read-only t))
    (apply #'delete-region prop-boundaries)
    (if parsed
	(diogenes--lookup-insert-and-format parsed)
      (insert (propertize (diogenes--fontify-nxml xml)
			  'invalid-xml id
			  'inhibit-read-only t
			  'begin line-start
			  'end line-end)))))

(defun diogenes--fontify-nxml (str)
  "Use nxml-mode to fontify a string.
All overlays added by rng-validate-mode are converted to text
properties."
  (with-temp-buffer
    (pop-to-buffer (current-buffer))
    (insert str)
    (nxml-mode)
    (rng-validate-mode)
    (font-lock-ensure)
    (cl-loop for ov in (overlays-in (point-min) (point-max))
	     for start = (overlay-start ov)
	     for end = (overlay-end ov)
	     for values = (overlay-properties ov)
	     when (eq (plist-get values 'category) 'rng-error)
	     do (add-text-properties
		 start end
		 (list 'face 'rng-error
		       'font-lock-face 'rng-error
		       'help-echo (plist-get values 'help-echo))))
    ;; (remove-overlays)
    (let ((map (make-sparse-keymap)))
      (keymap-set map "C-c C-c" #'diogenes--lookup-xml-validate)
      (keymap-set map "C-c '" #'diogenes--lookup-xml-edit)
      (propertize (buffer-string)
		  'keymap map))))

;;; ... in a dedicated NXML buffer
(defun diogenes--lookup-xml-edit ()
  "Edit a corrupt dictionary entry in XML-mode"
  (interactive)
  (let* ((id (or (get-text-property (point) 'invalid-xml)
	         (error "No corrupt XML at point to edit!")))
	 (prop-boundaries (diogenes--get-text-prop-boundaries (point)
							      'invalid-xml))
	 (xml (apply #'buffer-substring prop-boundaries))
	 (lookup-buffer (current-buffer))
	 (xml-buffer (diogenes--get-fresh-buffer "xml"))
	 (map (make-sparse-keymap)))
    (keymap-set map "C-c C-c" #'diogenes--xml-submit)
    (pop-to-buffer xml-buffer)
    (nxml-mode)
    (insert (propertize xml
			'lookup-buffer lookup-buffer
			'id id
			'prop-boundaries prop-boundaries
			'keymap map))
    (goto-char (point-min))))

(defun diogenes--xml-submit ()
  "Try to submit a fixed XML dictionary entry."
  (interactive)
  (let* ((id (or (get-text-property (point) 'invalid-xml)
	         (error "No corrupt XML at point to edit!")))
	(prop-boundaries (diogenes--get-text-prop-boundaries (point)
							     'invalid-xml))
	(lookup-buffer (get-text-property (point) 'lookup-buffer))
	(xml-buffer (current-buffer))
	(invalid-xml (with-current-buffer lookup-buffer
		       (save-excursion
			 (goto-char (point-min))
			 (text-property-search-forward 'invalid-xml id t))))
	(prop-start (prop-match-beginning invalid-xml))
	(prop-end (prop-match-end invalid-xml))
	(line-start (get-text-property prop-start 'begin))
	(line-end (get-text-property prop-start 'end))
	(parsed (diogenes--dict-parse-xml (buffer-string) line-start line-end))
	(inhibit-read-only t))
    (cond (parsed (kill-buffer xml-buffer)
		  (pop-to-buffer lookup-buffer)
		  (delete-region prop-start prop-end)
		  (diogenes--lookup-insert-and-format parsed))
	  (t (rng-first-error)))))



(defvar diogenes--lookup-same-window nil
  "When non-nil, show a looked-up entry in the CURRENT window.
`diogenes--search-dict' normally opens each entry in a fresh
`*Diogenes Lookup*' buffer and `pop-to-buffer's it, which may split or
reuse another window.  When this variable is non-nil the fresh buffer
is shown in the window that was selected when the lookup was invoked
\(via `pop-to-buffer-same-window'), so a `C-c C-c' chain stays in one
window while the previous entry's buffer remains live (reachable with
the usual buffer/window history).  Bound by `diogenes-perseus-action';
nil everywhere else keeps the old behaviour.")

(defun diogenes--search-dict (word lang sort-fn key-fn)
  "Search for a word in a Diogenes dictionary.
The lines in dictionary file must be sorted according to SORT-FN,
while KEY-FN must return the key."
  (seq-let (xml-bytes start end exact-hit)
      (diogenes--binary-search (diogenes--dict-file lang)
			       sort-fn key-fn word)
    (unless exact-hit (message "No results for %s! Showing nearest entry" word))
    (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	   (formatted (diogenes--dict-parse-xml xml start end))
	   (lookup-buffer (diogenes--get-fresh-buffer "lookup")))
      ;; A fresh buffer either way (the previous entry is never destroyed);
      ;; `diogenes--lookup-same-window' only chooses WHERE to show it -- in
      ;; the calling window, or (default) via the usual `pop-to-buffer'.
      ;;
      ;; Turn the major mode ON BEFORE displaying: `display-buffer' (and the
      ;; `pop-to-buffer' below) consult `display-buffer-alist', whose rules
      ;; may dispatch on the buffer's major mode.  If the mode were switched
      ;; on only afterwards, the buffer would still be in Fundamental mode at
      ;; display time and such a rule could not recognise it as a Diogenes
      ;; lookup.  `diogenes-lookup-mode' derives from `text-mode', so it runs
      ;; `kill-all-local-variables'; the buffer-local settings below are
      ;; therefore assigned AFTER it, as before.
      (with-current-buffer lookup-buffer
	(diogenes-lookup-mode))
      (if diogenes--lookup-same-window
	  (pop-to-buffer-same-window lookup-buffer)
	(pop-to-buffer lookup-buffer))
      (setq diogenes--lookup-file (diogenes--dict-file lang)
	    diogenes--lookup-bufstart start
	    diogenes--lookup-bufend end
	    diogenes--lookup-lang lang)
      (cond (formatted (diogenes--lookup-insert-and-format formatted))
	    (t (diogenes--lookup-insert-xml xml start end lookup-buffer)))
      ;; Record the first entry's headword (a fallback for the openers) and
      ;; give the entry its own clickable link banner (OLD/TLL for Latin;
      ;; Montanari, CGL, BDAG, Passow, TGL for Greek).  Navigation adds a
      ;; banner per entry too, so links follow you between entries.
      (setq diogenes--lookup-headword
	    (diogenes--lookup-first-headword))
      (save-excursion
	(goto-char (point-min))
	(diogenes--lookup-insert-entry-links lang)))))

(defun diogenes--lookup-insert-entry-links (lang &optional pos)
  "Insert the print-dictionary link banner for the entry at POS (point default).
Resolves that entry's own headword via `diogenes--lookup-headword-at-point'
and inserts its links just before the headword, so every entry -- the one
first looked up and each later `diogenes-lookup-next' / `-previous' step --
carries links that act on ITS headword.  A no-op when the entry has no
detectable headword."
  (let ((pos (or pos (point))))
    (save-excursion
      (goto-char pos)
      (let ((hw (diogenes--lookup-headword-at-point pos)))
	(when hw
	  (diogenes--lookup-insert-dict-links hw lang))))))

(defvar diogenes--lookup-headword nil
  "Headword of the entry shown in the current lookup buffer.
Buffer-local in `diogenes-lookup-mode' buffers; used by the
print-dictionary openers.")
(defvar diogenes--lookup-lang nil
  "Language (\"greek\" or \"latin\") of the current lookup buffer's entry.
Buffer-local in `diogenes-lookup-mode' buffers.")

(defun diogenes--lookup-assert-lang (expected dict-name)
  "Abort unless the current lookup entry's language is EXPECTED.
EXPECTED is \"greek\" or \"latin\"; DICT-NAME is the dictionary's
name, used in the error message.  The print dictionaries call this
at the start of their opener commands so that, e.g., a Greek-only
lexicon is not opened on a Latin entry and vice versa.  The check
relies on the buffer-local `diogenes--lookup-lang' recorded when
the lookup buffer was built; if the language is unknown, no error
is raised."
  (let ((lang (and (boundp 'diogenes--lookup-lang) diogenes--lookup-lang)))
    (when (and lang (not (string= lang expected)))
      (user-error "%s is a %s dictionary, but this entry is %s"
                  dict-name
                  (capitalize expected)
                  lang))))

(defun diogenes--lookup-insert-dict-links (headword lang)
  "Insert clickable print-dictionary links for HEADWORD at point.
For Latin (LANG \"latin\") this inserts [OLD] and [TLL]; for Greek
it inserts [Montanari] [CGL] [BDAG] [Passow] [TGL].  Clicking a link
\(or pressing RET on it) opens the corresponding PDF at the page
containing HEADWORD.  The links are inserted AT POINT, so the caller
positions to the top of the entry the links belong to; the initial
lookup and each `diogenes-lookup-next' / `-previous' step do this once
per entry, so every entry carries its own banner.  Each link is only
useful when its dictionary's path variable is set (`diogenes-old-pdf-file',
`diogenes-tll-pdf-directory', `diogenes-montanari-pdf-file',
`diogenes-cambridge-pdf-file', `diogenes-bdag-pdf-file',
`diogenes-passow-directory', `diogenes-tgl-directory')."
  (let ((inhibit-read-only t))
    (save-excursion
      (pcase lang
	("latin"
	 (insert (propertize "[OLD]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'old
			     'headword headword
			     'help-echo (format "Open the OLD at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "
		 (propertize "[TLL]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'tll
			     'headword headword
			     'help-echo (format "Open the TLL at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "))
	("greek"
	 (insert (propertize "[Montanari]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'montanari
			     'headword headword
			     'help-echo (format "Open Montanari at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "
		 (propertize "[CGL]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'cambridge
			     'headword headword
			     'help-echo (format "Open the Cambridge Greek Lexicon at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "
		 (propertize "[BDAG]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'bdag
			     'headword headword
			     'help-echo (format "Open BDAG (Bauer) at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "
		 (propertize "[Passow]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'passow
			     'headword headword
			     'help-echo (format "Open Passow at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "
		 (propertize "[TGL]"
			     'font-lock-face 'link
			     'keymap diogenes-perseus-action-map
			     'action 'tgl
			     'headword headword
			     'help-echo (format "Open Estienne's Thesaurus Graecae Linguae at \"%s\"" headword)
			     'rear-nonsticky t)
		 "  "))))))

(defun diogenes--lookup-first-headword ()
  "Return the first entry headword in the current lookup buffer.
Reads the `orth' text property placed on head elements by
`diogenes--dict-handle-elt'.  Returns nil if none is found."
  (save-excursion
    (goto-char (point-min))
    (let ((match (text-property-search-forward 'orth nil
						(lambda (_ v) (and v t)))))
      (and match (prop-match-value match)))))

(defun diogenes--lookup-headword-at-point (&optional pos)
  "Return the headword of the entry containing POS (point by default).
A lookup buffer accumulates entries as you navigate with
`diogenes-lookup-next' / `diogenes-lookup-previous'; each entry's
headword carries the `orth' text property (placed by
`diogenes--dict-handle-elt').  The entry POS sits in is the one whose
headword is the NEAREST `orth' at or before POS, so this reads the
`orth' at POS when point is inside a headword, else searches backward;
if POS precedes the first headword, it falls back to the first `orth'
after POS.  Returns nil when the buffer has no `orth' property at all.

This is what makes the print-dictionary keys (o m c b p t) and the
per-entry link banners act on the entry the cursor is in, rather than
the entry the buffer was first opened on."
  (let ((pos (or pos (point))))
    (save-excursion
      (goto-char pos)
      (or (get-text-property pos 'orth)
          (let ((match (text-property-search-backward 'orth nil
                        (lambda (_ v) (and v t)))))
            (if match
                (prop-match-value match)
              (goto-char pos)
              (let ((m (text-property-search-forward 'orth nil
                        (lambda (_ v) (and v t)))))
                (and m (prop-match-value m)))))))))

(defun diogenes--lookup-dict (word lang)
  "Search for a word in a Diogenes dictionary. Dispatcher function."
  (pcase lang
    ("greek" (let ((normalized (diogenes--beta-normalize-gravis
		     (diogenes--greek-ensure-beta word))))
	       (diogenes--search-dict normalized "greek"
				      #'diogenes--beta-sort-function
				      #'diogenes--xml-key-fn)))
    ("latin" (diogenes--search-dict word "latin"
			 #'diogenes--ascii-sort-function
			 #'diogenes--xml-key-fn))))

(defun diogenes-lookup-next (&optional n)
  "Find and show the next entry in the active dictionary.
When called with a numerical prefix, show the next N entries."
  (interactive "p")
  (unless (eq major-mode 'diogenes-lookup-mode)
    (error "Not in Diogenes Lookup Mode!"))
  (seq-let (xml-bytes start end)
      (diogenes--get-dict-line diogenes--lookup-file
			       (1+ diogenes--lookup-bufend))
    (unless xml-bytes (error "No further entries!"))
    (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	   (formatted (diogenes--dict-parse-xml xml start end))
	   (inhibit-read-only t))
      (setq diogenes--lookup-bufend end)
      (goto-char (point-max))
      (diogenes--lookup-print-separator)
      (let ((entry-start (point)))
	(if formatted
	    (diogenes--lookup-insert-and-format formatted)
	  (diogenes--lookup-insert-xml xml start end (current-buffer)))
	;; give the newly-appended entry its own dictionary link banner,
	;; acting on ITS headword (see `diogenes--lookup-insert-entry-links').
	(diogenes--lookup-insert-entry-links diogenes--lookup-lang entry-start))
      (when (and n (> n 1)) (diogenes-lookup-next (1- n))))))

(defun diogenes-lookup-previous (&optional n)
  "Find and show the previous entry in the active dictionary.
When called with a numerical prefix, show the previous N entries."
  (interactive "p")
  (unless (eq major-mode 'diogenes-lookup-mode)
    (error "Not in Diogenes Lookup Mode!"))
  (seq-let (xml-bytes start end)
      (diogenes--get-dict-line diogenes--lookup-file
			       (1- diogenes--lookup-bufstart))
    (unless xml-bytes (error "No further entries!"))
    (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	   (formatted (diogenes--dict-parse-xml xml start end))
	   (inhibit-read-only t))
      (setq diogenes--lookup-bufstart start)
      (goto-char (point-min))
      (diogenes--lookup-print-separator)
      (goto-char (point-min))
      (let ((entry-start (point)))
	(if formatted
	    (diogenes--lookup-insert-and-format formatted)
	  (diogenes--lookup-insert-xml xml start end (current-buffer)))
	;; link banner for the just-prepended entry, on ITS headword.
	(diogenes--lookup-insert-entry-links diogenes--lookup-lang entry-start))
      (goto-char (point-min))
      (when (and n (> n 1)) (diogenes-lookup-previous (1- n))))))



;;; LOOKUP MODE
(defun diogenes--lookup-parse-bibl-string (str)
  "Parse a DICT bibliography reference string.
Returns a list that diogenes--browse-work can be applied to."
  (seq-let (corpus author work-and-passage)
      (split-string (replace-regexp-in-string "^Perseus:abo:" "" str)
		    ",")
    (seq-let (work &rest passage)
	(split-string work-and-passage ":")
      (let ((labels-missing
	     (- (length (diogenes--get-work-labels (list :type corpus)
						   (list author work)))
		(length passage))))
	(cond ((< labels-missing 0) (error "Too many labels! %s" str))
	      ((> labels-missing 0)
	       (setq passage (nconc passage (cl-loop for i from 1 to labels-missing
						     collect "")))))
	(list (list :type corpus)
	      (append (list author work) passage))))))

(defun diogenes-lookup-forward-line (&optional N)
  (interactive "p")
  (forward-line N)
  (when (eobp) (diogenes-lookup-next)))

(defun diogenes-lookup-backward-line (&optional N)
  (interactive "p")
  (forward-line (- N))
  (when (bobp) (diogenes-lookup-previous)))

(defun diogenes-lookup-beginning-of-buffer (&optional N)
  (interactive "^P")
  (when (and (not N) (bobp))
    (diogenes-lookup-previous))
  (beginning-of-buffer N))

(defun diogenes-lookup-end-of-buffer (&optional N)
  (interactive "^P")
  (when (and (not N) (eobp))
    (diogenes-lookup-next))
  (end-of-buffer N))


(defvar diogenes-lookup-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    ;; Overrides of movement keys
    (keymap-set map "<remap> <previous-line>"       #'diogenes-lookup-backward-line)
    (keymap-set map "<remap> <next-line>"           #'diogenes-lookup-forward-line)
    (keymap-set map "<remap> <beginning-of-buffer>" #'diogenes-lookup-beginning-of-buffer)
    (keymap-set map "<remap> <end-of-buffer>"       #'diogenes-lookup-end-of-buffer)
    (keymap-set map "C-c C-n"                       #'diogenes-lookup-next)
    (keymap-set map "C-c C-p"                       #'diogenes-lookup-previous)
    (keymap-set map "C-c C-c"                       #'diogenes-perseus-action)
    (keymap-set map "o"                             #'diogenes-lookup-open-old)
    (keymap-set map "t"                             #'diogenes-lookup-open-tll-or-tgl)
    (keymap-set map "m"                             #'diogenes-lookup-open-montanari)
    (keymap-set map "c"                             #'diogenes-lookup-open-cambridge)
    (keymap-set map "b"                             #'diogenes-lookup-open-bdag)
    (keymap-set map "p"                             #'diogenes-lookup-open-passow)
    (keymap-set map "q"                             #'diogenes--quit)
    map)
  "Basic mode map for the Diogenes Lookup Mode.")

(define-derived-mode diogenes-lookup-mode text-mode "Diogenes Lookup"
  "Major mode to browse databases."
  (make-local-variable 'diogenes--lookup-file)
  (make-local-variable 'diogenes--lookup-bufstart)
  (make-local-variable 'diogenes--lookup-bufend)
  (make-local-variable 'diogenes--lookup-lang)
  (make-local-variable 'diogenes--lookup-headword)
  (setq buffer-read-only t))



;;;; --------------------------------------------------------------------
;;;; PERSEUS PARSING
;;;; --------------------------------------------------------------------

;;; Cached functions for information retrieval
(let ((cache (make-hash-table :test 'equal)))
  (defun diogenes--get-all-analyses (lang)
    "Returns the entirety of an analysis file as a hash table.
This function is cached, so that it actually reads and parses teh
file only at the first call."
    (or (gethash (cons lang 'analyses) cache)
	(setf (gethash (cons lang 'analyses) cache)
	      (diogenes--analyses-file-to-hashtable
	       (file-name-concat (diogenes--perseus-path)
				 (concat lang "-analyses.txt"))))))

  (defun diogenes--get-analyses-index (lang)
    "Returns the indices of an analysis file written by Diogenes.
 This function is cached, so that it actually reads and parses
the file only at the first call."
    (or (gethash (cons lang 'index) cache)
	(setf (gethash (cons lang 'index) cache)
	      (diogenes--read-analyses-index lang))))

  (defun diogenes--get-all-lemmata (lang)
    "Returns the entirety of a lemmata file as a hash table.
 This function is cached, so that it actually reads and parses
the file only at the first call."
    (or (gethash (cons lang 'lemmata) cache)
	(setf (gethash (cons lang 'lemmata) cache)
	      (diogenes--lemmata-file-to-hashtable
	       (file-name-concat (diogenes--perseus-path)
				 (concat lang "-lemmata.txt")))))))



;;; Analysis mode
;; TODO: This should be made better
;; - Inhibit editing the invisible text
;; - org-mode-style  visibility cycling
;; - etc.
(defun diogenes-analysis-cycle (pos)
  "On a heading in analysis mode, show or hide its contents."
  (interactive "d")
  (when-let ((level (get-char-property pos 'heading))
	     (region-start (next-single-property-change pos level))
	     (region-end (or (next-single-property-change region-start level)
			     (point-max))))
    (put-text-property region-start region-end 'invisible
		       (if (get-text-property region-start 'invisible)
			   nil t))))

(defvar diogenes-analysis-mode-map
  (let ((map (nconc (make-sparse-keymap) text-mode-map)))
    (keymap-set map "TAB"  #'diogenes-analysis-cycle)
    map)
  "Basic mode map for the Diogenes Analysis Mode.")

(define-derived-mode diogenes-analysis-mode text-mode "Diogenes Analysis"
  "Display analysis of search term.")


(defun diogenes--process-parse-result (encoded-str lang)
  "Split a bytestring as retrieved form the analyses file into a
list of the corresponding entries. Each entry consists of the headword, the
lemma, the lemma-number, translation and analysis."
  (cl-loop with str = (decode-coding-string encoded-str 'utf-8)
	   for entry in (split-string (cadr (diogenes--split-once "\t+" str))
				      ;; Remove also trailing [\d+] after }
				      "[{}]\\(?:\\[[0-9]+\\]\\)*"
				      t "\\s-")
	   for (lemma-str translation analysis) = (split-string entry "\t" nil "\\s-")
	   for (lemma-nr lemma-cat headword-and-lemma) = (split-string lemma-str)
	   for (headword lemma) = (split-string headword-and-lemma "," t "\\s-")
	   collect (list headword
			 lemma
			 lemma-nr
			 translation
			 analysis)))

(defun diogenes--process-lemma (lemma lang)
  "Process a lemma entry as returned from `diogenes--get-all-lemmata'.
Returns a list with the form (lemma raw-lemma lemma-nr &rest analyses)"
  (when lemma
    (nconc (list (diogenes--perseus-ensure-utf8 (car lemma)
						lang)
		 (car lemma)
		 (cadr lemma))
	   (mapcar (lambda (e)
		     (seq-let (form analysis)
			 (diogenes--split-once "\\s-" e)
		       (cons (diogenes--perseus-ensure-utf8 form lang)
			     (with-temp-buffer
			       (insert analysis)
			       (goto-char (point-min))
			       (cl-loop with substrings
					for pos = (scan-sexps (point) 1)
					if pos
					collect (buffer-substring (1+ (point))
								  (1- pos))
					into substrings
					else return substrings
					do (goto-char (1+ pos)))))))
		   (cddr lemma)))))

;;; Parsing functions
(defun diogenes--parse-word (word lang)
  "Search the ananlyses file of lang for word using a binary search.
Returns the nearest hit to the query."
  (let* ((normalized (downcase (diogenes--beta-normalize-gravis
				(diogenes--greek-ensure-beta word))))
	 (analyses-file (file-name-concat (diogenes--perseus-path)
					  (concat lang "-analyses.txt")))
	 (index (diogenes--get-analyses-index lang))
	 (key (if (> (length normalized) 3) (substring normalized 0 3) normalized))
	 (start (let ((s (cdr (assoc key (plist-get index :index-start)))))
		  (if s (- s 2) 0)))
	 (end (or (cdr (assoc key (plist-get index :index-end)))
		  (plist-get index :index-max))))
    (let ((result (diogenes--binary-search analyses-file
					   #'diogenes--ascii-sort-function
					   #'diogenes--tab-key-fn
					   normalized
					   start end)))
      (unless (nth 3 result)
	(message "No result for %s! Showing nearest entry" word))
      (cons (and (car result)
		 (diogenes--process-parse-result (car result) lang))
	    (cdr result)))))

(let ((cache (make-hash-table :test 'equal)))
 (defun diogenes--all-matches-in-hashtable (query hash-table filter ignore-case no-diacritics)
   "Search for all entries in the table where querey matches the key via filter.
Additionally, letter case and diacritics can be ignored."
   (let* ((filter (or filter #'string-equal))
	  (ignore-case (and ignore-case t))
	  (no-diacritics (and no-diacritics t))
	  (transformation (cond ((and ignore-case no-diacritics)
				 (lambda (x) (downcase (diogenes--ascii-alpha-only x))))
				(ignore-case #'downcase)
				(no-diacritics #'diogenes--ascii-alpha-only)))
	  (query (if (not (or ignore-case no-diacritics))
		     query
		   (funcall transformation query)))
	  (hash (if (not (or ignore-case no-diacritics))
		    hash-table
		  (or (gethash (list hash-table ignore-case no-diacritics) cache)
		      (setf (gethash (list hash-table ignore-case no-diacritics) cache)
			    (cl-loop with hash =
				     (make-hash-table :test 'equal :size 50000)
				     for k being the hash-keys of hash-table
				     do (push k
					      (gethash (funcall transformation k) hash))
				     finally return hash)))))
	  (results (if (eq filter #'string-equal)
		       (when-let ((entry (gethash query hash)))
			 (list (cons query entry)))
		     (cl-loop for k being the hash-keys of hash
			      using (hash-values v)
			      when (funcall filter query k)
			      collect (cons k v)))))
     (if (not (or ignore-case no-diacritics))
	 results
       (cl-loop for (q . keys) in results append
		(cl-loop for key in keys collect
			 (cons key (gethash key hash-table))))))))

(defun diogenes--parse-all (query lang &optional filter ignore-case no-diacritics)
   "Search all the forms in the analyses file.
Return all the entries whose keys match query when filter is applied to them.
Unless specified, filter defaults to string-equal."
   (let ((entries (diogenes--all-matches-in-hashtable query
						      (diogenes--get-all-analyses lang)
						      filter
						      ignore-case
						      no-diacritics)))
     (when entries
       (mapcar (lambda (x) (cons (car x)
			    (diogenes--process-parse-result (cdr x) lang)))
	       entries))))

(defun diogenes--get-all-forms (lemma lang)
  "Get all attested forms of LEMMA in LANG.
As there vould be several entries for the same lemma, this
function returns a list of lists."
  (mapcar (lambda (l) (diogenes--process-lemma l lang))
	  (gethash lemma (or (diogenes--get-all-lemmata lang)
			     (error "No lemmata retrieved for %s" lang)))))

(defun diogenes--query-all-lemmata (query lang &optional filter ignore-case no-diacritics)
  "Search all lemmata in the lemmata file.
Return all the entries whose keys match query when filter is applied to them.
Unless specified, filter defaults to string-equal."
  (let ((entries (diogenes--all-matches-in-hashtable query
						     (diogenes--get-all-lemmata lang)
						     filter
						     ignore-case
						     no-diacritics)))
    (when entries
      (mapcar (lambda (l) (diogenes--process-lemma (cadr l) lang))
	      entries))))

(defun diogenes--parse-and-lookup (word lang)
  "Try to parse a word by looking it up in the morphological files,
and show the entry for it in the lexica. Dispatcher function."
  (seq-let (analyses start stop exact-hit) (diogenes--parse-word word lang)
    (cond
     (exact-hit
      (let* ((lemmata (diogenes--assign-parse-result-to-lemmata analyses))
	     (lemma
	      (if (= 1 (length lemmata))
		  (caar lemmata)
		(let ((alist
		       (cl-loop
			for lemma in lemmata
			for (word nr translation analyses-entries) = lemma
			for analyses = (mapcar #'cdr analyses-entries)
			collect
			(list (format "%s (%s)"
				      (diogenes--perseus-ensure-utf8
				       word lang)
				      translation)
			      word
			      (concat "\t"
				      (string-join analyses ",")))))
		      (completion-extra-properties
		       '(:annotation-function
			 (lambda (s)
			   (caddr (assoc s minibuffer-completion-table))))))
		  (cadr (assoc (completing-read
				(format "Choose a lemma for %s: "
					word)
				alist)
			       alist))))))
	(cond (lemma (diogenes--lookup-dict lemma lang))
	      (t (message "Trying to look %s up in the dictionaries!" wor
			  d)
		 (diogenes--lookup-dict word lang)))))
     (t (message "No results for %s, trying to look it up in the dictionaries!"
		 word)
	(diogenes--lookup-dict word lang)))))

(defun diogenes--add-parse-entry ()
  "Get or create an Diogenes Analysis buffer, and begin a new entry."
  (pop-to-buffer (get-buffer-create "*Diogenes Analysis*"))
  (goto-char (point-max))
  (unless (eq major-mode #'diogenes-analysis-mode)
    (diogenes-analysis-mode))
  (unless (diogenes--first-line-p)
    (insert "\n")))

(defun diogenes--parse-and-show-choose-filter (filter ignore-case no-diacritics)
  "Choose an approriate filter function for `diogenes--parse-and-show'."
  (cons
   (or filter
       (let* ((functions '((?l . string-equal)
			   (?p . string-prefix-p)
			   (?s . string-suffix-p)
			   (?i . string-search)
			   (?r . string-match-p)
			   (?o . other)))
	      (filter (alist-get (read-char-from-minibuffer
				  (concat "Match (l)iterally, or as "
					  "(p)refix, "
					  "(s)uffix, "
					  "(i)nfix, "
					  "(r)egular expression,"
					  "(o)ther: ")
				  (cl-loop for l in functions
					   collect (car l)))
				 functions nil nil #'eql)))
      (cl-case filter
	((nil) #'string-equal)
	(other
	 (read-minibuffer
	  "Enter a function-object of two arguments, the query and the string: "))
	(t filter))))
   (list (cl-case ignore-case
	   ((nil) (not (y-or-n-p "Make the search case sensitive?")))
	   (ignore nil)
	   (t t))
	 (cl-case no-diacritics
	   ((nil) (not (y-or-n-p "Make the search diacritics sensitive?")))
	   (ignore nil)
	   (t t)))))


(defun diogenes--assign-parse-result-to-lemmata (parse-results)
  "Loop through the result of `diogenes--process-parse-result',
assigning the single results to their respective lemmata. Returns the lemmata as a list,
where each lemma is itself a list consisting of the LEMMA-NR, the LEMMA-WORD, the TRANSLATION
and the list on ANALYSES."
  (cl-loop
   with lemmata
   for (headword lemma-word lemma-nr translation analysis) in parse-results
   for existent-lemma = (assoc lemma-word lemmata)
   for entry = (cons headword analysis)
   unless existent-lemma do (push (list (or lemma-word
					    headword)
					lemma-nr
					(if (string-blank-p translation)
					    "No translation available"
					  translation)
					(list entry))
				  lemmata)
   else do (push entry (cl-fourth existent-lemma))
   finally return lemmata))

(defun diogenes--format-parse-results (query lang results)
  "Process and format the results of `diogenes--process-parse-result'.
Besides the fontification, it also checks for duplicate lemma
entries and orders them accordingly."
  (let ((lemmata (diogenes--assign-parse-result-to-lemmata results)))
    (cl-loop
     for lemma in lemmata
     for (lemma-word lemma-nr translation entries) = lemma
     concat (concat (propertize (string-trim
				 (format "%s (%s)"
					 (diogenes--perseus-ensure-utf8 lemma-word
									lang)
					 translation))
				'font-lock-face 'link
				'heading 'h3
				'lemma-nr lemma-nr
				'action 'lookup
				'lemma lemma-word
				'lang lang
				'keymap diogenes-perseus-action-map
				'rear-nonsticky t)
		    " "
		    (propertize "[Attested Forms]"
				'font-lock-face 'warning
				'action 'forms
				'lemma lemma-word
				'lang lang
				'keymap diogenes-perseus-action-map
				'rear-nonsticky t)
		    "\n\n"
		    (cl-loop for (headword . analysis) in entries
			     concat (propertize
				     (format "%-20s → %s\n"
					     (diogenes--perseus-ensure-utf8 headword
									    lang)
					     analysis)
				     'h3 t))
		    "\n"))))

(defun diogenes--parse-and-show (query lang &optional filter ignore-case no-diacritics)
  "Display all possible morphological analyses for query, with FILTER applied.
 Dispatcher function. IGNORE-CASE and NO-DIACRITICS should be either t or 'ignore;
if nil, query interactively for their values"
  (seq-let (filter ignore-case no-diacritics)
      (diogenes--parse-and-show-choose-filter filter ignore-case no-diacritics)
    (let ((results (diogenes--parse-all query lang filter ignore-case no-diacritics)))
      (unless results (error "No results for %s!" query))
      (diogenes--add-parse-entry)
      (insert (propertize (format "Results for %s:\n" query)
			  'font-lock-face 'shr-h1
			  'heading 'h1))
      (insert (propertize (format "(%s, %s, %s)\n\n"
				  (if (eq filter #'string-equal)
				      "No filter"
				    (format "filtered by %s" filter))
				  (if ignore-case "ignoring case"
				    "case sensitive")
				  (if no-diacritics "ignoring diacritics"
				    "diacritics sensitive"))
			  'font-lock-face 'italic
			  'h1 t))
      (cl-loop for (headword . analyses) in results
	       do (insert
		   (propertize (format "Form %s:\n\n"
				       (if (string= lang "greek")
					   (diogenes--perseus-beta-to-utf8 headword)
					 headword))
			       'font-lock-face 'success
			       'h1 t
			       'heading 'h2))
	       do (insert
		   (propertize (diogenes--format-parse-results headword lang analyses)
			       'h1 t
			       'h2 t))))))


;;; Show all attested forms of lemma
(defun diogenes--format-lemma-and-forms (lemma lang)
  "Format a LEMMA entry as returned by `diogenes--get-all-forms'."
  (concat (propertize (car lemma)
		      'font-lock-face 'shr-h2
		      'heading 'h2
		      'action 'lookup
		      'lemma (cadr lemma)
		      'lang lang
		      'lemma-nr (caddr lemma)
		      'keymap diogenes-perseus-action-map
		      'rear-nonsticky t)
	  " \n"
	  (cl-loop
	   for (form . analyses) in (cdddr lemma)
	   concat (propertize
		   (concat (format "%-20s " form)
			   (propertize (car analyses)
				       'font-lock-face 'italic)
			   "\n"
			   (cl-loop
			    for a in (cdr analyses)
			    concat (concat (make-string 21 ? )
					   (propertize a
						       'font-lock-face 'italic)
					   "\n")))
		   'h2 t))
	  "\n"))

(defun diogenes--show-all-forms (lemma lang)
  "Show all attested forms of LEMMA in LANG."
  (let ((results (diogenes--get-all-forms lemma lang)))
    (unless results (error "No result for %s in %s" lemma lang))
    (pop-to-buffer (get-buffer-create "*Diogenes Forms*"))
    (diogenes-analysis-mode)
    (goto-char (point-max))
    (save-excursion
      (mapc (lambda (x)
	      (insert (diogenes--format-lemma-and-forms x lang)))
	    (sort results (lambda (a b)
		     (diogenes--sort-alphabetically-no-diacritics (car a)
								  (car b))))))
    t))

;;; Show all lemmata that match query
(defun diogenes--show-all-lemmata (query lang &optional filter ignore-case no-diacritics)
  "Show all lemmata that match QUERY in lang, with FILTER applied.
IGNORE-CASE and NO-DIACRITICS should be either t or 'ignore;
if nil, query interactively for their values"
 (seq-let (filter ignore-case no-diacritics)
      (diogenes--parse-and-show-choose-filter filter ignore-case no-diacritics)
   (let ((results (diogenes--query-all-lemmata query lang filter ignore-case no-diacritics)))
     (unless results (error "No results for lemma %s!" query))
     (pop-to-buffer (get-buffer-create "*Diogenes Forms*"))
     (diogenes-analysis-mode)
     (goto-char (point-max))
     (insert (propertize (format "Results for %s:\n" query)
			 'font-lock-face 'shr-h1
			 'heading 'shr-h1))
     (insert (propertize (format "(%s, %s, %s)\n\n"
				 (if (eq filter #'string-equal)
				     "No filter"
				   (format "filtered by %s" filter))
				 (if ignore-case "ignoring case"
				   "case sensitive")
				 (if no-diacritics "ignoring diacritics"
				   "diacritics sensitive"))
			 'font-lock-face 'italic
			 'h1 t))
     (save-excursion
       (mapc (lambda (x)
	       (insert (diogenes--format-lemma-and-forms x lang)))
	     (sort results
		   (lambda (a b)
		     (diogenes--sort-alphabetically-no-diacritics (car a)
								  (car b)))))))))


;;; Callback function
(defun diogenes-perseus-action (char)
  "Callback for the links in Diogenes Lookup and Analysis Mode."
  (interactive "d")
  (let ((action (get-text-property char 'action)))
    (cl-case action
      (bibl (apply #'diogenes--browse-work (diogenes--lookup-parse-bibl-string
					    (get-text-property char 'bibl))))
      (old (diogenes-lookup-open-old (get-text-property char 'headword)))
      (tll (diogenes-lookup-open-tll (get-text-property char 'headword)))
      (montanari (diogenes-lookup-open-montanari (get-text-property char 'headword)))
      (cambridge (diogenes-lookup-open-cambridge (get-text-property char 'headword)))
      (bdag (diogenes-lookup-open-bdag (get-text-property char 'headword)))
      (passow (diogenes-lookup-open-passow (get-text-property char 'headword)))
      (tgl (diogenes-lookup-open-tgl (get-text-property char 'headword)))
      (lookup (diogenes--lookup-dict (get-text-property char 'lemma)
				     (get-text-property char 'lang)))
      (forms (diogenes--show-all-forms (get-text-property char 'lemma)
				       (get-text-property char 'lang)))
      (t (let* ((prop-lang (get-text-property char 'lang))
		(buf-lang (and (boundp 'diogenes--lookup-lang)
			       diogenes--lookup-lang))
		;; The text-property language is only useful when it is
		;; actually a lookup language.  In a Latin (Lewis & Short)
		;; entry the definition prose is tagged "english", so a
		;; Latin word under point carries lang="english" -- not
		;; nil -- which is why keying on the property alone failed.
		;; Treat only "greek"/"latin" as usable, and otherwise fall
		;; back to the language of the entry we are reading.
		(lang (if (member prop-lang '("greek" "latin"))
			  prop-lang
			buf-lang)))
	   (pcase lang
	     ((or "greek" "latin")
	      ;; Looking up a word opens its dictionary entry.  When we are
	      ;; already in a lookup buffer, offer to show it in THIS window
	      ;; (staying put) rather than popping open another one; either
	      ;; way the entry we came from stays alive.  The choice only
	      ;; matters when there is another window to pop into -- with a
	      ;; single window there is nowhere else to go, so default to
	      ;; reusing it without asking.
	      (let ((diogenes--lookup-same-window
		     (and (derived-mode-p 'diogenes-lookup-mode)
			  (or (= (count-windows) 1)
			      (y-or-n-p "Open the result in this same window? ")))))
		(diogenes--parse-and-lookup (thing-at-point 'word) lang)))
	     (_ (message "C-c C-c cannot do anything useful here!"))))))))

(defun diogenes-lookup-open-tll-or-tgl ()
  "Open the print thesaurus appropriate to the current entry's language.
For a Latin entry this opens the TLL (Thesaurus Linguae Latinae); for
a Greek entry, Estienne's TGL (Thesaurus Graecae Linguae).  Bound to
\\`t' in `diogenes-lookup-mode', it dispatches on the buffer-local
`diogenes--lookup-lang' so the same key serves both languages.  A
prefix argument is passed through to the underlying opener (which then
prompts for a word).  If the language is unknown, it defaults to the
TLL, the historical binding of this key."
  (interactive)
  (let ((lang (and (boundp 'diogenes--lookup-lang) diogenes--lookup-lang)))
    (pcase lang
      ("greek" (call-interactively #'diogenes-lookup-open-tgl))
      (_       (call-interactively #'diogenes-lookup-open-tll)))))



(provide 'diogenes-perseus)

;;; diogenes-perseus.el ends here
