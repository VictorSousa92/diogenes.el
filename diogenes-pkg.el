;;; diogenes-pkg.el --- package descriptor  -*- lexical-binding: t -*-
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor2971@gmail.com>

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

(define-package "diogenes" "20250219.75835"
  "Interface to diogenes"
  '((cl-lib "0") (thingatpt "0") (seq "0") (transient "0")) :authors
  '(("Michael Neidhart" . "mayhoth@gmail.com")) :maintainer
  '("Michael Neidhart" . "mayhoth@gmail.com") :keywords
  '("classics" "tools" "philology" "humanities"))
;; Local Variables:
;; no-byte-compile: t
;; End:
