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
