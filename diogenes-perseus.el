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

;; Called across files that cannot be required from here without a
;; cycle, and -- where the name is one of this package's own caches --
;; defined inside a `let', which the compiler does not count as a
;; definition at all.
(declare-function diogenes-browser--word-at-point-joined "diogenes-browser" ())
(defvar diogenes-browser-join-broken-words)
(declare-function diogenes--browse-work "diogenes-browser" (options passage))
(declare-function diogenes--perseus-path "diogenes-perl-interface" (&rest parts))
(declare-function diogenes--dict-file "diogenes-perl-interface" (lang))
(declare-function diogenes--get-all-analyses "diogenes-perseus" (query &rest args))
(declare-function diogenes--get-all-lemmata "diogenes-perseus" (query &rest args))
(declare-function diogenes--get-analyses-index "diogenes-perseus" (lang))
(declare-function diogenes--all-matches-in-hashtable "diogenes-perseus" (query hash filter ignore-case no-diacritics))
(declare-function diogenes--lookup-insert-xml "diogenes-perseus" (xml start end buffer))

(declare-function rng-first-error "rng-valid" ())
(declare-function diogenes-perseus-action nil)
(declare-function diogenes-lookup-open-old "diogenes-old" (&optional word))
(declare-function diogenes-lookup-open-tll "diogenes-tll" (&optional word))
(declare-function diogenes-lookup-open-montanari "diogenes-montanari" (&optional word))
(declare-function diogenes-lookup-open-cambridge "diogenes-cambridge" (&optional word))
(declare-function diogenes-lookup-open-bailly "diogenes-bailly" (&optional word))
(declare-function diogenes-lookup-gaffiot "diogenes-gaffiot" (&optional word))
(declare-function diogenes-gaffiot-lookup-buffer-p "diogenes-gaffiot" ())
(declare-function diogenes-lookup-open-gaffiot-pdf "diogenes-gaffiot-pdf"
                  (&optional word))
(declare-function diogenes-lookup-open-bdag "diogenes-bdag" (&optional word))
(declare-function diogenes-lookup-open-passow "diogenes-passow" (&optional word))
(declare-function diogenes-lookup-open-tgl "diogenes-tgl" (&optional word))
(declare-function diogenes-lookup-pape "diogenes-pape" (&optional word))
(declare-function diogenes-lookup-lsj "diogenes-pape" (&optional word))
(declare-function diogenes-pape-lookup-buffer-p "diogenes-pape" ())

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

;; C, i.e. raw byte order
(defun diogenes--c-sort-function (a b)
  "Compare A and B as `LC_ALL=C sort' ordered them: by character code.
The comparator a binary search is given must agree with the order of the
file it walks, and for the analyses and lemmata files that order is over
the RAW beta-code keys, in which `)', `(' and `/' precede every letter:

    o)mi/xlh   o)mi/xlhn   o)mi/xlhs   o)mi/xlh|   o)mi/xlh|sin

`diogenes--ascii-sort-function' cannot be used on them, because it
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

(defcustom diogenes-latin-fold-letters '((?j . ?i))
  "Initial letters folded together when searching the Latin dictionary.
An alist of (FROM . TO) characters, applied to the FIRST letter of both the
search word and the dictionary key before they are compared.

The Lewis & Short that comes with Diogenes is ordered two ways at once,
depending on where the j falls.  An initial J is interleaved with I --

  I, J, Jabolenus, Iacchus, jacea, jaceo, Jacetani, ja^ci^o

which is alphabetical only if j counts as i -- while an internal j sorts
after i, as it does in print:

  abitus, abjecte, ... circumitus, circumjaceo, ... deitas, dejecte

so folding everywhere trades one set of inversions for another (measured on
the shipped file: 126 with no folding, 129 folding throughout, and fewest
folding the initial letter alone).  Hence the fold applies only to the
first letter.

The u/v distinction is NOT folded: this dictionary keeps separate U and V
sections.  Set this to nil to compare keys literally, as Diogenes\\=' own
`$do_lookup\\=' does -- at the cost of `iacio\\=' landing between the letter
articles and `jacio\\=' overshooting its whole block."
  :type '(alist :key-type character :value-type character)
  :group 'diogenes)

(defun diogenes--latin-fold-key (str)
  "Reduce STR to the letters the Latin dictionary is ordered by.
ASCII letters only, downcased, with `diogenes-latin-fold-letters' applied
to the initial letter."
  (let ((key (downcase (diogenes--ascii-alpha-only str))))
    (if (or (null diogenes-latin-fold-letters)
	    (zerop (length key)))
	key
      (let ((folded (cdr (assq (aref key 0) diogenes-latin-fold-letters))))
	(if folded
	    (concat (string folded) (substring key 1))
	  key)))))

(defun diogenes--latin-sort-function (a b)
  "Compare two Lewis & Short keys as the dictionary itself orders them.
`diogenes--ascii-sort-function' with `diogenes-latin-fold-letters' applied
to both sides; see that variable for why the Latin dictionary needs it."
  (let ((word-a (diogenes--latin-fold-key a))
	(word-b (diogenes--latin-fold-key b)))
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
    (diogenes--display-buffer (current-buffer))
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
    (diogenes--display-buffer xml-buffer)
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
		  ;; Back to the entry being edited, which is where we were.
		  (diogenes--display-buffer lookup-buffer
					    :kind 'lookup :same-window t)
		  (delete-region prop-start prop-end)
		  (diogenes--lookup-insert-and-format parsed))
	  (t (rng-first-error)))))



(defcustom diogenes-lookup-show-all-entries t
  "Whether a parse shows every dictionary entry it found.
Non-nil reproduces the Diogenes application: all distinct entries named in
the analyses record are shown one after another in a single lookup buffer.
When nil, the lemmata are offered through `completing-read' and only the
chosen one is shown, though still fetched by offset rather than by a
headword search."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-lookup-show-analysis t
  "Whether to head a parsed lookup with its morphological analysis.
Non-nil reproduces the application, which prints \"Perseus analysis of X\"
and the lemmata above the dictionary entries."
  :type 'boolean
  :group 'diogenes)

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

(defun diogenes--search-dict (word lang sort-fn key-fn &optional file)
  "Search for a word in a Diogenes dictionary.
The lines in dictionary file must be sorted according to SORT-FN,
while KEY-FN must return the key.

FILE names the dictionary to search, defaulting to LANG\'s own
\(`diogenes--dict-file\').  Another dictionary of the same language may be
passed instead -- `diogenes-gaffiot.el\' passes Gaffiot for Latin -- and
LANG then still says which language the ENTRIES are in, so `C-c C-c\',
the print-dictionary banner and the rest behave as they do for the LSJ
and Lewis & Short.

NB. This finds an entry by where its key SORTS, so it is only as good as
the file\'s order.  The Lewis & Short that comes with Diogenes is ordered
by the i-spelling of its headwords while the `key\' attributes retain the
j-spelling (the entry displayed as `iacio\' has key=\"ja^ci^o\"), so no
j-lemma can be reached this way.  This is `$do_lookup\' in Perseus.pm and
it has the same flaw there; the parse path avoids it by using the byte
offset recorded in the analyses file -- see
`diogenes--lookup-dict-offset\'."
  (seq-let (xml-bytes start end exact-hit)
      (diogenes--binary-search (or file (diogenes--dict-file lang))
			       sort-fn key-fn word)
    (unless exact-hit (message "No results for %s! Showing nearest entry" word))
    (diogenes--show-dict-entry xml-bytes start end lang file)))

(defun diogenes--dict-offset (nr)
  "Return NR as a usable dictionary offset, or nil.
NR is the first field of an analyses entry or the second of a lemmata
entry -- a byte offset into the dictionary, as a number or a string.  Zero
is make_latin_lemmata.pl\'s \"no entry\" marker rather than an offset, so it
counts as nil."
  (let ((n (cond ((integerp nr) nr)
		 ((and (stringp nr)
		       (string-match-p "\\`[[:space:]]*[0-9]+[[:space:]]*\\'"
				       nr))
		  (string-to-number nr)))))
    (and n (> n 0) n)))

(defun diogenes--lookup-dict-offset (offset lang &optional file)
  "Show the dictionary entry that begins OFFSET bytes into the dictionary.
This is how Diogenes itself reaches an entry after a parse: the offset
comes from the analyses or the lemmata file, so the entry is the one the
morphological data was built against, with no headword to get wrong.
LANG is the language of the entry; FILE defaults to LANG\'s own
dictionary."
  (let ((dict (or file (diogenes--dict-file lang))))
    (seq-let (xml-bytes start end) (diogenes--get-dict-line dict offset)
      (unless xml-bytes
	(error "No dictionary entry at offset %d of %s" offset dict))
      (diogenes--show-dict-entry xml-bytes start end lang file))))

(defun diogenes--show-dict-entry (xml-bytes start end lang &optional file)
  "Show the dictionary entry in XML-BYTES in a fresh lookup buffer.
START and END are its offsets in the dictionary file, as returned by
`diogenes--binary-search\' or `diogenes--get-dict-line\'; they are what
`diogenes-lookup-next\' and `-previous\' walk from.  LANG says which
language the ENTRY is in, FILE which dictionary it came from.

Returns the lookup buffer."
    (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	   (lookup-buffer (diogenes--get-fresh-buffer "lookup"))
	   formatted)
      ;; A fresh buffer either way (the previous entry is never destroyed);
      ;; `diogenes--lookup-same-window' only chooses WHERE to show it -- in
      ;; the calling window, or (default) via the usual `pop-to-buffer'.
      ;;
      ;; The gate is whether the optional `diogenes-purpose' module is loaded
      ;; -- NOT whether `purpose-mode' is on.  Spacemacs turns `purpose-mode'
      ;; on for everyone, so keying on that would always fire; the real
      ;; question is whether the user has opted in to giving the Diogenes
      ;; buffers their own window-purposes by loading `diogenes-purpose'.
      ;;
      ;; * `diogenes-purpose' LOADED: set the major mode BEFORE displaying, so
      ;;   purpose (whose action runs at display time and dispatches on the
      ;;   major mode) classifies the buffer as a lookup and gives it the
      ;;   lookup window instead of the browser/edit window.
      ;;
      ;; * `diogenes-purpose' NOT loaded: run the ORIGINAL sequence verbatim --
      ;;   display first, then set the mode.  This is exactly the pre-existing
      ;;   behaviour (reuse an existing window or open a new one from the
      ;;   browser; show in place on a single-window frame), and it holds
      ;;   whether or not `purpose-mode' happens to be on and whether or not
      ;;   `pop-up-frames' is set.
      ;;
      ;; In both, `diogenes-lookup-mode' derives from `text-mode' and runs
      ;; `kill-all-local-variables', so the buffer-locals are assigned after.
      ;; And in either case: a frame showing only a startup page is a frame
      ;; with nothing in it, so the entry takes that window rather than
      ;; splitting it or opening a frame beside it.  `diogenes-purpose' had
      ;; this carve-out for the Spacemacs home buffer alone; it belongs here,
      ;; where it holds for Doom's dashboard and Emacs's own splash too, and
      ;; whether or not either display module is loaded.  See
      ;; `diogenes--sole-home-window-p'.
      (let ((diogenes--lookup-same-window
             (or diogenes--lookup-same-window
                 (diogenes--sole-home-window-p))))
        ;; `purpose-mode', not `(featurep 'diogenes-purpose)': our own module
        ;; is required from `diogenes.el' and so always present, where the
        ;; question is whether window-purpose is running and will classify
        ;; this buffer as it is displayed.
        (if (bound-and-true-p purpose-mode)
            ;; --- window-purpose running: mode before display ---
            (progn
              (with-current-buffer lookup-buffer
                (diogenes-lookup-mode))
              (diogenes--display-buffer lookup-buffer
                                        :kind 'lookup
                                        :same-window
                                        diogenes--lookup-same-window))
          ;; --- otherwise: the original order, unchanged ---
          (diogenes--display-buffer lookup-buffer
                                    :kind 'lookup
                                    :same-window diogenes--lookup-same-window)
          (diogenes-lookup-mode)))
      (setq diogenes--lookup-file (or file (diogenes--dict-file lang))
	    diogenes--lookup-bufstart start
	    diogenes--lookup-bufend end
	    diogenes--lookup-lang lang)
      ;; Paint the window BEFORE parsing.  `diogenes--dict-parse-xml' runs
      ;; `xml-parse-region', which is Lisp, over the whole of the entry --
      ;; and an entry can be large: Georges gives 26 KB to `a' as a
      ;; preposition alone.  Emacs is single-threaded, so nothing is redrawn
      ;; while that runs, and on Wayland (`pgtk') a frame that has not been
      ;; redrawn is not merely stale but blank: the frame the reader was
      ;; looking at goes black for as long as the parse takes.  Showing
      ;; something first, and forcing it onto the screen, leaves the
      ;; compositor a painted surface to hold on to.
      (let ((inhibit-read-only t))
	(erase-buffer)
	(insert (propertize "Looking up ...\n" 'font-lock-face 'italic)))
      (redisplay t)
      (setq formatted (diogenes--dict-parse-xml xml start end))
      (let ((inhibit-read-only t))
	(erase-buffer))
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
	(diogenes--lookup-insert-entry-links lang))
      ;; So that navigation can tell which entry point is in, once more
      ;; than one is on show.
      (diogenes--lookup-mark-entry (point-min) (point-max) start end)
      lookup-buffer))

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

(defface diogenes-lookup-link-key
  '((((background light)) :foreground "#a0522d" :weight bold :underline nil
     :inherit nil)
    (((background dark)) :foreground "#f0c674" :weight bold :underline nil
     :inherit nil)
    (t :weight bold :underline nil :inherit nil))
  "Face for the key hint inside a print-dictionary link, the \"t\" of \"[TLL (t)]\".
Deliberately NOT a blue: the link around it is already coloured, and a hint
in a neighbouring shade of the same colour is no hint at all.  A warm
foreground, bold, and no underline set it apart from the link whatever the
theme does with links themselves -- sienna on a light background, a soft
amber on a dark one.

To suit it to your own theme:

  M-x customize-face RET diogenes-lookup-link-key RET

or, in your init file,

  (set-face-attribute \\='diogenes-lookup-link-key nil
                      :foreground \"orange red\" :weight \\='bold)"
  :group 'diogenes)

(defun diogenes--lookup-dict-link (name key action headword help)
  "Return a clickable link reading \"[NAME (KEY)]\" for HEADWORD.
ACTION is the symbol `diogenes-perseus-action' dispatches on, HELP a format
string taking the headword, and KEY the key bound to the same command --
shown in parentheses, in `diogenes-lookup-link-key', so the binding can be
read off the entry instead of looked up.  KEY may be nil for a link with no
key of its own."
  (let* ((label (if key (format "[%s (%s)]" name key) (format "[%s]" name)))
         (link (propertize label
                           'font-lock-face 'link
                           'keymap diogenes-perseus-action-map
                           'action action
                           'headword headword
                           'help-echo (format help headword)
                           'rear-nonsticky t)))
    (when key
      ;; The key sits between "(" and ")]", i.e. two characters from the end.
      (put-text-property (- (length label) 2 (length key))
                         (- (length label) 2)
                         'font-lock-face 'diogenes-lookup-link-key
                         link))
    link))

(defvar diogenes--lookup-dictionaries nil
  "Every dictionary that may appear in an entry's link banner.
A list of plists, one per dictionary, in the order they are offered.  Built
by `diogenes-lookup-register-dictionary', which is how a dictionary module
announces itself: adding a dictionary to Diogenes takes no edit to this
file, and a dictionary whose module is not loaded is simply not registered
and not offered.

Before this existed, three separate places here had to be taught about
each new dictionary -- the two link lists, the per-entry choice among them,
and the action dispatch that ran a link.  A module that forgot one of the
three failed in a different way each time.")

(defcustom diogenes-declared-dictionaries nil
  "Dictionaries you use, named by id, whatever their paths say.
A list of symbols: `old', `tll', `montanari', `cambridge', `bdag',
`passow', `tgl', `gaffiot', `gaffiot-pdf', `georges', `georges-pdf',
`pape', `dge', `bailly', `bailly-pdf'.  Order does not matter -- this is a
set, tested with `memq'.

A declared dictionary is offered on every entry of its language, and its
key and its link explain what to set when pressed with nothing configured.
An undeclared one is offered when its paths are set, which is what makes
an installation that declares nothing behave sensibly: configure a
dictionary and it appears.

    (setq diogenes-declared-dictionaries \\='(old tll bailly tgl))

Loading a module yourself declares it too -- `(require \\='diogenes-tll)'
before `diogenes.el' loads -- and saying it both ways is harmless.  See
`diogenes--loading-bundle' for why the load-order proviso, and
\\[diogenes-list-dictionaries] to see which dictionaries are declared, by
which route, and what their paths are doing."
  :type '(repeat symbol)
  :group 'diogenes)

(defcustom diogenes-lookup-keys
  '((diogenes-perseus-action        . "RET")
    (diogenes-perseus-action        . "C-c C-c")
    (diogenes-lookup-in-dictionary  . "C-c C-o")
    (diogenes-lookup-next           . "C-c C-n")
    (diogenes-lookup-previous       . "C-c C-p")
    (diogenes-lookup-open-tll-or-tgl . "t")
    (diogenes-lookup-lewis          . "l")
    (diogenes--quit                 . "q"))
  "The keys of a lookup buffer, as (COMMAND . KEY).
Every key the lookup buffer binds for itself is here, so that any of them can
be moved or removed -- nil for a KEY binds nothing.  A command may appear
twice, `diogenes-perseus-action\=' being on `RET\=' and `C-c C-c\=' both.

The dictionary letters are NOT here: they belong to the dictionaries, which
come and go with the modules that provide them, and
`diogenes-lookup-dictionary-keys\=' answers for those.  `t\=' and `l\=' are here
because they dispatch between two dictionaries rather than naming one.

Consulted when the map is built, so set it before the package loads -- in
`:init\=' with `use-package\=', or in a preset."
  :type '(alist :key-type function
                :value-type (choice key-sequence (const :tag "Unbound" nil)))
  :group 'diogenes)

(defcustom diogenes-lookup-dictionary-keys nil
  "Keys for the dictionaries in a lookup buffer, overriding their defaults.
An alist of (ID . KEY), where ID is a dictionary\='s registered identifier --
`old\=', `tll\=', `gaffiot\=', `georges\=', `montanari\=', `cambridge\=', `bdag\=',
`passow\=', `tgl\=', `bailly\=', `pape\=', `dge\=', `lewis\=' -- and KEY a key
description, or nil to bind nothing at all:

    (setq diogenes-lookup-dictionary-keys
          \='((old . \"O\") (gaffiot . \"F\") (bdag . nil)))

The letters the package chooses are opinionated and finite, and a reader who
consults the Gaffiot constantly and the BDAG never has better uses for `g\=' and
`b\='.  Nil frees a letter for something of your own.

The BANNER reads this too, so `[OLD (O)]\=' says what the key now is.  A
rebinding the banner did not know about would be worse than none: the offer
printed under an entry is the package telling the reader what to press."
  :type '(alist :key-type symbol
                :value-type (choice key-sequence (const :tag "Unbound" nil)))
  :group 'diogenes)

(defun diogenes--lookup-dictionary-key (id default)
  "The key for dictionary ID: what the reader asked for, or DEFAULT.
Returns nil where the reader asked for nil, which means bind nothing -- so a
caller must distinguish `no preference\=' from `no key\=', and consult
`diogenes-lookup-dictionary-keys\=' with `assq\=' rather than reading its cdr."
  (let ((cell (assq id diogenes-lookup-dictionary-keys)))
    (if cell (cdr cell) default)))

(cl-defun diogenes-lookup-register-dictionary
    (id &key name lang key command help (show 'always) buffer-p of
             available-p (order 50) bind declared paths)
  "Register the dictionary ID for the entry link banner.  Idempotent.
Registering an ID already present replaces it, so a module may be reloaded.

ID is the symbol the link carries as its `action' property and the symbol
`diogenes-perseus-action' dispatches on; keep it unique.  NAME is the label
shown in brackets, KEY the key bound to the same command -- shown after the
name, so the binding can be read off the entry -- and HELP a format string
taking the headword, for the echo area.  LANG is \"greek\" or \"latin\": the
language of entry the dictionary is offered on.  COMMAND is called with the
headword as its only argument.

SHOW says when the dictionary appears, and is the whole of the arrangement
the banner used to spell out by hand:

  `always'         -- a print dictionary: offered on every entry of its
                     language, so long as AVAILABLE-P says this user has
                     it.
  `unless-current' -- an electronic dictionary: offered except in its own
                     lookup buffer, where the link would lead nowhere.
                     Needs BUFFER-P, a predicate that is non-nil when the
                     current buffer is showing this dictionary.  The way
                     back to a language's own dictionary -- the LSJ, Lewis
                     & Short -- is this with `diogenes--lookup-own-dictionary-p'.
  `when-current'   -- offered ONLY inside another dictionary's buffer,
                     named by OF.  This is how a printed companion to an
                     electronic dictionary is reached: Gaffiot's PDF from a
                     Gaffiot entry, Bailly's from a Bailly entry.

AVAILABLE-P, if given, is called with no arguments and must return non-nil
for the dictionary to be offered at all.  This is how a dictionary is
optional: every one of them but the LSJ and Lewis & Short passes a
predicate over its own path options, so a dictionary the user has not got
is silently absent from the banner instead of being offered and then
refusing.  The predicate is asked afresh each time an entry is drawn, so
setting a path -- or building an XML -- takes effect at once, with no
reload; it must therefore be cheap, and it must neither signal nor prompt.
`diogenes--path-usable-p' is the usual way to write one.

A dictionary with both an XML and a printed edition, such as Gaffiot,
Bailly and Georges, is available when EITHER is: its command dispatches on
which, so the one link leads to whichever the user actually has.  Its PDF
companion, registered separately with `when-current', carries the
PDF-only predicate, so the \"[PDF]\" link appears inside the entry only
when there is a PDF behind it.

DECLARED says the user asked for this dictionary by loading its module,
rather than receiving it with the bundle `diogenes.el' loads; a module
computes it at load time with `diogenes--declared-at-load-p'.  A declared
dictionary is offered whatever its paths say, AVAILABLE-P not being
consulted, so that a dictionary you use but have misconfigured explains
itself instead of disappearing.  `diogenes-declared-dictionaries' declares
one the other way, by id; either is enough and both together are harmless.

PATHS is the list of option symbols this dictionary reads -- purely so
\\[diogenes-list-dictionaries] can report on them.

ORDER sorts the banner, low to high; the shipped dictionaries leave gaps to
sort between.  BIND, if non-nil, binds KEY to COMMAND in
`diogenes-lookup-mode-map'.  A key that must serve both languages cannot be
bound this way -- it needs a command that dispatches on
`diogenes--lookup-lang', as `diogenes-lookup-pape-or-gaffiot-pdf' does --
so such modules leave BIND nil and bind the key themselves."
  (let ((entry (list :id id :name name :lang lang :key key
                     :command command :help help :show show
                     :buffer-p buffer-p :of of
                     :available-p available-p :order order
                     :bind bind :declared declared :paths paths)))
    (setq diogenes--lookup-dictionaries
          (append (cl-remove id diogenes--lookup-dictionaries
                             :key (lambda (e) (plist-get e :id)))
                  (list entry)))
    ;; Through the installer rather than by binding here, so that a key two
    ;; dictionaries want gets the command that chooses between them.  Binding
    ;; directly would have given it to whichever registered last.
    (when (and bind command (boundp 'diogenes-lookup-mode-map))
      (diogenes--lookup-install-registered-keys))
    id))

(defun diogenes--lookup-dictionary (id)
  "Return the registration plist of dictionary ID, or nil."
  (cl-find id diogenes--lookup-dictionaries
           :key (lambda (e) (plist-get e :id))))

(defun diogenes--lookup-install-registered-keys ()
  "Bind the keys of dictionaries registered with a non-nil BIND.
Called once `diogenes-lookup-mode-map' exists, for modules that registered
before it did; `diogenes-lookup-register-dictionary' binds directly when it
can.  Re-registering is idempotent, so doing both is harmless."
  (let ((by-key nil))
    ;; Gather what wants each key, so that a key wanted by two dictionaries can
    ;; be given a command that chooses between them.
    (dolist (entry diogenes--lookup-dictionaries)
      (let* ((id (plist-get entry :id))
             (command (plist-get entry :command))
             (key (diogenes--lookup-dictionary-key id (plist-get entry :key))))
        (when (and (plist-get entry :bind) key command)
          (let ((cell (assoc key by-key)))
            (if cell
                (setcdr cell (append (cdr cell) (list entry)))
              (push (cons key (list entry)) by-key))))))
    (dolist (cell by-key)
      (let ((key (car cell))
            (entries (cdr cell)))
        (keymap-set diogenes-lookup-mode-map key
                    (if (cdr entries)
                        (diogenes--lookup-key-dispatcher entries)
                      (plist-get (car entries) :command)))))))

(defun diogenes--lookup-key-dispatcher (entries)
  "A command opening whichever of ENTRIES matches the language being read.
Two dictionaries may want one key, and where they are of different languages
there is no conflict to resolve: `t\=' is the TLL in a Latin entry and the TGL
in a Greek one, and a reader who puts Gaffiot and Bailly both on `g\=' means the
same thing -- the French dictionary of whichever language is in front of them.

The buffer says which language it holds, so the choice needs no prompt.  Where
none of ENTRIES is of that language the first is used, which is what a reader
asking for a dictionary of the other language can only have meant."
  (lambda ()
    (interactive)
    (let* ((lang (or (and (boundp 'diogenes--lookup-lang) diogenes--lookup-lang)
                     "latin"))
           (match (or (cl-find lang entries
                               :key (lambda (e) (plist-get e :lang))
                               :test #'equal)
                      (car entries))))
      (call-interactively (plist-get match :command)))))

;;;###autoload
(defun diogenes-lookup-install-dictionary-keys ()
  "Apply `diogenes-lookup-dictionary-keys\=' to the lookup buffers.
Called for its effect after changing that option in a running Emacs; the
keys are installed at load time without it."
  (interactive)
  (when (boundp 'diogenes-lookup-mode-map)
    (diogenes--lookup-install-registered-keys)
    (when (called-interactively-p 'interactive)
      (message "Diogenes: dictionary keys installed"))))

(defun diogenes--lookup-dict-in-buffer-p (id)
  "Non-nil if the current lookup buffer is showing dictionary ID.
Asks that dictionary's own BUFFER-P predicate, which knows how to
recognise itself -- usually by comparing `diogenes--lookup-file' with the
dictionary it converted."
  (let* ((entry (diogenes--lookup-dictionary id))
         (predicate (and entry (plist-get entry :buffer-p))))
    (and predicate (funcall predicate) t)))

(defun diogenes--lookup-dict-available-p (predicate)
  "Non-nil if the dictionary guarded by PREDICATE is installed here.
PREDICATE is a registration's AVAILABLE-P: nil for a dictionary that needs
no configuration -- the LSJ and Lewis & Short, which come with Diogenes
itself -- and otherwise a function of no arguments that answers whether
this user has the dictionary.

Three ways of not having it are all one answer here:

  the option is unset, so the predicate returns nil;
  the module is not loaded, so the predicate is not even defined;
  the predicate signals, `diogenes-path' itself not being set yet.

None of them is an error to report from inside a redisplay, so all three
mean the same thing: leave that dictionary out of the banner.  The keys
remain bound, and pressing one still explains what to set -- see
`diogenes--require-path'."
  (cond
   ((null predicate) t)
   ((not (functionp predicate)) nil)
   (t (and (ignore-errors (funcall predicate)) t))))

(defun diogenes--lookup-dict-declared-p (entry)
  "Non-nil if the user has said ENTRY's dictionary is one they use.
Two ways of saying it, either sufficient and both together harmless:

  its id is in `diogenes-declared-dictionaries';
  its module was loaded by the user rather than by the bundle, which the
  module recorded at load time as DECLARED.

The first is a set, so the order it is written in means nothing.  The
second depends on load order -- see `diogenes--loading-bundle' -- which is
why the variable exists."
  (or (plist-get entry :declared)
      (and (memq (plist-get entry :id) diogenes-declared-dictionaries) t)))

(defun diogenes--lookup-dict-visible-p (entry)
  "Non-nil if ENTRY should be offered on the entry now on screen.
Declared first, configured second: a dictionary the user has said they use
is offered whatever its paths are doing, and one they have not is offered
when its paths are set.  Either way the SHOW rules then decide whether it
belongs on THIS entry -- see `diogenes-lookup-register-dictionary'."
  (and (or (diogenes--lookup-dict-declared-p entry)
           (diogenes--lookup-dict-available-p (plist-get entry :available-p)))
       (pcase (plist-get entry :show)
         ('always t)
         ('unless-current
          (let ((predicate (plist-get entry :buffer-p)))
            (not (and predicate (funcall predicate)))))
         ('when-current
          (diogenes--lookup-dict-in-buffer-p (plist-get entry :of)))
         (_ t))))

(defun diogenes--lookup-dict-specs (lang)
  "Return (NAME KEY ID HELP) for each dictionary offered on a LANG entry.
Sorted by the registrations' ORDER; `sort' is stable, so dictionaries
sharing an order keep the sequence they were registered in, which is the
order their modules were loaded."
  (let ((entries (seq-filter
                  (lambda (e)
                    (and (equal (plist-get e :lang) lang)
                         (diogenes--lookup-dict-visible-p e)))
                  diogenes--lookup-dictionaries)))
    (mapcar (lambda (e)
              ;; The key as it IS, not as it was registered: a reader who has
              ;; moved the OLD to `O' must be told `O', the banner being the
              ;; package saying what to press.
              (list (plist-get e :name)
                    (diogenes--lookup-dictionary-key (plist-get e :id)
                                                     (plist-get e :key))
                    (plist-get e :id) (plist-get e :help)))
            (sort entries (lambda (a b) (< (plist-get a :order)
                                           (plist-get b :order)))))))

(defun diogenes--lookup-register-shipped-dictionaries ()
  "Register the dictionaries that come with Diogenes itself.
That is now only Lewis & Short -- and, from `diogenes-pape.el', the LSJ --
the two dictionaries Diogenes searches by default and so the way back from
any other dictionary of their language.  They need no AVAILABLE-P: their
files ship with Diogenes, and if they are missing nothing in this package
works at all.

Every other dictionary registers itself from its own module, with an
AVAILABLE-P that reports whether this user has it: see
`diogenes-old.el', `diogenes-tll.el', `diogenes-montanari.el',
`diogenes-cambridge.el', `diogenes-bdag.el', `diogenes-passow.el',
`diogenes-tgl.el', `diogenes-gaffiot.el', `diogenes-georges.el',
`diogenes-pape.el', `diogenes-dge.el' and `diogenes-bailly.el'.  A
dictionary whose module is not loaded is not registered, and one whose
paths are unset is registered but not offered, so an installation with no
extra dictionaries at all draws no banner and never mentions a dictionary
it does not have."
  ;; Lewis & Short: the way back to the Latin dictionary Diogenes searches
  ;; by default, so offered in any Latin entry that is not itself one.
  (diogenes-lookup-register-dictionary
   'lewis :lang "latin" :name "Lewis & Short" :key "l" :order 70
   :command #'diogenes-lookup-lewis
   :show 'unless-current
   :buffer-p #'diogenes--lookup-own-dictionary-p
   :help "Show Lewis & Short's entry for \"%s\""))

(diogenes--lookup-register-shipped-dictionaries)


(defun diogenes--lookup-dict-declared-how (entry)
  "How ENTRY's dictionary came to be declared, as a short string."
  (let ((by-module (plist-get entry :declared))
        (by-list (memq (plist-get entry :id) diogenes-declared-dictionaries)))
    (cond ((and by-module by-list) "declared (require + list)")
          (by-module               "declared (require)")
          (by-list                 "declared (list)")
          (t                       "auto"))))

(defun diogenes--lookup-dict-path-report (entry)
  "What ENTRY's dictionary's own options are doing, as a list of strings.
One line per option: unset, set but not there, or set and readable.  The
middle case is the one worth seeing -- a moved volume or a mistyped path,
which shows the link and fails on being pressed."
  (let ((paths (plist-get entry :paths)))
    (if (null paths)
        (list "no paths (ships with Diogenes)")
      (mapcar
       (lambda (symbol)
         (let ((value (and (boundp symbol) (symbol-value symbol))))
           (cond
            ((not (diogenes--source-set-p value))
             (format "%s: unset" symbol))
            ((consp value)
             (format "%s: set (%d entries)" symbol (length value)))
            ((or (file-readable-p value) (file-directory-p value))
             (format "%s: %s" symbol (abbreviate-file-name value)))
            (t
             (format "%s: %s -- NOT FOUND" symbol
                     (abbreviate-file-name value))))))
       paths))))

;;;###autoload
(defun diogenes-list-dictionaries ()
  "Show every registered dictionary, how it is declared, and its paths.
The answer to \"is this dictionary going to appear, and if not why not\":
each is listed with its language, its key, whether it is declared -- by
`diogenes-declared-dictionaries', by having had its module loaded, or not
at all -- and what each of its own options currently holds.

A dictionary appears in an entry's link banner when it is declared, or when
its paths are set; `Offered' says which of those it manages, before the
per-entry rules about the dictionary you happen to be reading.  A module
that is not loaded at all is not here, having never registered."
  (interactive)
  (let ((entries (sort (copy-sequence diogenes--lookup-dictionaries)
                       (lambda (a b)
                         (let ((la (or (plist-get a :lang) ""))
                               (lb (or (plist-get b :lang) "")))
                           (if (string= la lb)
                               (< (plist-get a :order) (plist-get b :order))
                             (string< la lb)))))))
    (with-current-buffer (get-buffer-create "*Diogenes Dictionaries*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Diogenes dictionaries\n\n" 'face 'bold))
        (insert (format "diogenes-declared-dictionaries: %s\n\n"
                        (if diogenes-declared-dictionaries
                            (mapconcat #'symbol-name
                                       diogenes-declared-dictionaries " ")
                          "(empty -- every dictionary is path-detected)")))
        (dolist (entry entries)
          (insert (propertize (format "%s (%s)"
                                      (or (plist-get entry :name) "?")
                                      (plist-get entry :id))
                              'face 'bold))
          (insert (format "  %s" (or (plist-get entry :lang) "-")))
          (let ((key (diogenes--lookup-dictionary-key (plist-get entry :id)
                                                      (plist-get entry :key))))
            (cond (key (insert (format "  key %s" key)))
                  ((plist-get entry :key)
                   (insert (format "  key %s (unbound by you)"
                                   (plist-get entry :key))))))
          (insert "\n")
          (insert (format "  %s, %s\n"
                          (diogenes--lookup-dict-declared-how entry)
                          (if (diogenes--lookup-dict-visible-p entry)
                              "offered here"
                            "not offered")))
          (dolist (line (diogenes--lookup-dict-path-report entry))
            (insert (format "  %s\n" line)))
          (insert "\n"))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))


(defun diogenes--lookup-insert-dict-links (headword lang)
  "Insert clickable print-dictionary links for HEADWORD at point.
Each link reads \"[NAME (KEY)]\", the key being the one bound to the same
command in `diogenes-lookup-mode-map'.

Which dictionaries those are is not decided here: each is registered by its
own module through `diogenes-lookup-register-dictionary', and
`diogenes--lookup-dict-specs' picks the ones this entry should offer.  For
Latin that is normally [OLD], [TLL] and [Georges], then either [Gaffiot]
-- an entry in a lookup buffer, not a PDF -- or, when the entry shown IS
Gaffiot, [Lewis & Short] leading back and [PDF] for the same page in
print; for Greek [Montanari], [CGL], [BDAG], [Passow] and [TGL], then
whichever of [Pape], [Bailly] and [LSJ] is not on screen, and [PDF] inside
Bailly.

Clicking a link (or pressing RET on it) opens that dictionary at the page
holding HEADWORD.  The links are inserted AT POINT, so the caller positions
to the top of the entry they belong to; the initial lookup and each
`diogenes-lookup-next' / `-previous' step do this once per entry, so every
entry carries its own banner.

Only dictionaries this user actually has are listed: each registration's
AVAILABLE-P reads its own path options (`diogenes-old-pdf-file',
`diogenes-tll-pdf-directory', `diogenes-georges-directory',
`diogenes-georges-file', `diogenes-gaffiot-file',
`diogenes-gaffiot-pdf-file', `diogenes-montanari-pdf-file',
`diogenes-cambridge-pdf-file', `diogenes-bdag-pdf-file',
`diogenes-bailly-file', `diogenes-bailly-pdf-file',
`diogenes-passow-directory', `diogenes-tgl-directory',
`diogenes-pape-file', `diogenes-dge-file'), and an unset one drops out of
the banner rather than being offered and then refusing.  With none of them
set there are no links at all, and the whole banner -- newline included --
is omitted."
  (let ((inhibit-read-only t)
        (specs (diogenes--lookup-dict-specs lang)))
    (when specs
      (save-excursion
        (let ((links (mapcar (lambda (spec)
                               (seq-let (name key action help) spec
                                 (diogenes--lookup-dict-link name key action
                                                             headword help)))
                             specs))
              ;; Six Greek dictionaries do not fit one line at most widths, and
              ;; letting them run on wraps a link across two lines and pushes
              ;; the entry itself onto the end of the banner.  So break between
              ;; links, never inside one, and close with a newline of its own so
              ;; the headword always starts a line.
              (width (max 20 (or fill-column 70)))
              (column 0))
          (dolist (link links)
            (let ((len (string-width link)))
              (cond ((zerop column))               ; first link on a line
                    ((> (+ column 2 len) width)
                     (insert "\n")
                     (setq column 0))
                    (t (insert "  ")
                       (setq column (+ column 2))))
              (insert link)
              (setq column (+ column len))))
          (insert "\n"))))))

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
			 #'diogenes--latin-sort-function
			 #'diogenes--xml-key-fn))))

(defun diogenes--lookup-own-dictionary-p ()
  "Non-nil if this lookup buffer shows the language\'s own Diogenes dictionary.
That is the LSJ for Greek and Lewis & Short for Latin -- what
`diogenes--lookup-dict' searches -- as opposed to another dictionary shown
through the same machinery, such as Gaffiot.  Compared by file, since that
is what a lookup buffer records."
  (and (derived-mode-p 'diogenes-lookup-mode)
       (boundp 'diogenes--lookup-file) diogenes--lookup-file
       (boundp 'diogenes--lookup-lang) diogenes--lookup-lang
       (ignore-errors
         (string= (file-truename diogenes--lookup-file)
                  (file-truename (diogenes--dict-file diogenes--lookup-lang))))))

(defun diogenes--word-at-point-for-lookup ()
  "The word at point, where a word at point could be a word to look up.
Nil in a buffer whose text is not a text: a startup screen, whose words are
English prose about Emacs, and a document viewer, whose buffer holds the bytes
of a PDF and answers `%PDF\='.

`thing-at-point\=' has no opinion about where it is, so a lookup offered
`Welcome\=' or `%PDF\=' as its default -- and a reader who pressed RET at the
prompt got a lookup of that.  A default is a guess at what the reader means,
and in those buffers there is nothing to guess from."
  (unless (or (diogenes--home-buffer-p (buffer-name))
              (derived-mode-p 'pdf-view-mode 'doc-view-mode)
              (and (fboundp 'reader-mode) (derived-mode-p 'reader-mode)))
    (or
     ;; A word the text broke across two lines is one word, and looking up
     ;; either half finds nothing: no dictionary has `praeci' or `pitur'.  The
     ;; browser can tell, the citation being a text property it knows to skip,
     ;; so it is asked first.
     (and (derived-mode-p 'diogenes-browser-mode)
          (bound-and-true-p diogenes-browser-join-broken-words)
          (fboundp 'diogenes-browser--word-at-point-joined)
          (diogenes-browser--word-at-point-joined))
     (thing-at-point 'word t))))

(defun diogenes--lookup-current-headword ()
  "Return the headword of the entry point is in, for the lookup commands."
  (or (diogenes--lookup-headword-at-point)
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (diogenes--word-at-point-for-lookup)
      (user-error "No headword found at point")))

(defun diogenes--language-at-point (&optional pos)
  "The lookup language of the word at POS: \"greek\", \"latin\", or nil.
The rules `C-c C-c\=' goes by, factored out so that a second command need not
guess differently from the first.

The text-property language is only useful when it is actually a lookup
language.  In a Latin (Lewis & Short) entry the definition prose is tagged
\"english\", so a Latin word under point carries lang=\"english\" -- not nil
-- which is why keying on the property alone failed.  Only \"greek\" and
\"latin\" count; otherwise the language of the entry being read is used.

But not blindly.  Where the element says the text is neither Greek nor
Latin -- the German definitions of Pape, the English glosses of the LSJ --
falling back to a Greek entry\='s language would parse a word of prose as
Greek and answer with whatever sorts nearest.  A Greek lemma is written in
Greek letters, so Latin script under the cursor is prose and there is
nothing to look up.  Greek inside that prose is still recognised, tagged or
not.

In the browser there are no text properties to consult and no lookup
buffer: the language is the one the text is being read in.

Before any of that, the script is consulted.  A word written in Greek
letters is Greek whatever the markup says or fails to say -- and it often
fails to say: Gaffiot quotes his Greek untagged, so a Greek word in a
Gaffiot article would otherwise inherit the article\='s Latin and be parsed
as a Latin word that does not exist.  The same holds of the Greek in Lewis
& Short, in Georges, and of a Greek word a reader has typed into a buffer
of their own.  Script is the one piece of evidence that cannot be wrong
about this, so it is taken first."
  (let* ((pos (or pos (point)))
	 (prop-lang (get-text-property pos 'lang))
	 (buf-lang (or (and (boundp 'diogenes--lookup-lang)
			    diogenes--lookup-lang)
		       (and (boundp 'diogenes--browser-language)
			    diogenes--browser-language)))
	 (word (diogenes--word-at-point-for-lookup)))
    (cond
     ;; Greek letters mean Greek, tagged or not.
     ((and word (string-match-p "\\cg" word)) "greek")
     ((member prop-lang '("greek" "latin")) prop-lang)
     ((and prop-lang (equal buf-lang "greek")) nil)
     (t buf-lang))))

(defun diogenes--lookup-choosable-dictionaries (&optional lang)
  "The registered dictionaries a word can be looked up in, for completion.
Returns an alist of (LABEL . ENTRY).  With LANG, only that language\='s
dictionaries and the label is the name alone; without, every language\='s and
the label says which: \"Bailly (greek)\".

Only dictionaries with a `:command\=' and a `:buffer-p\=' are offered -- which
is what distinguishes an electronic dictionary, searchable by headword, from
a print one that can only be opened at a page.  `:show\=' is deliberately NOT
consulted: the point of choosing a dictionary by hand is to reach one the
banner is not offering, whether because the word is not in Lewis & Short at
all or because you are already inside the dictionary the banner would
suggest."
  (cl-loop for entry in diogenes--lookup-dictionaries
	   for name = (plist-get entry :name)
	   for entry-lang = (plist-get entry :lang)
	   when (and (plist-get entry :command)
		     (plist-get entry :buffer-p)
		     name entry-lang
		     (or (null lang) (equal lang entry-lang)))
	   collect (cons (if lang name (format "%s (%s)" name entry-lang))
			 entry)))

(defun diogenes--lookup-lemma-of (word lang)
  "The lemma of WORD in LANG, or WORD itself if it will not parse.
A dictionary is keyed by headword, and the word under point is usually
inflected, so `C-c C-c\=' parses before it looks anything up.  The same
courtesy is due a dictionary chosen by hand: `\\=e)poi/hsen\\=' should reach
`poie/w\\=', not fail to be a headword.

The whole apparatus is used -- the shipped analyses, the spelling variants,
Morpheus where it is available -- but only the first analysis is taken.
Where a form is ambiguous this picks the commonest reading rather than
asking, which is the right trade for a key whose purpose is to get you into
another dictionary quickly; `C-u\=' prompts for a word if the guess is wrong."
  (or (let ((raw (diogenes--do-parse word lang)))
	(when raw
	  (let* ((record (diogenes--parse-analyses-record raw lang))
		 (first (car (plist-get record :analyses))))
	    (when first
	      ;; Two conversions, and neither is optional.
	      ;;
	      ;; `:lemma' holds the field as the analyses file writes it, which
	      ;; is the pair FORM,LEMMA -- "dei/knu_mi,dei/knumi" -- so the
	      ;; lemma is what follows the comma, as make_latin_analyses.pl
	      ;; also takes it (s/^.*,\s*//).  Handing a dictionary the whole
	      ;; pair asks it about a string with a comma in the middle.
	      ;;
	      ;; And the field is beta code for Greek, where the dictionary
	      ;; commands expect what `diogenes--lookup-current-headword' hands
	      ;; them interactively: Unicode.  Each converts Unicode to its own
	      ;; key, so given beta code they read ASCII letters as Greek and
	      ;; land somewhere arbitrary -- consistently arbitrary across all
	      ;; of them, which is why Bailly, Pape, the LSJ and the DGE
	      ;; answered `δείκνυμι' alike with the neighbourhood of
	      ;; `δίξεστον'.
	      (let* ((field (plist-get first :lemma))
		     (lemma (if (string-match "," field)
				(substring field (match-end 0))
			      field)))
		(diogenes--munge-ls-lemma (string-trim lemma) lang))))))
      (and (fboundp 'diogenes--extra-lemma)
	   (diogenes--extra-lemma word lang))
      ;; Morpheus, which the two lines above and the parse before them have
      ;; between them failed to answer for.  The order is
      ;; `diogenes--parse-and-lookup''s: the shipped analyses, then the
      ;; hand-written table, then the cruncher.
      ;;
      ;; Without this the promise of the docstring was not kept, and the
      ;; consequence was worse than a form that would not resolve.  A
      ;; dictionary is keyed by headword; handed an inflected form it does
      ;; not have, it reports no exact entry -- and Gaffiot, told there is no
      ;; entry, opens the printed page instead.  So `C-c C-o' on
      ;; `frugalitatis', a form the wordlists never harvested, showed a scan
      ;; of the page rather than the article on `frugalitas', with nothing
      ;; said about why.
      (and (diogenes-morpheus-available-p)
	   (let ((first (car (diogenes--morpheus-analyses word lang))))
	     (when first
	       (let* ((field (plist-get first :lemma))
		      (lemma (if (string-match "," field)
				 (substring field (match-end 0))
			       field)))
		 (diogenes--munge-ls-lemma (string-trim lemma) lang)))))
      word))

(defcustom diogenes-lookup-always-ask-dictionary nil
  "Whether the language lookup commands always ask which dictionary.
Nil, the default, sends `\\[diogenes-lookup-greek]\=' to the LSJ and
`\\[diogenes-lookup-latin]\=' to Lewis & Short, and a prefix argument asks;
non-nil asks every time and a prefix argument makes no difference.

Worth setting for a reader who works mostly in Bailly, Georges or the DGE
and finds the default an extra keystroke rather than a convenience."
  :type 'boolean
  :group 'diogenes)

(defun diogenes--lookup-read-args (lang prompt)
  "Read the arguments for a LANG lookup: (WORD DICTIONARY).
PROMPT is used when the default dictionary is to be searched.  DICTIONARY
is nil unless a choice was asked for, by a prefix argument or by
`diogenes-lookup-always-ask-dictionary\=', in which case the prompt names
what was chosen -- so the minibuffer says what it is about to do."
  (let ((dictionary
	 (when (or current-prefix-arg diogenes-lookup-always-ask-dictionary)
	   (diogenes--read-dictionary lang))))
    (list (read-from-minibuffer
	   (if dictionary
	       (format "Look up in %s: " (plist-get dictionary :name))
	     prompt)
	   (diogenes--word-at-point-for-lookup))
	  dictionary)))

(defun diogenes--read-dictionary (lang &optional prompt)
  "Ask which of LANG\='s registered dictionaries to use; return its entry.
Signals if none is registered, which is the honest answer to a request that
cannot be met -- better than silently falling back on the default and
leaving the reader to wonder why the choice was ignored."
  (let ((alist (diogenes--lookup-choosable-dictionaries lang)))
    (unless alist
      (user-error "No searchable %s dictionary is registered: \
load diogenes-bailly, -gaffiot, -georges, -pape or -dge" lang))
    (cdr (assoc (completing-read (or prompt
				     (format "Which %s dictionary: " lang))
				 alist nil t)
		alist))))

(defun diogenes--lookup-word-in-dictionary (word dictionary &optional parse)
  "Show WORD in DICTIONARY, a registry entry; with PARSE, its lemma instead.
The one place that knows how to send a word to a dictionary chosen at
runtime, used by `diogenes-lookup-in-dictionary\=' and by the language
commands when they are asked to offer a choice."
  (let* ((lang (plist-get dictionary :lang))
	 (command (plist-get dictionary :command))
	 (word (string-trim (or word "")))
	 (target (if parse (diogenes--lookup-lemma-of word lang) word)))
    (when (string-empty-p word)
      (user-error "Nothing to look up"))
    ;; The dictionary commands assert the language of the buffer they are
    ;; called from, so that a Greek lexicon is not opened on a Latin entry.
    ;; Here the language comes from the dictionary that was chosen, which is
    ;; the whole point: let-binding the buffer-local tells the assertion the
    ;; truth about what is being looked up.  And nothing may be inherited
    ;; from the entry we are leaving: a Greek word looked up in Georges must
    ;; not carry the Greek file along with it.
    (let ((diogenes--lookup-lang lang)
	  ;; Where the entry appears is NOT decided here.  Each dictionary
	  ;; command decides it -- the five XML dictionaries from their own
	  ;; `...-display-in-same-window', and only when the lookup was made
	  ;; from a lookup buffer -- so a binding made here would be
	  ;; discarded by theirs.  An earlier attempt bound it, which asked
	  ;; "Open the result in this same window?" and then ignored the
	  ;; answer.
	  (diogenes--lookup-file nil))
      (unless (equal target word)
	(message "%s: looking up %s" word target))
      (funcall command target))))

;;;###autoload
(defun diogenes-lookup-in-dictionary (&optional word dictionary)
  "Look a word up in a dictionary of your choosing.
Like `C-c C-c\=', but instead of going to Lewis & Short or the LSJ -- the
dictionaries Diogenes searches by default -- it asks which dictionary, of
those registered, and in which language, since the label names both.

For a word that is in neither of the default dictionaries but is in another:
a late or technical word Lewis & Short does not carry, a proper name, a
sense Bailly gives and the LSJ does not.  And for reading a Greek word in
German rather than in English, or a Latin one in French, whatever the
language of the entry you are looking at.

The language is settled the way `C-c C-c\=' settles it, by
`diogenes--language-at-point\=': the word\='s own tagging where the markup says
what it is, otherwise the language of the entry or text being read.  Only
that language\='s dictionaries are then offered, since the others could not
answer.  Where the language cannot be told, it is asked for.

WORD defaults to the headword or word at point, and is parsed first, so an
inflected form reaches its lemma.  With a prefix argument, prompt for the
word as well.  DICTIONARY is a registry entry; interactively it is chosen by
completion."
  (interactive
   (let* ((lang (or (diogenes--language-at-point)
		    (completing-read "Language: " '("greek" "latin") nil t)))
	  (alist (diogenes--lookup-choosable-dictionaries lang))
	  (_ (unless alist
	       (user-error "No searchable %s dictionary is registered: \
load diogenes-bailly, -gaffiot, -georges or -pape" lang)))
	  (choice (completing-read (format "Look this %s word up in: " lang)
				   alist nil t))
	  (entry (cdr (assoc choice alist)))
	  ;; The word under the cursor, and only then the entry's headword.
	  ;; `diogenes--lookup-current-headword' answers with the headword of
	  ;; the ARTICLE, which is what the dictionary keys want when the whole
	  ;; article is the subject -- and quite wrong here, where the point of
	  ;; the command is the word you are looking at.  Reading Gaffiot on
	  ;; `dico', it took `dico' rather than the Greek word under point;
	  ;; `dico' read as beta code is δ-ι-ξ-ο, which is how a Greek lookup
	  ;; came to answer with `δίξεστον'.  `C-c C-c' takes the word at point
	  ;; and this must agree with it.
	  (default (or (diogenes--word-at-point-for-lookup)
		       (ignore-errors (diogenes--lookup-current-headword))
		       "")))
     (list (if (or current-prefix-arg (string-empty-p default))
	       (read-string (if (string-empty-p default)
				(format "Look up in %s: " choice)
			      (format "Look up in %s (%s): " choice default))
			    nil nil default)
	     default)
	   entry)))
  (unless dictionary
    (user-error "No dictionary chosen"))
  (diogenes--lookup-word-in-dictionary word dictionary t))

;;;###autoload
(defun diogenes-lookup-lewis (&optional word)
  "Show Lewis & Short's entry for WORD in a lookup buffer.
Interactively, WORD defaults to the headword of the Latin entry at point;
with a prefix argument, prompt for it.  This is the way back from another
Latin dictionary -- Gaffiot, say -- to the one Diogenes searches by
default, and it is what the \"[Lewis & Short]\" link in a Gaffiot entry
runs."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "Lewis & Short")
     ;; `l' is the way BACK from another Latin dictionary; in Lewis & Short
     ;; itself it would look up the entry already on screen.
     (unless (or current-prefix-arg
                 (not (diogenes--lookup-own-dictionary-p)))
       (user-error "This entry is Lewis & Short already; `g' opens Gaffiot, \
`C-u l' looks up another word here"))
     (list (if current-prefix-arg
               (read-string "Look up in Lewis & Short: ")
             (diogenes--lookup-current-headword)))))
  (let ((word (string-trim (or word (diogenes--lookup-current-headword))))
        (diogenes--lookup-same-window
         (derived-mode-p 'diogenes-lookup-mode)))
    (when (string-empty-p word)
      (user-error "No word given"))
    (diogenes--lookup-dict word "latin")))

(defun diogenes--lookup-mark-entry (beg end start-offset end-offset)
  "Record on the text from BEG to END which dictionary entry it is.
START-OFFSET and END-OFFSET are the entry\='s offsets in the dictionary
file.  `diogenes--lookup-bufstart\=' and `-bufend\=' track only the outermost
pair on show, which is all that is needed to extend the stack at either
edge; navigating from where point happens to be needs to know which of
several stacked entries that is, so each carries its own offsets."
  (let ((inhibit-read-only t))
    (put-text-property beg end 'diogenes-entry
		       (cons start-offset end-offset))))

(defun diogenes--lookup-entry-at-point ()
  "The (START . END) dictionary offsets of the entry point is in, or nil.
A separator or a link banner belongs to the entry it follows, so where
point is between entries the one before it answers."
  (or (get-text-property (point) 'diogenes-entry)
      (let ((pos (previous-single-property-change (point) 'diogenes-entry)))
	(and pos (get-text-property (1- pos) 'diogenes-entry)))
      (and (get-text-property (point-min) 'diogenes-entry))))

(defun diogenes--lookup-entry-region (offsets)
  "The buffer positions (BEG . END) of the displayed entry whose OFFSETS match."
  (let ((pos (point-min))
	found)
    (while (and pos (not found))
      (let ((here (get-text-property pos 'diogenes-entry)))
	(if (equal here offsets)
	    (setq found (cons pos (or (next-single-property-change
				       pos 'diogenes-entry)
				      (point-max))))
	  (setq pos (next-single-property-change pos 'diogenes-entry)))))
    found))

(defun diogenes--lookup-entry-starting-at (offset)
  "The buffer position of a displayed entry whose START offset is OFFSET."
  (let ((pos (point-min))
	found)
    (while (and pos (not found))
      (let ((here (get-text-property pos 'diogenes-entry)))
	(if (and here (= (car here) offset))
	    (setq found pos)
	  (setq pos (next-single-property-change pos 'diogenes-entry)))))
    found))

(defun diogenes--lookup-insert-entry (xml-bytes start end position before)
  "Insert the entry in XML-BYTES at POSITION, and return where it begins.
A separator goes between it and what it is joined to: after the entry when
BEFORE is non-nil, since the entry then precedes what is already there, and
before it otherwise.  The inserted text is marked with its offsets by
`diogenes--lookup-mark-entry\=', and given its own link banner."
  (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	 (formatted (diogenes--dict-parse-xml xml start end))
	 (inhibit-read-only t)
	 (beg (copy-marker position nil))
	 (fin (copy-marker position t)))
    (goto-char position)
    (unless before (diogenes--lookup-print-separator))
    (let ((entry-start (point)))
      (if formatted
	  (diogenes--lookup-insert-and-format formatted)
	(diogenes--lookup-insert-xml xml start end (current-buffer)))
      (goto-char fin)
      (when before (diogenes--lookup-print-separator))
      (diogenes--lookup-insert-entry-links diogenes--lookup-lang entry-start))
    (diogenes--lookup-mark-entry beg fin start end)
    (setq diogenes--lookup-bufstart (min diogenes--lookup-bufstart start)
	  diogenes--lookup-bufend (max diogenes--lookup-bufend end))
    (marker-position beg)))

(defun diogenes-lookup-next (&optional n)
  "Go to the entry after the one point is in, showing it if need be.
With a numerical prefix, move on N entries.

Movement is relative to point, not to the stack: with several entries on
show, this goes to the one after the entry point is in.  Where that entry
is already displayed -- as the next of a stacked pair, or because it was
fetched before -- point simply moves to it and nothing is read; otherwise
it is fetched and inserted directly after the current entry, so that the
buffer keeps the dictionary\='s own order."
  (interactive "p")
  (unless (eq major-mode 'diogenes-lookup-mode)
    (error "Not in Diogenes Lookup Mode!"))
  (dotimes (_ (max 1 (or n 1)))
    (let* ((here (or (diogenes--lookup-entry-at-point)
		     (cons diogenes--lookup-bufstart diogenes--lookup-bufend)))
	   (wanted (1+ (cdr here)))
	   (shown (diogenes--lookup-entry-starting-at wanted)))
      (if shown
	  (goto-char shown)
	(seq-let (xml-bytes start end)
	    (diogenes--get-dict-line diogenes--lookup-file wanted)
	  (unless xml-bytes (error "No further entries!"))
	  (goto-char (or (cdr (diogenes--lookup-entry-region here))
			 (point-max)))
	  (goto-char (diogenes--lookup-insert-entry xml-bytes start end
						    (point) nil)))))))

(defun diogenes-lookup-previous (&optional n)
  "Go to the entry before the one point is in, showing it if need be.
With a numerical prefix, move back N entries.  The counterpart of
`diogenes-lookup-next\=', and relative to point in the same way."
  (interactive "p")
  (unless (eq major-mode 'diogenes-lookup-mode)
    (error "Not in Diogenes Lookup Mode!"))
  (dotimes (_ (max 1 (or n 1)))
    (let* ((here (or (diogenes--lookup-entry-at-point)
		     (cons diogenes--lookup-bufstart diogenes--lookup-bufend)))
	   (wanted (1- (car here))))
      (seq-let (xml-bytes start end)
	  (diogenes--get-dict-line diogenes--lookup-file wanted)
	(unless xml-bytes (error "No further entries!"))
	(let ((shown (diogenes--lookup-entry-starting-at start)))
	  (if shown
	      (goto-char shown)
	    (goto-char (or (car (diogenes--lookup-entry-region here))
			   (point-min)))
	    (goto-char (diogenes--lookup-insert-entry xml-bytes start end
						      (point) t))))))))



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
    (dolist (cell diogenes-lookup-keys)
      (when (cdr cell)
        (keymap-set map (cdr cell) (car cell))))
    (keymap-set map "<remap> <previous-line>"       #'diogenes-lookup-backward-line)
    (keymap-set map "<remap> <next-line>"           #'diogenes-lookup-forward-line)
    (keymap-set map "<remap> <beginning-of-buffer>" #'diogenes-lookup-beginning-of-buffer)
    (keymap-set map "<remap> <end-of-buffer>"       #'diogenes-lookup-end-of-buffer)
    ;; Keys that dispatch between two dictionaries, or between the two
    ;; languages, are bound here when the command that does the dispatching
    ;; lives here too: `t' is the TLL in Latin and the TGL in Greek, and
    ;; `l' is Lewis & Short -- redefined by `diogenes-pape--install-keys'
    ;; into the Lewis/LSJ dispatcher once Pape is loaded.  Every other
    ;; dictionary key is bound by the module that owns it, with `:bind t' in
    ;; its registration or by hand -- so a dictionary whose module is not
    ;; loaded leaves its key alone instead of binding it to a command that
    ;; does not exist.
    map)
  "Basic mode map for the Diogenes Lookup Mode.")

(diogenes--lookup-install-registered-keys)

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
  (when-let* ((level (get-char-property pos 'heading))
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
(defun diogenes--beta-drop-extra-accents (word)
  "WORD with every accent after the first removed.
A Greek word bears one accent of its own.  A second appears when an ENCLITIC
follows: a proparoxytone takes an extra acute on its ultima, so the text prints
`*bria/rew/n\=' where the analyses file has `*bria/rewn\=' -- and the search then
looks for a key that cannot exist, lands on whatever sorts next to it, and shows
that entry as though it had found something.  `Βριάρεών\=' answered with
`Βρίακχος\='.

The added accent is always the last, the rule putting it on the ultima, so the
first is the word\='s own and the rest come off."
  (let ((seen nil))
    (apply #'string
           (cl-loop for c across word
                    if (memq c '(?/ ?\\ ?=))
                    unless seen collect c and do (setq seen t)
                    end
                    else collect c))))

(defun diogenes--parse-word-keys (normalized lang)
  "The keys to try for NORMALIZED, in order.
The form as it stands first, so nothing that works today stops working.  Then,
for Greek, the form with an enclitic\='s accent taken off -- see
`diogenes--beta-drop-extra-accents\='."
  (let ((keys (list normalized)))
    (when (string= lang "greek")
      (let ((dropped (diogenes--beta-drop-extra-accents normalized)))
        (unless (equal dropped normalized)
          (setq keys (append keys (list dropped))))))
    keys))

(defun diogenes--parse-word (word lang)
  "Search the ananlyses file of lang for word using a binary search.
Returns the nearest hit to the query.

Every key `diogenes--parse-word-keys\=' offers is tried before a miss is
reported, so a word carrying an enclitic\='s second accent is found under its own
spelling rather than answered with its alphabetical neighbour."
  (let* ((normalized (downcase (diogenes--beta-normalize-gravis
				(diogenes--greek-ensure-beta word))))
	 (analyses-file (file-name-concat (diogenes--perseus-path)
					  (concat lang "-analyses.txt")))
	 (index (diogenes--get-analyses-index lang))
	 (keys (diogenes--parse-word-keys normalized lang))
	 nearest)
    (cl-loop for candidate in keys
	     for key = (if (> (length candidate) 3)
			   (substring candidate 0 3)
			 candidate)
	     for start = (let ((s (cdr (assoc key (plist-get index :index-start)))))
			   (if s (- s 2) 0))
	     for end = (or (cdr (assoc key (plist-get index :index-end)))
			   (plist-get index :index-max))
	     for result = (diogenes--binary-search analyses-file
						   #'diogenes--c-sort-function
						   #'diogenes--tab-key-fn
						   candidate
						   start end)
	     ;; The first miss is kept: where every key misses, the nearest entry
	     ;; to the word AS WRITTEN is the one to show, not the nearest to a
	     ;; spelling the reader never typed.
	     do (unless nearest (setq nearest result))
	     when (nth 3 result) return (diogenes--parse-word-result result lang)
	     finally return (progn
			      (message "No result for %s! Showing nearest entry" word)
			      (diogenes--parse-word-result nearest lang)))))

(defun diogenes--parse-word-result (result lang)
  "RESULT from the binary search, shaped as `diogenes--parse-word\=' returns it."
  (cons (and (car result)
	     (diogenes--process-parse-result (car result) lang))
	(cdr result)))

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
		       (when-let* ((entry (gethash query hash)))
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

;;; Parse and look up -- a port of Perseus.pm's $do_parse / $format_analysis
;;
;; An analyses record looks like this (one line of latin-analyses.txt, for
;; the form `iacio'):
;;
;;   iacio<TAB>{34221511 9 jacio_,jacio<TAB> <TAB>pres ind act 1st sg}
;;
;; The first number of each {...} group is the BYTE OFFSET of the entry in
;; the dictionary, computed at build time by make_latin_analyses.pl through
;; a hash lookup against index_lewis.pl's key index; the second is a
;; confidence, 9 for an exact match down to 0 for "this is merely where the
;; headword would sort".  Diogenes seeks to the offset and reads a line:
;;
;;   seek $dict_fh, $dict, 0;  my $entry = <$dict_fh>;
;;
;; and so never compares the lemma against anything.  That matters, because
;; the lemma keeps Lewis & Short's j-spelling while the dictionary is
;; ordered by the i-spelling: `jacio' cannot be found by
;; `diogenes--binary-search', but offset 34221511 is exact.  Searching for
;; the lemma is only the fallback for a form that would not parse at all.

(defconst diogenes--analysis-group-re
  "{\\([^}]+\\)}\\(\\(?:\\[[0-9]+\\]\\)*\\)"
  "One analysis group of a record, with its supplementary offsets.
Mirrors Perl's m/{([^\\}]+)}((?:\\[\\d+\\])*)/g.  The bracketed numbers
that may follow the closing brace are further dictionary offsets --
supplementary prefix entries -- and are captured, not discarded.")

(defconst diogenes--analysis-fields-re
  "\\`\\([0-9]+\\) \\([0-9]\\) \\([^\t]*\\)\t\\([^\t]*\\)\t\\(.*\\)\\'"
  "The fields inside one analysis: OFFSET CONF LEMMA<TAB>TRANS<TAB>INFO.")

(defun diogenes--lemma-of-field (field)
  "The lemma in FIELD, which the analyses file gives as FORM,LEMMA.

    *bria/rew^n,bria/rews   ->  bria/rews
    si_derum,sidus          ->  sidus
    sidus                   ->  sidus

The form comes first, carrying the vowel quantities the key has not got, and
the lemma second.  `diogenes--process-parse-result' has always split it this
way; the record parser did not, so the analysis header showed both joined by
the comma -- and then asked the dictionary for that, which no dictionary has as
a headword.

Where there is no comma the field IS the lemma, so nothing is lost by asking.
Where there are several, the second is taken and the rest left: a lemma may
carry a comma of its own, as `a)mfi/,peri/-pla/zw' does for a pair of
prefixes, and guessing which comma means what is beyond a display function."
  (let ((parts (split-string (or field "") "," t "[ \t]+")))
    (cond ((null parts) (or field ""))
          ((cdr parts) (cadr parts))
          (t (car parts)))))

(defun diogenes--munge-ls-lemma (lemma lang)
  "Render a raw lemma from the analyses file for display.
Mirrors Perl's $munge_ls_lemma for Latin -- the vowel-quantity markers
become combining diacritics and a trailing homograph numeral is set off
by a space -- and beta-code conversion for Greek."
  (if (string= lang "greek")
      (diogenes--perseus-ensure-utf8 lemma lang)
    (diogenes--replace-regexes-in-string
	(diogenes--perseus-ensure-utf8
	 (replace-regexp-in-string "#?\\([0-9]\\)\\'" " \\1" lemma)
	 lang)
      ("&lt;" "<")
      ("&gt;" ">"))))

(defun diogenes--parse-analyses-record (encoded-str lang)
  "Parse the raw analyses record in ENCODED-STR.
Returns a plist (:analyses ANALYSES :suppl OFFSETS), where each analysis
is itself a plist

  (:offset N :conf N :lemma RAW :display SHOWN :trans TRANS :info INFO)

in the order the record gives them.  Nothing is dropped and nothing is
merged; grouping is `diogenes--analyses-dicts''s job.

`diogenes-latin-analysis-corrections' is applied here, keyed by the form
the record itself is filed under, so every caller of a parse gets the same
corrected morphology -- the analysis header, the entries chosen, and the
lemma a hand-picked dictionary is asked about alike."
  (let* ((str (decode-coding-string encoded-str 'utf-8))
	 (body (or (cadr (diogenes--split-once "\t+" str)) ""))
	 (pos 0)
	 analyses suppl)
    (while (string-match diogenes--analysis-group-re body pos)
      ;; Both captured here, before anything that could clobber the match
      ;; data of BODY: the loop below reads EXTRA after `:display' has run.
      (let ((group (match-string 1 body))
	    (extra (or (match-string 2 body) "")))
	(setq pos (match-end 0))
	(if (not (string-match diogenes--analysis-fields-re group))
	    (message "Diogenes: bad analysis: %s" group)
	  ;; EVERY field is read before anything else is called.  The plist was
	  ;; built inline, and `:display' -- which is
	  ;; `diogenes--munge-ls-lemma', and so `replace-regexp-in-string' --
	  ;; was evaluated before `:trans' and `:info' read groups 4 and 5.
	  ;; Match data is global: by then it belonged to munge's own regexps,
	  ;; those groups were nil, and `string-trim' was handed nil.  A latent
	  ;; fault for as long as the code has existed, waiting for an
	  ;; implementation that leaves fewer groups behind.
	  ;; The five reads come first and NOTHING is called between them --
	  ;; not even `string-trim', which is regexps like everything else and
	  ;; clobbered group 5 for the `info' below it when the trimming was
	  ;; done inline.  `let' binds in order, so `string-trim' on group 4
	  ;; ran before group 5 was ever read.  The trimming and the numbers
	  ;; happen in the second `let', where there is nothing left to lose.
	  (let* ((raw (list (match-string 1 group)
			    (match-string 2 group)
			    (match-string 3 group)
			    (match-string 4 group)
			    (match-string 5 group)))
		 (offset (string-to-number (nth 0 raw)))
		 (conf (string-to-number (nth 1 raw)))
		 (lemma (nth 2 raw))
		 (trans (string-trim (or (nth 3 raw) "")))
		 (info (string-trim (or (nth 4 raw) ""))))
	    (push (list :offset offset
			:conf conf
			:lemma lemma
			:display (diogenes--munge-ls-lemma
				  (diogenes--lemma-of-field lemma) lang)
			:trans trans
			:info info)
		  analyses)))
	(let ((p 0))
	  (while (string-match "\\[\\([0-9]+\\)\\]" extra p)
	    (push (string-to-number (match-string 1 extra)) suppl)
	    (setq p (match-end 0))))))
    (list :analyses (diogenes--correct-analyses
                     (car (diogenes--split-once "\t+" str))
                     (nreverse analyses)
                     lang)
	  :suppl (delete-dups (nreverse suppl)))))

(defun diogenes--analyses-dicts (record)
  "Return the entries to show for RECORD, as an alist of (OFFSET . CONF).
Offsets keep their first-seen order and occur only once; CONF is the LOWEST
confidence among the analyses pointing there.  Perl SUMS them
\(`$conf{$dict} += $conf'), which silently clears the caveat thresholds
whenever a doubtful headword is reached by several analyses at once: the
three analyses of `retemptare' are each recorded at 2, and 2+2+2 is 6, so
upstream prints no warning about an entry it knows to be a guess.  Three
uncertain analyses are not one certain one.  Supplementary offsets are
appended with a CONF of -1 unless they already occur among the analyses."
  (let (dicts)
    (dolist (a (plist-get record :analyses))
      (let* ((offset (plist-get a :offset))
	     (cell (assq offset dicts)))
	(if cell
	    (setcdr cell (min (cdr cell) (plist-get a :conf)))
	  (push (cons offset (plist-get a :conf)) dicts))))
    (setq dicts (nreverse dicts))
    (dolist (offset (plist-get record :suppl))
      (unless (assq offset dicts)
	(setq dicts (nconc dicts (list (cons offset -1))))))
    dicts))

(defun diogenes--analysis-caveat (conf)
  "The note to print above an entry whose summed confidence is CONF.
Diogenes' own wording."
  (cond ((= conf -2)
	 "(Headword found by assimilating the prefix of the lemma.)")
	((= conf -1) "Supplementary prefix entry:")
	((= conf 0) "(NB. Could not find dictionary headword; \
this is around the spot it should appear.)")
	((<= conf 2) "(NB. This dictionary headword is a guess.)")))

(defun diogenes--lookup-append-entry (xml-bytes start end &optional note)
  "Append the entry in XML-BYTES to the current lookup buffer.
The body of `diogenes-lookup-next' minus the reading, plus an optional
NOTE above the entry.  Stacks the several entries of one analysis the way
the application does."
  (let* ((xml (decode-coding-string xml-bytes 'utf-8))
	 (formatted (diogenes--dict-parse-xml xml start end))
	 (inhibit-read-only t))
    (setq diogenes--lookup-bufend (max diogenes--lookup-bufend end))
    (goto-char (point-max))
    (let ((beg (copy-marker (point) nil))
	  (fin (copy-marker (point) t)))
      (diogenes--lookup-print-separator)
      (when note
	(insert (propertize (concat note "\n\n") 'font-lock-face 'italic)))
      (let ((entry-start (point)))
	(if formatted
	    (diogenes--lookup-insert-and-format formatted)
	  (diogenes--lookup-insert-xml xml start end (current-buffer)))
	(diogenes--lookup-insert-entry-links diogenes--lookup-lang entry-start))
      (diogenes--lookup-mark-entry beg fin start end))))

(defun diogenes--lookup-insert-at-top (text)
  "Insert TEXT at the top of the current lookup buffer."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (insert text))))

(defun diogenes--format-analysis-header (query lang record)
  "The analysis header for QUERY, as the application prints it."
  (let ((analyses (plist-get record :analyses)))
    (cl-labels ((line (a)
		  (concat (plist-get a :display)
			  (let ((trans (plist-get a :trans)))
			    (if (string-blank-p trans)
				""
			      (format " (%s)" trans)))
			  ": " (plist-get a :info))))
      (concat
       (propertize (format "Perseus analys%s of %s:\n\n"
			   (if (= 1 (length analyses)) "is" "es")
			   (if (string= lang "greek")
			       (diogenes--perseus-ensure-utf8 query lang)
			     query))
		   'font-lock-face 'shr-h2)
       (if (= 1 (length analyses))
	   (concat (line (car analyses)) "\n")
	 (cl-loop for a in analyses
		  for i from 1
		  concat (format "%2d. %s\n" i (line a))))
       "\n"))))

(defcustom diogenes-lookup-expand-homographs t
  "Whether a guessed dictionary entry is shown together with its homographs.
When the offset recorded for a lemma is a guess -- confidence 2 or less --
the entry it names is as likely as not the wrong one of a numbered set, and
the others are worth seeing.

`index_lewis.pl' indexes each Lewis & Short key five ways and keeps the
first claim on each spelling:

    print \"$basic_key $i\\n\" unless $seen{$basic_key}++;

so of the two entries keyed `re^tento1' and `re^tento2' only the first ever
answers to the letters-only spelling `retento'.  Morpheus writes the
compound as `re-tento', which matches no key at all, so
`make_latin_analyses.pl' falls through to its last resort --

    unless ($ls{$real_lemma}) { $conf = 2; $real_lemma =~ s/[^a-zA-Z]//g }

-- and records the offset of `re^tento1', the frequentative of `retineo',
for a form belonging to `re^tento2', to attempt again.  Parsing
`retemptare' then shows the wrong entry with no hint that anything is
amiss.  Showing both leaves the reader to pick, which is the best that can
be done without an index that distinguishes them."
  :type 'boolean
  :group 'diogenes)

(defun diogenes--dict-basic-key (entry)
  "The letters of ENTRY's key, downcased: `re^tento2' gives `retento'.
The spelling `index_lewis.pl' reduces a key to for its coarsest index, and
the only one a homograph number does not distinguish."
  (when (string-match "key\\s-*=\\s-*\"\\([^\"]*\\)\"" entry)
    (downcase (diogenes--ascii-alpha-only (match-string 1 entry)))))

(defun diogenes--dict-homograph-run (offset lang &optional file limit)
  "The entries around OFFSET that share its headword, as (START END BYTES).
Homographs are numbered forms of one headword -- `re^tento1', `re^tento2'
-- and so are always neighbours in the file: this walks outwards from
OFFSET while the letters-only key still matches, at most LIMIT entries in
each direction (six by default).  Returns them in file order, OFFSET's own
entry among them."
  (let* ((dict (or file (diogenes--dict-file lang)))
	 (limit (or limit 6))
	 (here (diogenes--get-dict-line dict offset)))
    (if (not (car here))
	nil
      ;; `diogenes--get-dict-line' returns (BYTES START END); a run entry is
      ;; (START END BYTES).
      (let* ((key (diogenes--dict-basic-key (car here)))
	     (self (list (nth 1 here) (nth 2 here) (nth 0 here)))
	     (before nil)
	     (after nil))
	(when key
	  ;; Leftwards from the START of the leftmost entry so far.  Stepping
	  ;; from its END would land inside the entry itself, which of course
	  ;; still has the same key, and the entry would be collected again and
	  ;; again until LIMIT stopped it.
	  (let ((pos (1- (nth 0 self)))
		(n 0))
	    (while (and (< n limit) (> pos 0))
	      (let ((line (diogenes--get-dict-line dict pos)))
		(if (and (car line)
			 (equal key (diogenes--dict-basic-key (car line)))
			 (< (nth 1 line) (nth 0 (or (car before) self))))
		    (progn (push (list (nth 1 line) (nth 2 line) (nth 0 line))
				 before)
			   (setq pos (1- (nth 1 line))
				 n (1+ n)))
		  (setq n limit)))))
	  ;; Rightwards from the END of the rightmost entry so far.
	  (let ((pos (1+ (nth 1 self)))
		(n 0))
	    (while (< n limit)
	      (let ((line (diogenes--get-dict-line dict pos)))
		(if (and (car line)
			 (equal key (diogenes--dict-basic-key (car line)))
			 (> (nth 1 line)
			    (nth 0 (or (car (last after)) self))))
		    (setq after (nconc after
				       (list (list (nth 1 line) (nth 2 line)
						   (nth 0 line))))
			  pos (1+ (nth 2 line))
			  n (1+ n))
		  (setq n limit))))))
	(append before (list self) after)))))

(defun diogenes--dict-entry-hyphenated-p (entry)
  "Whether ENTRY's printed headword contains a hyphen.
Lewis & Short prints the compound as `rĕ-tento' and the frequentative as
`rĕtento', a distinction its keys drop but its `orth_orig' keeps -- the
same distinction Morpheus makes by writing the lemma `re-tento'."
  (and (string-match "orth_orig\\s-*=\\s-*\"\\([^\"]*\\)\"" entry)
       (string-search "-" (match-string 1 entry))
       t))

(defcustom diogenes-latin-assimilate-prefixes t
  "Whether a hyphenated Latin lemma is retried with its prefix assimilated.
Morpheus writes a compound unassimilated, marking the morpheme boundary --
`in-mitto\=', `in-lido\=', `con-pello\=' -- where Lewis & Short keys the
assimilated form: `immitto\=', `illido\=', `compello\='.
`make_latin_analyses.pl\=' strips the lemma to its bare letters as a last
resort, which yields `inmitto\=', matches no key, and leaves the confidence
at 0 with the offset at wherever that spelling would sort -- `innabilis\=',
as it happens.

The hyphen says where the boundary falls, so the assimilated spellings can
be worked out and offered to the dictionary, and only the one it has a key
for is used.  Nothing is guessed: a spelling the dictionary does not
confirm is discarded."
  :type 'boolean
  :group 'diogenes)

(defconst diogenes--latin-labials '(?p ?b ?m)
  "The letters before which a nasal is written m.")

(defcustom diogenes-latin-prefix-variants
  '(("de" . "di") ("di" . "de"))
  "Prefixes the dictionary may key under a spelling other than Morpheus\\='s.
An alist of (LEMMA . DICTIONARY): the prefix as the analyses file writes it,
and the prefix to try instead when nothing else has matched a key.

This is not assimilation, which is a sound change the hyphen lets one work
out.  It is one prefix written two ways, the choice falling out differently
in the two sources: Morpheus has `de-rego\\=' and `de-rigo\\=' where Lewis &
Short keys `dirigo\\=', with derigo named inside the entry as the spelling
Roby and Ribbeck preferred and the manuscripts mostly print.  A reader
parsing any form of it -- `derigamus\\=' -- got no headword at all.

Each is tried last, after every spelling `diogenes--latin-assimilations\\='
works out, so a compound the dictionary has under its own prefix is never
sent elsewhere: `de-duco\\=' finds `deduco\\=' and is not offered `diduco\\=',
which is another verb.  Only a spelling the dictionary confirms is used."
  :type '(alist :key-type (string :tag "Lemma prefix")
                :value-type (string :tag "Dictionary prefix"))
  :group 'diogenes)

(defun diogenes--latin-assimilations (lemma)
  "The spellings a hyphenated LEMMA might be keyed under, likeliest first.
`in-mitto\=' gives `immitto\=' and `inmitto\='; `con-pello\=' gives `compello\=',
`conpello\=' and `coppello\='; `con-eo\=' gives `coeo\='.  Nothing is decided
here -- every candidate is offered, and `diogenes--assimilated-offset\=' keeps
whichever the dictionary actually has."
  (let* ((clean (replace-regexp-in-string
		 "[_^+]" ""
		 (replace-regexp-in-string "#?[0-9]+\\'" "" lemma)))
	 ;; The analyses file writes some lemmata as FORM,LEMMA -- the accented
	 ;; form and then the lemma proper, `obsessi_s,ob-sedeo'.  Only the part
	 ;; after the comma is the compound to be assimilated: with the form
	 ;; still attached every candidate came out as `obsessi_s,obsideo', which
	 ;; is nobody's key, and the reader was shown `ob-septus' -- the entry
	 ;; that follows where `obsideo' would have been.
	 (clean (if (string-match ",\\([^,]*\\)\\'" clean)
		    (match-string 1 clean)
		  clean))
	 (parts (split-string clean "-" t)))
    (when (= 2 (length parts))
      (let* ((prefix (downcase (car parts)))
	     (stem (downcase (cadr parts)))
	     (final (and (> (length prefix) 0)
			 (aref prefix (1- (length prefix)))))
	     (initial (and (> (length stem) 0) (aref stem 0)))
	     (stub (substring prefix 0 (max 0 (1- (length prefix)))))
	     candidates)
	(when (and final initial)
	  ;; The compound simply run together comes FIRST, and deliberately.
	  ;; It is what make_latin_lemmata.pl assumes, and it costs nothing: a
	  ;; confidence of 0 means make_latin_analyses.pl already tried the
	  ;; letters-only spelling -- this very one -- and found no key, so it
	  ;; cannot match here either.  At a confidence of 2 it DOES match, and
	  ;; matching it returns the offset the build already chose, which
	  ;; leaves `re-tento\=' to the homograph sweep where it belongs.  Trying
	  ;; an assimilated spelling first would instead send `ad-sum\=' to
	  ;; `assum\=', roast meat, in preference to `adsum\='.
	  (push (concat prefix stem) candidates)
	  (when (memq final '(?n ?m ?d ?b ?s ?x))
	    (cond
	     ;; A nasal is written m before a labial: con+pello, in+mitto.
	     ((and (memq final '(?n ?m))
		   (memq initial diogenes--latin-labials))
	      (push (concat stub "m" stem) candidates))
	     ;; Before a vowel the consonant drops: con+eo.
	     ((memq initial '(?a ?e ?i ?o ?u ?y))
	      (push (concat stub stem) candidates)))
	    ;; Total assimilation, which is what doubles the letter: in+lido,
	    ;; ad+sum, ob+fero, ex+fero.
	    (push (concat stub (string initial) stem) candidates)))
	;; `ex' loses its consonant before s: ex+surio is esurio, and likewise
	;; educo, evado, emitto.  Not the vowel rule above -- the stem begins
	;; with a consonant -- and without this `ex-surio' reaches no key and
	;; the reader is shown `exsurrectio', which is the next entry along.
	(when (and final (eq final ?x) initial)
	  (push (concat stub stem) candidates))
	;; And the stem's own first vowel weakens in composition: sedeo becomes
	;; -sideo, teneo -tineo, facio -ficio, capio -cipio, cado -cido.  So
	;; `ob-sedeo' is keyed `obsideo', and until this was offered the reader
	;; got `ob-septus'.  Offered LAST, being the least common of these, and
	;; harmless where it is wrong: a spelling the dictionary has not got
	;; costs one binary search.
	(when (and prefix stem (> (length stem) 0))
	  (let ((weakened (diogenes--latin-weaken-stem stem)))
	    (when weakened
	      (push (concat prefix weakened) candidates)
	      ;; ...and with the prefix assimilated as well: ad+teneo is
	      ;; `attineo', both changes at once.
	      (when (and final initial (memq final '(?n ?m ?d ?b ?s ?x)))
		(push (concat stub (string (aref weakened 0)) weakened)
		      candidates)))))
	;; And the PREFIX itself may be spelt otherwise in the dictionary.
	;; Not an assimilation: de- and di- are one prefix written two ways,
	;; and the two spellings are distributed between Morpheus and Lewis
	;; & Short.  Morpheus writes `de-rego' and `de-rigo'; the dictionary
	;; keys the verb `dirigo' and mentions derigo only inside the entry.
	;; So no candidate above reached a key, the confidence stayed at 0,
	;; and every form of the commonest verb of its family -- `derigamus'
	;; -- printed the gap between `derelictio' and `deripio'.
	;;
	;; Offered after everything else, and so tried only where the
	;; dictionary has not got the compound under its own spelling:
	;; `de-duco' matches `deduco' first and never asks about `diduco',
	;; which is a different verb.
	(let ((alt (cdr (assoc prefix diogenes-latin-prefix-variants))))
	  (when (and alt (> (length stem) 0))
	    (push (concat alt stem) candidates)
	    (let ((weakened (diogenes--latin-weaken-stem stem)))
	      (when weakened
		(push (concat alt weakened) candidates)))))
	(nreverse (delete-dups candidates))))))

(defun diogenes--latin-weaken-stem (stem)
  "STEM with its first vowel weakened to `i\=', or nil if nothing changes.
The vowel of a simple verb weakens when it becomes the second element of a
compound: sedeo/-sideo, teneo/-tineo, facio/-ficio, capio/-cipio,
cado/-cido, salio/-silio, statuo/-stituo.  So a lemma Morpheus writes
`ob-sedeo\=' is keyed in the dictionary as `obsideo\='.

Only a first-syllable `a\=' or `e\=' is touched, and only where a consonant
follows it, which is where the change occurs.  Returns nil when there is
nothing to do, so the caller can tell a real candidate from a repetition."
  (when (and stem (> (length stem) 1))
    (let ((i 0) (len (length stem)))
      ;; Past any initial consonants to the first vowel.
      (while (and (< i len)
		  (not (memq (aref stem i) '(?a ?e ?i ?o ?u ?y))))
	(setq i (1+ i)))
      (when (and (< i len)
		 (memq (aref stem i) '(?a ?e))
		 ;; A consonant must follow: this is a closed syllable's vowel,
		 ;; not a hiatus.
		 (< (1+ i) len)
		 (not (memq (aref stem (1+ i)) '(?a ?e ?i ?o ?u ?y))))
	(concat (substring stem 0 i) "i" (substring stem (1+ i)))))))

(defun diogenes--dict-exact-offset (word lang &optional file)
  "The offset of the entry whose key is WORD, or nil if there is none.
Unlike `diogenes--lookup-dict\=', a miss is a miss: nothing is displayed and
no nearest entry offered, so this can be used to ask the dictionary whether
a spelling exists at all."
  (seq-let (_bytes start _end exact-hit)
      (diogenes--binary-search
       (or file (diogenes--dict-file lang))
       (if (string= lang "latin")
	   #'diogenes--latin-sort-function
	 #'diogenes--ascii-sort-function)
       #'diogenes--xml-key-fn
       word)
    (and exact-hit start)))

(defun diogenes--assimilated-offset (lemma lang &optional file)
  "The offset of the entry for the hyphenated LEMMA, or nil.
The first of `diogenes--latin-assimilations\=' that the dictionary has a key
for.  See `diogenes-latin-assimilate-prefixes\='."
  (when (and diogenes-latin-assimilate-prefixes
	     (string= lang "latin")
	     (string-search "-" lemma))
    (cl-loop for candidate in (diogenes--latin-assimilations lemma)
	     thereis (diogenes--dict-exact-offset candidate lang file))))

(defun diogenes--expand-homographs (offset conf lemma lang &optional file)
  "The homographs of the entry at OFFSET, each carrying CONF.
LEMMA settles their order: where it is hyphenated, an entry whose printed
headword is hyphenated comes first, that being the same distinction between
a compound and a simple verb."
  (let* ((run (diogenes--dict-homograph-run offset lang file))
	 (hyphenated (and lemma (string-search "-" lemma))))
    (cond
     ((< (length run) 2) (list (cons offset conf)))
     (t (let ((offsets (mapcar #'car run)))
	  (when hyphenated
	    (setq offsets
		  (append
		   (cl-loop for (start _end bytes) in run
			    when (diogenes--dict-entry-hyphenated-p bytes)
			    collect start)
		   (cl-loop for (start _end bytes) in run
			    unless (diogenes--dict-entry-hyphenated-p bytes)
			    collect start))))
	  (mapcar (lambda (o) (cons o conf))
		  (delete-dups offsets)))))))

(defun diogenes--expand-uncertain-dicts (record dicts lang &optional file)
  "Add the homographs of any guessed entry in DICTS, an alist of (OFFSET . CONF).
An entry whose confidence is 2 or less was reached by stripping the lemma
down to its letters, which cannot tell numbered homographs apart, so its
neighbours are included too.  Where the lemma is hyphenated, an entry whose
printed headword is hyphenated is shown first, that being the same
distinction; otherwise file order is kept.  Governed by
`diogenes-lookup-expand-homographs'."
  (if (not diogenes-lookup-expand-homographs)
      dicts
    (cl-loop
     for (offset . conf) in dicts
     append
     (if (or (< conf 0) (> conf 2))
	 (list (cons offset conf))
       (let* ((lemma (cl-loop for a in (plist-get record :analyses)
			      thereis (and (= offset (plist-get a :offset))
					   (plist-get a :lemma))))
	      (assimilated (and lemma
				(diogenes--assimilated-offset lemma lang file))))
	 (if assimilated
	     ;; The dictionary has a key for the assimilated spelling, so the
	     ;; guessed offset can be replaced outright rather than hedged.
	     (list (cons assimilated -2))
	   (diogenes--expand-homographs offset conf lemma lang file)))))))

(defcustom diogenes-lookup-drop-suffix-analyses t
  "Whether to drop an analysis whose entry presents its lemma as a suffix.

`τέως\=' has two analyses.  The first, lemma `τέος\=', carries the offset of
`κινδυν-ευτέον\=' and that entry\='s gloss, `one must venture', Perseus took the
`-τέος\=' at the end of it for a headword.  So a reader looking up `τέως\=' was
shown an entry about venturing.

`-τέος\=', `-τέα\=', `-τέον\=' are the verbal-adjective suffixes and not words.  The
LSJ marks them the only way it can, with a leading hyphen, inside the entry of a
word that uses them -- and that mark is what this reads.  See
`diogenes--lemma-shown-as-suffix-p\=' for why the test is narrow enough to leave
the prefixed compounds alone, those being 7 analyses in every 100 and every one
of them right."
  :type 'boolean
  :group 'diogenes)

(defun diogenes--greek-letters-only (text)
  "TEXT as bare Greek letters: no accents, no hyphens, no case.
So that a lemma in one form can be compared with a headword in another."
  (let* ((decomposed (ucs-normalize-NFD-string (or text "")))
         (kept (cl-loop for c across decomposed
                        unless (<= #x0300 c #x036f)
                        collect (downcase c))))
    (apply #'string
           (cl-remove-if-not
            (lambda (c)
              (let ((o (if (characterp c) c 0)))
                (or (<= #x03b1 o #x03c9) (<= #x0391 o #x03a9))))
            (mapcar (lambda (c)
                      (if (eq c ?\N{GREEK SMALL LETTER FINAL SIGMA})
                          ?\N{GREEK SMALL LETTER SIGMA}
                        c))
                    kept)))))

(defun diogenes--lemma-shown-as-suffix-p (offset lemma lang &optional file)
  "Whether the entry at OFFSET names LEMMA as a hyphen-initial form.

The LSJ says which forms an entry covers, in `<orth>' elements, and where the
form is a suffix it writes it with a leading hyphen.  `κινδυν-ευτέον' ends:

    <pos>Adj.</pos> <orth lang=\"greek\">-τέος</orth>, <itype>α</itype>, ...

So the test is the dictionary's own markup: the lemma equals one of the
entry's hyphen-initial forms, and is not the entry's own key.

Not `extent=\"suff\"' on the head, which says the HEADWORD is printed truncated
-- `κινδυν-ευτέον' for `κινδυνευτέον' -- and appears on 55252 entries.  That is
most of the compounds in the dictionary and would filter nothing usefully.

And not a hyphen anywhere in the text, which was the first attempt: the entry's
prose has hyphens of its own, and the test would have caught the compounds it
exists to protect.

Nil where the entry cannot be read, an unreadable entry being no evidence."
  (let* ((dict (or file (diogenes--dict-file lang)))
         (line (car (diogenes--get-dict-line dict offset))))
    (when (and line lemma)
      (let* ((text (if (multibyte-string-p line) line
                     (decode-coding-string line 'utf-8)))
             (want (diogenes--greek-letters-only
                    (diogenes--perseus-beta-to-utf8 lemma)))
             (key (and (string-match "key=\"\\([^\"]+\\)\"" text)
                       (diogenes--greek-letters-only
                        (diogenes--perseus-beta-to-utf8
                         (match-string 1 text)))))
             (found nil)
             (start 0))
        (when (and want (> (length want) 0) (not (equal key want)))
          (while (and (not found)
                      (string-match "<orth[^>]*>\\([^<]+\\)</orth>" text start))
            (setq start (match-end 0))
            (let ((form (match-string 1 text)))
              ;; Hyphen-initial only: an `<orth>' without one is an ordinary
              ;; variant spelling, which is no reason to doubt anything.
                            (when (and (string-match-p "\\`-" form)
                         (equal (diogenes--greek-letters-only form) want))
                (setq found t))))
          found)))))

(defun diogenes--drop-suffix-analyses (record dicts lang &optional file)
  "DICTS without the entries that present their lemma as a suffix.
Never all of them: where every analysis fails the test the list is returned
whole, an empty lookup being worse than a wrong one and the test being a
safeguard rather than an authority."
  (if (not diogenes-lookup-drop-suffix-analyses)
      dicts
    (let ((kept (cl-loop
                 for (offset . conf) in dicts
                 for lemma = (cl-loop for a in (plist-get record :analyses)
                                      thereis (and (= offset (plist-get a :offset))
                                                   (plist-get a :lemma)))
                 unless (and lemma
                             (diogenes--lemma-shown-as-suffix-p
                              offset lemma lang file))
                 collect (cons offset conf))))
      (or kept dicts))))

(defun diogenes--show-analysis-entries (dicts lang &optional file)
  "Show the entries named by DICTS, an alist of (OFFSET . CONF).
The first goes into a fresh lookup buffer and the rest are appended to
it, as `$format_analysis' stacks them.  Returns that buffer."
  (unless dicts (error "No dictionary entries to show"))
  (let ((dict (or file (diogenes--dict-file lang)))
	(buffer nil))
    (cl-loop for (offset . conf) in dicts
	     for note = (diogenes--analysis-caveat conf)
	     do (seq-let (xml-bytes start end)
		    (diogenes--get-dict-line dict offset)
		  (cond
		   ((not xml-bytes)
		    (message "Diogenes: no dictionary entry at offset %d"
			     offset))
		   ((not buffer)
		    (setq buffer (diogenes--show-dict-entry
				  xml-bytes start end lang file))
		    (when note
		      (with-current-buffer buffer
			(diogenes--lookup-insert-at-top
			 (propertize (concat note "\n\n")
				     'font-lock-face 'italic)))))
		   (t
		    (with-current-buffer buffer
		      (diogenes--lookup-append-entry
		       xml-bytes start end note))))))
    (or buffer (error "None of the offsets could be read"))))

(defun diogenes--try-parse (word lang)
  "Look WORD up in LANG's analyses file; return the raw record or nil.
`$try_parse': the .idt index gives the byte range of the bucket for the
first three characters of WORD and the binary search is confined to it.
WORD is used AS GIVEN -- make_index.pl keys the buckets on the raw prefix
and the file is LC_ALL=C sorted, so a query downcased before the key is
computed looks in the wrong bucket and can never match `Itys'."
  (let* ((analyses-file (file-name-concat (diogenes--perseus-path)
					  (concat lang "-analyses.txt")))
	 (index (diogenes--get-analyses-index lang))
	 (key (if (> (length word) 3) (substring word 0 3) word))
	 (start (let ((s (cdr (assoc key (plist-get index :index-start)))))
		  (if s (- s 2) 0)))
	 (end (or (cdr (assoc key (plist-get index :index-end)))
		  (plist-get index :index-max)))
	 (result (diogenes--binary-search analyses-file
					  #'diogenes--c-sort-function
					  #'diogenes--tab-key-fn
					  word
					  start end)))
    (and (nth 3 result) (car result))))

(defcustom diogenes-latin-try-spelling-variants t
  "Whether a Latin form that will not parse is retried under other spellings.
The wordlists Morpheus was run over do not agree with every text a reader
copies from, in three ways.

They spell consonantal i as i -- there are 108 j-initial forms in the whole
of `latin-analyses.txt\=' -- so a form written `jacio\=' is not a key in it at
all.  They spell consonantal u as v, so `ualdissime\=' is likewise absent.
And the cruncher assimilated a nasal before a consonant only sometimes: it
produced `quendam\=' and `quandam\=', but `quorumdam\=' where every text
prints `quorundam\='.

Either way the parse fails and falls through to a headword search, which
cannot help: an inflected form is nobody\='s dictionary headword, so
`quorundam\=' landed on `quorsum\='.  Trying the other spelling finds the
record, and with it the offset of the right entry.

The form as typed is always tried first, so a form that parses costs
nothing.  Set to nil to try only what the user typed, as Diogenes\=' own
`$do_parse\=' does."
  :type 'boolean
  :group 'diogenes)

(defconst diogenes--latin-vowels '(?a ?e ?i ?o ?u ?y)
  "The letters that count as vowels when reading a spelling.")

(defun diogenes--latin-swap-letters (word from to)
  "Replace every FROM in WORD with TO, in upper case as well as lower.
For the swaps that need no judgement: every j in a Latin word stands for
the consonant, and so does every v, so they can be rewritten wholesale as
i and u."
  (concat (mapcar (lambda (c)
		    (cond ((eq c from) to)
			  ((eq c (upcase from)) (upcase to))
			  (t c)))
		  word)))

(defun diogenes--latin-swap-at (word positions mask from to)
  "WORD with the POSITIONS picked out by MASK rewritten from FROM to TO."
  (let ((variant (copy-sequence word)))
    (cl-loop for bit from 0
	     for i in positions
	     unless (zerop (logand mask (ash 1 bit)))
	     do (aset variant i (if (eq (aref variant i) (upcase from))
				    (upcase to)
				  to)))
    variant))

(defun diogenes--latin-positional-swaps (word from to predicate &optional cap)
  "Spellings of WORD with some of its FROMs, where PREDICATE holds, written TO.
PREDICATE is called with the character following the candidate.  Rewriting
every occurrence gives nonsense -- `iacio\=' would become `jacjo\=', `seruus\='
`servvs\=' -- so each combination of the qualifying positions is returned
instead, at most CAP of them considered (four by default)."
  (let* ((positions (cl-loop for i from 0 below (max 0 (1- (length word)))
			     when (and (eq (downcase (aref word i)) from)
				       (funcall predicate
						(downcase (aref word (1+ i)))))
			     collect i))
	 (positions (seq-take positions (or cap 4))))
    (cl-loop for mask from 1 to (1- (ash 1 (length positions)))
	     collect (diogenes--latin-swap-at word positions mask from to))))

(defun diogenes--latin-vowel-p (char)
  "Whether CHAR is a vowel."
  (memq char diogenes--latin-vowels))

(defun diogenes--latin-consonant-p (char)
  "Whether CHAR is a letter and not a vowel."
  (and (>= char ?a) (<= char ?z) (not (memq char diogenes--latin-vowels))))

(defun diogenes--latin-exs-variants (word)
  "Spellings of WORD with an s inserted or dropped after an initial ex.
Editions differ over the prefix: `exstruo\=' and `extruo\=', `exspecto\=' and
`expecto\=', `exstinguo\=' and `extinguo\=', `exsisto\=' and `existo\='.  The
wordlists carry one of the pair and not the other -- `exstruxit\=' is there,
`extruxit\=' is not, so a text printing the shorter form parsed as nothing
and fell through to a headword search that landed on `extrudo\='.

The s is only meaningful before a consonant: `exeo\=' and `exsul\=' are not
alternatives of one another."
  (let ((case-fold-search nil))
    (cond
     ((string-match "\\`\\([Ee]\\)xs\\([bcdfglmnpqrstv]\\)" word)
      (list (concat (match-string 1 word) "x"
		    (substring word (match-beginning 2)))))
     ;; No s in this class: the s of `exsul\=' is the word's own, and adding
     ;; another would only ask the dictionary about `exssul\='.
     ((string-match "\\`\\([Ee]\\)x\\([bcdfglmnpqrtv]\\)" word)
      (list (concat (match-string 1 word) "xs"
		    (substring word (match-beginning 2))))))))

(defun diogenes--latin-genitive-plural-variants (word)
  "Spellings of WORD with the other third-declension genitive plural ending.
`aedium\=' and `aedum\=' are both the genitive plural of `aedes\=', and the
wordlists have the second: `aedum\=' is recorded at confidence 9 against
`aedes\=', `aedium\=' not at all, so the commoner of the two forms parsed as
nothing and fell through to `aedon\=', the nightingale.

Nothing here decides whether a word IS a genitive plural -- a noun in -um
gets an -ium candidate whether it could bear one or not.  That costs one
binary search on a form that would have failed anyway, and only an exact
match counts, so a candidate like `bellium\=' is looked for and not found."
  (cond
   ((string-suffix-p "ium" word)
    (list (concat (substring word 0 -3) "um")))
   ((string-suffix-p "um" word)
    (list (concat (substring word 0 -2) "ium")))))

(defcustom diogenes-latin-spelling-rules
  '(diogenes--latin-exs-variants
    diogenes--latin-genitive-plural-variants)
  "Functions producing further spellings of a Latin form that will not parse.
Each is called with a form and returns a list of alternatives, or nil.
Unlike the letter swaps `diogenes--latin-form-variants\=' applies, these are
insertions and endings rather than substitutions, so each needs a rule of
its own.

Add to this to cover a variation of your own texts: a function here is
tried against every spelling the letter swaps produce, and its answers are
looked for in the analyses file like any other."
  :type '(repeat function)
  :group 'diogenes)

(defun diogenes--latin-form-variants (word)
  "Spelling variants of WORD to try in the analyses file, WORD first.
Three conventions the wordlists and the texts disagree over are applied in
turn -- i/j, u/v, and a nasal before a consonant -- so a form ambiguous on
more than one count is covered.  See `diogenes-latin-try-spelling-variants\='."
  (if (not diogenes-latin-try-spelling-variants)
      (list word)
    (let ((variants (list word)))
      (dolist (axis
	       ;; Each axis: the wholesale swap, then the positional one.
	       '((?j ?i ?i ?j diogenes--latin-vowel-p)
		 (?v ?u ?u ?v diogenes--latin-vowel-p)
		 ;; A nasal before a consonant, either way about: the cruncher
		 ;; wrote `quorumdam\=' but `quendam\='.
		 (nil nil ?n ?m diogenes--latin-consonant-p)
		 (nil nil ?m ?n diogenes--latin-consonant-p)))
	(seq-let (from to pos-from pos-to predicate) axis
	  (setq variants
		(cl-loop
		 for v in variants
		 append (append (list v)
				 (when from
				   (list (diogenes--latin-swap-letters v from to)))
				 (diogenes--latin-positional-swaps
				  v pos-from pos-to predicate))))))
      ;; The rules go last, and over everything the swaps produced, so that a
      ;; form needing both -- `exstruxit\=' typed with a u for its v, say --
      ;; is still reached.
      (dolist (rule diogenes-latin-spelling-rules)
	(setq variants
	      (append variants
		      (cl-loop for v in variants
			       append (ignore-errors (funcall rule v))))))
      (delete-dups variants))))

(defcustom diogenes-latin-expand-contractions t
  "Whether a circumflex in a Latin form is read as a contraction.
The editions the corpora print do not mark quantity, so a circumflex in
them is not decoration: it marks a contracted syllable, the vowel standing
for the two it was made from.  `desîmus' is `desiimus', `dî' is `dii'.
Non-nil reads it that way.

The distinction decides which word you are shown, because both spellings
can be keys.  `desîmus' is the syncopated perfect of `desino', while
`desimus' without the mark is a key too -- the present subjunctive of
`dēsum' -- and a text that meant that verb would not have printed the
circumflex.  Strip the mark as though it said nothing and the answer is
confidently the wrong verb.

Nil treats a circumflex like any other mark, to be removed."
  :type 'boolean
  :group 'diogenes)

(defun diogenes--latin-expand-contractions (word)
  "WORD with each circumflexed vowel written as the pair it stands for.
Returns nil when WORD carries no circumflex, so a caller can tell the
expansion from the form itself.  Works on the decomposition, so a
precomposed `î' and an `i' followed by a combining circumflex are treated
alike, and any other marks are left for `diogenes--strip-diacritics'."
  (let ((out nil)
        (found nil))
    (dolist (c (string-to-list (ucs-normalize-NFD-string (or word ""))))
      (if (= c ?\N{COMBINING CIRCUMFLEX ACCENT})
          ;; The mark says the letter just read stands for two of itself.
          (when out
            (push (car out) out)
            (setq found t))
        (push c out)))
    (and found (apply #'string (nreverse out)))))

(defun diogenes--latin-parse-candidates (word)
  "The spellings of Latin WORD to look for in the analyses file, in order.
The file is keyed by bare ASCII forms, while the corpora print what their
editors chose, so a form as printed may be no key at all.  Three spellings,
each tried only if it differs from those before it:

  WORD itself, which is the whole of the matter for an unmarked form;

  WORD with its circumflexes read as contractions -- `desîmus' as
  `desiimus', which is in the file, under `desino'.  This is the reading
  that matters, the texts marking no quantities: a circumflex in them says
  the syllable is contracted.  It comes BEFORE the stripped spelling
  because `desimus' is a key as well, for the present subjunctive of
  `dēsum', and a text meaning that verb would not have printed the mark.
  See `diogenes-latin-expand-contractions';

  WORD with every mark removed.  Last, and for two things the corpora do
  not produce: a contraction whose expansion is not a form -- `nîl' gives
  `niil', which is nothing, where the bare `nil' is a key -- and a word
  from somewhere else, typed into the minibuffer with macrons or copied
  from a dictionary headword.

Normalisation, not guesswork, so this is not one of
`diogenes-latin-spelling-rules' and not subject to
`diogenes-latin-try-spelling-variants': i-for-j is a convention two sources
disagree about, where these are the same word written as an editor prints
it and as a wordlist keys it."
  (let* ((expanded (and diogenes-latin-expand-contractions
                        (diogenes--latin-expand-contractions word)))
         (candidates (list word
                           (and expanded (diogenes--strip-diacritics expanded))
                           (diogenes--strip-diacritics word))))
    (delete-dups (delq nil candidates))))

(defun diogenes--beta-drop-capital-marker (word)
  "WORD without the leading asterisk beta code marks a capital with.
`Εὐφήμει\=' is `*eu)fh/mei\=', and the analyses file keeps proper names under the
asterisk and everything else without it -- so a word capitalised only because
it opens a sentence is looked for among the names and not found.

The asterisk sits before the letter and before its breathing, so removing it is
removing the first character; nothing else moves."
  (if (and (> (length word) 1) (eq (aref word 0) ?*))
      (substring word 1)
    word))

(defun diogenes--greek-parse-candidates (word)
  "The Greek forms to try for WORD, in order.

WORD as it stands first: nothing that parses today may stop parsing, and a
genuine proper name -- `Εὐφράτης\=', which the file really does keep under the
asterisk -- must find itself before anything else is tried.

Then, on a miss:

  * without the CAPITAL MARKER, for a word capitalised because it opens a
    sentence.  Latin has had this since Diogenes\=' own \"Fixed parsing of
    capitalized Latin words\"; Greek had not, and `Εὐφήμει\=' answered with
    `εὐφαής\=' -- the nearest name in `*eu)-\=' -- where `εὐφήμει\=' finds
    `εὐφημέω\='.  See `diogenes--beta-drop-capital-marker\='.

  * without the accent an ENCLITIC added, where the form carries more than
    one.  See `diogenes--beta-drop-extra-accents\='.

  * and without either, since a capitalised word may also carry an enclitic\='s
    accent.

`delete-dups\=' in the caller removes the repetitions this leaves when a form
needs only one of the two."
  (let* ((plain (diogenes--beta-drop-capital-marker word))
         (dropped (diogenes--beta-drop-extra-accents word))
         (both (diogenes--beta-drop-extra-accents plain)))
    (delete-dups (list word plain dropped both))))

(defun diogenes--do-parse (word lang)
  "Return the raw analyses record for WORD in LANG, or nil.
`$do_parse': the form is tried as it stands and a capitalised Latin form
is then retried in lower case -- Diogenes' \"Fixed parsing of capitalized
Latin words\".  The reshuffling of diacritics after a beta-code asterisk
that $do_parse also does for Greek capitals is not attempted here.

Beyond the application, a Latin form is also tried as a contraction and
without its diacritics (see `diogenes--latin-parse-candidates') and with j
and i exchanged (see `diogenes--latin-form-variants')."
  (let* ((word (diogenes--beta-normalize-gravis
                (diogenes--greek-ensure-beta word)))
         (variants
          (if (string= lang "latin")
              (cl-loop for base in (diogenes--latin-parse-candidates word)
                       append (diogenes--latin-form-variants base))
            ;; Greek: the form as it stands, and then without the accent an
            ;; ENCLITIC put on it.  A proparoxytone takes an extra acute on its
            ;; ultima when an enclitic follows, so the text prints
            ;; `*bria/rew/n' where the analyses file has `*bria/rewn' -- and the
            ;; search then looked for a key that cannot exist, landed on
            ;; whatever sorted next to it, and showed that entry: `Briareon'
            ;; was answered with `Briakchos'.
            ;;
            ;; The word as written stays first, so nothing that parses today
            ;; stops parsing.
            (diogenes--greek-parse-candidates word))))
    (cl-loop for variant in (delete-dups variants)
             thereis (or (diogenes--try-parse variant lang)
                         (and (string-match-p "[[:upper:]]" variant)
                              (diogenes--try-parse (downcase variant) lang))))))

(defun diogenes--choose-analysis (record dicts word)
  "Ask which lemma of RECORD to show; return its (OFFSET . CONF) alone.
Used when `diogenes-lookup-show-all-entries' is nil."
  (let* ((alist (cl-loop
		 with seen = nil
		 for a in (plist-get record :analyses)
		 for label = (format "%s (%s)"
				     (plist-get a :display)
				     (if (string-blank-p (plist-get a :trans))
					 "No translation available"
				       (plist-get a :trans)))
		 unless (member label seen)
		 collect (progn (push label seen)
				(list label
				      (plist-get a :offset)
				      (concat "\t" (plist-get a :info))))))
	 (completion-extra-properties
	  '(:annotation-function
	    (lambda (s) (caddr (assoc s minibuffer-completion-table)))))
	 (offset (if (= 1 (length alist))
		     (cadr (car alist))
		   (cadr (assoc (completing-read
				 (format "Choose a lemma for %s: " word)
				 alist)
				alist)))))
    (if offset
	(list (or (assq offset dicts) (cons offset 9)))
      dicts)))

(defcustom diogenes-latin-extra-lemmata nil
  "Forms Morpheus does not analyse, and the headword to look up instead.
An alist of (FORM . HEADWORD), consulted only when a form will not parse at
all, and before falling back on a search for the form itself.

Diogenes\=' analyses are a batch run of Morpheus over wordlists harvested
from the corpora it indexes, so a form those wordlists missed is missing
altogether -- not misspelt, which
`diogenes-latin-try-spelling-variants\=' would cover, but absent.  The gaps
are not random: `illidant\=', the present subjunctive of `illido\=', whose
fourteen other forms are all there; `aedium\=', where the wordlists have only
the rarer `aedum\='; `transilire\='.  Each parsed as nothing and fell through
to a search for itself, which found the nearest headword instead --
`illico\=', `aedon\=' the nightingale, `transilis\='.

HEADWORD is a headword, not an offset, so an entry here survives a rebuild
of the Perseus data.  Matching ignores case and the spelling conventions,
so one entry answers for `ualdissime\=' as well as `valdissime\='.

Consulted AFTER the parse, never instead of it: a form Morpheus does know
keeps its own analysis, and an entry here for such a form is simply never
reached.  A serious accumulation of these is an argument for running
Morpheus itself over the form -- it generates paradigms rather than
harvesting a corpus -- rather than for a longer alist."
  :type '(alist :key-type (string :tag "Form")
		:value-type (string :tag "Headword"))
  :group 'diogenes)

(defcustom diogenes-greek-extra-lemmata nil
  "Greek forms the wordlists have no analysis for, and the headword to show.
An alist of (FORM . HEADWORD), as `diogenes-latin-extra-lemmata\=' is for Latin:

    (setq diogenes-greek-extra-lemmata
          \='((\"οὑτοσί\" . \"οὗτος\")
            (\"ταὐτόν\"  . \"αὐτός\")))

Consulted only when the analyses file has nothing at all for the form, so it
adds and never overrides.  Accents and breathings are compared as the rest of
the Greek lookup compares them, so an entry written unaccented answers for the
accented form.

Deictic and crasis forms are what this is mostly for: the wordlists carry the
plain word and not `οὑτοσί\=', and Morpheus does not always oblige."
  :type '(alist :key-type (string :tag "Form")
                :value-type (string :tag "Headword"))
  :group 'diogenes)

(defcustom diogenes-greek-analysis-corrections nil
  "Greek analyses the shipped data gets wrong, and what to say instead.
Keyed by the form, as `diogenes-latin-analysis-corrections\=' is for Latin, and
taking the same three keys:

  :info STRING     -- the morphology to print instead
  :lemma STRING    -- the headword, and the entry the dictionary keys open
  :add ENTRIES     -- ((LEMMA . INFO) ...), readings to show as well

    (setq diogenes-greek-analysis-corrections
          \='((\"ᾖ\" :info \"pres subj act 3rd sg\")))

The Greek data is wrong more often than the Latin, not less: Morpheus knows
less of it, and the LSJ keys some headwords differently from the form Morpheus
gives.  A reader who has worked out what a form actually is should be able to
record it."
  :type '(alist :key-type (string :tag "Form") :value-type plist)
  :group 'diogenes)

(defun diogenes--extra-lemmata-for (lang)
  "The extra-lemmata table for LANG."
  (if (string= lang "greek")
      diogenes-greek-extra-lemmata
    diogenes-latin-extra-lemmata))

(defun diogenes--analysis-corrections-for (lang)
  "The corrections table for LANG."
  (if (string= lang "greek")
      diogenes-greek-analysis-corrections
    diogenes-latin-analysis-corrections))

(defun diogenes--extra-lemma (word lang)
  "The headword the extra-lemmata table for LANG gives WORD, or nil.
Latin tries every spelling variant, so an entry written with v and j answers
for the form written with u and i; Greek compares the form as it stands and
again stripped of its accents, so an entry written unaccented answers for the
accented word."
  (let ((table (diogenes--extra-lemmata-for lang)))
    (when table
      (cl-loop for variant in (if (string= lang "greek")
                                  (list word (diogenes--ascii-alpha-only word))
                                (diogenes--latin-form-variants word))
               thereis (cdr (assoc-string variant table t))))))

(defun diogenes--latin-extra-lemma (word)
  "The headword `diogenes-latin-extra-lemmata\=' gives for WORD, or nil.
Every spelling variant of WORD is tried, so an entry written with v and j
also answers for the form written with u and i."
  (cl-loop for variant in (diogenes--latin-form-variants word)
	   thereis (cdr (assoc-string variant
				    diogenes-latin-extra-lemmata t))))

(defcustom diogenes-latin-mark-corrections t
  "Whether a corrected analysis is marked as corrected.
Non-nil appends \" [corr.]\" to any morphology that
`diogenes-latin-analysis-corrections' has altered or added, so that what
you are reading is never silently other than what the shipped data says.
Nil prints the correction as though it came from the file."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-latin-analysis-corrections nil
  "Corrections to the morphology the analyses file records for a Latin form.
An alist of (FORM . PLIST).  FORM is the form as `latin-analyses.txt' keys
it -- bare ASCII, which is what a contraction or an accented spelling has
been resolved to by the time this is consulted.  PLIST takes:

  :info STRING     -- the morphology to print instead, for every analysis
                      of FORM.
  :info ALIST      -- ((OLD . NEW) ...), replacing only the analyses whose
                      morphology is OLD.  For a form with several analyses
                      of which one is wrong.
  :lemma STRING    -- the headword to print instead, for every analysis of
                      FORM.  Where Morpheus has the morphology of one word
                      and the lemma of another: `superstite' is the ablative
                      of `superstes', analysed from `super-sto'.  The entry
                      the dictionary keys open follows the corrected lemma,
                      the file's byte offset being dropped with it.
  :add ENTRIES     -- ((LEMMA . INFO) ...), further analyses to show after
                      those the file gives.  LEMMA nil means the lemma the
                      file already names, so a missing reading of the same
                      word is added without repeating its headword; a
                      string is a headword, whose entry is fetched and
                      shown alongside.

For example, where the batch run of Morpheus over the wordlists labels the
deponent's imperative an active infinitive:

    (setq diogenes-latin-analysis-corrections
          \\='((\"experire\" :info \"pres imperat pass 2nd sg\")))

or, where both the lemma and the morphology are wrong:

    (setq diogenes-latin-analysis-corrections
          \\='((\"superstite\" :lemma \"superstes\" :info \"abl sg\")))

or, to keep the file's reading and add the missing one:

    (setq diogenes-latin-analysis-corrections
          \\='((\"experire\" :add ((nil . \"pres imperat pass 2nd sg\")))))

This is for a form the file analyses WRONGLY.  A form it does not analyse
at all is `diogenes-latin-extra-lemmata'; a form whose spelling the file
does not use is normalised before it gets here -- see
`diogenes--latin-parse-candidates' -- and neither is a correction.

A long list here is an argument for reporting the analyses upstream rather
than for maintaining it: the data is a batch run of Morpheus, so a
systematic error in it is one error, not a hundred."
  :type '(alist :key-type (string :tag "Form")
                :value-type (sexp :tag "Plist"))
  :group 'diogenes)

(defun diogenes--analysis-correction (form lang)
  "The correction plist for FORM in LANG, or nil.
The Greek and Latin tables are read the same way; only the table differs."
  (let ((table (diogenes--analysis-corrections-for lang)))
    (and table
         (cl-loop for variant in (if (string= lang "greek")
                                     (list form (diogenes--ascii-alpha-only form))
                                   (diogenes--latin-form-variants form))
                  thereis (cdr (assoc-string variant table t))))))

(defun diogenes--latin-analysis-correction (form)
  "The correction plist `diogenes-latin-analysis-corrections' gives FORM.
Every spelling variant is tried, so an entry written with v and j answers
for the form written with u and i."
  (and diogenes-latin-analysis-corrections
       (cl-loop for variant in (diogenes--latin-form-variants form)
                thereis (cdr (assoc-string
                              variant diogenes-latin-analysis-corrections t)))))

(defun diogenes--mark-correction (info)
  "INFO marked as corrected, if `diogenes-latin-mark-corrections' says so."
  (if diogenes-latin-mark-corrections
      (concat info " [corr.]")
    info))

(defun diogenes--corrected-info (info spec)
  "INFO as SPEC would have it: SPEC itself, its alist entry, or INFO."
  (cond ((stringp spec) spec)
        ((consp spec) (or (cdr (assoc-string info spec t)) info))
        (t info)))

(defun diogenes--added-analysis (lemma info model lang)
  "An analysis of LEMMA reading INFO, shaped like the file's own.
LEMMA nil takes the lemma and the byte offset of MODEL, the analysis the
file gave, so a missing reading of the same word costs no lookup and lands
on the same entry.  A LEMMA given is resolved against the dictionary's own
keys, as `diogenes--morpheus-analyses' resolves one: found, it carries that
offset and a confidence of 5; not found, 0, which prints the caveat about
the headword being a guess."
  (if (null lemma)
      (list :offset (or (plist-get model :offset) 0)
            :conf (or (plist-get model :conf) 5)
            :lemma (plist-get model :lemma)
            :display (plist-get model :display)
            :trans ""
            :info (diogenes--mark-correction info))
    (let ((offset (diogenes--dict-exact-offset
                   (diogenes--ascii-alpha-only lemma) lang)))
      (list :offset (or offset 0)
            :conf (if offset 5 0)
            :lemma lemma
            :display (diogenes--munge-ls-lemma lemma lang)
            :trans ""
            :info (diogenes--mark-correction info)))))

(defun diogenes--correct-analyses (form analyses lang)
  "ANALYSES of FORM, with `diogenes-latin-analysis-corrections' applied.
Returns ANALYSES unchanged when there is no entry for FORM, which is the
usual case and costs one `assoc-string' per lookup.  Either language: the
table is `diogenes-latin-analysis-corrections' or
`diogenes-greek-analysis-corrections' according to LANG."
  (let ((spec (diogenes--analysis-correction form lang)))
    (if (null spec)
        analyses
      (let ((info-spec (plist-get spec :info))
            (lemma-spec (plist-get spec :lemma))
            (model (car analyses)))
        (append
         (mapcar (lambda (analysis)
                   (let* ((old (plist-get analysis :info))
                          (new (diogenes--corrected-info old info-spec))
                          (analysis (if (equal old new)
                                        analysis
                                      (plist-put (copy-sequence analysis) :info
                                                 (diogenes--mark-correction new)))))
                     ;; A corrected LEMMA is the headword the reader has
                     ;; supplied, so its ENTRY is found the way a Morpheus
                     ;; lemma's is -- by name among the dictionary's keys, and
                     ;; under the assimilated spellings if it is a compound.
                     ;; See `diogenes--morpheus-analyses'.
                     ;;
                     ;; Three fields and not one.  `:display' is what is
                     ;; printed, `:lemma' what the assimilation machinery
                     ;; reads, and `:offset' where the entry begins.  Setting
                     ;; only `:lemma' left the wrong headword on the screen;
                     ;; setting the offset to 0 opened byte 0 of the file,
                     ;; which is the entry for the letter A.
                     (if (not lemma-spec)
                         analysis
                       (let* ((plain (diogenes--ascii-alpha-only lemma-spec))
                              ;; A correction must not signal: the dictionary
                              ;; may not be searchable at all -- `diogenes-path'
                              ;; unset, the file absent -- and a reader who has
                              ;; named a better headword should still see it,
                              ;; with the caveat that its entry is a guess.
                              (offset
                               (ignore-errors
                                 (or (diogenes--dict-exact-offset plain lang)
                                     (diogenes--assimilated-offset lemma-spec
                                                                   lang))))
                              (shown (diogenes--mark-correction lemma-spec))
                              (copy (copy-sequence analysis)))
                         (setq copy (plist-put copy :lemma lemma-spec))
                         (setq copy (plist-put copy :display shown))
                         ;; A confidence of 5 where the entry was found, and 0
                         ;; where it was not -- which prints the caveat about
                         ;; the headword being a guess rather than pretending
                         ;; to an entry it has not got.
                         (setq copy (plist-put copy :conf (if offset 5 0)))
                         (plist-put copy :offset
                                    (or offset
                                        (plist-get analysis :offset)))))))
                 analyses)
         (cl-loop for (lemma . info) in (plist-get spec :add)
                  collect (diogenes--added-analysis lemma info model lang)))))))


;;; Morpheus as a fallback
;;
;; Diogenes' analyses are a batch run of Morpheus over wordlists harvested
;; from the corpora it indexes, so a form those wordlists never saw is not
;; misspelt but absent -- `transilire', `illidant', `aedium', while their
;; sibling forms are all present.  Morpheus itself generates paradigms from
;; stems and knows them.  If a build of it is to hand, asking it is better
;; than falling back on a search for a form that is nobody's headword.
;;
;; Second, and not first.  The shipped data has two things Morpheus does not:
;; the BYTE OFFSET of the dictionary entry, resolved at build time through
;; `index_lewis.pl''s key index, and the short gloss.  A Morpheus lemma is a
;; string, so its entry has to be found by name -- which is exactly the
;; unreliable path.  Diogenes' own analyses are therefore always preferred,
;; and Morpheus asked only where they have nothing.
;;
;; It also emits the same hyphenated compounds the shipped data does --
;; `in-mitto', `con-pello', flagged `raw_preverb' -- so its lemmas go through
;; `diogenes--assimilated-offset' like any other.  And it is fast: 2.7 ms for
;; one word, startup included, so a process per lookup is simpler than
;; keeping one alive and costs nothing measurable.

(defcustom diogenes-morpheus-directory nil
  "Directory of a built Morpheus, or nil not to use one.
Must hold `bin/cruncher' and `stemlib/', which is how the tree is laid out
by

    git clone https://github.com/VictorSousa92/morpheus
    cd morpheus/src && make CC=\"gcc -std=gnu17 -fpermissive\" && make install
    cd ../stemlib/Latin && env PATH=\"$PWD/../../bin:$PATH\" MORPHLIB=\"$PWD/..\" make

That fork is the one this was tested against, and the recommended one: its
stems are more complete, so it answers for forms another build declines.

Nothing here requires it.  Any Morpheus laid out the same way is run the
same way -- the cruncher reading forms from stdin, `-L' for Latin, MORPHLIB
naming `stemlib' -- and two things have to hold of whichever is used.  Its
output must carry the `<NL>...</NL>' wrappers the parser reads (see
`diogenes--morpheus-analysis-re'), and it must spell a lemma as Lewis & Short
keys it, since Morpheus has no notion of where an entry sits in a file and
the lemma is resolved against the dictionary's own keys.  Beyond the initial
`j' that `diogenes-latin-fold-letters' folds and the prefixes
`diogenes-latin-assimilate-prefixes' assimilates, a lemma spelt otherwise
gets a confidence of 0 and the caveat about the headword being a guess,
rather than a wrong entry.

Consulted only when a form will not parse from the shipped data, so an
installation without this set behaves as before."
  :type '(choice (const :tag "Do not use Morpheus" nil) directory)
  :group 'diogenes)

(defcustom diogenes-morpheus-timeout 10
  "Seconds to wait for Morpheus before giving up on a form."
  :type 'natnum
  :group 'diogenes)

(defun diogenes-morpheus-available-p ()
  "Whether `diogenes-morpheus-directory' holds a usable Morpheus."
  (and diogenes-morpheus-directory
       (let ((bin (expand-file-name "bin/cruncher"
				    diogenes-morpheus-directory))
	     (lib (expand-file-name "stemlib" diogenes-morpheus-directory)))
	 (and (file-executable-p bin) (file-directory-p lib)))))

(defun diogenes--morpheus-run (word lang)
  "Ask Morpheus about WORD in LANG; return its raw output, or nil.
The cruncher reads forms from stdin, one per line, and wants beta code for
Greek -- which is what it gets, `diogenes--do-parse' having converted the
form already.  MORPHLIB must name the `stemlib' directory itself, not its
parent: the cruncher appends the language to it."
  (when (diogenes-morpheus-available-p)
    (let* ((dir (file-name-as-directory
		 (expand-file-name diogenes-morpheus-directory)))
	   (process-environment
	    (cons (concat "MORPHLIB=" dir "stemlib") process-environment))
	   (args (append (when (string= lang "latin") '("-L"))
			 nil)))
      (with-temp-buffer
	(let ((exit (condition-case err
			(apply #'call-process-region
			       (concat word "\n") nil
			       (concat dir "bin/cruncher")
			       nil t nil args)
		      (error (message "Morpheus: %s" (error-message-string err))
			     nil))))
	  (when (and exit (or (eq exit 0) (integerp exit)))
	    (buffer-string)))))))

(defconst diogenes--morpheus-analysis-re
  "<NL>\\([^<]*\\)</NL>"
  "One analysis in Morpheus' output.
The cruncher answers with the form, then its analyses run together:

  <NL>V transi^li_re,transilio  pres inf act\t\t\tconj4,ire_vb</NL>

which is part of speech, then form and lemma, then the morphology, then
dialect and stem-class fields separated by tabs.")

(defcustom diogenes-morpheus-lemma-markers
  '(("pl" . "lemma listed under the plural")
    ("dual" . "lemma listed under the dual")
    ("indecl" . "indeclinable"))
  "What Morpheus\=' lemma markers mean, as (MARKER . WHAT-TO-SAY).
Morpheus spells some lemmata with a marker after a hyphen -- `*bria/rews-pl\=' is
Briareus, listed under the plural -- and the marker is no part of the name: left
on, it is asked of the dictionary, matches no headword, and the search falls to
whatever sorts first.

So it is taken off the lemma and said in words beside the morphology.  A marker
not listed here is shown as it stands, which is better than dropping it and
better than pretending to translate it."
  :type '(alist :key-type (string :tag "Marker")
                :value-type (string :tag "What to say"))
  :group 'diogenes)

(defun diogenes--morpheus-lemma-marker (lemma)
  "The marker at the end of LEMMA, or nil.
Only what `diogenes-morpheus-lemma-markers\=' names.  A hyphen in a Morpheus
lemma is usually a COMPOUND -- `a)mfi/-pla/ssw\=' is one word -- so a rule that
took whatever followed the last hyphen would cut real lemmata in half wherever
the second element happened to carry no accent.  Nothing comes off unless it is
known to be a marker."
  (when (and lemma (string-match-p "-" lemma))
    (let ((tail (car (last (split-string lemma "-")))))
      (and (assoc tail diogenes-morpheus-lemma-markers) tail))))

(defun diogenes--morpheus-parse-output (output lang)
  "Turn Morpheus' OUTPUT into analyses shaped like an analyses record's.
Each is a plist (:offset :conf :lemma :display :trans :info), the same
shape `diogenes--parse-analyses-record' produces, so that everything
downstream -- the stacking, the notes, the homograph sweep, navigation --
works on it unchanged.

:offset is filled in later by `diogenes--morpheus-analyses': the lemma has
to be resolved against the dictionary's own keys, Morpheus having no notion
of where an entry sits in a file.  :trans is empty, Morpheus giving no
glosses."
  (let ((pos 0) out)
    (while (string-match diogenes--morpheus-analysis-re (or output "") pos)
      (setq pos (match-end 0))
      (let* ((body (match-string 1 output))
	     (fields (split-string body "\t" nil))
	     (head (string-trim (or (car fields) "")))
	     ;; "V transi^li_re,transilio  pres inf act"
	     (parts (split-string head "[[:space:]]\\{2,\\}" t))
	     (lemma-field (string-trim (or (car parts) "")))
	     (info (string-join (cdr parts) " "))
	     ;; Drop the part-of-speech letter that opens the field.
	     (lemma-field (if (string-match "\\`[A-Z] +" lemma-field)
			      (substring lemma-field (match-end 0))
			    lemma-field))
	     ;; "form,lemma" -- the lemma is what follows the comma, as
	     ;; make_latin_analyses.pl also takes it.
	     (lemma (if (string-match "," lemma-field)
			(substring lemma-field (match-end 0))
		      lemma-field))
	     ;; And Morpheus marks some lemmata: `*bria/rews-pl' is Briareus
	     ;; listed under the plural.  The marker is no part of the name, so
	     ;; it cannot stay on a string that will be asked of a dictionary --
	     ;; `Briareos-pl' matches no headword, and the search fell to the
	     ;; dictionary's first entry with a note that it had found nothing.
	     (marker (diogenes--morpheus-lemma-marker lemma))
	     (lemma (if marker
			(substring lemma 0 (- (length lemma) (length marker) 1))
		      lemma))
	     (extra (string-join
		     (seq-remove #'string-empty-p
				 (mapcar #'string-trim (cdr fields)))
		     " "))
	     ;; The marker is not discarded: that the lemma is listed under the
	     ;; plural is worth a reader's knowing, and LSJ has such headwords.
	     ;; It goes where Morpheus' other remarks go.
	     (info (if marker
		       (concat info " ("
			       (or (cdr (assoc marker
					       diogenes-morpheus-lemma-markers))
				   marker)
			       ")")
		     info)))
	(when (and lemma (not (string-empty-p lemma)))
	  (push (list :offset 0
		      :conf 5
		      :lemma lemma
		      :display (diogenes--munge-ls-lemma lemma lang)
		      :trans ""
		      :info (string-trim
			     (concat info (if (string-empty-p extra)
					      ""
					    (concat " [" extra "]")))))
		out))))
    (nreverse out)))

(defun diogenes--morpheus-analyses (word lang)
  "Analyses of WORD from Morpheus, with their entries resolved, or nil.
A lemma is looked for among the dictionary's keys as it stands and, being
possibly a hyphenated compound, under its assimilated spellings as well.
An analysis whose lemma is found carries that offset and a confidence of 5;
one whose lemma is not carries 0, which prints the caveat about the headword
being a guess -- the morphology is worth showing either way, and it is more
than the alternative of an unrelated entry and no analysis at all."
  (let ((analyses (diogenes--morpheus-parse-output
		   (diogenes--morpheus-run word lang) lang)))
    (cl-loop
     for a in analyses
     for lemma = (plist-get a :lemma)
     for plain = (diogenes--ascii-alpha-only lemma)
     for offset = (or (diogenes--dict-exact-offset plain lang)
		      (diogenes--assimilated-offset lemma lang))
     collect (plist-put (plist-put (copy-sequence a) :offset (or offset 0))
			:conf (if offset 5 0)))))

(defun diogenes--parse-and-lookup (word lang)
  "Try to parse a word by looking it up in the morphological files,
and show the entry for it in the lexica. Dispatcher function.

A port of `$do_parse' followed by `$format_analysis': every entry named
in the analyses record is fetched from the byte offset recorded there.
Only a form that will not parse falls back on searching the dictionary by
headword, exactly as the application does."
  (let* ((raw (diogenes--do-parse word lang))
	 (extra (diogenes--extra-lemma word lang))
	 ;; Only where the shipped data has nothing: its offsets and glosses
	 ;; are better than anything that can be recovered from a lemma.
	 (morpheus (and (not raw) (not extra)
			(diogenes-morpheus-available-p)
			(diogenes--morpheus-analyses word lang))))
    (if (not raw)
	(cond
	 (morpheus
	  (let* ((record (list :analyses morpheus :suppl nil))
		 (dicts (diogenes--analyses-dicts record)))
	    (message "%s does not parse; analysed by Morpheus" word)
	    (let ((buffer (diogenes--show-analysis-entries
			   (diogenes--drop-suffix-analyses
			    record
			    (diogenes--expand-uncertain-dicts record dicts lang)
			    lang)
			   lang)))
	      (when diogenes-lookup-show-analysis
		(with-current-buffer buffer
		  (diogenes--lookup-insert-at-top
		   (diogenes--format-analysis-header word lang record))
		  (goto-char (point-min))))
	      buffer)))
	 ;; A form the wordlists never had.  The headword is known, even
	 ;; though the analysis is not, so show its entry rather than
	 ;; whatever happens to sort next to the form.
	 (extra
	  (message "%s does not parse; showing %s" word extra)
	  (diogenes--lookup-dict extra lang))
	 (t
	  (message "No results for %s, trying to look it up in the dictionaries!"
		   word)
	  (diogenes--lookup-dict word lang)))
      (let* ((record (diogenes--parse-analyses-record raw lang))
	     (dicts (diogenes--analyses-dicts record)))
	(if (null dicts)
	    (progn
	      (message "No dictionary entry for %s; searching by headword" word)
	      (diogenes--lookup-dict word lang))
	  (let ((buffer (diogenes--show-analysis-entries
			 (diogenes--drop-suffix-analyses
			  record
			  (if diogenes-lookup-show-all-entries
			      (diogenes--expand-uncertain-dicts record dicts lang)
			    (diogenes--choose-analysis record dicts word))
			  lang)
			 lang)))
	    (when diogenes-lookup-show-analysis
	      (with-current-buffer buffer
		(diogenes--lookup-insert-at-top
		 (diogenes--format-analysis-header word lang record))
		(goto-char (point-min))))
	    buffer))))))

(defun diogenes--add-parse-entry ()
  "Get or create an Diogenes Analysis buffer, and begin a new entry."
  ;; `morphology' and not `lookup': an analysis is not an entry, and displaying
  ;; it as one made it replace whatever entry the reader was consulting -- which
  ;; is the entry they wanted the analysis alongside.
  (diogenes--display-buffer (get-buffer-create "*Diogenes Analysis*")
			    :kind 'morphology)
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
    (diogenes--display-buffer (get-buffer-create "*Diogenes Forms*")
			      :kind 'morphology)
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
     (diogenes--display-buffer (get-buffer-create "*Diogenes Forms*")
			      :kind 'morphology)
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
  (let* ((action (get-text-property char 'action))
         ;; A link to a dictionary carries that dictionary's id, and the
         ;; registry knows what to run: one clause instead of the fifteen
         ;; that had to be added to, by hand, whenever a dictionary was.
         (dictionary (diogenes--lookup-dictionary action)))
    (if dictionary
        (funcall (plist-get dictionary :command)
                 (get-text-property char 'headword))
      (cl-case action
      (bibl (apply #'diogenes--browse-work (diogenes--lookup-parse-bibl-string
					    (get-text-property char 'bibl))))
      ;; The `lemma-nr' property is the byte offset of the entry in the
      ;; dictionary -- the first field of the analyses record, or the second
      ;; of a lemmata record, where make_latin_lemmata.pl writes 0 for "no
      ;; entry".  Seek to it when there is one; the headword search is only
      ;; the fallback (see `diogenes--search-dict' on why it cannot be
      ;; trusted for Latin j-lemmata).
      (lookup (let ((offset (diogenes--dict-offset
			     (get-text-property char 'lemma-nr)))
		    (lang (get-text-property char 'lang)))
		(if offset
		    (diogenes--lookup-dict-offset offset lang)
		  (diogenes--lookup-dict (get-text-property char 'lemma)
					 lang))))
      (forms (diogenes--show-all-forms (get-text-property char 'lemma)
				       (get-text-property char 'lang)))
      (t (let* ((lang (diogenes--language-at-point char))
		(word (diogenes--word-at-point-for-lookup)))
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
		(diogenes--parse-and-lookup (or word (diogenes--word-at-point-for-lookup)) lang)))
	     (_ (message "C-c C-c cannot do anything useful here!")))))))))

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
