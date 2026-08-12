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

(defcustom diogenes-passow-display-in-other-window t
  "If non-nil, show the Passow PDF in another window."
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

(defun diogenes-passow--volumes (&optional parent)
  "Return the list of volume plists under PARENT (cached).
PARENT defaults to `diogenes-passow-directory'."
  (let ((parent (or parent diogenes-passow-directory)))
    (unless parent
      (user-error "Set `diogenes-passow-directory' to your Passow parent folder first"))
    (setq parent (file-name-as-directory (expand-file-name parent)))
    (unless (file-directory-p parent)
      (user-error "Passow directory %s does not exist" parent))
    (let ((key (diogenes-passow--dir-signature parent)))
      (or (gethash key diogenes-passow--cache)
          (setf (gethash key diogenes-passow--cache)
                (let* ((subs (seq-filter #'file-directory-p
                                         (directory-files parent t "\\`[^.]" t)))
                       (vols (delq nil (mapcar #'diogenes-passow--build-volume
                                               (sort subs #'string<)))))
                  (unless vols
                    (user-error "No usable Passow volumes found under %s" parent))
                  ;; Order volumes by their dominant first letter (the letter
                  ;; heading the most pages), which is robust to OCR noise.
                  (sort vols
                        (lambda (a b)
                          (< (diogenes-passow--dominant-letter-rank a)
                             (diogenes-passow--dominant-letter-rank b))))))))))

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
  "Forget the cached Passow volume index.
Call this if you add, replace or re-OCR a volume while Emacs is
running."
  (interactive)
  (clrhash diogenes-passow--cache)
  (message "Diogenes Passow index cache cleared"))

(provide 'diogenes-passow)
;;; diogenes-passow.el ends here
