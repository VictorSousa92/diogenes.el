;;; diogenes-browser-compat.el --- internals that moved, pending deletion -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
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
(require 'classicist-citation)


(define-obsolete-function-alias 'diogenes--browser-format-citation
                                'classicist--browser-format-citation "0.1")
(define-obsolete-function-alias 'diogenes--citation-runs-on-p
                                'classicist--citation-runs-on-p "0.1")


;;; The browser, renamed
;; `diogenes-browser.el' is `classicist-browser.el' and its sixty names
;; went with it.  28 private ones answered here.

(define-obsolete-function-alias 'diogenes--browse-database
                                'classicist--browse-database "0.1")
(define-obsolete-function-alias 'diogenes--browse-work
                                'classicist--browse-work "0.1")
(define-obsolete-variable-alias 'diogenes--browser-addition
                                'classicist--browser-addition "0.1")
(define-obsolete-function-alias 'diogenes--browser-filter
                                'classicist--browser-filter "0.1")
(define-obsolete-function-alias 'diogenes--browser-format-header
                                'classicist--browser-format-header "0.1")
(define-obsolete-variable-alias 'diogenes--browser-output-buffer
                                'classicist--browser-output-buffer "0.1")
(define-obsolete-variable-alias 'diogenes--browser-page-lines
                                'classicist--browser-page-lines "0.1")
(define-obsolete-function-alias 'diogenes--browser-remove-duplicate-header
                                'classicist--browser-remove-duplicate-header "0.1")
(define-obsolete-variable-alias 'diogenes--browser-replace
                                'classicist--browser-replace "0.1")
(define-obsolete-function-alias 'diogenes--browser-set-height
                                'classicist--browser-set-height "0.1")
(define-obsolete-variable-alias 'diogenes--browser-turned
                                'classicist--browser-turned "0.1")
(define-obsolete-function-alias 'diogenes--dump-from-database
                                'classicist--dump-from-database "0.1")
(define-obsolete-function-alias 'diogenes--dump-from-database-sentinel
                                'classicist--dump-from-database-sentinel "0.1")
(define-obsolete-function-alias 'diogenes--dump-work
                                'classicist--dump-work "0.1")
(define-obsolete-function-alias 'diogenes--read-browser-output
                                'classicist--browser-read-output "0.1")
(define-obsolete-function-alias 'diogenes--send-cmd-to-browser
                                'classicist--browser-send-cmd "0.1")
(define-obsolete-function-alias 'diogenes-browser--at-click
                                'classicist-browser--at-click "0.1")
(define-obsolete-function-alias 'diogenes-browser--header-button
                                'classicist-browser--header-button "0.1")
(define-obsolete-function-alias 'diogenes-browser--header-button-runner
                                'classicist-browser--header-button-runner "0.1")
(define-obsolete-function-alias 'diogenes-browser--knows-its-work-p
                                'classicist-browser--knows-its-work-p "0.1")
(define-obsolete-function-alias 'diogenes-browser--lines-to-add
                                'classicist-browser--lines-to-add "0.1")
(define-obsolete-function-alias 'diogenes-browser--lines-to-request
                                'classicist-browser--lines-to-request "0.1")
(define-obsolete-function-alias 'diogenes-browser--mark-addition
                                'classicist-browser--mark-addition "0.1")
(define-obsolete-function-alias 'diogenes-browser--page-size
                                'classicist-browser--page-size "0.1")
(define-obsolete-function-alias 'diogenes-browser--read-levels
                                'classicist-browser--read-levels "0.1")
(define-obsolete-function-alias 'diogenes-browser--second-half
                                'classicist-browser--second-half "0.1")
(define-obsolete-function-alias 'diogenes-browser--unmark-addition
                                'classicist-browser--unmark-addition "0.1")
(define-obsolete-function-alias 'diogenes-browser--word-at-point-joined
                                'classicist-browser--word-at-point-joined "0.1")

(provide 'diogenes-browser-compat)

;;; diogenes-browser-compat.el ends here
