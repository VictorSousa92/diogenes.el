;;; classicist-installation.el --- is this set up, and if not, what to say -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor2971@gmail.com>
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

;; IS THIS SET UP, AND IF NOT, WHAT SHOULD THE READER BE TOLD?  Every
;; dictionary in the suite needs a path from its reader -- a PDF, a directory
;; of XML, an OCR dump -- and a missing one should say what to set and how,
;; rather than failing somewhere downstream with a `no such file'.
;;
;; THE SUITE'S SECOND EXTENSION POINT.  Eighteen files call these: sixteen
;; dictionary modules, the lookup buffer, and the lisp utilities they came
;; from.  `classicist-lookup''s registry says what a dictionary IS; this says
;; whether it can be used, and offers the sentence to show when it cannot.
;;
;; AND IT LEAVES `diogenes-lisp-utils.el' AS UPSTREAM'S.  That file had the
;; window layer, the focus commands and fifty-one obsolete aliases in it; with
;; those gone and these seven out, what remains is upstream's twenty-two
;; definitions exactly.

;;; Code:

(require 'cl-lib)
(require 'seq)

(defvar classicist--loading-bundle nil
  "Non-nil while `diogenes.el' loads the dictionary modules it ships with.
This is how a module tells apart the two ways it can come to be loaded:

  the user asked for it -- `(require \\='diogenes-tll)' in an init file --
  which is a declaration that this dictionary is wanted;

  `diogenes.el' loaded it along with everything else, which says nothing
  about whether the user has it.

A module reads this AT LOAD TIME, through `classicist--declared-at-load-p',
and passes the answer to `diogenes-lookup-register-dictionary' as
DECLARED.  Read at load time rather than at registration because
registration is deferred through `with-eval-after-load' and would
otherwise run inside the bundle's own binding.

`diogenes-declared-dictionaries' is the other way to declare one, and the
one that does not depend on load order.")

(defun classicist--declared-at-load-p ()
  "Whether the file now being loaded was asked for, rather than bundled.
Call at the top level of a dictionary module, never from a function: the
answer is about the moment the file is read.  See
`classicist--loading-bundle'."
  (not (bound-and-true-p classicist--loading-bundle)))

(defun classicist--path-set-p (value)
  "Non-nil if VALUE is a path the user has actually named.
Set-ness only: whether anything is there is not asked.  A dictionary whose
path is set is one the user means to have, so its link is offered and the
command explains what is wrong with the path -- a moved volume or a typo
being a thing to report rather than a reason to make the dictionary
disappear.  `classicist--path-usable-p' is the stricter question, for when
something is about to be read."
  (and (stringp value) (not (string-empty-p value)) t))

(defun classicist--source-set-p (value)
  "Non-nil if VALUE names TEI source material, without checking it is there.
As `classicist--path-set-p', but for the `...-source-file' options, which
take a file, a directory of files, or a list of either."
  (cond
   ((consp value) (seq-some #'classicist--source-set-p value))
   (t (classicist--path-set-p value))))

(defun classicist--path-usable-p (value kind)
  "Non-nil if VALUE names an existing file or readable directory.
KIND is `file' or `directory'.  VALUE is what a dictionary's path option
currently holds: nil, the empty string, or a path that does not exist all
count as unusable.

This is the half of the pair that ASKS, and it must stay cheap, silent and
free of side effects: the link banner calls it for every dictionary each
time it draws itself, so it may neither signal nor prompt.
`classicist--require-path' is the half that TELLS -- called by a command once
the user has actually pressed a key, and which explains what to set."
  (and (stringp value)
       (not (string-empty-p value))
       (if (eq kind 'directory)
           (file-directory-p value)
         (file-readable-p value))
       t))

(defun classicist--source-usable-p (value)
  "Non-nil if VALUE names TEI source material that is actually there.
The `...-source-file' options each take any of three things -- a single XML
file, a directory of them, or an explicit list -- so this accepts all
three: a list is usable when any of its members is, a string when it names
either a readable file or an existing directory.

Asked when deciding whether to offer a dictionary that has not been
converted yet: a source that is present means \\[diogenes-lookup-pape] and
its kind can offer to build the dictionary, so the link leads somewhere
after all.  Like `classicist--path-usable-p', it neither signals nor
prompts."
  (cond
   ((consp value) (seq-some #'classicist--source-usable-p value))
   (t (or (classicist--path-usable-p value 'file)
          (classicist--path-usable-p value 'directory)))))

(defun classicist--require-path (value variable dictionary kind)
  "Return VALUE, or explain how to set VARIABLE if it will not serve.
The dictionaries each need a path from the user, and a missing one should
say what to set and how rather than failing somewhere downstream.  VALUE is
what the option currently holds, VARIABLE its symbol, DICTIONARY the name to
call it by in the message, and KIND either `file' or `directory'.

Set as an ordinary variable, before Diogenes loads, or through Customize;
either way the value survives the `defcustom'."
  (let ((name (symbol-name variable)))
    (cond
     ((or (null value) (and (stringp value) (string-empty-p value)))
      (user-error "%s is not set up yet: `%s' must name %s.  \
Put (setq %s \"/path/to/%s\") in your init file before Diogenes loads, or \
run M-x customize-variable RET %s RET"
                  dictionary name
                  (if (eq kind 'directory) "a directory" "a file")
                  name
                  (if (eq kind 'directory) "folder/" "file.pdf")
                  name))
     ((eq kind 'directory)
      (unless (file-directory-p value)
        (user-error "%s: `%s' is %s, which is not an existing directory"
                    dictionary name value))
      value)
     (t
      (unless (file-readable-p value)
        (user-error "%s: `%s' is %s, which cannot be read"
                    dictionary name value))
      value))))

;;; What the base must already have

;; NINE OF THE FIFTEEN PATCHES ARE LOAD-BEARING.  The suite takes upstream as
;; a package dependency and inherits `corpora\=', `user-interface\=',
;; `perl-interface\=', `forms\=', `search\=' and `lisp-utils\=' -- so a base
;; without those fixes is a base the suite cannot run on, and it should say
;; which one is missing rather than failing somewhere downstream.
;;
;; ASKED OF THE CODE AND NOT OF A VERSION, as `classicist-base-page-turn-p\='
;; is and for the same reason: the base may be upstream, or any fork of it, or
;; upstream with some of these merged and not others.  A version number would
;; be a guess about what somebody shipped.

(defun classicist-base--defined-in (symbol kind)
  "Which file defined SYMBOL, as a base name, or nil.
KIND is `defun\=' or `defvar\='.  `symbol-file\=' answers this exactly, which
makes three of the probes below a fact rather than an inference: whether a
patch landed is whether a definition moved."
  (let ((f (ignore-errors (symbol-file symbol kind))))
    (and f (file-name-base f))))

(defun classicist-base--body-mentions (fn string)
  "Whether FN's definition mentions STRING.
The same reading `classicist-windows-compat--needed-p\=' does, and for the same
reason: a call is visible in the function that makes it, whatever version the
file claims to be."
  (and (fboundp fn)
       (string-match-p (regexp-quote string)
                       (prin1-to-string (indirect-function fn)))))

(defconst classicist-base-requirements
  '((perl-variables
     "the Perl bridge can be loaded without the entry point"
     (lambda ()
       (equal (classicist-base--defined-in 'diogenes-perl-executable 'defvar)
              "diogenes-perl-interface")))
    (word-lists
     "the word lists are their own file, so nothing drags in a second lexicon"
     (lambda ()
       (or (and (locate-library "diogenes-lemmata") t)
           (equal (classicist-base--defined-in 'diogenes--get-all-forms 'defun)
                  "diogenes-lemmata"))))
    (page-turn
     "the Perl browse loop understands F and B"
     (lambda () (classicist-base-page-turn-p))))
  "What the suite needs its base to have, and how to tell.
Each entry is a symbol, a sentence saying what is wanted, and a thunk
answering whether it is there.  The sentence is what a reader is shown, so it
says what is missing and not which patch number supplies it.

THREE, AND NOT NINE, because only three of the load-bearing patches fail
QUIETLY.  A base without them:

    the page turn      `F\=' matches no branch, the loop prints nothing, the
                       process filter waits on output that is never coming,
                       and the page simply never turns
    the word lists     `diogenes-forms\=' and `diogenes-search\=' require the
                       base\='s own lexicon, so two implementations of the
                       same thing load and whichever came last wins
    the Perl variables `diogenes-perl-executable\=' is defined in the entry
                       point this suite replaces, so the bridge has no `perl\='
                       to run

The other six announce themselves and want no probe: `y-or-n-q\=' and
`copy-list\=' are void-function with a backtrace naming the symbol, the
passage selector makes Perl exit 255 and the bridge already errors on that,
and the `format\=' fault prints `Rename nil to: \=' where a reader can see it.

Probe what fails silently; let what fails loudly be loud.")

(defun classicist-base-report ()
  "Say which of `classicist-base-requirements\=' the base does not meet.
Returns a list of the unmet ones, and nil when all is well."
  (cl-loop for (name want test) in classicist-base-requirements
           unless (ignore-errors (funcall test))
           collect (cons name want)))

;;;###autoload
(defun classicist-check-base ()
  "Report whether the installed Diogenes has what this suite needs.
Interactively, say so either way."
  (interactive)
  (let ((missing (classicist-base-report)))
    (cond
     ((null missing)
      (when (called-interactively-p 'interactive)
        (message "The base has everything the suite needs"))
      t)
     (t
      (message
       "This Diogenes is missing %d thing%s the suite needs:\n%s\n\
See https://github.com/VictorSousa92/diogenes.el branch classicist-base."
       (length missing) (if (cdr missing) "s" "")
       (mapconcat (lambda (m) (format "  - %s" (cdr m))) missing "\n"))
      nil))))

(provide 'classicist-installation)

;;; classicist-installation.el ends here
