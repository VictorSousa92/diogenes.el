;;; classicist-groups.el --- the suite's customize groups -*- lexical-binding: t; -*-

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

;; TWELVE LINES AND A FILE OF ITS OWN, because the suite's modules do not
;; require one another.  Nothing ties `classicist-windows.el\\=' to
;; `classicist-citation.el\\='; so whichever held the root group, the other
;; would name a parent it had not loaded.  Customize copes with that by
;; inventing a placeholder, and a reader loading one module alone finds its
;; options orphaned from the tree.
;;
;; A shared declaration with no other home is what a small file is for.

;;; Code:

(defgroup classicist nil
  "A suite of tools for classicists.
Diogenes\\=' corpora and lexica, the Diorisis corpus, treebank annotation, and
editions as TEI -- see `classicist\\=' for the modules and their options.

BESIDE `diogenes\\=' AND NOT UNDER IT.  The suite loads Diogenes\\=' Perl bridge
and its corpus plumbing, and replaces the rest; an option of the suite\\='s is
not an option of Diogenes\\=', and a reader browsing one should not have to
read the other."
  :group 'tools)

(provide 'classicist-groups)

;;; classicist-groups.el ends here
