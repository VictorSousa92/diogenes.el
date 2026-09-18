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

(provide 'diogenes-browser-compat)

;;; diogenes-browser-compat.el ends here
