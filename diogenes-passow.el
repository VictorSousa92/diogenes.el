;;; diogenes-passow.el --- Open Passow's Handwörterbuch page images -*- lexical-binding: t -*-

;;; Commentary:

;; Jump from a Diogenes *Greek* dictionary entry to the page of Passow's
;; _Handwörterbuch der griechischen Sprache_ (Rost/Palm) that contains
;; that entry, shown in the volume's PDF with `pdf-tools'.  Passow comes
;; in four volumes (Passow 1.1, 1.2, 2.1, 2.2); each lives in its own
;; sub-directory holding
;;   * that volume's PDF, and
;;   * an OCR text file whose pages are delimited by lines of the form
;;         ----- N / TOTAL -----
;;     (N = running OCR page number).
;;
;; Passow has no usable PDF bookmarks, so the page is found by PARSING
;; THE OCR to locate the entry, then opening the PDF at the matching
;; page.  The scanned PDFs have one extra front cover page that the OCR
;; numbering lacks, so PDF page = OCR page + `diogenes-passow-page-offset'
;; (default 1).
;;
;; Unlike the PDF dictionaries, Passow has no bookmarks: the page index
;; is built by PARSING THE OCR.  On each body page the printed running
;; head gives the page's first and last entry; we reconstruct that from
;; the text instead.  Two problems are handled:
;;
;;   1. Telling an ENTRY headword apart from Greek merely quoted inside
;;      an entry.  An entry begins at the LEFT MARGIN with a Greek word
;;      followed by a comma or "(" .  Quoted Greek is mid-line or, when
;;      the two-column scan wraps a word to the next line, breaks the
;;      alphabetical order.  We therefore keep only the longest
;;      non-decreasing run of candidate headwords down the page (their
;;      keys ascend; OCR fragments are the order-violating outliers).
;;
;;   2. Locating the word.  FIRST we find the page (or pages) whose
;;      first/last entry bracket the word; THEN, when several pages
;;      qualify (an OCR-mangled bound can widen a page's apparent
;;      range), we pick the page on which the word actually sits between
;;      two real entries, preferring the narrowest range.
;;
;; Volumes are routed automatically by the letter range each volume's
;; OCR turns out to cover, so no per-volume table is needed.
;;
;; Setup:
;;
;;   (setq diogenes-passow-directory "/path/to/passow/")   ; parent folder
;;
;; where that folder contains one sub-directory per volume.  Then, in a
;; Greek lookup buffer, press `p' or click the "[Passow]" link.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-old)                 ; reuse the PDF display driver
(require 'diogenes-montanari)           ; reuse the Greek collation key

(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-passow-directory nil
  "Directory holding Passow's volumes, one sub-directory per volume.
Each volume sub-directory must contain a PDF of that volume and an
OCR text file whose pages are delimited by \"----- N / TOTAL -----\"
lines.  The four folders correspond to Passow 1.1, 1.2, 2.1 and
2.2; their letter ranges are detected automatically from the OCR."
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'diogenes)

(defcustom diogenes-passow-text-regexp "\\.txt\\'"
  "Regexp matching the OCR text file within a volume sub-directory."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-passow-pdf-regexp "\\.pdf\\'"
  "Regexp matching the PDF within a volume sub-directory.
The first file matching this in a volume folder is used."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-passow-page-offset 0
  "Integer added to the OCR page number to get the PDF page.
The scanned PDFs carry one extra front cover page (absent from the
OCR's page numbering), so a word found on OCR page N is shown on
PDF page N + 1.  Adjust only if your PDFs have a different amount
of front matter."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-passow-page-marker-regexp
  "^-----[[:space:]]*\\([0-9]+\\)[[:space:]]*/[[:space:]]*[0-9]+[[:space:]]*-----[[:space:]]*$"
  "Regexp matching an OCR page-delimiter line; group 1 is the OCR page."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-passow-display-in-other-window nil
  "If non-nil, show the Passow PDF in another window.
Bound to `diogenes-old-display-in-other-window' for the duration of the
display, and defaults to nil for the same reason: the page appears in the
window the lookup was made from, replacing the entry.

Left as it is, and not folded into `diogenes-window-behaviour\=': this says
whether THIS dictionary's page goes somewhere other than the window it was
asked for from, which is a question about one printed dictionary rather than
about where Diogenes buffers go.  Where it sends the page elsewhere,
`diogenes-dictionary-display-action\=' and `diogenes-window-behaviour\=' decide
where elsewhere is."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; ENTRY DETECTION
;;;; --------------------------------------------------------------------

;; A line begins an entry when it starts (at the left margin) with a run
;; of Greek letters -- possibly preceded by a breathing/apostrophe glyph
;; on a capitalised proper noun -- followed by a comma or an opening
;; parenthesis.  We also allow a leading combining/spacing breathing.
(defconst diogenes-passow--entry-regexp
  (concat "\\`['’᾿῾´`]?"
          "\\([" "\u0386-\u03ce" "\u1f00-\u1fff" "]\\{2,\\}\\)"
          "[[:space:]]*[,(]")
  "Regexp matching an entry headword at the start of a stripped line.
Group 1 is the headword.")

(defun diogenes-passow--line-headword (line)
  "Return the entry headword LINE begins with, or nil.
Uses `diogenes-passow--entry-regexp'; LINE should be whitespace
trimmed by the caller."
  (when (string-match diogenes-passow--entry-regexp line)
    (match-string 1 line)))

(defun diogenes-passow--page-candidates (body)
  "Return a list of (HEADWORD . KEY) for entry-like lines in BODY, in order."
  (let (out)
    (dolist (line (split-string body "\n"))
      (let* ((s (string-trim line))
             (hw (and (> (length s) 0) (diogenes-passow--line-headword s))))
        (when hw
          (let ((k (diogenes-montanari--greek-key hw)))
            (when (>= (length k) 2)
              (push (cons hw k) out))))))
    (nreverse out)))

(defun diogenes-passow--monotone-backbone (cands)
  "Return the longest non-decreasing subsequence of CANDS by key.
CANDS is a list of (HEADWORD . KEY).  This is the reconstructed
column of real entry headwords: OCR fragments, which break the
alphabetical order, are dropped.  Ties (equal keys) are kept."
  (let* ((n (length cands)))
    (if (zerop n)
        nil
      (let* ((vec (vconcat cands))
             (keys (make-vector n nil))
             ;; tails[L] = index into VEC of the smallest possible tail
             ;; key of a non-decreasing subsequence of length L+1.
             (tails (make-vector n 0))
             (tails-len 0)
             (prev (make-vector n -1)))
        (dotimes (i n) (aset keys i (cdr (aref vec i))))
        (dotimes (i n)
          (let ((k (aref keys i))
                (lo 0) (hi tails-len))
            ;; upper-bound: first L with key(tails[L]) > k  (keep equals left)
            (while (< lo hi)
              (let ((mid (/ (+ lo hi) 2)))
                (if (string< k (aref keys (aref tails mid)))
                    (setq hi mid)
                  (setq lo (1+ mid)))))
            (aset prev i (if (> lo 0) (aref tails (1- lo)) -1))
            (aset tails lo i)
            (when (= lo tails-len) (setq tails-len (1+ tails-len)))))
        ;; reconstruct from tails[tails-len-1]
        (let ((seq nil) (i (aref tails (1- tails-len))))
          (while (>= i 0)
            (push (aref vec i) seq)
            (setq i (aref prev i)))
          seq)))))

;;;; --------------------------------------------------------------------
;;;; BUILDING THE VOLUME INDEX
;;;; --------------------------------------------------------------------

;; Per volume we store a plist:
;;   :dir     volume directory
;;   :image-prefix / :image-ext / :image-width  (to rebuild image paths)
;;   :offset  scan-page = book-page + offset  (detected)
;;   :lo :hi  volume's overall first/last entry key (for routing)
;;   :pages   vector of page plists, sorted by first-key, each:
;;              (:scan N :book B :lo K :hi K :keys [k0 k1 ...])
(defvar diogenes-passow--cache (make-hash-table :test 'equal)
  "Cache mapping the parent directory (truename+signature) to volume data.")

(defun diogenes-passow--find-book-page (body)
  "Return the printed book-page number found near the top of BODY, or nil.
The book page is a short all-digit line among the first several
lines of the page body."
  (let ((lines (seq-take (split-string body "\n") 10))
        (result nil))
    (cl-loop for line in lines
             for s = (string-trim line)
             when (and (null result) (string-match-p "\\`[0-9]\\{1,4\\}\\'" s))
             do (setq result (string-to-number s)))
    result))

(defun diogenes-passow--majority-first-letter (keys)
  "Return the Greek first letter heading most of KEYS (a vector), or nil.
KEYS are collation keys; this is robust to a few OCR-fragment keys
whose first letter differs from the page's true letter."
  (when (> (length keys) 0)
    (let ((counts (make-hash-table :test 'eql)) (best nil) (bestn 0))
      (cl-loop for k across keys
               for c = (aref k 0)
               do (puthash c (1+ (gethash c counts 0)) counts))
      (maphash (lambda (c n) (when (> n bestn) (setq best c bestn n))) counts)
      best)))

(defun diogenes-passow--parse-text (file)
  "Parse OCR FILE into a list of page plists (:scan :book :lo :hi :keys).
Only pages that yield at least two backbone entries are kept."
  (let ((pages nil))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((marker diogenes-passow-page-marker-regexp)
            (seg-start nil) (scan nil))
        (while (re-search-forward marker nil t)
          (let ((this-scan (string-to-number (match-string 1)))
                (body-start (match-end 0)))
            ;; close previous segment
            (when (and seg-start scan)
              (let* ((body (buffer-substring-no-properties
                            seg-start (match-beginning 0)))
                     (core (diogenes-passow--monotone-backbone
                            (diogenes-passow--page-candidates body))))
                (when (>= (length core) 2)
                  (let ((keyvec (vconcat (mapcar #'cdr core))))
                    (push (list :scan scan
                                :book (diogenes-passow--find-book-page body)
                                :lo (cdr (car core))
                                :hi (cdr (car (last core)))
                                :maj (diogenes-passow--majority-first-letter keyvec)
                                :keys keyvec)
                          pages)))))
            (setq seg-start body-start scan this-scan)))
        ;; last segment
        (when (and seg-start scan)
          (let* ((body (buffer-substring-no-properties seg-start (point-max)))
                 (core (diogenes-passow--monotone-backbone
                        (diogenes-passow--page-candidates body))))
            (when (>= (length core) 2)
              (let ((keyvec (vconcat (mapcar #'cdr core))))
                (push (list :scan scan
                            :book (diogenes-passow--find-book-page body)
                            :lo (cdr (car core))
                            :hi (cdr (car (last core)))
                            :maj (diogenes-passow--majority-first-letter keyvec)
                            :keys keyvec)
                      pages)))))))
    (nreverse pages)))

(defun diogenes-passow--find-pdf (dir)
  "Return the first PDF file in DIR matching `diogenes-passow-pdf-regexp', or nil."
  (car (seq-filter (lambda (f) (string-match-p diogenes-passow-pdf-regexp f))
                   (directory-files dir t nil t))))

(defun diogenes-passow--build-volume (dir)
  "Build and return the volume plist for directory DIR, or nil if unusable.
Pages are kept in scan (reading) order.  The volume records a
histogram of how many pages each Greek first letter heads; the
letter->volume routing map is derived from these histograms across
all volumes.  The volume's PDF is discovered automatically."
  (let* ((txt (car (seq-filter
                    (lambda (f) (string-match-p diogenes-passow-text-regexp f))
                    (directory-files dir t nil t)))))
    (when txt
      (let ((pages (diogenes-passow--parse-text txt))
            (pdf (diogenes-passow--find-pdf dir)))
        (when pages
          ;; Reading order = scan order (robust; not affected by fragments).
          (setq pages (sort pages (lambda (a b) (< (plist-get a :scan)
                                                   (plist-get b :scan)))))
          (let ((hist (make-hash-table :test 'eql)))
            (dolist (pg pages)
              (let ((maj (plist-get pg :maj)))
                (when maj (puthash maj (1+ (gethash maj hist 0)) hist))))
            (list :dir dir
                  :txt txt
                  :pdf pdf
                  :letter-hist hist
                  :pages (vconcat pages))))))))

(defun diogenes-passow--dir-signature (parent)
  "Return a cache signature for PARENT (its subdirs + their mtimes)."
  (let ((subs (seq-filter #'file-directory-p
                          (directory-files parent t "\\`[^.]" t)))
        (sig nil))
    (dolist (d (sort subs #'string<))
      (push (cons d (file-attribute-modification-time (file-attributes d))) sig))
    (cons (file-truename parent) sig)))

(defcustom diogenes-passow-cache-directory
  (expand-file-name "diogenes-passow" user-emacs-directory)
  "Directory where the parsed Passow index is cached on disk.
Parsing the Passow OCR volumes takes several seconds; the result is
saved here so later Emacs sessions load it in milliseconds instead of
re-parsing.  The cache is keyed by the OCR files' modification times,
so replacing or re-OCRing a volume automatically invalidates it.  Set
to nil to disable on-disk caching (the in-memory cache still applies
within a session)."
  :type '(choice (const :tag "Disable disk cache" nil) directory)
  :group 'diogenes)

(defconst diogenes-passow--cache-format-version 1
  "Bumped when the cached data structure changes, to invalidate old files.")

(defun diogenes-passow--signature-hash (signature)
  "Return a short stable string hash of dir SIGNATURE for use in a filename."
  (secure-hash 'sha1 (format "%S" signature)))

(defun diogenes-passow--cache-file (signature)
  "Return the on-disk cache file path for dir SIGNATURE, or nil if disabled."
  (when diogenes-passow-cache-directory
    (expand-file-name (format "passow-%d-%s.eld"
                              diogenes-passow--cache-format-version
                              (diogenes-passow--signature-hash signature))
                      diogenes-passow-cache-directory)))

(defun diogenes-passow--vol-to-serializable (vol)
  "Return a copy of VOL with its hash-table fields turned into alists.
Only `:letter-hist' is a hash table; converting it to an alist makes
the cached form plain data, independent of hash-table print syntax."
  (let ((copy (copy-sequence vol))
        (hist (plist-get vol :letter-hist)))
    (when (hash-table-p hist)
      (let (alist)
        (maphash (lambda (k v) (push (cons k v) alist)) hist)
        (setq copy (plist-put copy :letter-hist (cons :alist alist)))))
    copy))

(defun diogenes-passow--vol-from-serializable (vol)
  "Inverse of `diogenes-passow--vol-to-serializable': restore `:letter-hist'."
  (let ((copy (copy-sequence vol))
        (hist (plist-get vol :letter-hist)))
    (when (and (consp hist) (eq (car hist) :alist))
      (let ((table (make-hash-table :test 'eql)))
        (dolist (kv (cdr hist)) (puthash (car kv) (cdr kv) table))
        (setq copy (plist-put copy :letter-hist table))))
    copy))

(defun diogenes-passow--load-disk-cache (signature)
  "Return the cached volume list for SIGNATURE from disk, or nil.
The stored form embeds the signature; a mismatch (should not happen,
since the filename encodes the signature) is treated as a miss."
  (let ((file (diogenes-passow--cache-file signature)))
    (when (and file (file-readable-p file))
      (condition-case err
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (let ((data (read (current-buffer))))
              (when (and (consp data)
                         (equal (car data) signature))
                (mapcar #'diogenes-passow--vol-from-serializable (cdr data)))))
        ;; A corrupt or unreadable cache file must never break lookup.
        (error (ignore err) nil)))))

(defun diogenes-passow--save-disk-cache (signature vols)
  "Write VOLS for SIGNATURE to the on-disk cache; return VOLS.
Failures (unwritable directory, disk full) are swallowed: the disk
cache is an optimisation, never required for correctness."
  (let ((file (diogenes-passow--cache-file signature)))
    (when file
      (condition-case err
          (progn
            (make-directory (file-name-directory file) t)
            (let ((coding-system-for-write 'utf-8)
                  (print-length nil)     ; never abbreviate long structures
                  (print-level nil)
                  (print-circle nil))
              (with-temp-file file
                (prin1 (cons signature
                             (mapcar #'diogenes-passow--vol-to-serializable vols))
                       (current-buffer)))))
        (error (ignore err) nil))))
  vols)

(defconst diogenes-passow--prebuilt-index-name "passow-index.eld"
  "Filename of the portable prebuilt index, kept in the Passow parent folder.
Unlike the mtime-keyed cache under `diogenes-passow-cache-directory',
this file is a deliberate, shippable artifact: build it once with
\\[diogenes-passow-build-index] and it makes every lookup instant, on
any machine, without the OCR being parsed at run time.")

(defun diogenes-passow--prebuilt-index-file (parent)
  "Return the prebuilt-index path for PARENT."
  (expand-file-name diogenes-passow--prebuilt-index-name parent))

(defun diogenes-passow--load-prebuilt-index (parent signature)
  "Load and return the volume list from PARENT's prebuilt index, or nil.
SIGNATURE is the current directory signature; when the stored one
differs, the OCR has changed since the index was built, so we WARN
(the index may be stale) but still use it -- the user can rebuild with
\\[diogenes-passow-build-index].  A missing, corrupt or wrong-version
file is a silent miss, so lookup falls through to the caches/parse."
  (let ((file (diogenes-passow--prebuilt-index-file parent)))
    (when (and file (file-readable-p file))
      (condition-case err
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (let ((data (read (current-buffer))))
              ;; Stored form: (:diogenes-passow-index VERSION SIGNATURE . VOLS)
              (when (and (consp data)
                         (eq (car data) :diogenes-passow-index)
                         (eq (nth 1 data) diogenes-passow--cache-format-version))
                (let ((stored-sig (nth 2 data))
                      (vols (nthcdr 3 data)))
                  (unless (equal stored-sig signature)
                    (message "Passow: prebuilt index %s may be stale (OCR changed); \
rebuild with M-x diogenes-passow-build-index"
                             (abbreviate-file-name file)))
                  (mapcar #'diogenes-passow--vol-from-serializable vols)))))
        (error (ignore err) nil)))))

(defun diogenes-passow--parse-all-volumes (parent)
  "Parse every volume under PARENT and return the ordered volume list.
This is the expensive step (it reads and scans each volume's OCR).
PARENT must already be an existing, expanded directory."
  (let* ((subs (seq-filter #'file-directory-p
                           (directory-files parent t "\\`[^.]" t)))
         (vols (delq nil (mapcar #'diogenes-passow--build-volume
                                 (sort subs #'string<)))))
    (unless vols
      (user-error "No usable Passow volumes found under %s" parent))
    ;; Order volumes by their dominant first letter (the letter heading the
    ;; most pages), which is robust to OCR noise.
    (sort vols
          (lambda (a b)
            (< (diogenes-passow--dominant-letter-rank a)
               (diogenes-passow--dominant-letter-rank b))))))

(defun diogenes-passow--volumes (&optional parent)
  "Return the list of volume plists under PARENT (cached in memory and on disk).
PARENT defaults to `diogenes-passow-directory'.  Resolution order,
cheapest first:

  1. the in-memory cache (instant within a session);
  2. a PREBUILT index file (`passow-index.eld' in the parent folder,
     written by \\[diogenes-passow-build-index]) -- a portable, shippable
     artifact, so even the first lookup on a fresh machine is instant;
  3. the mtime-keyed on-disk cache from a previous session; and only
  4. a cold parse of the OCR (several seconds), which is then memoised
     and written to the mtime-keyed cache.

Parsing the OCR is thus paid at most once, and with a prebuilt index
never at lookup time at all."
  (let ((parent (or parent diogenes-passow-directory)))
    (unless parent
      (diogenes--require-path parent 'diogenes-passow-directory
                              "Passow" 'directory))
    (setq parent (file-name-as-directory (expand-file-name parent)))
    (let ((key (diogenes-passow--dir-signature parent)))
      (or
       ;; 1. In-memory cache.
       (gethash key diogenes-passow--cache)
       ;; 2. Prebuilt, portable index file beside the OCR.
       (let ((pre (diogenes-passow--load-prebuilt-index parent key)))
         (when pre
           (setf (gethash key diogenes-passow--cache) pre)))
       ;; 3. mtime-keyed on-disk cache from a previous session.
       (let ((disk (diogenes-passow--load-disk-cache key)))
         (when disk
           (setf (gethash key diogenes-passow--cache) disk)))
       ;; 4. Cold parse, then memoise and persist to the mtime cache.
       (setf (gethash key diogenes-passow--cache)
             (let ((vols (diogenes-passow--parse-all-volumes parent)))
               (diogenes-passow--save-disk-cache key vols)
               vols))))))

(defconst diogenes-passow--greek-order
  "αβγδεζηθικλμνξοπρστυφχψω"
  "Lowercase Greek alphabet, for ranking first letters.")

(defun diogenes-passow--letter-rank (ch)
  "Return the alphabetical rank of Greek letter CH, or a large number."
  (let ((i (and ch (cl-position ch diogenes-passow--greek-order))))
    (or i 999)))

(defun diogenes-passow--dominant-letter (vol)
  "Return the Greek first letter heading the most pages of VOL."
  (let ((hist (plist-get vol :letter-hist)) (best nil) (bestn -1))
    (when hist
      (maphash (lambda (c n) (when (> n bestn) (setq best c bestn n))) hist))
    best))

(defun diogenes-passow--dominant-letter-rank (vol)
  "Alphabetical rank of VOL's dominant first letter."
  (diogenes-passow--letter-rank (diogenes-passow--dominant-letter vol)))

;;;; --------------------------------------------------------------------
;;;; ROUTING: WORD -> VOLUME -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-passow--letter-map (vols)
  "Return a hash mapping each Greek first letter to its owning VOLS element.
Each letter is assigned to the volume on whose pages it is the
majority first letter most often (argmax of the per-volume page
counts).  This yields a clean, contiguous split of the alphabet
across the volumes and is robust to sparse OCR-fragment letters."
  (let ((map (make-hash-table :test 'eql))
        (bestn (make-hash-table :test 'eql)))
    (dolist (vol vols)
      (let ((hist (plist-get vol :letter-hist)))
        (when hist
          (maphash (lambda (c n)
                     (when (> n (gethash c bestn -1))
                       (puthash c n bestn)
                       (puthash c vol map)))
                   hist))))
    map))

(defun diogenes-passow--volume-for-key (key vols)
  "Return the volume in VOLS that owns KEY's first Greek letter.
If no volume owns that letter (e.g. the relevant volume is not
installed), return nil."
  (when (> (length key) 0)
    (gethash (aref key 0) (diogenes-passow--letter-map vols))))

(defun diogenes-passow--stage1 (key pages)
  "Return the pages in PAGES whose majority first letter matches KEY's.
This restricts the search to the block of the volume that holds
KEY's initial letter, ignoring OCR-fragment keys entirely."
  (let ((L (and (> (length key) 0) (aref key 0))) hits)
    (when L
      (cl-loop for pg across pages
               when (eql (plist-get pg :maj) L)
               do (push pg hits)))
    (nreverse hits)))

(defun diogenes-passow--page-gap (key pg)
  "Classify how KEY sits among PG's entry keys.
0 = KEY equals an entry on the page; 1 = KEY lies strictly between
two entries on the page; 2 = KEY is at/beyond an end of the page."
  (let* ((keys (plist-get pg :keys))
         (n (length keys)))
    (if (zerop n)
        2
      (let ((lo 0) (hi n) (found nil))
        (while (< lo hi)
          (let* ((mid (/ (+ lo hi) 2)) (k (aref keys mid)))
            (cond ((string= k key) (setq found t lo hi))
                  ((string< k key) (setq lo (1+ mid)))
                  (t (setq hi mid)))))
        (cond (found 0)
              ((and (> lo 0) (< lo n)) 1)
              (t 2))))))

(defun diogenes-passow--stage2 (key candidates)
  "Pick the best page plist from CANDIDATES for KEY.
Among the same-initial-letter pages, prefer the smallest gap class:

  * gap 0 (KEY equals an entry headword on the page): the entry may
    span several pages, its headword recurring on each.  It BEGINS on
    the earliest such page, so the earliest gap-0 page in reading
    order is chosen.

  * gap 1 (KEY falls between two entries): choose the page whose
    entries bracket KEY most tightly -- the latest first-entry still
    <= KEY, else the earliest page starting after KEY.

Gap-0 pages always sort before gap-1 pages, so a real headword page
wins over a page that merely happens to straddle KEY."
  (car (sort (copy-sequence candidates)
             (lambda (a b)
               (let ((ga (diogenes-passow--page-gap key a))
                     (gb (diogenes-passow--page-gap key b)))
                 (cond
                  ((/= ga gb) (< ga gb))
                  ;; exact-headword match: earliest page = where it begins.
                  ((= ga 0) (< (plist-get a :scan) (plist-get b :scan)))
                  ;; between-entries match: tightest bracket.
                  (t
                   (let* ((ka (aref (plist-get a :keys) 0))
                          (kb (aref (plist-get b :keys) 0))
                          (a-le (not (string< key ka)))
                          (b-le (not (string< key kb))))
                     (cond
                      ((and a-le (not b-le)) t)
                      ((and b-le (not a-le)) nil)
                      ((and a-le b-le)
                       (if (string= ka kb)
                           (< (plist-get a :scan) (plist-get b :scan))
                         (string> ka kb)))
                      (t (if (string= ka kb)
                             (< (plist-get a :scan) (plist-get b :scan))
                           (string< ka kb))))))))))))

(defun diogenes-passow--locate (word)
  "Return (VOLUME . PAGE-PLIST) for WORD, or nil.
Two-stage search: route to the VOLUME that owns WORD's initial
Greek letter, restrict to that volume's pages sharing the letter,
then choose the page on which WORD actually sits."
  (let* ((vols (diogenes-passow--volumes))
         (key (diogenes-montanari--greek-key word)))
    (when (> (length key) 0)
      (let ((vol (diogenes-passow--volume-for-key key vols)))
        (when vol                       ; nil => letter not in installed volumes
          (let* ((pages (plist-get vol :pages))
                 (cands (diogenes-passow--stage1 key pages)))
            (cond
             (cands (cons vol (diogenes-passow--stage2 key cands)))
             ;; Letter owned but no page detected for it (shouldn't happen):
             ;; fall back to the nearest page by first key.
             ((> (length pages) 0)
              (let ((best (aref pages 0)))
                (cl-loop for pg across pages
                         when (not (string< key (aref (plist-get pg :keys) 0)))
                         do (setq best pg))
                (cons vol best))))))))))

;;;; --------------------------------------------------------------------
;;;; DISPLAY -- open the volume PDF at the located page
;;;; --------------------------------------------------------------------

(defun diogenes-passow--pdf-page (pg)
  "Return the PDF page for page-plist PG (OCR page + offset)."
  (+ (plist-get pg :scan) diogenes-passow-page-offset))

(defun diogenes-passow--show (vol pg)
  "Show volume VOL's PDF at the page for page-plist PG.
Reuses `diogenes-old--show-page', so paging, zooming and so on are
handled by `pdf-tools' (or `doc-view') exactly as for the other
print dictionaries.  Honours `diogenes-passow-display-in-other-window'
via `diogenes-old-display-in-other-window'."
  (let ((pdf (plist-get vol :pdf))
        (page (diogenes-passow--pdf-page pg))
        (diogenes-old-display-in-other-window
         diogenes-passow-display-in-other-window))
    (unless pdf
      (user-error "No PDF found in %s"
                  (abbreviate-file-name (plist-get vol :dir))))
    (diogenes-old--show-page page pdf)
    page))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

(declare-function diogenes--lookup-headword-at-point "diogenes-perseus" (&optional pos))

(defun diogenes-passow--current-headword ()
  "Return the headword to look up for the Greek entry point is in.
Resolved from point on every call via
`diogenes--lookup-headword-at-point', so the opener always acts on
the entry the cursor is currently in -- including entries loaded
later by `diogenes-lookup-next' / `diogenes-lookup-previous'."
  (or (and (fboundp 'diogenes--lookup-headword-at-point)
           (diogenes--lookup-headword-at-point))
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-passow (&optional word)
  "Open Passow's Handwörterbuch PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at
point in a `diogenes-lookup-mode' buffer.  With a prefix argument,
prompt for the word.

Requires `diogenes-passow-directory' to point at the parent folder
of the four Passow volume sub-directories, each holding that
volume's PDF and OCR text.  Uses `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "Passow's Handwörterbuch")
     (list (if current-prefix-arg
               (read-string "Open Passow at word: ")
             (diogenes-passow--current-headword)))))
  (let* ((word (or word (diogenes-passow--current-headword)))
         (hit (diogenes-passow--locate word)))
    (unless hit
      (user-error "Could not locate \"%s\" in Passow (is its volume installed?)" word))
    (let* ((vol (car hit))
           (pg (cdr hit))
           (page (diogenes-passow--show vol pg)))
      (message "Passow: \"%s\" -> %s PDF p.%d (OCR p.%s)"
               word
               (file-name-nondirectory (directory-file-name (plist-get vol :dir)))
               page
               (plist-get pg :scan)))))

;;;###autoload
(defun diogenes-passow-clear-cache ()
  "Forget the cached Passow volume index (in memory and on disk).
Call this if you add, replace or re-OCR a volume while Emacs is
running.  Also deletes the on-disk cache files under
`diogenes-passow-cache-directory', so the next lookup rebuilds from
the current OCR rather than reloading a stale cache."
  (interactive)
  (clrhash diogenes-passow--cache)
  (when (and diogenes-passow-cache-directory
             (file-directory-p diogenes-passow-cache-directory))
    (dolist (f (directory-files diogenes-passow-cache-directory t
                                "\\`passow-[0-9]+-.*\\.eld\\'"))
      (ignore-errors (delete-file f))))
  ;; NB: the portable prebuilt index (`passow-index.eld', written by
  ;; `diogenes-passow-build-index') is a deliberate artifact and is left
  ;; in place -- rebuild it with that command after re-OCRing.  It records
  ;; the directory signature and warns when it looks stale.
  (message "Diogenes Passow index cache cleared"))

;;;###autoload
(defun diogenes-passow-build-index ()
  "Parse the Passow OCR now and write a portable prebuilt index file.
Reads every volume under `diogenes-passow-directory', builds the
page index (the slow step, a few seconds), and writes it to
`passow-index.eld' in that parent folder.  Thereafter every lookup --
including the first one in a session, and on any other machine the
folder is copied to -- loads that file instantly instead of parsing
the OCR.  Run this once after installing or re-OCRing the volumes;
it also refreshes the in-memory and mtime caches so the current
session benefits immediately."
  (interactive)
  (let ((parent (or diogenes-passow-directory
                    (diogenes--require-path nil 'diogenes-passow-directory
                                            "Passow" 'directory))))
    (setq parent (file-name-as-directory (expand-file-name parent)))
    (diogenes--require-path parent 'diogenes-passow-directory
                            "Passow" 'directory)
    (let* ((key (diogenes-passow--dir-signature parent))
           (file (diogenes-passow--prebuilt-index-file parent)))
      (message "Passow: building index from OCR (this may take a few seconds)...")
      (let ((vols (diogenes-passow--parse-all-volumes parent)))
        (let ((coding-system-for-write 'utf-8)
              (print-length nil)
              (print-level nil)
              (print-circle nil))
          (with-temp-file file
            (prin1 (append (list :diogenes-passow-index
                                 diogenes-passow--cache-format-version
                                 key)
                           (mapcar #'diogenes-passow--vol-to-serializable vols))
                   (current-buffer))))
        ;; Warm the session's caches too.
        (setf (gethash key diogenes-passow--cache) vols)
        (diogenes-passow--save-disk-cache key vols)
        (message "Passow: wrote prebuilt index (%d volume%s) to %s"
                 (length vols) (if (= (length vols) 1) "" "s")
                 (abbreviate-file-name file))))))

;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))

;;;###autoload
(defun diogenes-passow-available-p ()
  "Non-nil if Passow's Handwörterbuch can be opened.
True when `diogenes-passow-directory' is set.  Whether it exists, and
whether every volume is in it, is not asked here."
  (diogenes--path-set-p diogenes-passow-directory))

(defconst diogenes-passow--declared-at-load (diogenes--declared-at-load-p)
  "Whether Passow was asked for, rather than bundled with the rest.
Computed when this file is read: a `require' in an init file means the
user wants this dictionary, and it is then offered whatever its paths
say.  See `diogenes--loading-bundle'.")

(defun diogenes-passow--register ()
  "Announce Passow to the lookup banner.  Idempotent."
  (diogenes-lookup-register-dictionary
   'passow :lang "greek" :name "Passow" :key "p" :order 40
   :command #'diogenes-lookup-open-passow
   :available-p #'diogenes-passow-available-p
   :declared diogenes-passow--declared-at-load
   :paths '(diogenes-passow-directory)
   :bind t
   :help "Open Passow at \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-passow--register))

(provide 'diogenes-passow)
;;; diogenes-passow.el ends here
