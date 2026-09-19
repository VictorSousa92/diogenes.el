;;; diogenes-lisp-utils-compat.el --- internals that moved, pending deletion -*- lexical-binding: t; -*-

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

;; THE INTERNALS, AND THIS FILE IS MEANT TO BE DELETED.  Every name here is
;; double-dashed: private by convention, and nothing outside this repository
;; could have called it.  When the fork and the TEI packages name the new ones
;; throughout, delete the file -- there is nothing to edit and nothing to keep.
;;
;; `classicist-obsolete.el' holds the names a reader might have set or bound,
;; which are not ours to drop.
;;
;; A FILE OF ITS OWN because a rename of the code is a `sed' over the files
;; that hold it, and a `sed' that reaches an alias turns it into a symbol
;; aliased to itself: an infinite loop on the first call, and not a warning.

;;; Code:
(require 'classicist-windows)


(define-obsolete-function-alias 'diogenes--behaviour-action
                                'classicist--behaviour-action "0.1")
(define-obsolete-function-alias 'diogenes--behaviour-for
                                'classicist--behaviour-for "0.1")
(define-obsolete-function-alias 'diogenes--buffer-role
                                'classicist--buffer-role "0.1")
(define-obsolete-function-alias 'diogenes--claim-buffer
                                'classicist--claim-buffer "0.1")
(define-obsolete-function-alias 'diogenes--companion-role
                                'classicist--companion-role "0.1")
(define-obsolete-function-alias 'diogenes--display-action
                                'classicist--display-action "0.1")
(define-obsolete-function-alias 'diogenes--display-buffer
                                'classicist-display-buffer "0.1")
(define-obsolete-function-alias 'diogenes--display-log
                                'classicist--display-log "0.1")
(define-obsolete-variable-alias 'diogenes--display-log-before
                                'classicist--display-log-before "0.1")
(define-obsolete-variable-alias 'diogenes--display-log-branch
                                'classicist--display-log-branch "0.1")
(define-obsolete-variable-alias 'diogenes--display-log-detail
                                'classicist--display-log-detail "0.1")
(define-obsolete-function-alias 'diogenes--display-split-anyway
                                'classicist--display-split-anyway "0.1")
(define-obsolete-variable-alias 'diogenes--focus-maps
                                'classicist--focus-maps "0.1")
(define-obsolete-function-alias 'diogenes--focus-role
                                'classicist--focus-role "0.1")
(define-obsolete-function-alias 'diogenes--gathering-action
                                'classicist--gathering-action "0.1")
(define-obsolete-function-alias 'diogenes--gathering-p
                                'classicist--gathering-p "0.1")
(define-obsolete-function-alias 'diogenes--home-buffer-p
                                'classicist--home-buffer-p "0.1")
(define-obsolete-function-alias 'diogenes--remember-role
                                'classicist--remember-role "0.1")
(define-obsolete-variable-alias 'diogenes--role-modes
                                'classicist--role-modes "0.1")
(define-obsolete-function-alias 'diogenes--sole-home-window-p
                                'classicist--sole-home-window-p "0.1")
(define-obsolete-function-alias 'diogenes--split-alist
                                'classicist--split-alist "0.1")
(define-obsolete-function-alias 'diogenes--split-functions
                                'classicist--split-functions "0.1")
(define-obsolete-function-alias 'diogenes--split-size-for
                                'classicist--split-size-for "0.1")
(define-obsolete-function-alias 'diogenes--window-of-role
                                'classicist--window-of-role "0.1")
(define-obsolete-function-alias 'diogenes--window-that-held
                                'classicist--window-that-held "0.1")
(define-obsolete-function-alias 'diogenes--windows-of-role
                                'classicist--windows-of-role "0.1")

(provide 'diogenes-lisp-utils-compat)

;;; diogenes-lisp-utils-compat.el ends here
