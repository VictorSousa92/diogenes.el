;;; display-repro.el --- Why does a lookup reuse the browser's window?  -*- lexical-binding: t -*-

;; Run it, from the package directory:
;;
;;     emacs -Q -batch -L . -l test/display-repro.el
;;
;; and again with window-purpose available, if it is installed somewhere:
;;
;;     emacs -Q -batch -L . -L ~/.config/spacemacs-emacs/elpa/31.1/develop/window-purpose-20240101.0 \
;;           -l test/display-repro.el
;;
;; Or inside a running Emacs -- which is the interesting case, since that is
;; where the fault appears:
;;
;;     M-x load-file RET .../test/display-repro.el RET
;;     M-x diogenes-repro RET
;;
;; It reports one table: for each combination of window-purpose on or off and
;; `diogenes-lookup-display-action' set or nil, how many windows the frame
;; ends with after a lookup-shaped buffer is displayed from a browser-shaped
;; one.  Two windows means the entry got its own; one means it took the
;; browser's.
;;
;; The point of doing it this way is that the whole state is built from
;; nothing each time, so nothing survives between cases -- which is what went
;; wrong when this was chased by hand: a lookup window left over from an
;; earlier attempt makes the next attempt reuse it, correctly, and look like
;; the fault under investigation.

;;; Code:

(require 'diogenes-lisp-utils)
(require 'diogenes-perseus)

(defvar diogenes-repro--action
  '((diogenes-display-in-role-frame display-buffer-pop-up-window))
  "The action under suspicion.")

(defun diogenes-repro--case (label purpose-on action)
  "Run one case and return a line describing what happened."
  (let ((frame (selected-frame)))
    (with-selected-frame frame
      (delete-other-windows)
      ;; A browser-shaped buffer: the name is what `diogenes--buffer-role'
      ;; reads, and the mode is what window-purpose reads.
      (let ((browser (get-buffer-create "*diogenes-browser*")))
        (with-current-buffer browser
          (when (fboundp 'diogenes-browser-mode)
            (ignore-errors (diogenes-browser-mode))))
        (switch-to-buffer browser)
        (set-window-dedicated-p (selected-window) nil)
        ;; And no lookup window anywhere, which is the state the fault is
        ;; reported in.
        (dolist (buffer (buffer-list))
          (when (string-match-p "\\`\\*diogenes-lookup" (buffer-name buffer))
            (kill-buffer buffer)))
        (when (and purpose-on (fboundp 'purpose-mode)) (purpose-mode 1))
        (when (and (not purpose-on) (fboundp 'purpose-mode)) (purpose-mode -1))
        (let* ((diogenes-lookup-display-action action)
               (target (get-buffer-create "*diogenes-lookup*"))
               (before (length (window-list)))
               (window (diogenes--display-buffer target :kind 'lookup))
               (after (length (window-list)))
               (browser-visible (and (get-buffer-window browser) t)))
          (format "%-34s before=%d after=%d browser-visible=%-5s window=%s"
                  label before after
                  (if browser-visible "yes" "no")
                  (if window "yes" "NONE")))))))

;;;###autoload
(defun diogenes-repro ()
  "Report how a lookup is displayed, in four combinations."
  (interactive)
  (let* ((purpose (and (require 'window-purpose nil t) t))
         (lines
          (list
           (format "window-purpose available: %s" (if purpose "yes" "no"))
           (format "pop-up-frames: %s   split-height-threshold: %s   \
split-width-threshold: %s"
                   pop-up-frames split-height-threshold split-width-threshold)
           (format "frame: %d lines x %d columns"
                   (frame-height) (frame-width))
           ""
           (diogenes-repro--case "action set, purpose off" nil
                                 diogenes-repro--action)
           (diogenes-repro--case "action nil, purpose off" nil nil)
           (when purpose
             (diogenes-repro--case "action set, purpose ON " t
                                   diogenes-repro--action))
           (when purpose
             (diogenes-repro--case "action nil, purpose ON " t nil))
           ""
           "after=2 means the entry got its own window."
           "after=1 with browser-visible=no means it took the browser's.")))
    (if noninteractive
        (dolist (line lines) (when line (princ (format "%s\n" line))))
      (with-current-buffer (get-buffer-create "*diogenes-repro*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (dolist (line lines) (when line (insert line "\n")))
          (goto-char (point-min))
          (special-mode))
        (display-buffer (current-buffer))))))

(when noninteractive (diogenes-repro))

(provide 'display-repro)
;;; display-repro.el ends here
