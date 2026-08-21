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
(declare-function diogenes-lookup-open-bailly "diogenes-bailly" (&optional word))
(declare-function diogenes-lookup-gaffiot "diogenes-gaffiot" (&optional word))
(declare-function diogenes-gaffiot-lookup-buffer-p "diogenes-gaffiot" ())
(declare-function diogenes-lookup-open-gaffiot-pdf "diogenes-gaffiot-pdf"
                  (&optional word))
(declare-function diogenes-lookup-open-georges "diogenes-georges" (&optional word))
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
	   (formatted (diogenes--dict-parse-xml xml start end))
	   (lookup-buffer (diogenes--get-fresh-buffer "lookup")))
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
      (if (featurep 'diogenes-purpose)
          ;; --- diogenes-purpose active: mode before display ---
          (progn
            (with-current-buffer lookup-buffer
              (diogenes-lookup-mode))
            (if diogenes--lookup-same-window
                (pop-to-buffer-same-window lookup-buffer)
              (pop-to-buffer lookup-buffer)))
        ;; --- otherwise: the original order, unchanged ---
        (if diogenes--lookup-same-window
            (pop-to-buffer-same-window lookup-buffer)
          (pop-to-buffer lookup-buffer))
        (diogenes-lookup-mode))
      (setq diogenes--lookup-file (or file (diogenes--dict-file lang))
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
	(diogenes--lookup-insert-entry-links lang))
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

(cl-defun diogenes-lookup-register-dictionary
    (id &key name lang key command help (show 'always) buffer-p of
             available-p (order 50) bind)
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

  `always'         -- a print dictionary: always offered, and it explains
                     itself when pressed if its path variable is unset.
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
for the dictionary to be offered at all -- for a PDF companion that has no
PDF configured, where an unset path is a reason to hide the link rather
than to explain it.

ORDER sorts the banner, low to high; the shipped dictionaries leave gaps to
sort between.  BIND, if non-nil, binds KEY to COMMAND in
`diogenes-lookup-mode-map'.  A key that must serve both languages cannot be
bound this way -- it needs a command that dispatches on
`diogenes--lookup-lang', as `diogenes-lookup-pape-or-gaffiot-pdf' does --
so such modules leave BIND nil and bind the key themselves."
  (let ((entry (list :id id :name name :lang lang :key key
                     :command command :help help :show show
                     :buffer-p buffer-p :of of
                     :available-p available-p :order order)))
    (setq diogenes--lookup-dictionaries
          (append (cl-remove id diogenes--lookup-dictionaries
                             :key (lambda (e) (plist-get e :id)))
                  (list entry)))
    (when (and bind key command (boundp 'diogenes-lookup-mode-map))
      (keymap-set diogenes-lookup-mode-map key command))
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
  (dolist (entry diogenes--lookup-dictionaries)
    (let ((key (plist-get entry :key))
          (command (plist-get entry :command)))
      (when (and (plist-get entry :bind) key command)
        (keymap-set diogenes-lookup-mode-map key command)))))

(defun diogenes--lookup-dict-in-buffer-p (id)
  "Non-nil if the current lookup buffer is showing dictionary ID.
Asks that dictionary's own BUFFER-P predicate, which knows how to
recognise itself -- usually by comparing `diogenes--lookup-file' with the
dictionary it converted."
  (let* ((entry (diogenes--lookup-dictionary id))
         (predicate (and entry (plist-get entry :buffer-p))))
    (and predicate (funcall predicate) t)))

(defun diogenes--lookup-dict-visible-p (entry)
  "Non-nil if ENTRY should be offered on the entry now on screen.
See `diogenes-lookup-register-dictionary' for what the SHOW values mean."
  (let ((available (plist-get entry :available-p)))
    (and (or (null available) (funcall available))
         (pcase (plist-get entry :show)
           ('always t)
           ('unless-current
            (let ((predicate (plist-get entry :buffer-p)))
              (not (and predicate (funcall predicate)))))
           ('when-current
            (diogenes--lookup-dict-in-buffer-p (plist-get entry :of)))
           (_ t)))))

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
              (list (plist-get e :name) (plist-get e :key)
                    (plist-get e :id) (plist-get e :help)))
            (sort entries (lambda (a b) (< (plist-get a :order)
                                           (plist-get b :order)))))))

(defun diogenes--lookup-register-shipped-dictionaries ()
  "Register the dictionaries that come with Diogenes itself.
The print dictionaries, whose modules only open a PDF and have nothing else
to say here, and the two dictionaries Diogenes searches by default -- the
LSJ and Lewis & Short -- which are the way back from any other dictionary
of their language.  Everything else registers itself: see
`diogenes-gaffiot.el', `diogenes-pape.el' and `diogenes-bailly.el'."
  ;; Greek, print
  (diogenes-lookup-register-dictionary
   'montanari :lang "greek" :name "Montanari" :key "m" :order 10
   :command #'diogenes-lookup-open-montanari
   :help "Open Montanari at \"%s\"")
  (diogenes-lookup-register-dictionary
   'cambridge :lang "greek" :name "CGL" :key "c" :order 20
   :command #'diogenes-lookup-open-cambridge
   :help "Open the Cambridge Greek Lexicon at \"%s\"")
  (diogenes-lookup-register-dictionary
   'bdag :lang "greek" :name "BDAG" :key "b" :order 30
   :command #'diogenes-lookup-open-bdag
   :help "Open BDAG (Bauer) at \"%s\"")
  (diogenes-lookup-register-dictionary
   'passow :lang "greek" :name "Passow" :key "p" :order 40
   :command #'diogenes-lookup-open-passow
   :help "Open Passow at \"%s\"")
  (diogenes-lookup-register-dictionary
   'tgl :lang "greek" :name "TGL" :key "t" :order 50
   :command #'diogenes-lookup-open-tgl
   :help "Open Estienne's Thesaurus Graecae Linguae at \"%s\"")
  ;; Latin, print
  (diogenes-lookup-register-dictionary
   'old :lang "latin" :name "OLD" :key "o" :order 10
   :command #'diogenes-lookup-open-old
   :help "Open the OLD at \"%s\"")
  (diogenes-lookup-register-dictionary
   'tll :lang "latin" :name "TLL" :key "t" :order 20
   :command #'diogenes-lookup-open-tll
   :help "Open the TLL at \"%s\"")
  (diogenes-lookup-register-dictionary
   'georges :lang "latin" :name "Georges" :key "G" :order 30
   :command #'diogenes-lookup-open-georges
   :help "Open Georges at \"%s\"")
  ;; Lewis & Short: the way back to the Latin dictionary Diogenes searches
  ;; by default, so offered in any Latin entry that is not itself one.
  (diogenes-lookup-register-dictionary
   'lewis :lang "latin" :name "Lewis & Short" :key "l" :order 70
   :command #'diogenes-lookup-lewis
   :show 'unless-current
   :buffer-p #'diogenes--lookup-own-dictionary-p
   :help "Show Lewis & Short's entry for \"%s\""))

(diogenes--lookup-register-shipped-dictionaries)


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
entry carries its own banner.  A link is only useful when its dictionary's
path variable is set (`diogenes-old-pdf-file', `diogenes-tll-pdf-directory',
`diogenes-georges-directory', `diogenes-gaffiot-file',
`diogenes-gaffiot-pdf-file', `diogenes-montanari-pdf-file',
`diogenes-cambridge-pdf-file', `diogenes-bdag-pdf-file',
`diogenes-bailly-pdf-file', `diogenes-passow-directory',
`diogenes-tgl-directory'); each says how to set it when pressed."
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

(defun diogenes--lookup-current-headword ()
  "Return the headword of the entry point is in, for the lookup commands."
  (or (diogenes--lookup-headword-at-point)
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

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
    (keymap-set map "g"                             #'diogenes-lookup-gaffiot)
    (keymap-set map "l"                             #'diogenes-lookup-lewis)
    (keymap-set map "P"                             #'diogenes-lookup-open-gaffiot-pdf)
    (keymap-set map "G"                             #'diogenes-lookup-open-georges)
    (keymap-set map "p"                             #'diogenes-lookup-open-passow)
    ;; `B' is bound by `diogenes-bailly.el', which registers itself with
    ;; :bind t -- as any dictionary module may.
    (keymap-set map "q"                             #'diogenes--quit)
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
					   #'diogenes--c-sort-function
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
merged; grouping is `diogenes--analyses-dicts''s job."
  (let* ((str (decode-coding-string encoded-str 'utf-8))
	 (body (or (cadr (diogenes--split-once "\t+" str)) ""))
	 (pos 0)
	 analyses suppl)
    (while (string-match diogenes--analysis-group-re body pos)
      (let ((group (match-string 1 body))
	    (extra (match-string 2 body)))
	(setq pos (match-end 0))
	(if (not (string-match diogenes--analysis-fields-re group))
	    (message "Diogenes: bad analysis: %s" group)
	  (push (list :offset (string-to-number (match-string 1 group))
		      :conf (string-to-number (match-string 2 group))
		      :lemma (match-string 3 group)
		      :display (diogenes--munge-ls-lemma
				(match-string 3 group) lang)
		      :trans (string-trim (match-string 4 group))
		      :info (string-trim (match-string 5 group)))
		analyses))
	(let ((p 0))
	  (while (string-match "\\[\\([0-9]+\\)\\]" extra p)
	    (push (string-to-number (match-string 1 extra)) suppl)
	    (setq p (match-end 0))))))
    (list :analyses (nreverse analyses)
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
    (setq diogenes--lookup-bufend end)
    (goto-char (point-max))
    (diogenes--lookup-print-separator)
    (when note
      (insert (propertize (concat note "\n\n") 'font-lock-face 'italic)))
    (let ((entry-start (point)))
      (if formatted
	  (diogenes--lookup-insert-and-format formatted)
	(diogenes--lookup-insert-xml xml start end (current-buffer)))
      (diogenes--lookup-insert-entry-links diogenes--lookup-lang entry-start))))

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

(defun diogenes--latin-assimilations (lemma)
  "The spellings a hyphenated LEMMA might be keyed under, likeliest first.
`in-mitto\=' gives `immitto\=' and `inmitto\='; `con-pello\=' gives `compello\=',
`conpello\=' and `coppello\='; `con-eo\=' gives `coeo\='.  Nothing is decided
here -- every candidate is offered, and `diogenes--assimilated-offset\=' keeps
whichever the dictionary actually has."
  (let* ((clean (replace-regexp-in-string
		 "[_^+]" ""
		 (replace-regexp-in-string "#?[0-9]+\\'" "" lemma)))
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
	(nreverse (delete-dups candidates))))))

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

(defun diogenes--latin-form-variants (word)
  "Spelling variants of WORD to try in the analyses file, WORD first.
The Latin wordlists Morpheus was run over spell consonantal i as i, so a
form typed or copied with j -- `jacio\\=', `jactatus\\=' -- is not a key in
`latin-analyses.txt\\=' at all, and the parse would fail and fall through to
a headword search.  Swapping j for i (and, for a form taken from a text
that prints the classical spelling, i for j) gives it a second chance.
Only initial and intervocalic positions could bear a consonantal i, but
trying the whole word costs one more binary search and misses nothing."
  (delete-dups
   (list word
	 (replace-regexp-in-string "j" "i" (replace-regexp-in-string "J" "I" word))
	 (replace-regexp-in-string "i" "j" word))))

(defun diogenes--do-parse (word lang)
  "Return the raw analyses record for WORD in LANG, or nil.
`$do_parse': the form is tried as it stands and a capitalised Latin form
is then retried in lower case -- Diogenes' \"Fixed parsing of capitalized
Latin words\".  The reshuffling of diacritics after a beta-code asterisk
that $do_parse also does for Greek capitals is not attempted here.

Beyond the application, a Latin form is also tried with j and i exchanged;
see `diogenes--latin-form-variants'."
  (let ((word (diogenes--beta-normalize-gravis
	       (diogenes--greek-ensure-beta word))))
    (cl-loop for variant in (if (string= lang "latin")
				(diogenes--latin-form-variants word)
			      (list word))
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

(defun diogenes--parse-and-lookup (word lang)
  "Try to parse a word by looking it up in the morphological files,
and show the entry for it in the lexica. Dispatcher function.

A port of `$do_parse' followed by `$format_analysis': every entry named
in the analyses record is fetched from the byte offset recorded there.
Only a form that will not parse falls back on searching the dictionary by
headword, exactly as the application does."
  (let ((raw (diogenes--do-parse word lang)))
    (if (not raw)
	(progn
	  (message "No results for %s, trying to look it up in the dictionaries!"
		   word)
	  (diogenes--lookup-dict word lang))
      (let* ((record (diogenes--parse-analyses-record raw lang))
	     (dicts (diogenes--analyses-dicts record)))
	(if (null dicts)
	    (progn
	      (message "No dictionary entry for %s; searching by headword" word)
	      (diogenes--lookup-dict word lang))
	  (let ((buffer (diogenes--show-analysis-entries
			 (if diogenes-lookup-show-all-entries
			     (diogenes--expand-uncertain-dicts record dicts lang)
			   (diogenes--choose-analysis record dicts word))
			 lang)))
	    (when diogenes-lookup-show-analysis
	      (with-current-buffer buffer
		(diogenes--lookup-insert-at-top
		 (diogenes--format-analysis-header word lang record))
		(goto-char (point-min))))
	    buffer))))))

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
      (t (let* ((prop-lang (get-text-property char 'lang))
		(buf-lang (and (boundp 'diogenes--lookup-lang)
			       diogenes--lookup-lang))
		(word (thing-at-point 'word t))
		;; The text-property language is only useful when it is
		;; actually a lookup language.  In a Latin (Lewis & Short)
		;; entry the definition prose is tagged "english", so a
		;; Latin word under point carries lang="english" -- not
		;; nil -- which is why keying on the property alone failed.
		;; Treat only "greek"/"latin" as usable, and otherwise fall
		;; back to the language of the entry we are reading.
		(lang (cond
		       ((member prop-lang '("greek" "latin")) prop-lang)
		       ;; ...but not blindly.  Where the element says the text
		       ;; is neither Greek nor Latin -- the German definitions
		       ;; of Pape, the English glosses of the LSJ -- falling
		       ;; back to a Greek entry's language would parse a word
		       ;; of prose as Greek and answer with whatever sorts
		       ;; nearest.  A Greek lemma is written in Greek letters,
		       ;; so Latin script under the cursor is prose and there
		       ;; is nothing to look up.  Greek inside that prose is
		       ;; still recognised, tagged or not.
		       ((and prop-lang
			     (equal buf-lang "greek")
			     (not (and word (string-match-p "\\cg" word))))
			nil)
		       (t buf-lang))))
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
		(diogenes--parse-and-lookup (or word (thing-at-point 'word)) lang)))
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
