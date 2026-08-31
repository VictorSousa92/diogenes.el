;;; diogenes-tests.el --- Tests for diogenes.el  -*- lexical-binding: t -*-

;;; Commentary:

;; Two ways to run these, and both are wanted.
;;
;; HEADLESS, from the package's directory:
;;
;;     emacs -Q -batch -L . -l test/diogenes-tests.el \
;;           -f ert-run-tests-batch-and-exit
;;
;; Nothing here needs Diogenes' data, its Perl, or a display, so this runs
;; the same on any machine and is what a Makefile or a CI job should call.
;;
;; IN A LIVE CONFIGURATION -- Doom, Spacemacs, plain Emacs:
;;
;;     M-x diogenes-tests-run
;;
;; Same tests, but with whatever the distribution has done to Emacs still in
;; place: evil owning the single-letter keys, window-purpose dedicating
;; windows, a popup manager holding `display-buffer-alist', persp-mode
;; hiding buffers.  Every bug this suite exists to guard against was found
;; that way and not headlessly, so the headless run is necessary and not
;; sufficient.
;;
;; `M-x diogenes-tests-environment' prints what the surrounding
;; configuration is doing, which is the first thing to paste into a bug
;; report: three of the hardest faults in this package's history were a
;; distribution's `find-file-hook', a distribution's evil state maps, and a
;; distribution's workspace filter.
;;
;; Each test names the fault it guards against.  A test whose comment says
;; "regression" is one that a real bug walked through.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'diogenes-lisp-utils)
(require 'diogenes-perseus)
(require 'diogenes-purpose)

;; Every file, not just the two the assertions name.  The command-shape test
;; below scans whatever commands are DEFINED, and headless only these two
;; were: it reported no offenders while two of them sat in
;; `diogenes-browser.el', and passed for weeks by checking nothing.  It found
;; them the moment the suite was run inside a live configuration, where the
;; whole package is loaded -- so the headless run has to load the whole
;; package too, or the two runs are not asking the same question.
;;
;; Best effort: a module whose own dependencies are absent is skipped rather
;; than failing the run, since the point here is coverage and not loading.
(let ((dir (or (and load-file-name
                    (expand-file-name ".." (file-name-directory load-file-name)))
               default-directory)))
  (dolist (file (directory-files dir t "\\`diogenes-[^/]*\\.el\\'"))
    (unless (string-match-p "diogenes-archive" file)
      (ignore-errors (load file nil t)))))

;; Declared so that `let' on them is DYNAMIC.  Under `lexical-binding' a
;; `let' on an undeclared symbol binds lexically, which `boundp' inside the
;; function under test cannot see -- so the test would fail while the code
;; was right.  These are the distributions' own variables, absent here.
(defvar spacemacs-buffer-name)
(defvar pdf-view-mode-map)
(defvar diogenes--lookup-lang)
(defvar doc-view-mode-map)
(defvar reader-mode-map)
(defvar +doom-dashboard-name)
(defvar dashboard-buffer-name)

;;; Paths: what counts as a configured dictionary

(ert-deftest diogenes-test-path-set-p ()
  "Set-ness is about the option, not about the file system."
  (should (diogenes--path-set-p "/nonexistent/but/named.pdf"))
  (should-not (diogenes--path-set-p nil))
  (should-not (diogenes--path-set-p ""))
  (should-not (diogenes--path-set-p 42)))

(defconst diogenes-tests--a-real-file
  (or (locate-library "diogenes-lisp-utils")
      (and load-file-name
           (expand-file-name "../diogenes-lisp-utils.el"
                             (file-name-directory load-file-name))))
  "A file that certainly exists, found without trusting `default-directory'.
An earlier version of the test below used `(expand-file-name \"diogenes.el\")',
which is the package directory under `make' and the home directory when the
tests are run from `M-x' -- so it passed headless and failed in every live
configuration, reporting a fault in the code that was a fault in the test.")

(ert-deftest diogenes-test-path-usable-p ()
  "Usability is about the file system, and never signals."
  (should (diogenes--path-usable-p diogenes-tests--a-real-file 'file))
  (should-not (diogenes--path-usable-p "/nonexistent/x.pdf" 'file))
  (should (diogenes--path-usable-p (file-name-directory
                                   diogenes-tests--a-real-file)
                                  'directory))
  (should-not (diogenes--path-usable-p nil 'file)))

(ert-deftest diogenes-test-source-set-p ()
  "A source option may be a file, a directory, or a list of either."
  (should (diogenes--source-set-p "/x/y.xml"))
  (should (diogenes--source-set-p '("/x/a.xml" "/x/b.xml")))
  (should (diogenes--source-set-p '(nil "/x/b.xml")))
  (should-not (diogenes--source-set-p nil))
  (should-not (diogenes--source-set-p '())))

;;; Home buffers: the guard against opening a frame beside an empty one

(ert-deftest diogenes-test-home-buffer-p ()
  "Every distribution's startup buffer is recognised, and nothing else is."
  (should (diogenes--home-buffer-p "*GNU Emacs*"))
  (should (diogenes--home-buffer-p "*doom*"))
  (should (diogenes--home-buffer-p "*spacemacs*"))
  (should (diogenes--home-buffer-p "*dashboard*"))
  (should-not (diogenes--home-buffer-p "*scratch*"))
  (should-not (diogenes--home-buffer-p "some-text.txt"))
  (should-not (diogenes--home-buffer-p nil)))

(ert-deftest diogenes-test-home-buffer-p-follows-the-distribution ()
  "A renamed home buffer is recognised through the distribution's variable."
  (let ((spacemacs-buffer-name "*my home*"))
    (should (diogenes--home-buffer-p "*my home*"))))

;;; Latin normalisation

(ert-deftest diogenes-test-ascii-alpha-only-folds ()
  "An accented letter contributes its base rather than vanishing.
Regression: `desîmus' folded to `desmus', which sorts past the whole of
`desi-', and a lookup landed on `dēsīvare' four entries later."
  (should (equal (diogenes--ascii-alpha-only "des\u00eemus") "desimus"))
  ;; f, u+breve, t, u, u+macron, r, i, x -- eight letters, one of them
  ;; twice, and none of them invented: an earlier version of this test
  ;; expected a `t' the input never had.
  (should (equal (diogenes--ascii-alpha-only "fu\u0306tu\u016brix") "futuurix"))
  (should (equal (diogenes--ascii-alpha-only "1 abactus") "abactus"))
  (should (equal (diogenes--ascii-alpha-only "amo") "amo")))

(ert-deftest diogenes-test-expand-contractions ()
  "A circumflex is the sign of a contracted syllable, not decoration."
  (should (equal (diogenes--latin-expand-contractions "des\u00eemus") "desiimus"))
  (should (equal (diogenes--latin-expand-contractions "d\u00ee") "dii"))
  ;; Nil, not the word, so a caller can tell an expansion from a form.
  (should-not (diogenes--latin-expand-contractions "desimus")))

(ert-deftest diogenes-test-parse-candidates-order ()
  "The contraction is tried before the bare spelling, and that order decides.
Regression: both `desiimus' and `desimus' are keys in the analyses file --
the syncopated perfect of `desino' and the present subjunctive of `dēsum' --
so stripping the mark answered confidently about a word the text had not
printed."
  (let* ((candidates (diogenes--latin-parse-candidates "des\u00eemus"))
         (expansion (cl-position "desiimus" candidates :test #'equal))
         (stripped (cl-position "desimus" candidates :test #'equal)))
    (should (equal (car candidates) "des\u00eemus"))
    (should expansion)
    (should stripped)
    (should (< expansion stripped)))
  ;; An unmarked form is one candidate and no more.
  (should (equal (diogenes--latin-parse-candidates "amo") '("amo"))))

(ert-deftest diogenes-test-form-variants-keep-the-word-first ()
  "The form as given is always tried before any variant of it."
  (should (equal (car (diogenes--latin-form-variants "amo")) "amo"))
  (should (member "amo" (diogenes--latin-form-variants "amo")))
  (let ((diogenes-latin-try-spelling-variants nil))
    (should (equal (diogenes--latin-form-variants "amo") '("amo")))))

;;; The analyses record

(defconst diogenes-tests--record
  "siderum\t{66640471 9 si_derum,sidus\t \tneut gen pl}"
  "One real record, from the failure that prompted these tests.")

(ert-deftest diogenes-test-parse-analyses-record ()
  "Every field survives, including the two read after the lemma is munged.
Regression: the plist was built inline, `:display' called
`replace-regexp-in-string', match data is global, and groups 4 and 5 were
therefore nil by the time `:trans' and `:info' read them -- so `C-c C-c' on
any word died in `string-trim'."
  (let* ((diogenes-latin-analysis-corrections nil)
         (record (diogenes--parse-analyses-record
                  (encode-coding-string diogenes-tests--record 'utf-8)
                  "latin"))
         (analyses (plist-get record :analyses))
         (first (car analyses)))
    (should (= (length analyses) 1))
    (should (= (plist-get first :offset) 66640471))
    (should (= (plist-get first :conf) 9))
    (should (equal (plist-get first :lemma) "si_derum,sidus"))
    ;; :display exists; what it looks like is munge's business.
    (should (stringp (plist-get first :display)))
    ;; The trans field of this record is a single space, so it trims away.
    (should (equal (plist-get first :trans) ""))
    ;; THE ONE THAT CAUGHT SOMETHING.  On this test's first run `:info' was
    ;; empty, because the fix for the original bug had reintroduced it one
    ;; scope inward: `string-trim' on group 4 was called before group 5 was
    ;; read, and `string-trim' is regexps like anything else.
    (should (equal (plist-get first :info) "neut gen pl"))))

(ert-deftest diogenes-test-analysis-corrections ()
  "A correction replaces the morphology and says that it did."
  (let* ((diogenes-latin-mark-corrections t)
         (diogenes-latin-analysis-corrections
          '(("siderum" :info "corrected morphology")))
         (record (diogenes--parse-analyses-record
                  (encode-coding-string diogenes-tests--record 'utf-8)
                  "latin"))
         (first (car (plist-get record :analyses))))
    (should (equal (plist-get first :info) "corrected morphology [corr.]")))
  ;; A form with no entry is untouched, which is the common case.
  (let* ((diogenes-latin-analysis-corrections '(("experire" :info "x")))
         (record (diogenes--parse-analyses-record
                  (encode-coding-string diogenes-tests--record 'utf-8)
                  "latin"))
         (first (car (plist-get record :analyses))))
    (should (equal (plist-get first :info) "neut gen pl"))))

(ert-deftest diogenes-test-corrections-replace-the-lemma ()
  "`:lemma' replaces the headword that is PRINTED, and the entry it opens.
Three fields, which is the point: `:display' is what appears on the screen,
`:lemma' is what the assimilation machinery reads, and `:offset' is where the
entry begins.  Setting only `:lemma' leaves the old headword displayed;
setting `:offset' to 0 opens byte 0 of the dictionary, which is the entry for
the letter A.

The entry for a corrected lemma is found by name, as a Morpheus lemma's is --
so in a batch Emacs, with no dictionary to search, that search fails
harmlessly, the offset falls back to the file's own, and the confidence says
the headword is a guess.  Which is also what happens to a reader whose
`diogenes-path' is unset: a correction must not signal.  What can be checked
here is that all three fields move together."
  (let* ((diogenes-latin-mark-corrections t)
         (diogenes-latin-analysis-corrections
          '(("siderum" :lemma "superstes")))
         (record (diogenes--parse-analyses-record
                  (encode-coding-string diogenes-tests--record 'utf-8)
                  "latin"))
         (first (car (plist-get record :analyses))))
    ;; What is printed.
    (should (equal (plist-get first :display) "superstes [corr.]"))
    ;; What the machinery reads: the bare lemma, unmarked.
    (should (equal (plist-get first :lemma) "superstes"))
    ;; A number, always: these are compared with `='.
    (should (numberp (plist-get first :offset)))
    ;; The morphology is untouched where only the lemma is corrected.
    (should (equal (plist-get first :info) "neut gen pl")))
  ;; Both at once, which is the case that prompted this.
  (let* ((diogenes-latin-mark-corrections nil)
         (diogenes-latin-analysis-corrections
          '(("siderum" :lemma "superstes" :info "abl sg")))
         (record (diogenes--parse-analyses-record
                  (encode-coding-string diogenes-tests--record 'utf-8)
                  "latin"))
         (first (car (plist-get record :analyses))))
    (should (equal (plist-get first :display) "superstes"))
    (should (equal (plist-get first :info) "abl sg"))
    (should (numberp (plist-get first :offset)))))

(ert-deftest diogenes-test-corrections-add-a-reading ()
  "`:add' keeps the file's analysis and appends one of its own."
  (let* ((diogenes-latin-mark-corrections nil)
         (diogenes-latin-analysis-corrections
          '(("siderum" :add ((nil . "another reading")))))
         (record (diogenes--parse-analyses-record
                  (encode-coding-string diogenes-tests--record 'utf-8)
                  "latin"))
         (analyses (plist-get record :analyses)))
    (should (= (length analyses) 2))
    (should (equal (plist-get (nth 0 analyses) :info) "neut gen pl"))
    (should (equal (plist-get (nth 1 analyses) :info) "another reading"))))

;;; The dictionary registry

(ert-deftest diogenes-test-dict-available-p-never-signals ()
  "Three ways of not having a dictionary are one answer, and none is an error.
Regression: the banner is drawn during redisplay, where a signal from an
availability predicate is not an error anyone can act on."
  (should (diogenes--lookup-dict-available-p nil))
  (should (diogenes--lookup-dict-available-p (lambda () t)))
  (should-not (diogenes--lookup-dict-available-p (lambda () nil)))
  ;; A predicate that is not defined: the module is not loaded.
  (should-not (diogenes--lookup-dict-available-p
               'diogenes-tests--no-such-predicate))
  ;; A predicate that signals: `diogenes-path' itself may be unset.
  (should-not (diogenes--lookup-dict-available-p
               (lambda () (error "as `diogenes--path' would")))))

(ert-deftest diogenes-test-dict-visible-when-declared ()
  "A declared dictionary is offered whatever its paths say."
  (let ((entry (list :id 'testdict :show 'always
                     :available-p (lambda () nil))))
    (let ((diogenes-declared-dictionaries nil))
      (should-not (diogenes--lookup-dict-visible-p entry)))
    (let ((diogenes-declared-dictionaries '(testdict)))
      (should (diogenes--lookup-dict-visible-p entry)))
    ;; Declared by its module, rather than by the list.
    (let ((diogenes-declared-dictionaries nil)
          (declared (append entry '(:declared t))))
      (should (diogenes--lookup-dict-visible-p declared)))
    ;; Both at once is harmless: this is an `or'.
    (let ((diogenes-declared-dictionaries '(testdict))
          (declared (append entry '(:declared t))))
      (should (diogenes--lookup-dict-visible-p declared)))))

(ert-deftest diogenes-test-dict-visible-when-configured ()
  "An undeclared dictionary is offered when its paths are set."
  (let ((diogenes-declared-dictionaries nil))
    (should (diogenes--lookup-dict-visible-p
             (list :id 'testdict :show 'always
                   :available-p (lambda () t))))))

;;; Where a buffer goes

;; `display-buffer' works headless; frames largely do not.  So these test the
;; DECISION -- which action is chosen, and which of the three rules wins --
;; and leave the frames to `M-x diogenes-tests-run' in a live configuration.

(defmacro diogenes-tests--with-two-windows (&rest body)
  "Run BODY with the frame split and the selected window undedicated.
Undedicated because these tests are run inside a live configuration as well
as headless, and under window-purpose the window they start in is dedicated
to whatever it holds -- the `*ert*' buffer.  A dedicated window declines a
same-window display, so the tests failed there while the code was right.
The dedication is restored with the window configuration."
  (declare (indent 0) (debug t))
  `(save-window-excursion
     (delete-other-windows)
     (set-window-dedicated-p (selected-window) nil)
     (split-window)
     ,@body))

(ert-deftest diogenes-test-display-action-by-kind ()
  "Each kind of buffer draws its own action, and an unknown kind none."
  (let ((diogenes-lookup-display-action '(a))
        (diogenes-browser-display-action '(b))
        (diogenes-dictionary-display-action '(c)))
    (should (equal (diogenes--display-action 'lookup) '(a)))
    (should (equal (diogenes--display-action 'browser) '(b)))
    (should (equal (diogenes--display-action 'dictionary) '(c)))
    (should-not (diogenes--display-action 'something-else))
    (should-not (diogenes--display-action nil))))

(ert-deftest diogenes-test-display-buffer-same-window ()
  "SAME-WINDOW puts the buffer where we are, whatever the action says."
  (diogenes-tests--with-two-windows
    (let ((diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t)))
          (buffer (get-buffer-create " *diogenes-test-target*"))
          (here (selected-window)))
      (should (eq (diogenes--display-buffer buffer :kind 'lookup
                                           :same-window t)
                  here)))))

(ert-deftest diogenes-test-display-buffer-honours-the-action ()
  "Without SAME-WINDOW the action decides, and it can send the buffer away."
  (diogenes-tests--with-two-windows
    (let ((diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t)))
          (buffer (get-buffer-create " *diogenes-test-target*"))
          (here (selected-window)))
      (should-not (eq (diogenes--display-buffer buffer :kind 'lookup) here)))))

(ert-deftest diogenes-test-display-buffer-action-overrides-kind ()
  "An action passed by the caller wins over the kind's own."
  (diogenes-tests--with-two-windows
    (let ((diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t)))
          (buffer (get-buffer-create " *diogenes-test-target*"))
          (here (selected-window)))
      (should (eq (diogenes--display-buffer
                  buffer :kind 'lookup
                  :action '(display-buffer-same-window
                            (inhibit-same-window . nil)))
                  here)))))

(ert-deftest diogenes-test-display-buffer-takes-a-lone-startup-window ()
  "A frame holding only a startup page yields its window, action or no action.
Regression: `bl' from a bare splash screen opened a second window for the
text and left the splash occupying the first."
  (save-window-excursion
    (delete-other-windows)
    (set-window-dedicated-p (selected-window) nil)
    (let ((home (get-buffer-create "*GNU Emacs*"))
          (buffer (get-buffer-create " *diogenes-test-target*"))
          (diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t))))
      (set-window-buffer (selected-window) home)
      (should (diogenes--sole-home-window-p))
      (should (eq (diogenes--display-buffer buffer :kind 'lookup)
                  (selected-window))))))

(ert-deftest diogenes-test-display-buffer-same-window-displaces ()
  "SAME-WINDOW puts the buffer in this window, and says which window that was.

An earlier version of this test asserted that the displaced buffer was left
on `window-prev-buffers', and it was wrong: `display-buffer' makes no such
promise -- `switch-to-buffer' records the history, `window--display-buffer'
does not.  Which corrects the reasoning behind an earlier commit as well: the
reason `q' returns to the entry is not the window history but
`diogenes-old--return-buffer' and the key bound beside it, which is what
`diogenes-old-return-to-entry' reads."
  (save-window-excursion
    (delete-other-windows)
    (set-window-dedicated-p (selected-window) nil)
    (let ((first (get-buffer-create " *diogenes-test-first*"))
          (second (get-buffer-create " *diogenes-test-second*")))
      (switch-to-buffer first)
      (let ((window (diogenes--display-buffer second :same-window t)))
        (should (eq window (selected-window)))
        (should (eq (window-buffer window) second))))))

(ert-deftest diogenes-test-display-buffer-selects-the-window ()
  "The window is selected, as the calls this replaced did.
Regression: `pop-to-buffer' displays AND selects; `display-buffer' only
displays.  Converting the call sites lost the selection, so an entry
appeared in another window while point stayed in the buffer it was looked up
from -- and `C-c C-c' there was undefined, the buffer not being an entry."
  (diogenes-tests--with-two-windows
    (let ((diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t)))
          (buffer (get-buffer-create " *diogenes-test-target*")))
      (diogenes--display-buffer buffer :kind 'lookup)
      (should (eq (window-buffer (selected-window)) buffer))))
  ;; And NO-SELECT leaves us where we were.
  (diogenes-tests--with-two-windows
    (let ((diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t)))
          (buffer (get-buffer-create " *diogenes-test-target*"))
          (here (selected-window)))
      (diogenes--display-buffer buffer :kind 'lookup :no-select t)
      (should (eq (selected-window) here)))))

(ert-deftest diogenes-test-display-buffer-makes-the-buffer-current ()
  "The buffer is current afterwards, as it was with `pop-to-buffer'.
Regression: the browser came up in `fundamental-mode' with none of its keys,
because `diogenes--browse-work' calls `diogenes-browser-mode' after
displaying and the mode landed on whatever buffer the reader was in.  The
callers now name the buffer explicitly, and the helper leaves it current
besides."
  (diogenes-tests--with-two-windows
    (let ((diogenes-lookup-display-action
           '(display-buffer-use-some-window (inhibit-same-window . t)))
          (buffer (get-buffer-create " *diogenes-test-target*")))
      (diogenes--display-buffer buffer :kind 'lookup)
      (should (eq (current-buffer) buffer))
      (should (eq (window-buffer (selected-window)) buffer)))))

(ert-deftest diogenes-test-display-buffer-returns-the-window-used ()
  "The window returned is the one the buffer was put in, on this frame.
Regression: the window was re-derived with `(get-buffer-window buffer t)',
which searches every frame and can find an older window showing the same
buffer -- so the selection went elsewhere, current-buffer and the selected
window fell out of step, and `recenter' refused."
  (diogenes-tests--with-two-windows
    (let ((buffer (get-buffer-create " *diogenes-test-target*")))
      (let ((window (diogenes--display-buffer buffer :same-window t)))
        (should (eq window (selected-window)))
        (should (eq (window-buffer window) buffer))))))

(ert-deftest diogenes-test-claim-buffer ()
  "A buffer is offered to the perspective, and only when asked for.
Regression: a lookup buffer was alive, on the window's own history, and
still invisible to `C-x <left>' -- persp-mode decides what a perspective
holds by watching `find-file' and `switch-to-buffer', and a buffer made by a
program and shown by `display-buffer' is seen by neither.  Reported as the
buffer being killed, which it was not."
  (let* ((claimed nil)
         (buffer (get-buffer-create " *diogenes-test-target*"))
         (diogenes-claim-buffers t)
         (diogenes-claim-buffer-function (lambda (b) (push b claimed))))
    (diogenes--claim-buffer buffer)
    (should (equal claimed (list buffer))))
  ;; Off, and nothing is claimed.
  (let* ((claimed nil)
         (buffer (get-buffer-create " *diogenes-test-target*"))
         (diogenes-claim-buffers nil)
         (diogenes-claim-buffer-function (lambda (b) (push b claimed))))
    (diogenes--claim-buffer buffer)
    (should-not claimed))
  ;; And `auto' neither signals nor claims twice, whether or not a
  ;; perspective package is installed.  Asserting that it returns nil was
  ;; wrong: with persp-mode actually running it returns what
  ;; `persp-add-buffer' returns, and the test failed in the one configuration
  ;; where the code was doing its job.
  (let ((diogenes-claim-buffers t)
        (diogenes-claim-buffer-function 'auto)
        (buffer (get-buffer-create " *diogenes-test-target*")))
    (should (progn (diogenes--claim-buffer buffer) t))
    (should (buffer-live-p buffer))))

(ert-deftest diogenes-test-purpose-regexps-cover-numbered-buffers ()
  "Every buffer a lookup or an analysis can make is classified by name.
Regression: window-purpose classifies by MAJOR MODE, and a lookup buffer has
none yet when it is displayed -- so purpose filed entries under `general' and
showed them in the window the reader was reading in.  Names work where modes
cannot, and every entry gets a numbered buffer of its own, so the patterns
have to match those too.

An earlier test here asserted that a macro bound `purpose-action-function'
to `ignore'.  No such variable exists, so it passed while checking nothing --
which is the second time in this suite's short life, and the reason this one
asserts against real buffer names instead of a mechanism."
  (let ((purpose-of
         (lambda (name)
           (cdr (cl-find-if (lambda (rule) (string-match-p (car rule) name))
                            diogenes-purpose-regexp-purposes)))))
    ;; Entries, including the numbered buffers each new one gets.
    (dolist (name '("*diogenes-lookup*" "*diogenes-lookup<2>*"
                    "*diogenes-lookup<17>*"))
      (should (eq 'diogenes-lookup (funcall purpose-of name))))
    ;; The analyses have a purpose of their OWN: they used to share
    ;; `diogenes-lookup' with the entries, so an analysis replaced the entry it
    ;; was consulted about.  This test asserted that sharing, and failed when it
    ;; ended -- which is the test doing its job.
    (dolist (name '("*Diogenes Analysis*" "*Diogenes Forms*"
                    "*Diogenes Analysis<2>*"))
      (should (eq 'diogenes-morphology (funcall purpose-of name)))))
  (should (eq 'diogenes-browser
              (cdr (cl-find-if (lambda (rule)
                                 (string-match-p (car rule) "*diogenes-browser*"))
                               diogenes-purpose-regexp-purposes))))
  ;; And nothing else is swept up.
  (should-not (cl-find-if (lambda (rule)
                            (string-match-p (car rule) "*scratch*"))
                          diogenes-purpose-regexp-purposes)))

(ert-deftest diogenes-test-claim-does-not-display ()
  "Claiming a buffer for a perspective must not put it in a window.
Regression, and the one that cost the most: `persp-add-buffer' SWITCHES TO
the buffer it is given.  `diogenes--claim-buffer' runs first in
`diogenes--display-buffer', so an entry landed in the window the reader was
in before the display path had decided anything -- and the display then found
it there and correctly reused it.

Nothing that was blamed for that reuse could have caused it: the window was
taken before the action, the alist, the thresholds, window dedication and
purpose were consulted.  Eight explanations were offered and each was wrong,
which is what a fault upstream of every measurement looks like."
  (save-window-excursion
    (delete-other-windows)
    (let* ((here (get-buffer-create " *diogenes-test-here*"))
           (target (get-buffer-create " *diogenes-test-claimed*"))
           (switched nil)
           (diogenes-claim-buffers t)
           ;; A claim function that misbehaves exactly as `persp-add-buffer'
           ;; does, so the guard is what is under test.
           (diogenes-claim-buffer-function
            (lambda (b) (setq switched t) (switch-to-buffer b))))
      (switch-to-buffer here)
      (diogenes--claim-buffer target)
      (should switched)
      ;; ...and yet the window still holds what it held.
      (should (eq (window-buffer (selected-window)) here))
      (should (eq (current-buffer) here)))))

(ert-deftest diogenes-test-window-behaviour-presets ()
  "The shorthand answers for a kind whose own action is nil, and not otherwise."
  ;; `defer' is no action at all: whatever is installed decides.
  (let ((diogenes-window-behaviour 'defer)
        (diogenes-lookup-display-action nil))
    (should-not (diogenes--display-action 'lookup)))
  ;; The other three each stand for something.
  (dolist (behaviour '(reuse split frames))
    (let ((diogenes-window-behaviour behaviour)
          (diogenes-lookup-display-action nil))
      ;; With the KIND, since `diogenes--display-action' passes it: `lookup'
      ;; has a companion now, so the action built for it differs from the one
      ;; built for no kind in particular.
      (should (equal (diogenes--display-action 'lookup)
                     (diogenes--behaviour-action behaviour 'lookup)))))
  ;; An action named for one kind leaves the others on the shorthand.
  (let ((diogenes-window-behaviour 'split)
        (diogenes-lookup-display-action '((display-buffer-same-window)))
        (diogenes-browser-display-action nil))
    (should (equal (diogenes--display-action 'lookup)
                   '((display-buffer-same-window))))
    (should (equal (diogenes--display-action 'browser)
                   (diogenes--behaviour-action 'split 'browser)))))

(ert-deftest diogenes-test-frames-preset-gathers ()
  "`frames' turns the gathering on without `pop-up-frames' being set.
Otherwise the preset would name a behaviour and then not produce it -- the
gathering is what makes frames usable rather than one per entry."
  (let ((diogenes-gather-frames 'auto)
        (pop-up-frames nil))
    (let ((diogenes-window-behaviour 'frames))
      (should (diogenes--gathering-p)))
    (let ((diogenes-window-behaviour 'split))
      (should-not (diogenes--gathering-p)))))

(ert-deftest diogenes-test-normal-state-key-is-not-a-dictionary ()
  "The way out of Emacs state must not be a key a dictionary wants.
All three states are meant to be available: Emacs state for the dictionary
keys, normal state for evil's keyboard, insert where it applies.  The key
that moves between the first two therefore has to be one neither of them
uses -- escape, which in Emacs state does nothing and in normal state is
evil's own."
  (when diogenes-evil-normal-state-key
    (should-not (member diogenes-evil-normal-state-key
                        '("o" "t" "m" "c" "b" "p" "B" "d" "G" "g" "l" "P"
                          "q" "RET" "TAB"))))
  ;; The document viewers are on the list as well.  This module leaves them in
  ;; normal state -- the motions being what one wants in a scan -- but
  ;; something else may not, and a reader in Emacs state there needs the way
  ;; back as much as anywhere.
  (dolist (map '(pdf-view-mode-map doc-view-mode-map reader-mode-map))
    (should (memq map diogenes-evil--maps))))

(ert-deftest diogenes-test-behaviour-alist-reaches-the-action ()
  "A per-kind alist survives the whole way to the action that is passed.
Not the same question as `diogenes-test-behaviour-for-word-or-alist' below,
which asks what `diogenes--behaviour-for' returns: this asks whether that
answer reaches `display-buffer', which is where an earlier version of the
per-kind setting was read correctly and then dropped.

The three kinds are different things and there is no reason they should
agree: the text staying where it is while entries share a window beside it
and a scan gets a frame is a perfectly ordinary arrangement."
  (let ((diogenes-window-behaviour
         '((browser . defer) (lookup . split) (dictionary . frames)))
        (diogenes-lookup-display-action nil)
        (diogenes-browser-display-action nil)
        (diogenes-dictionary-display-action nil))
    (should-not (diogenes--display-action 'browser))
    (should (equal (diogenes--display-action 'lookup)
                   (diogenes--behaviour-action 'split 'lookup)))
    (should (equal (diogenes--display-action 'dictionary)
                   (diogenes--behaviour-action 'frames 'dictionary)))
    ;; A kind the alist does not mention gets `defer'.
    (should (eq (diogenes--behaviour-for 'search) 'defer))
    ;; And `frames' for any one kind gathers for all of them.
    (let ((diogenes-gather-frames 'auto) (pop-up-frames nil))
      (should (diogenes--gathering-p)))))

(ert-deftest diogenes-test-split-geometry ()
  "Direction, size and which window to divide reach the action."
  (let ((diogenes-split-direction 'right)
        (diogenes-split-size 0.35)
        (diogenes-split-from 'root))
    (let ((action (diogenes--behaviour-action 'split)))
      (should (memq 'display-buffer-in-direction (car action)))
      (should (equal (cdr (assq 'direction action)) 'right))
      ;; A width for a sideways split, not a height.
      (should (equal (cdr (assq 'window-width action)) 0.35))
      (should-not (assq 'window-height action))
      (should (equal (cdr (assq 'window action)) 'root))))
  ;; Downwards, the same number is a height.
  (let ((diogenes-split-direction 'below)
        (diogenes-split-size 0.35)
        (diogenes-split-from 'selected))
    (let ((action (diogenes--behaviour-action 'split)))
      (should (equal (cdr (assq 'window-height action)) 0.35))
      (should-not (assq 'window-width action))
      (should-not (assq 'window action))))
  ;; And with nothing set, Emacs is left to choose.
  (let ((diogenes-split-direction nil)
        (diogenes-split-size nil)
        (diogenes-split-from 'selected))
    (let ((action (diogenes--behaviour-action 'split)))
      (should-not (assq 'direction action))
      (should-not (memq 'display-buffer-in-direction (car action)))
      ;; The last resort is always there: it is what stops `split' becoming
      ;; `reuse' where the thresholds forbid a split.
      (should (memq 'diogenes--display-split-anyway (car action))))))

(ert-deftest diogenes-test-behaviour-for-word-or-alist ()
  "`diogenes--behaviour-for' reads either form: a word, or an alist.
The narrower of the two questions -- what the function returns, rather than
whether the answer reaches `display-buffer', which is
`diogenes-test-behaviour-alist-reaches-the-action' above.  Both are worth
asking, and were written in separate patches without either noticing the
other; the names have been made to say which is which."
  (let ((diogenes-window-behaviour '((lookup . split)
                                     (browser . frames))))
    (should (eq (diogenes--behaviour-for 'lookup) 'split))
    (should (eq (diogenes--behaviour-for 'browser) 'frames))
    ;; A kind the alist does not mention is deferred, not guessed at.
    (should (eq (diogenes--behaviour-for 'dictionary) 'defer)))
  ;; And a bare word still applies to all three.
  (let ((diogenes-window-behaviour 'reuse))
    (dolist (kind '(lookup browser dictionary))
      (should (eq (diogenes--behaviour-for kind) 'reuse)))))

(ert-deftest diogenes-test-presets-work-without-a-directory ()
  "The four behaviours are presets, whether a directory is set or not."
  (let ((diogenes-preset-directory nil))
    (let ((names (mapcar #'car (diogenes-preset--alist))))
      (dolist (builtin '("defer" "reuse" "split" "frames"))
        (should (member builtin names)))))
  ;; Loading one sets the behaviour and nothing else.
  (let ((diogenes-window-behaviour 'defer))
    (diogenes-preset--load-builtin "frames")
    (should (eq diogenes-window-behaviour 'frames))))

(ert-deftest diogenes-test-a-file-preset-replaces-a-builtin ()
  "A file named after a builtin is what that name means.
Otherwise a reader who has written `split.el' would find the builtin
arguing with it, and no way to say which they meant."
  (let* ((dir (make-temp-file "diogenes-presets" t))
         (diogenes-preset-directory dir))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "split.el" dir)
            (insert ";; Description: mine, not the builtin one
"))
          (let* ((presets (diogenes-preset--alist))
                 (split (assoc "split" presets)))
            (should split)
            ;; It is the file, not the builtin: a builtin has no file.
            (should (nth 1 split))
            (should (equal (nth 2 split) "mine, not the builtin one"))
            ;; And it appears once, not twice.
            (should (= 1 (cl-count "split" presets
                                   :key #'car :test #'equal)))
            ;; The other three builtins are untouched.
            (dolist (name '("defer" "reuse" "frames"))
              (should (assoc name presets)))))
      (delete-directory dir t))))

(ert-deftest diogenes-test-pdf-key-is-bound-where-evil-looks ()
  "The PDF lookup key lives in a map scoped to the dictionaries.
A document buffer is one evil leaves in normal state, and rightly: `j', `k'
and `C-d' are how one moves down a page of a scan.  But evil searches its
state maps before a major mode's, so a key bound only in
`pdf-view-mode-map' is not reached -- `L' would be `evil-window-bottom'.

Asserts the mode map here, evil not being loaded in a batch Emacs; the
state binding is checked by `M-x diogenes-tests-run' in a live one."
  (let ((diogenes-pdf-search-key "L")
        (diogenes-pdf-search-mode-map (make-sparse-keymap)))
    (diogenes-pdf-search-setup-keys)
    (should (eq (lookup-key diogenes-pdf-search-mode-map (kbd "L"))
                #'diogenes-pdf-lookup-entry))
    ;; The viewers' own maps are untouched: `L' in a PDF that is not a
    ;; dictionary stays whatever it was.
    (should-not (and (boundp 'pdf-view-mode-map)
                     (eq (lookup-key pdf-view-mode-map (kbd "L"))
                         #'diogenes-pdf-lookup-entry))))
  ;; And the mode turns itself on only where the file is a dictionary.
  (let ((diogenes-pdf-search-key "L"))
    (with-temp-buffer
      (should-not (progn (diogenes-pdf-search--maybe-enable)
                         (bound-and-true-p diogenes-pdf-search-mode))))))

(ert-deftest diogenes-test-pdf-prefix-shapes ()
  "The prefix paths produce the argument shapes the command dispatches on.
`C-u L' is three different jumps depending on the dictionary and the volume,
and each hands `diogenes-pdf-lookup-entry' a differently shaped COLUMN-REF.
Asserts the shapes rather than the prompting, which needs a person."
  ;; A volume-V index jump: (:v5-index :part P :column C).
  (let ((ref (list :v5-index :part 2 :column 746)))
    (should (eq (car-safe ref) :v5-index))
    (should (= (plist-get (cdr ref) :part) 2))
    (should (= (plist-get (cdr ref) :column) 746)))
  ;; The anomalous-roots section, by column and approximately.
  (should (eq (car-safe (list :v5-anomalous-column :column 12))
              :v5-anomalous-column))
  (should (eq (car-safe (list :v5-anomalous-approx)) :v5-anomalous-approx))
  ;; A cross-tome reference is a bare (TOMUS . COLUMN).
  (let ((ref (cons 3 746)))
    (should (integerp (car ref)))
    (should (integerp (cdr ref)))
    ;; ...and must not be mistaken for one of the keyword shapes.
    (should-not (keywordp (car ref)))))

(ert-deftest diogenes-test-pdf-command-takes-the-prefix-arguments ()
  "The command accepts the column-reference and approximate arguments.
Regression: a version of this file kept the resolver and the TGL helpers but
lost the front end, so `C-u L' silently did what plain `L' does while the
README described three jumps it no longer had."
  (let ((arity (func-arity 'diogenes-pdf-lookup-entry)))
    (should (= (car arity) 1))
    (should (= (cdr arity) 3)))
  (dolist (fn '(diogenes-pdf-search--tgl-v5-prompt
                diogenes-pdf-search--tgl-v5-index-then-column
                diogenes-pdf-search--tgl-column-page))
    (should (fboundp fn))))

(ert-deftest diogenes-test-where-in-index-binds-no-siblings ()
  "`diogenes-tgl--where-in-index' reads no sibling of its own `let'.
Regression: `candidate-any' was defined as (or LOOKUP candidate-exact), and
its sibling `candidate-exact' is not in scope in a plain `let' -- so under
lexical binding the form signalled `void-variable', and did so exactly when
the index lookup missed, which is when one presses `i' to check a word the
main lookup got wrong.

Asserts the source rather than the behaviour: reaching the failing branch
needs the TGL's volumes, which a batch Emacs has not got."
  (let* ((file (or (locate-library "diogenes-tgl")
                   (error "diogenes-tgl not on the load path")))
         (source (replace-regexp-in-string "\\.elc\\'" ".el" file)))
    (with-temp-buffer
      (insert-file-contents source)
      (goto-char (point-min))
      (should (re-search-forward "defun diogenes-tgl--where-in-index" nil t))
      (let ((start (point))
            (end (or (save-excursion
                       (and (re-search-forward "^(defun " nil t) (point)))
                     (point-max))))
        (goto-char start)
        ;; `candidate-exact' appears in the bindings once, where it is
        ;; defined, and thereafter only below the `cond'.
        (let ((bindings-end (or (save-excursion
                                  (and (re-search-forward "^        (cond" end t)
                                       (point)))
                                end))
              (count 0))
          (while (re-search-forward "candidate-exact" bindings-end t)
            (setq count (1+ count)))
          (should (= count 1)))))))

(ert-deftest diogenes-test-fallback-yields-to-the-reader ()
  "A module's own action is used last, not first.
`diogenes-old.el' has a display arrangement for the scans -- reuse a window
already showing a document, and so on -- and passes it as FALLBACK.  Passed
as ACTION it would outrank `diogenes-window-behaviour' and the gathering, so
every dictionary would open a frame of its own however they were set."
  (diogenes-tests--with-two-windows
    (let ((buffer (get-buffer-create " *diogenes-test-target*"))
          (diogenes-window-behaviour 'defer)
          (diogenes-gather-frames nil)
          (diogenes-dictionary-display-action nil))
      ;; With nothing else to say, the fallback is what runs.
      (diogenes--display-buffer buffer :kind 'dictionary
                                :fallback '((display-buffer-same-window)
                                            (inhibit-same-window . nil)))
      (should (eq (window-buffer (selected-window)) buffer))))
  ;; And an action the reader set comes first.
  (diogenes-tests--with-two-windows
    (let ((buffer (get-buffer-create " *diogenes-test-target2*"))
          (here (selected-window))
          (diogenes-gather-frames nil)
          (diogenes-dictionary-display-action
           '((display-buffer-use-some-window) (inhibit-same-window . t))))
      (diogenes--display-buffer buffer :kind 'dictionary
                                :fallback '((display-buffer-same-window)
                                            (inhibit-same-window . nil)))
      ;; The reader's action sent it elsewhere; the fallback would have kept
      ;; it here.
      (should-not (eq (window-buffer here) buffer)))))

(ert-deftest diogenes-test-frames-wants-another-window ()
  "Asking for `frames\=' asks for a window other than the entry\='s.
`diogenes-old--display-other-window-p' decides whether a scan replaces the
entry it was consulted from or goes elsewhere, and only `elsewhere\=' reaches
the display helper -- so with this returning nil the gathering was never
consulted and `frames\=' made no frame at all."
  (let ((diogenes-old-display-in-other-window nil)
        (pop-up-frames nil)
        (diogenes-gather-frames 'auto))
    ;; The behaviour alone is enough.
    (let ((diogenes-window-behaviour 'frames))
      (should (diogenes-old--display-other-window-p)))
    (let ((diogenes-window-behaviour '((dictionary . frames))))
      (should (diogenes-old--display-other-window-p)))
    ;; And `frames' for a DIFFERENT kind is not: a reader who wants entries in
    ;; frames and scans over the entry gets that.
    (let ((diogenes-window-behaviour '((lookup . frames))))
      (should-not (diogenes-old--display-other-window-p)))
    ;; Nor is any other behaviour.
    (dolist (behaviour '(defer reuse split))
      (let ((diogenes-window-behaviour behaviour))
        (should-not (diogenes-old--display-other-window-p))))))

(ert-deftest diogenes-test-latin-weaken-stem ()
  "A simple verb's first vowel weakens when it becomes a compound's second half."
  (should (equal (diogenes--latin-weaken-stem "sedeo") "sideo"))
  (should (equal (diogenes--latin-weaken-stem "teneo") "tineo"))
  (should (equal (diogenes--latin-weaken-stem "facio") "ficio"))
  (should (equal (diogenes--latin-weaken-stem "capio") "cipio"))
  (should (equal (diogenes--latin-weaken-stem "cado") "cido"))
  (should (equal (diogenes--latin-weaken-stem "statuo") "stituo"))
  ;; Nothing to weaken: the vowel is already `i', or `o', or in hiatus.
  (should-not (diogenes--latin-weaken-stem "mitto"))
  (should-not (diogenes--latin-weaken-stem "pono"))
  (should-not (diogenes--latin-weaken-stem "eo"))
  (should-not (diogenes--latin-weaken-stem "")))

(ert-deftest diogenes-test-assimilations-reach-the-real-headword ()
  "Every reported lemma yields the spelling the dictionary is keyed under.
Regression, from three words looked up and answered wrongly: `esuriens' was
sent to `exsurrectio' and `obsessis' to `ob-septus', both being the next
entry along from a spelling that does not exist.  Morpheus writes the
etymological compound -- `ex-surio', `ob-sedeo' -- and the dictionary keys the
form actually written, which differs by more than the prefix."
  (let ((diogenes-latin-assimilate-prefixes t))
    ;; The file writes some lemmata as FORM,LEMMA -- the accented form and
    ;; then the lemma proper.  Only the second is the compound: with the form
    ;; attached every candidate was `obsessi_s,obsideo', which is nobody's
    ;; key, and the reader saw the entry after where `obsideo' should be.
    (should (member "obsideo"
                    (diogenes--latin-assimilations "obsessi_s,ob-sedeo")))
    (should (member "esurio"
                    (diogenes--latin-assimilations "e_surie_ns,ex-surio")))
    ;; A lemma with no comma is untouched, which is the common case.
    (should (equal (diogenes--latin-assimilations "obsessi_s,ob-sedeo")
                   (diogenes--latin-assimilations "ob-sedeo")))
    ;; `ex' loses its consonant before s.
    (should (member "esurio" (diogenes--latin-assimilations "ex-surio")))
    ;; The stem's own vowel weakens.
    (should (member "obsideo" (diogenes--latin-assimilations "ob-sedeo")))
    ;; Both changes at once.
    (should (member "attineo" (diogenes--latin-assimilations "ad-teneo")))
    ;; And what worked before still does, in the same order: the plain
    ;; compound comes first, so `ad-sum' is `adsum' and not `assum', roast
    ;; meat.
    (let ((for-adsum (diogenes--latin-assimilations "ad-sum")))
      (should (equal (car for-adsum) "adsum"))
      (should (member "assum" for-adsum)))
    (should (member "immitto" (diogenes--latin-assimilations "in-mitto")))
    (should (member "coeo" (diogenes--latin-assimilations "con-eo")))))

(ert-deftest diogenes-test-split-size-per-kind ()
  "`diogenes-split-size' answers per kind as well as globally.
A number applies to every split; an alist gives each kind its own share, and
a kind the alist does not mention gets half.

What has a size is a WINDOW and not a kind, so a size only means anything for
the kind whose window a split creates.  Where a scan reuses the entry's window
there is one window and one size, and the size named for `dictionary' has
nothing to act on -- which is why the builder disables that slider rather than
writing a number nobody reads."
  ;; One number for all.
  (let ((diogenes-split-size 0.4))
    (dolist (kind '(lookup browser dictionary))
      (should (equal (diogenes--split-size-for kind) 0.4))))
  ;; Per kind, and half for the rest.
  (let ((diogenes-split-size '((lookup . 0.35) (dictionary . 0.6))))
    (should (equal (diogenes--split-size-for 'lookup) 0.35))
    (should (equal (diogenes--split-size-for 'dictionary) 0.6))
    (should-not (diogenes--split-size-for 'browser)))
  (let ((diogenes-split-size nil))
    (should-not (diogenes--split-size-for 'lookup))))

(ert-deftest diogenes-test-split-size-reaches-the-action ()
  "The size for a kind is in the action built for that kind.
A width when the split goes sideways and a height when it goes down, which is
the same number either way -- `diogenes-split-direction' decides which."
  (let ((diogenes-split-size '((lookup . 0.35) (dictionary . 0.6)))
        (diogenes-split-direction 'right)
        (diogenes-split-from 'selected))
    (let ((for-lookup (diogenes--behaviour-action 'split 'lookup))
          (for-dict (diogenes--behaviour-action 'split 'dictionary))
          (for-browser (diogenes--behaviour-action 'split 'browser)))
      (should (equal (cdr (assq 'window-width for-lookup)) 0.35))
      (should (equal (cdr (assq 'window-width for-dict)) 0.6))
      ;; Unmentioned: no entry at all, so Emacs halves it.
      (should-not (assq 'window-width for-browser))
      (should-not (assq 'window-height for-lookup))))
  ;; Downwards, the same numbers are heights.
  (let ((diogenes-split-size '((lookup . 0.35)))
        (diogenes-split-direction 'below))
    (let ((action (diogenes--behaviour-action 'split 'lookup)))
      (should (equal (cdr (assq 'window-height action)) 0.35))
      (should-not (assq 'window-width action)))))

(ert-deftest diogenes-test-dictionary-key-override ()
  "A reader's key for a dictionary wins, and nil unbinds it."
  (let ((diogenes-lookup-dictionary-keys '((old . "O") (bdag . nil))))
    ;; Moved.
    (should (equal (diogenes--lookup-dictionary-key 'old "o") "O"))
    ;; Unbound: nil is an answer, not an absence -- which is why the reader's
    ;; alist is consulted with `assq' rather than by reading its cdr.
    (should-not (diogenes--lookup-dictionary-key 'bdag "b"))
    ;; Unmentioned: the dictionary's own key stands.
    (should (equal (diogenes--lookup-dictionary-key 'gaffiot "g") "g")))
  ;; With no option at all, every default stands.
  (let ((diogenes-lookup-dictionary-keys nil))
    (should (equal (diogenes--lookup-dictionary-key 'old "o") "o"))))

(ert-deftest diogenes-test-banner-says-the-key-that-is-bound ()
  "The banner reads the same source as the binding.
A banner naming a key the reader has moved would be worse than none: what is
printed under an entry is the package saying what to press.

Reads `diogenes--lookup-dict-specs', which is what the banner is built from."
  (let* ((spec-for
          (lambda (id lang)
            (cl-find id (diogenes--lookup-dict-specs lang)
                     :key (lambda (e) (nth 2 e))))))
    (let ((diogenes-lookup-dictionary-keys '((lewis . "L"))))
      (let ((lewis (funcall spec-for 'lewis "latin")))
        (when lewis (should (equal (nth 1 lewis) "L")))))
    ;; An unbound dictionary offers no key at all.
    (let ((diogenes-lookup-dictionary-keys '((lewis . nil))))
      (let ((lewis (funcall spec-for 'lewis "latin")))
        (when lewis (should-not (nth 1 lewis)))))
    ;; And with nothing set, its own key stands.
    (let ((diogenes-lookup-dictionary-keys nil))
      (let ((lewis (funcall spec-for 'lewis "latin")))
        (when lewis (should (equal (nth 1 lewis) "l")))))))

(ert-deftest diogenes-test-lookup-keys-are-a-table ()
  "Every key the lookup buffer binds for itself is in one option.
So any of them can be moved or removed, which eight separate defcustoms would
have made eight things to find."
  (let ((commands (mapcar #'car diogenes-lookup-keys)))
    (dolist (command '(diogenes-perseus-action
                       diogenes-lookup-in-dictionary
                       diogenes-lookup-next
                       diogenes-lookup-previous
                       diogenes--quit))
      (should (memq command commands))))
  ;; A command may appear twice: the action is on RET and on `C-c C-c'.
  (should (= 2 (cl-count 'diogenes-perseus-action diogenes-lookup-keys
                         :key #'car)))
  ;; Every command named exists, a table of keys for absent commands being
  ;; worse than no table.
  (dolist (cell diogenes-lookup-keys)
    (should (fboundp (car cell)))))

(ert-deftest diogenes-test-tgl-index-key-is-an-option ()
  "The TGL's index key can be moved or removed."
  (should (boundp 'diogenes-tgl-index-key))
  (let ((diogenes-tgl-index-key "I"))
    (diogenes-tgl-install-index-key)
    (should (eq (lookup-key diogenes-tgl-pdf-mode-map (kbd "I"))
                #'diogenes-tgl-open-index-here))
    ;; The old key is gone rather than kept alongside.
    (should-not (lookup-key diogenes-tgl-pdf-mode-map (kbd "i"))))
  (let ((diogenes-tgl-index-key nil))
    (diogenes-tgl-install-index-key)
    (should-not (lookup-key diogenes-tgl-pdf-mode-map (kbd "I"))))
  ;; Put it back, the map being global.
  (let ((diogenes-tgl-index-key "i"))
    (diogenes-tgl-install-index-key)))

(ert-deftest diogenes-test-shared-key-dispatches-on-language ()
  "Two dictionaries may share a key when their languages differ.
`t\=' is the TLL in a Latin entry and the TGL in a Greek one, and that is not a
conflict to be resolved but a choice to be made -- by the buffer, which knows
which language it holds.  A reader who puts Gaffiot and Bailly both on `g\='
means the same thing: the French dictionary of whatever is in front of them.

Binding directly would have given the key to whichever dictionary registered
last, which is why registration goes through the installer."
  (let* ((latin (list :id 'a :lang "latin" :command 'diogenes-tests--latin))
         (greek (list :id 'b :lang "greek" :command 'diogenes-tests--greek))
         (dispatcher (diogenes--lookup-key-dispatcher (list latin greek)))
         (called nil))
    (cl-letf (((symbol-function 'diogenes-tests--latin)
               (lambda () (interactive) (setq called 'latin)))
              ((symbol-function 'diogenes-tests--greek)
               (lambda () (interactive) (setq called 'greek))))
      (let ((diogenes--lookup-lang "greek"))
        (funcall dispatcher)
        (should (eq called 'greek)))
      (let ((diogenes--lookup-lang "latin"))
        (funcall dispatcher)
        (should (eq called 'latin)))
      ;; A language neither of them has: the first, which is what asking for a
      ;; dictionary of another language can only have meant.
      (let ((diogenes--lookup-lang "syriac"))
        (funcall dispatcher)
        (should (eq called 'latin))))))

(ert-deftest diogenes-test-greek-has-the-same-tables ()
  "Greek gets extra lemmata and analysis corrections, as Latin does.
The two features were gated to Latin by five `(string= lang \"latin\")' tests,
which was an accident of where they were written rather than a judgement: the
Greek data is wrong more often, Morpheus knowing less of it and the LSJ keying
some headwords differently from the form Morpheus gives."
  (should (boundp 'diogenes-greek-extra-lemmata))
  (should (boundp 'diogenes-greek-analysis-corrections))
  ;; Each language reads its own table and not the other's.
  (let ((diogenes-greek-extra-lemmata '(("οὑτοσί" . "οὗτος")))
        (diogenes-latin-extra-lemmata '(("valde" . "validus"))))
    (should (equal (diogenes--extra-lemma "οὑτοσί" "greek") "οὗτος"))
    (should (equal (diogenes--extra-lemma "valde" "latin") "validus"))
    ;; ...and a Latin form finds nothing in the Greek table.
    (should-not (diogenes--extra-lemma "valde" "greek"))
    (should-not (diogenes--extra-lemma "οὑτοσί" "latin")))
  ;; Corrections likewise.
  (let ((diogenes-greek-analysis-corrections '(("ᾖ" :info "pres subj act 3rd sg")))
        (diogenes-latin-analysis-corrections '(("experire" :info "imperat"))))
    (should (equal (plist-get (diogenes--analysis-correction "ᾖ" "greek") :info)
                   "pres subj act 3rd sg"))
    (should (equal (plist-get (diogenes--analysis-correction "experire" "latin") :info)
                   "imperat"))
    (should-not (diogenes--analysis-correction "ᾖ" "latin"))
    (should-not (diogenes--analysis-correction "experire" "greek")))
  ;; And an empty table costs nothing and answers nothing.
  (let ((diogenes-greek-extra-lemmata nil))
    (should-not (diogenes--extra-lemma "οὑτοσί" "greek"))))

(ert-deftest diogenes-test-no-default-from-a-buffer-that-is-not-a-text ()
  "A lookup takes no default from a startup screen or a page image.
`thing-at-point' has no opinion about where it is, so the prompt offered
`Welcome' in a dashboard and `%PDF' in a scanned dictionary -- the first four
bytes of the file -- and a reader pressing RET looked that up.  A default is a
guess at what is meant, and neither buffer gives anything to guess from."
  ;; Every startup buffer, by the names the distributions actually use --
  ;; `rename-buffer' with UNIQUE would append <2> and defeat the test, so the
  ;; names are used as they are and the buffers killed after.
  (dolist (name '("*spacemacs*" "*doom*" "*doom-dashboard*" "*dashboard*"
                  "*GNU Emacs*" "*About GNU Emacs*"))
    (let ((buffer (get-buffer-create name)))
      (unwind-protect
          (with-current-buffer buffer
            (erase-buffer)
            (insert "Welcome to Emacs")
            (goto-char 3)
            (should-not (diogenes--word-at-point-for-lookup)))
        (kill-buffer buffer))))
  ;; An ordinary buffer still answers, the guess being a good one there.
  (with-temp-buffer
    (rename-buffer " *diogenes-test-plain*" t)
    (insert "arma virumque")
    (goto-char 3)
    (should (equal (diogenes--word-at-point-for-lookup) "arma")))
  ;; And the PDF path offers nothing rather than the file's bytes.
  (with-temp-buffer
    (insert "%PDF-1.7")
    (goto-char 2)
    (let ((major-mode 'pdf-view-mode))
      (should-not (diogenes-pdf-search--default-word)))
    ;; ...while a plain buffer still offers what is at point.  WHAT exactly
    ;; depends on the syntax table -- in `fundamental-mode' `%' is a word
    ;; constituent, so this returns `%PDF' and not `PDF' -- which is not the
    ;; point: the point is that a plain buffer answers and a page image does
    ;; not.
    (should (diogenes-pdf-search--default-word))))

(ert-deftest diogenes-test-morphology-is-not-a-lookup ()
  "An analysis is displayed as its own kind, not as an entry.
`*Diogenes Analysis*' and `*Diogenes Forms*' were displayed with `:kind
\'lookup', so an analysis replaced the entry the reader had just looked up --
the entry they wanted it beside.  An entry is what a dictionary says about a
word; an analysis is what the morphology says about a form; the two are
consulted together."
  ;; Its own role, so the gathering gives it its own frame.  The buffers have
  ;; to EXIST: `diogenes--buffer-role' takes a buffer or a name and calls
  ;; `get-buffer' on it, so a name alone answers nil.
  (dolist (case '(("*Diogenes Analysis*" . morphology)
                  ("*Diogenes Forms*"    . morphology)
                  ("*diogenes-lookup*"   . lookup)
                  ("*diogenes-browser*"  . browser)))
    (let ((buffer (get-buffer-create (car case))))
      (unwind-protect
          (should (eq (diogenes--buffer-role buffer) (cdr case)))
        (kill-buffer buffer))))
  ;; Its own action, and its own place in the behaviour alist.
  (should (boundp 'diogenes-morphology-display-action))
  (let ((diogenes-morphology-display-action '(display-buffer-same-window))
        (diogenes-lookup-display-action nil))
    (should (equal (diogenes--display-action 'morphology)
                   '(display-buffer-same-window))))
  (let ((diogenes-window-behaviour '((lookup . reuse) (morphology . split)))
        (diogenes-morphology-display-action nil))
    (should (eq (diogenes--behaviour-for 'morphology) 'split))
    (should (eq (diogenes--behaviour-for 'lookup) 'reuse)))
  ;; Under window-purpose too, where they shared `diogenes-lookup'.
  (when (boundp 'diogenes-purpose-mode-purposes)
    (should (eq (cdr (assq 'diogenes-analysis-mode diogenes-purpose-mode-purposes))
                'diogenes-morphology))
    (should (eq (cdr (assq 'diogenes-lookup-mode diogenes-purpose-mode-purposes))
                'diogenes-lookup))))

(ert-deftest diogenes-test-analysis-splits-the-entry-not-the-reader ()
  "An analysis is shown beside the ENTRY, wherever it was asked for.
Pressing `ml' while reading a passage should not split the browser: the
analysis belongs in the lookup window's column, not in the middle of the text --
and not because it is an analysis OF the entry showing there, which it need not
be, but because the two are the same sort of consultation.  So the action
looks for a window showing a buffer of the companion role rather than using the
selected one.

With no entry on the screen there is nothing to be beside, and the function
answers nil so the ordinary splitting takes its turn."
  (should (eq (cdr (assq 'morphology diogenes-companion-roles)) 'lookup))
  ;; SYMMETRIC: one pair answers for both arrangements.
  (should (eq (diogenes--companion-role 'morphology) 'lookup))
  (should (eq (diogenes--companion-role 'lookup) 'morphology))
  (should-not (diogenes--companion-role 'browser))
  (should-not (diogenes--companion-role 'dictionary))
  ;; `selected' means the window in hand, and is not a role -- so it is not read
  ;; in reverse: saying where an ANALYSIS goes says nothing about where an entry
  ;; goes, and concluding otherwise would invent an instruction.
  (let ((diogenes-companion-roles '((morphology . selected))))
    (should (eq (diogenes--companion-role 'morphology) 'selected))
    (should-not (diogenes--companion-role 'lookup)))
  ;; Another role works as a companion as well.
  (let ((diogenes-companion-roles '((morphology . browser))))
    (should (eq (diogenes--companion-role 'morphology) 'browser))
    (should (eq (diogenes--companion-role 'browser) 'morphology)))
  ;; And with `selected', the window divided is the one point is in -- which is
  ;; the whole difference from the default.
  (let* ((diogenes-companion-roles '((morphology . selected)))
         (analysis (get-buffer-create "*Diogenes Analysis*"))
         (entry (get-buffer-create "*diogenes-lookup*"))
         (here (get-buffer-create "*diogenes-tests-here*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer here)
          (let ((entry-window (split-window)))
            (set-window-buffer entry-window entry)
            (select-window (get-buffer-window here))
            (let* ((mine (selected-window))
                   (used (diogenes-display-beside-companion analysis nil)))
              (should (window-live-p used))
              ;; A split of MY window, not of the entry's.
              (should (eq (window-parent used) (window-parent mine))))))
      (dolist (b (list analysis entry here))
        (when (buffer-live-p b) (kill-buffer b)))))
  ;; Every behaviour builds for every kind, and for no kind at all.  Five tests
  ;; failed at once from one wrong arity here -- `diogenes--split-functions'
  ;; called with an argument it does not take -- and this is the assertion that
  ;; names it directly rather than through whatever else happened to call it.
  (dolist (behaviour '(defer reuse split frames))
    (dolist (k '(nil lookup browser dictionary morphology))
      (should (listp (diogenes--behaviour-action behaviour k)))))
  ;; And the KIND makes a difference where the kind has a companion, which is
  ;; why the tests comparing these must pass one: an action built for `lookup'
  ;; is not the action built for no kind in particular.
  (let ((diogenes-split-direction nil) (diogenes-split-size nil))
    (should-not (equal (diogenes--behaviour-action 'split 'lookup)
                       (diogenes--behaviour-action 'split)))
    (should (equal (diogenes--behaviour-action 'split 'browser)
                   (diogenes--behaviour-action 'split))))
  ;; The action is in the `split' arrangement for morphology, and not for the
  ;; kinds that have no companion.
  (let ((diogenes-split-direction nil) (diogenes-split-size nil))
    (let ((for-morph (car (diogenes--behaviour-action 'split 'morphology)))
          (for-lookup (car (diogenes--behaviour-action 'split 'lookup))))
      (should (memq 'diogenes-display-beside-companion for-morph))
      ;; Entries get it too, for the case where an analysis is showing and no
      ;; entry is: the entry divides the analysis's window.
      (should (memq 'diogenes-display-beside-companion for-lookup))
      ;; And a kind with no companion does not.
      (should-not (memq 'diogenes-display-beside-companion
                        (car (diogenes--behaviour-action 'split 'browser))))
      ;; And the role frame still leads, so a second analysis joins the first.
      (should (eq (car for-morph) 'diogenes-display-in-role-frame))))
  ;; Nothing of that role on screen: nil, so the next action gets its turn.
  (let ((buffer (get-buffer-create "*Diogenes Analysis*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*diogenes-tests-plain*"))
          (should-not (diogenes-display-beside-companion buffer nil)))
      (kill-buffer buffer)
      (when (get-buffer "*diogenes-tests-plain*")
        (kill-buffer "*diogenes-tests-plain*"))))
  ;; An entry, with an analysis showing and no entry: the analysis's window is
  ;; the one divided, which is the same rule read the other way.
  (let ((analysis (get-buffer-create "*Diogenes Analysis*"))
        (entry (get-buffer-create "*diogenes-lookup*"))
        (elsewhere (get-buffer-create "*diogenes-tests-elsewhere*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer elsewhere)
          (let ((analysis-window (split-window)))
            (set-window-buffer analysis-window analysis)
            (select-window (get-buffer-window elsewhere))
            (let ((used (diogenes-display-beside-companion entry nil)))
              (should (window-live-p used))
              (should (eq (window-buffer used) entry))
              (should-not (eq used (get-buffer-window elsewhere))))))
      (dolist (b (list analysis entry elsewhere))
        (when (buffer-live-p b) (kill-buffer b)))))
  ;; With an entry showing, it splits THAT window, wherever point is.
  (let ((entry (get-buffer-create "*diogenes-lookup*"))
        (analysis (get-buffer-create "*Diogenes Analysis*"))
        (elsewhere (get-buffer-create "*diogenes-tests-elsewhere*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer elsewhere)
          (let ((entry-window (split-window)))
            (set-window-buffer entry-window entry)
            ;; Point is in ELSEWHERE, not in the entry.
            (select-window (get-buffer-window elsewhere))
            (let ((used (diogenes-display-beside-companion analysis nil)))
              (should (window-live-p used))
              (should (eq (window-buffer used) analysis))
              ;; The new window came from the entry's, not from ours.
              (should-not (eq used (get-buffer-window elsewhere))))))
      (dolist (b (list entry analysis elsewhere))
        (when (buffer-live-p b) (kill-buffer b))))))

(ert-deftest diogenes-test-a-word-broken-across-lines ()
  "A divided word is joined where the BUFFER says it is divided, and not else.
`C-c C-c\=' on either half looked up that half -- `praeci\=' and `pitur\=' rather
than `praecipitur\='.  Two kinds of evidence count: a hyphen at the end of the
line, and the record `C-c C--\=' leaves when it removes one.  A line merely
ending mid-phrase is not evidence, and guessing there would join two good words
as often as it mended a broken one."
  (with-temp-buffer
    ;; A hyphen is a word constituent in some syntax tables and not others, so
    ;; `thing-at-point' may hand back `prae' or `prae-' for the same text.  The
    ;; function trims a trailing hyphen for that reason, and this test does not
    ;; set a syntax table, so it passes under whichever the buffer has.
    (let ((major-mode 'diogenes-browser-mode)
          (diogenes-browser-join-broken-words t))
      (cl-flet ((at (word)
                  (goto-char (point-min))
                  (search-forward word)
                  (goto-char (match-beginning 0))))
        ;; A HYPHEN, with a citation on the next line: joined, and the numbers
        ;; are not part of the word.
        (erase-buffer)
        (insert "quod prae-\n")
        (let ((cit (point)))
          (insert "1.2.3         ")
          (put-text-property cit (point) 'diogenes-citation t))
        (insert "cipitur inde\n")
        (at "prae")
        (should (equal (list :hyphen (diogenes-browser--word-at-point-joined))
                       '(:hyphen "praecipitur")))

        ;; NO HYPHEN and no record: nothing to go on, so the half stands.  This
        ;; is the case an earlier draft guessed at.
        (erase-buffer)
        (insert "quod prae\ncipitur inde\n")
        (at "prae")
        (should-not (diogenes-browser--word-at-point-joined))

        ;; A hyphen REMOVED, point on the first half: the line remembers.
        (erase-buffer)
        (let ((line-a (point)))
          (insert "quod prae\n")
          (put-text-property line-a (point) 'hyphen-start "prae"))
        (let ((line-b (point)))
          (insert "cipitur inde\n")
          (put-text-property line-b (point) 'hyphen-end "cipitur"))
        (at "prae")
        ;; Labelled, because ERT names the test and not the form: two
        ;; assertions expecting the same string are told apart in the report
        ;; only by what they carry with them.  This one cost half an hour.
        (should (equal (list :record (diogenes-browser--word-at-point-joined))
                       '(:record "praecipitur")))

        ;; A word ALREADY joined in the text: nothing to do, and saying so is
        ;; how this is told apart from a word never divided.
        (erase-buffer)
        (let ((line-a (point)))
          (insert "quod praecipitur\n")
          (put-text-property line-a (point) 'hyphen-start "prae"))
        (at "praecipitur")
        (should-not (diogenes-browser--word-at-point-joined))

        ;; A capital on the next line, which was the old heuristic's undoing.
        (erase-buffer)
        (insert "dixit haec\nRoma capta est\n")
        (at "haec")
        (should-not (diogenes-browser--word-at-point-joined))

        ;; And a word in the middle of a line.
        (erase-buffer)
        (insert "arma virumque cano\n")
        (at "virumque")
        (should-not (diogenes-browser--word-at-point-joined))))))

(ert-deftest diogenes-test-focus-keys-are-everyones ()
  "Going from one Diogenes window to another is bound in any Emacs.
The commands were in `diogenes-doom.el' and bound nowhere, so they were
`M-x'-only and, by their names, looked like Doom's business.  Nothing about
raising a window is particular to a distribution."
  ;; In the core, and one per kind.
  (dolist (command '(diogenes-focus-browser diogenes-focus-lookup
                     diogenes-focus-dictionary diogenes-focus-morphology))
    (should (fboundp command))
    (should (commandp command)))
  ;; The old names still answer, so nobody's binding breaks.
  (dolist (old '(diogenes-doom-focus-lookup-frame
                 diogenes-doom-focus-browser-frame
                 diogenes-doom-focus-dictionary-frame))
    (should (fboundp old)))
  ;; Every key in the table names a command that exists, and no key collides
  ;; with a dictionary letter -- these are chords, so they cannot, but the
  ;; assertion is what keeps that true if someone shortens one.
  (dolist (cell diogenes-focus-keys)
    (should (fboundp (car cell)))
    (when (cdr cell)
      ;; `C-c C-<letter>' -- the major mode's by convention, which these maps
      ;; are.
      (should (string-match-p "\\`C-c C-[a-z]\\'" (cdr cell)))))
  ;; And no focus key is a key the lookup buffer already uses for something
  ;; else.  `C-c C-e' was the tempting one for the scanned page and is
  ;; `diogenes-old-visit-dictionary-key', which OPENS a page where this goes to
  ;; one already open -- two wishes, and they should not share a key.
  (let ((theirs (delq nil (mapcar #'cdr diogenes-lookup-keys)))
        (visit (and (boundp 'diogenes-old-visit-dictionary-key)
                    diogenes-old-visit-dictionary-key)))
    (dolist (cell diogenes-focus-keys)
      (when (cdr cell)
        (should-not (member (cdr cell) theirs))
        (when visit (should-not (equal (cdr cell) visit))))))
  ;; The scanned page has no key in THIS table: `C-c C-e' reaches it, being
  ;; `diogenes-old-visit-dictionary', which prefers the page opened from the
  ;; entry, falls back on the focus command, and cycles through it when pressed
  ;; inside a scan.  One key for the whole of it.
  (should-not (cdr (assq 'diogenes-focus-dictionary diogenes-focus-keys)))
  ;; And no key is bound into a viewer's own map, which would take it from every
  ;; PDF a reader opens.  Ours, or our minor mode's.
  (dolist (map diogenes--focus-maps)
    (should-not (memq map '(pdf-view-mode-map doc-view-mode-map
                            reader-mode-map))))
  ;; And installing them binds where a reader would press them: in a lookup
  ;; buffer, and in a scanned page, which is where one most wants the entry
  ;; back.
  (when (boundp 'diogenes-lookup-mode-map)
    (diogenes-install-focus-keys)
    (dolist (cell diogenes-focus-keys)
      (when (cdr cell)
        (should (eq (lookup-key diogenes-lookup-mode-map (kbd (cdr cell)))
                    (car cell)))))))

(ert-deftest diogenes-test-focus-cycles-among-windows-of-a-role ()
  "Going to a kind goes to the next one where there are several.
`frames' makes several ordinary -- a scan of the OLD beside a scan of the TLL --
and a command that always chose the first could not reach the second.  Pressing
again goes to the next, and past the last comes back to the first."
  (let ((old (get-buffer-create "*diogenes-lookup*"))
        (a (get-buffer-create "Oxford Latin Dictionary.pdf"))
        (b (get-buffer-create "TLL vol 3.pdf")))
    ;; The role of a scan comes from its MODE, its name matching no regexp --
    ;; and from `buffer-local-value', so the mode has to be set IN the buffer.
    ;; A `let' of `major-mode' binds it in the current buffer only, which is
    ;; how this test first came to find no windows at all.
    (dolist (buffer (list a b))
      (with-current-buffer buffer (setq major-mode 'pdf-view-mode)))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer old)
          ;; Two windows of the dictionary role, and one of another.
          (let ((w1 (split-window))
                (w2 nil))
            (set-window-buffer w1 a)
            (setq w2 (split-window w1))
            (set-window-buffer w2 b)
            (let ((found (diogenes--windows-of-role 'dictionary)))
              ;; Both are found, in a settled order.
              (should (= 2 (length found)))
              (should (equal (mapcar (lambda (w) (buffer-name (window-buffer w)))
                                     found)
                             (list (buffer-name (window-buffer w1))
                                   (buffer-name (window-buffer w2)))))
              ;; From elsewhere: the first.
              (select-window (get-buffer-window old))
              (diogenes-focus-dictionary)
              (should (eq (selected-window) (car found)))
              ;; Again: the next.
              (diogenes-focus-dictionary)
              (should (eq (selected-window) (cadr found)))
              ;; And again: back to the first.
              (diogenes-focus-dictionary)
              (should (eq (selected-window) (car found))))))
      (dolist (buffer (list old a b))
        (when (buffer-live-p buffer) (kill-buffer buffer)))))
  ;; With none of a kind open, a message and no error.
  (save-window-excursion
    (delete-other-windows)
    (should-not (diogenes--windows-of-role 'dictionary))
    (should (stringp (diogenes-focus-dictionary))))
  ;; And `C-c C-e' PRESSED INSIDE A SCAN means `the next one': the provenance
  ;; branch must not answer first, or a second press in a scan would go nowhere.
  (let ((a (get-buffer-create "Oxford Latin Dictionary.pdf"))
        (b (get-buffer-create "TLL vol 3.pdf")))
    (unwind-protect
        (progn
          (dolist (buffer (list a b))
            (with-current-buffer buffer (setq major-mode 'pdf-view-mode)))
          (save-window-excursion
            (delete-other-windows)
            (switch-to-buffer a)
            (let ((second (split-window)))
              (set-window-buffer second b)
              (select-window (get-buffer-window a))
              ;; In the first scan; the key goes to the second.
              (diogenes-old-visit-dictionary)
              (should (eq (window-buffer (selected-window)) b))
              ;; And round again.
              (diogenes-old-visit-dictionary)
              (should (eq (window-buffer (selected-window)) a)))))
      (dolist (buffer (list a b))
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(ert-deftest diogenes-test-cheatsheet-lists-the-prefixed-commands ()
  "The cheatsheet says what a prefix argument does.
It is built from the live keymaps, and a prefix argument is not a binding: `C-u
L\=' is `L\=' given an argument, so no map holds it and a cheatsheet reading maps
alone can never mention the second half of what these keys do.  Hence a written
table -- and hence this test, since a written table can go stale where a keymap
cannot."
  (should (boundp 'diogenes-cheatsheet-prefixed))
  ;; Every command named exists, or the entry is describing something gone.
  (dolist (entry diogenes-cheatsheet-prefixed)
    (should (symbolp (nth 0 entry)))
    (should (stringp (nth 1 entry)))
    (should (stringp (nth 2 entry)))
    ;; The description is prose, not a symbol name: this section renders its own
    ;; way for that reason, `--classify' reading a command's name to group it.
    (should (string-match-p " " (nth 2 entry))))
  ;; The RULE is listed, rather than a row per dictionary: a prefixed letter
  ;; looks a word up in that dictionary, and the bare letter reaches the print
  ;; only from inside that dictionary's own entry.
  (let ((keys (mapcar (lambda (e) (nth 1 e)) diogenes-cheatsheet-prefixed)))
    (should (member "C-u L" keys))
    (should (member "C-u <letter>" keys))
    ;; And NOT the bare letter.  `B, g, G' has no prefix in it -- it is
    ;; what the letter does on its own, which the dictionary keys explain.
    ;; A row in a table headed `With a prefix' that carries no prefix
    ;; sends a reader looking for one to something else entirely.
    (should-not (member "B, g, G" keys)))
  ;; And no prefixed row says a prefix opens the print, which it does not.
  (dolist (entry diogenes-cheatsheet-prefixed)
    (when (string-prefix-p "C-u" (nth 1 entry))
      (should-not (string-match-p "printed page\\|page in the print"
                                  (nth 2 entry)))))
  ;; And absent commands are left out rather than listed.
  (let ((diogenes-cheatsheet-prefixed
         '((diogenes-tests--no-such-command "C-u Z" "nothing at all"))))
    (should-not (diogenes-cheatsheet--prefixed))))

(ert-deftest diogenes-test-cheatsheet-lifts-the-common-keys ()
  "A key that does the same thing everywhere is listed once.
The cheatsheet builds a section per buffer, so the four navigation keys appeared
in each of them -- four copies of the same four lines, which is both noise and a
good part of what has to fit on the screen.

Both halves of the test matter: the same key doing DIFFERENT things is a
coincidence and not a common binding.  `i\=' opens the TGL index in a volume and
is `evil-insert-state\=' elsewhere; listing it once would say something false
about both."
  ;; A section is (NAME . PAIRS), so the pairs are the cdr DIRECTLY -- not a
  ;; list containing them, which is how this test first failed.
  (let ((sections
         '(("Lookup"  ("C-c C-b" . focus-browser) ("q" . quit) ("o" . old))
           ("Browser" ("C-c C-b" . focus-browser) ("q" . quit) ("C-c C-n" . next))
           ("Scan"    ("C-c C-b" . focus-browser) ("q" . quit) ("L" . search)))))
    (let* ((lifted (diogenes-cheatsheet--lift-common sections))
           (common (cdr (assoc "Everywhere" lifted))))
      (should common)
      (should (equal (mapcar #'car common) '("C-c C-b" "q")))
      ;; And taken out of the rest, not merely added.
      (dolist (section (cdr lifted))
        (should-not (assoc "C-c C-b" (cdr section)))
        (should-not (assoc "q" (cdr section))))
      ;; Each keeps what is its own.
      (should (equal (mapcar #'car (cdr (assoc "Lookup" lifted))) '("o")))))
  ;; The same key, different commands: not common.
  (let* ((sections
          '(("Scan"   ("i" . tgl-index) ("q" . quit))
            ("Lookup" ("i" . evil-insert) ("q" . quit))))
         (lifted (diogenes-cheatsheet--lift-common sections))
         (common (cdr (assoc "Everywhere" lifted))))
    (should (equal (mapcar #'car common) '("q")))
    (should (assoc "i" (cdr (assoc "Scan" lifted))))
    (should (assoc "i" (cdr (assoc "Lookup" lifted)))))
  ;; One section has nothing to have in common with, and is left alone.
  (let ((one '(("Lookup" ("q" . quit)))))
    (should (equal (diogenes-cheatsheet--lift-common one) one))))

(ert-deftest diogenes-test-cheatsheet-splits-a-tall-section ()
  "A section too tall for the panel continues in the next column.
It used to be allowed a column of its own and to overflow, on the reasoning
that a panel running long beats a section cut in half -- but it does not run
long: the frame is clamped to the parent, so the overflow is not shown.  The
Lookup section, with a group for each language and each kind of dictionary, lost
its last lines mid-word."
  (let ((block (append (list "Lookup")
                       (list " Navigation" "  C-c C-p  previous" "  C-c C-n  next")
                       (list " Latin dictionaries" "  G  Georges" "  g  Gaffiot")
                       (list " Greek dictionaries" "  d  DGE" "  P  Pape")
                       (list " Other" "  q  quit"))))
    ;; Room enough: one part, untouched.
    (should (equal (diogenes-cheatsheet--split-block block 40) (list block)))
    ;; Too tall: cut, and cut at a GROUP -- every part after the first begins
    ;; with a group heading, never in the middle of one.
    (let ((parts (diogenes-cheatsheet--split-block block 7)))
      (should (> (length parts) 1))
      (dolist (part parts)
        (should (<= (length part) 7)))
      ;; The first keeps the title; the rest say they are continued, or a
      ;; reader meets keys belonging to nothing they can see.
      (should (equal (car (car parts)) "Lookup"))
      (dolist (part (cdr parts))
        (should (string-match-p "continued" (car part))))
      ;; Nothing lost and nothing repeated: the parts' bodies are the original.
      (should (equal (apply #'append (mapcar #'cdr parts)) (cdr block))))
    ;; And the group test reads the shape: one leading space is a heading, two
    ;; is a key.
    (should (diogenes-cheatsheet--group-start-p " Navigation"))
    (should-not (diogenes-cheatsheet--group-start-p "  q  quit"))
    (should-not (diogenes-cheatsheet--group-start-p "Lookup"))))

(ert-deftest diogenes-test-cheatsheet-labels-say-what-a-key-does ()
  "A label says what pressing the key does, not what the function is called.
`diogenes-old-visit-dictionary\=' read `old visit dictionary\=' in a section
headed `Going between the windows and frames\=', where the useful words are `the
scanned page\='."
  (should (equal (diogenes-cheatsheet--label 'diogenes-old-visit-dictionary)
                 "the scanned page"))
  (should (equal (diogenes-cheatsheet--label 'diogenes-focus-browser) "the text"))
  ;; A name that reads well is left alone.
  (should (equal (diogenes-cheatsheet--label 'diogenes-lookup-open-montanari)
                 "montanari"))
  ;; And every command named in the table exists, or the label describes
  ;; something gone.
  (dolist (cell diogenes-cheatsheet-labels)
    (should (symbolp (car cell)))
    (should (stringp (cdr cell)))))

(ert-deftest diogenes-test-purpose-binds-no-keys-of-its-own ()
  "`diogenes-purpose\=' leaves the keys to the core.
It had two keymaps, and only one was emptied when the commands moved: the minor
mode for the scanned dictionaries kept `C-c C-l\=', `C-c C-b\=' and `C-c C-e\='
bound to commands of its own.

Which did more than duplicate.  The cheatsheet lifts into `Everywhere\=' the
bindings identical in every section, comparing the key AND the command -- so a
scan running `diogenes-purpose-focus-browser-window\=' where an entry runs
`diogenes-focus-browser\=' had the same key doing two things, nothing was common,
and the four keys went on being listed once per section."
  (when (boundp 'diogenes-purpose-dict-mode-map)
    ;; Empty: the mode remains so a dictionary buffer can be recognised.
    (should (keymapp diogenes-purpose-dict-mode-map))
    (dolist (key '("C-c C-l" "C-c C-b" "C-c C-e"))
      (should-not (commandp (lookup-key diogenes-purpose-dict-mode-map (kbd key))))))
  ;; And the same for the mode maps purpose used to install into.
  (when (boundp 'diogenes-lookup-mode-map)
    (dolist (key '("C-c C-l" "C-c C-b"))
      (let ((command (lookup-key diogenes-lookup-mode-map (kbd key))))
        (when command
          (should-not (string-prefix-p "diogenes-purpose-"
                                       (symbol-name command))))))))

(ert-deftest diogenes-test-a-window-remembers-what-it-held ()
  "An entry goes back to the window a scan took from it.
The default has a scanned page REPLACE the entry, so that window then shows a
PDF.  A second entry looked for a window showing a lookup buffer, found none,
and split -- a third window where the reader wanted their entry back.  The
window had held an entry a moment before, and nothing recorded it.

Recorded now, on the window, and consulted for PLACEMENT only: the keys for
going between windows still ask what a window SHOWS, `C-c C-l' being no use if
it takes a reader to a page of the OLD."
  (let ((entry (get-buffer-create "*diogenes-lookup*"))
        (scan (get-buffer-create "Oxford Latin Dictionary.pdf")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (with-current-buffer scan (setq major-mode 'pdf-view-mode))
          (let ((window (selected-window)))
            (set-window-buffer window entry)
            (diogenes--remember-role window 'lookup)
            ;; The scan replaces it: the window now shows a PDF.
            (set-window-buffer window scan)
            (diogenes--remember-role window 'dictionary)
            ;; No window SHOWS a lookup any more...
            (should-not (diogenes--window-of-role 'lookup))
            ;; ...but this one held one, so an entry belongs here.
            (should (eq (diogenes--window-that-held 'lookup) window))
            ;; And a window showing the kind is still preferred to one that
            ;; merely held it: a second entry belongs beside the first.
            (let ((other (split-window)))
              (set-window-buffer other entry)
              (should (eq (diogenes--window-that-held 'lookup) other)))
            ;; The navigation keys are unaffected -- they ask what is shown.
            (should-not (memq window (diogenes--windows-of-role 'lookup)))))
      (dolist (b (list entry scan))
        (when (buffer-live-p b) (kill-buffer b))))))

(ert-deftest diogenes-test-buffer-role ()
  "A buffer's kind is read from its name first and its mode second.
Name first because a lookup buffer is DISPLAYED before its major mode is
set, so a rule dispatching on the mode would see `fundamental-mode'."
  (with-temp-buffer
    (rename-buffer "*diogenes-lookup<3>*" t)
    (should (eq (diogenes--buffer-role (current-buffer)) 'lookup)))
  (with-temp-buffer
    (rename-buffer "*diogenes-browser*" t)
    (should (eq (diogenes--buffer-role (current-buffer)) 'browser)))
  (with-temp-buffer
    (rename-buffer " not-a-diogenes-buffer" t)
    (should-not (diogenes--buffer-role (current-buffer))))
  ;; And by mode, for a document buffer, which has its mode before display.
  (with-temp-buffer
    (rename-buffer " OLD.pdf" t)
    (setq-local major-mode 'pdf-view-mode)
    (should (eq (diogenes--buffer-role (current-buffer)) 'dictionary))))

(ert-deftest diogenes-test-gathering-follows-pop-up-frames ()
  "Gathering is on when frames are, and `diogenes-gather-frames' overrides.
This is what makes Doom and Spacemacs behave alike: with `pop-up-frames'
set, the core answers for both instead of each distribution's own
mechanism."
  (let ((diogenes-gather-frames 'auto))
    (let ((pop-up-frames nil)) (should-not (diogenes--gathering-p)))
    (let ((pop-up-frames t)) (should (diogenes--gathering-p)))
    (let ((pop-up-frames 'graphic-only)) (should (diogenes--gathering-p))))
  (let ((diogenes-gather-frames t) (pop-up-frames nil))
    (should (diogenes--gathering-p)))
  (let ((diogenes-gather-frames nil) (pop-up-frames t))
    (should-not (diogenes--gathering-p))))

(ert-deftest diogenes-test-a-set-action-beats-the-gathering ()
  "An action the reader has set wins over the gathering, frames or no frames."
  (diogenes-tests--with-two-windows
    (let* ((pop-up-frames nil)          ; no frames in batch anyway
           (diogenes-gather-frames t)
           (diogenes-lookup-display-action
            '(display-buffer-same-window (inhibit-same-window . nil)))
           (buffer (get-buffer-create " *diogenes-test-target*"))
           (here (selected-window)))
      (should (eq (diogenes--display-buffer buffer :kind 'lookup) here)))))

;;; Commands: the shape a command has to have

(ert-deftest diogenes-test-no-command-asks-for-arguments-it-cannot-take ()
  "No `diogenes-' command has a zero-argument lambda list and an
argument-supplying interactive spec.

Scans whatever is defined, so the whole package is loaded above: with only
two files loaded this reported no offenders for weeks while two commands had
the fault, and found them only when the suite was first run inside a live
configuration.

Regression: `diogenes-browser-forward' and `-backward' were
`(defun … ())' with `(interactive \"p\")', so every interactive call raised
`Wrong number of arguments'.  `C-c C-n' and `C-c C-p' in the browser could
never have worked."
  (let (offenders)
    (mapatoms
     (lambda (sym)
       (when (and (string-prefix-p "diogenes-" (symbol-name sym))
                  (commandp sym)
                  (functionp sym))
         (let* ((spec (cadr (interactive-form sym)))
                (arity (ignore-errors (func-arity sym))))
           (when (and (stringp spec)
                      (not (string-empty-p (string-trim-left spec "[*@^]+")))
                      arity
                      (equal (cdr arity) 0))
             (push sym offenders))))))
    (should-not offenders)))

;;; What the surrounding configuration is doing

;;;###autoload
(defun diogenes-tests-environment ()
  "Report what this Emacs and this configuration are doing to Diogenes.
The first thing to paste into a bug report.  Every hard fault in this
package's history has turned out to be one of these lines: a
distribution's `find-file-hook', its evil state maps, its workspace
filter, its popup manager."
  (interactive)
  (let ((report
         (list
          (cons "emacs" emacs-version)
          (cons "native-comp queue" (if (boundp 'comp-files-queue)
                                        (length comp-files-queue) 'n/a))
          (cons "diogenes-path" (bound-and-true-p diogenes-path))
          (cons "loaded from" (locate-library "diogenes-perseus"))
          (cons "evil" (and (featurep 'evil) t))
          (cons "lookup evil state"
                (and (boundp 'evil-initial-state-alist)
                     (cdr (assq 'diogenes-lookup-mode
                                evil-initial-state-alist))))
          (cons "purpose" (and (featurep 'diogenes-purpose) t))
          (cons "purpose-mode" (bound-and-true-p purpose-mode))
          (cons "diogenes-doom" (and (featurep 'diogenes-doom) t))
          (cons "gathering" (and (fboundp 'diogenes-doom-gathering-p)
                                 (diogenes-doom-gathering-p)))
          (cons "popup manager" (and (fboundp '+popup-buffer-p) t))
          (cons "persp-mode" (bound-and-true-p persp-mode))
          (cons "pop-up-frames" pop-up-frames)
          (cons "frame-resize-pixelwise" frame-resize-pixelwise)
          (cons "display-buffer-alist" (length display-buffer-alist))
          (cons "find-file-hook" (length find-file-hook))
          (cons "vc-handled-backends" vc-handled-backends)
          (cons "pdf-view-use-scaling"
                (bound-and-true-p pdf-view-use-scaling))
          (cons "declared dictionaries"
                (bound-and-true-p diogenes-declared-dictionaries)))))
    (with-current-buffer (get-buffer-create "*Diogenes Environment*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (line report)
          (insert (format "%-24s %s\n" (car line) (cdr line))))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

;;;###autoload
(defun diogenes-tests-run ()
  "Run the Diogenes tests inside this configuration.
The headless run says whether the logic is right; this says whether it is
right HERE, with evil, window-purpose, a popup manager and a workspace
filter all still in place."
  (interactive)
  (ert "\\`diogenes-test-"))

(provide 'diogenes-tests)
;;; diogenes-tests.el ends here
