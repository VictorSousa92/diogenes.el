;;; classicist-windows-compat.el --- window placement for an unforked base -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology, convenience

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

;; WHAT THE FORK DID BY EDITING, DONE BY ADVICE INSTEAD.
;;
;; `classicist-windows.el' decides where a buffer goes.  A base that calls it
;; needs no help; upstream Diogenes calls `pop-to-buffer' directly, at sixteen
;; places in eleven functions, and every one of them wants routing through the
;; suite instead.
;;
;; Editing those eleven functions is what the fork does, and it is why the
;; fork exists at all for four of its files.  Advice does the same thing
;; without a fork, because `pop-to-buffer' is an ordinary function and so can
;; be rebound for the dynamic extent of a call -- even inside code that was
;; byte-compiled against the real one.
;;
;; THE COST, SAID PLAINLY.  The rebinding holds for everything called during
;; that extent and not only for the call intended.  None of these eleven
;; displays a second buffer for another reason, so today it is exact; a future
;; upstream that displayed two would give both the same role.  That is a
;; smaller price than a fork of four files, and a louder one: this file names
;; what it advises, where a fork buries it in a diff.
;;
;; NOT LOADED WHERE IT IS NOT NEEDED.  A base that already routes through the
;; suite -- the fork, or an upstream that has taken the patch -- is left
;; alone, function by function, so a base halfway between the two is handled
;; without a switch anywhere.

;;; Code:
(require 'cl-lib)
(require 'classicist-windows)

(defconst classicist-windows-compat-sites
  '((diogenes--start-perl                 . browser)
    (diogenes--make-comint                . browser)
    (diogenes--debug-perl                 . debug)
    (diogenes--perl-execute-current-buffer . debug)
    (diogenes--search-dict                . lookup)
    (classicist--show-all-forms             . morphology)
    (classicist--show-all-lemmata           . morphology)
    (classicist--add-parse-entry            . morphology)
    (diogenes--fontify-nxml               . edit)
    (diogenes--lookup-xml-edit            . edit)
    (diogenes--xml-submit                 . edit)
    (diogenes--select-forms               . morphology)
    (diogenes--select-from-tlg-wordlist   . morphology)
    (diogenes-edit-user-corpus            . corpora)
    (diogenes-manage-user-corpora         . corpora))
  "Base functions that display a buffer, and the role of what they display.
Sixteen `pop-to-buffer' calls live in these, two of them in
`diogenes-manage-user-corpora'.  The roles are the suite's own -- see
`classicist-role-regexps' -- and `debug' and `edit' are not among the roles
the suite places by name, so they fall to `classicist-window-behaviour' and
are placed as anything unrecognised is.  Which is right: a buffer of Perl
being debugged is not a text and not a dictionary entry.")

(defun classicist-windows-compat--wrap (fn role)
  "Advise FN so that what it displays is displayed as ROLE."
  (advice-add
   fn :around
   (lambda (orig &rest args)
     (cl-letf (((symbol-function 'pop-to-buffer)
                (lambda (buffer &rest _)
                  ;; BUFFER, RETURNED, and this is not incidental.
                  ;; `pop-to-buffer' answers with the buffer it displayed, and
                  ;; callers here rely on it: `diogenes--start-perl' ends on
                  ;; that value and `diogenes--do-search' wraps it in
                  ;; `with-current-buffer' to set the buffer-locals a search
                  ;; needs.  A replacement answering with a window puts the
                  ;; search mode on whichever buffer the reader was in, and
                  ;; the search buffer gets none -- which looks like a search
                  ;; that ran and found nothing.
                  (classicist-display-buffer buffer :kind role)
                  buffer))
               ((symbol-function 'switch-to-buffer)
                (lambda (buffer &rest _)
                  (classicist-display-buffer buffer :kind role)
                  buffer)))
       (apply orig args)))
   `((name . ,(intern (format "classicist-windows-compat-%s" role))))))

(defun classicist-windows-compat--needed-p (fn)
  "Whether FN still displays buffers for itself.
ASKED OF THE FUNCTION, not of a version.  A base may route some of these
through the suite and not others -- the fork routes all of them, an upstream
that has taken the patch routes all of them, and one mid-way routes some --
so each is asked separately and a base halfway between is no special case.

Read out of the compiled or interpreted body with `symbol-function', which is
why this is a question worth asking rather than a guess: a function that
already calls `classicist-display-buffer' must not be wrapped, or its buffer
is placed twice and the second placement wins."
  (and (fboundp fn)
       (let ((body (prin1-to-string (indirect-function fn))))
         (and (string-match-p "pop-to-buffer\\|switch-to-buffer" body)
              (not (string-match-p "classicist-display-buffer" body))))))

;;;###autoload
(defun classicist-windows-compat-install ()
  "Route the base's buffer display through the suite.
Does nothing to a function that already routes through it, so calling this
against the fork is a no-op and calling it twice is the same as calling it
once.  Returns the functions it advised."
  (interactive)
  (let (done)
    (pcase-dolist (`(,fn . ,role) classicist-windows-compat-sites)
      (when (classicist-windows-compat--needed-p fn)
        (classicist-windows-compat--wrap fn role)
        (push fn done)))
    (when (called-interactively-p 'interactive)
      (message "%s" (if done
                        (format "Routed %d of the base's displays"
                                (length done))
                      "The base places its own buffers; nothing to do")))
    (nreverse done)))

(defun classicist-windows-compat-uninstall ()
  "Undo `classicist-windows-compat-install'."
  (interactive)
  (pcase-dolist (`(,fn . ,role) classicist-windows-compat-sites)
    (when (fboundp fn)
      (advice-remove
       fn (intern (format "classicist-windows-compat-%s" role))))))

;;; The browser's page turning

(defun classicist-base-page-turn-p ()
  "Whether the base's Perl browser loop understands `F\\=' and `B\\='.
ASKED OF THE SCRIPT, and not of a version, because the base may be upstream
or any fork of it.

`F\\=' and `B\\=' turn a page where `n\\=' and `p\\=' add to it: they move both
bounds where those move one.  A loop without them does not complain.  It
strips the leading count with its own `s/^(\\d+)//\\=', matches no branch, and
prints nothing -- so the process filter waits on output that is never coming
and the page simply never turns.  No error, no message, nothing at all, which
is the worst shape a missing capability can take and the whole reason this is
probed."
  (and (fboundp 'diogenes--browse-interactively-script)
       (let ((script (ignore-errors
                       (diogenes--browse-interactively-script
                        '(:type "tlg") '("0086" "010")))))
         (and (stringp script)
              ;; `and ... t' because `string-match-p' answers with the
              ;; position of the match and a predicate should answer `t'.
              ;; Truthy either way, so this was right and read wrong: the
              ;; probe reported `page turn: 1820'.
              (string-match-p "/\\^F\\$/" script)
              t))))

(provide 'classicist-windows-compat)

;;; classicist-windows-compat.el ends here
