;;; classicist-obsolete.el --- names that moved, and are still answered -*- lexical-binding: t; -*-

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

;; THE NAMES A READER MIGHT BE HOLDING, and so the ones that cannot be
;; deleted on a schedule of ours.  `diogenes-window-behaviour' and
;; `diogenes-role-regexps' are options somebody has set;
;; `diogenes-focus-browser' is bound to `C-c C-b'.
;;
;; FIVE OF THEM ARE DOUBLE-DASHED AND HERE ANYWAY.
;; `diogenes--browser-corpus' and its four fellows look private and are set
;; by `tei-browser.el' and `tei-diorisis.el', from another package.  The
;; convention is already broken there; deleting them with the internals would
;; break those two.
;;
;; A FILE OF ITS OWN, and not beside the code, because a rename of the code is
;; a `sed' over the files that hold it -- and a `sed' that reaches an alias
;; turns it into a symbol aliased to itself, which is an infinite loop on the
;; first call and not a warning.  Twice.

;;; Code:
(require 'classicist-windows)
(require 'classicist-citation)


(define-obsolete-variable-alias 'diogenes--browser-author
                                'classicist--browser-author "0.1")
(define-obsolete-variable-alias 'diogenes--browser-corpus
                                'classicist--browser-corpus "0.1")
(define-obsolete-variable-alias 'diogenes--browser-labels
                                'classicist--browser-labels "0.1")
(define-obsolete-variable-alias 'diogenes--browser-passage
                                'classicist--browser-passage "0.1")
(define-obsolete-variable-alias 'diogenes--browser-work
                                'classicist--browser-work "0.1")
(define-obsolete-variable-alias 'diogenes-abbreviation-overrides
                                'classicist-abbreviation-overrides "0.1")
(define-obsolete-function-alias 'diogenes-browser-citation-at
                                'classicist-browser-citation-at "0.1")
(define-obsolete-function-alias 'diogenes-browser-citation-interval
                                'classicist-browser-citation-interval "0.1")
(define-obsolete-variable-alias 'diogenes-browser-display-action
                                'classicist-browser-display-action "0.1")
(define-obsolete-function-alias 'diogenes-browser-reference
                                'classicist-browser-reference "0.1")
(define-obsolete-function-alias 'diogenes-citation-abbreviation
                                'classicist-citation-abbreviation "0.1")
(define-obsolete-function-alias 'diogenes-citation-from-key
                                'classicist-citation-from-key "0.1")
(define-obsolete-function-alias 'diogenes-citation-interval-from-key
                                'classicist-citation-interval-from-key "0.1")
(define-obsolete-variable-alias 'diogenes-citation-run-on-labels
                                'classicist-citation-run-on-labels "0.1")
(define-obsolete-function-alias 'diogenes-citation-to-key
                                'classicist-citation-to-key "0.1")
(define-obsolete-function-alias 'diogenes-citation-to-string
                                'classicist-citation-to-string "0.1")
(define-obsolete-variable-alias 'diogenes-claim-buffer-function
                                'classicist-claim-buffer-function "0.1")
(define-obsolete-variable-alias 'diogenes-claim-buffers
                                'classicist-claim-buffers "0.1")
(define-obsolete-variable-alias 'diogenes-companion-direction
                                'classicist-companion-direction "0.1")
(define-obsolete-variable-alias 'diogenes-companion-roles
                                'classicist-companion-roles "0.1")
(define-obsolete-variable-alias 'diogenes-dictionary-display-action
                                'classicist-dictionary-display-action "0.1")
(define-obsolete-function-alias 'diogenes-display-beside-companion
                                'classicist-display-beside-companion "0.1")
(define-obsolete-variable-alias 'diogenes-display-debug
                                'classicist-display-debug "0.1")
(define-obsolete-function-alias 'diogenes-display-in-role-frame
                                'classicist-display-in-role-frame "0.1")
(define-obsolete-function-alias 'diogenes-focus-browser
                                'classicist-focus-browser "0.1")
(define-obsolete-function-alias 'diogenes-focus-dictionary
                                'classicist-focus-dictionary "0.1")
(define-obsolete-variable-alias 'diogenes-focus-keys
                                'classicist-focus-keys "0.1")
(define-obsolete-function-alias 'diogenes-focus-lookup
                                'classicist-focus-lookup "0.1")
(define-obsolete-function-alias 'diogenes-focus-morphology
                                'classicist-focus-morphology "0.1")
(define-obsolete-variable-alias 'diogenes-frame-parameters
                                'classicist-frame-parameters "0.1")
(define-obsolete-variable-alias 'diogenes-gather-frames
                                'classicist-gather-frames "0.1")
(define-obsolete-variable-alias 'diogenes-home-buffer-names
                                'classicist-home-buffer-names "0.1")
(define-obsolete-function-alias 'diogenes-install-focus-keys
                                'classicist-install-focus-keys "0.1")
(define-obsolete-variable-alias 'diogenes-lookup-display-action
                                'classicist-lookup-display-action "0.1")
(define-obsolete-variable-alias 'diogenes-morphology-display-action
                                'classicist-morphology-display-action "0.1")
(define-obsolete-function-alias 'diogenes-open-reference
                                'classicist-open-reference "0.1")
(define-obsolete-function-alias 'diogenes-reference-to-string
                                'classicist-reference-to-string "0.1")
(define-obsolete-variable-alias 'diogenes-role-regexps
                                'classicist-role-regexps "0.1")
(define-obsolete-variable-alias 'diogenes-split-direction
                                'classicist-split-direction "0.1")
(define-obsolete-variable-alias 'diogenes-split-from
                                'classicist-split-from "0.1")
(define-obsolete-variable-alias 'diogenes-split-size
                                'classicist-split-size "0.1")
(define-obsolete-variable-alias 'diogenes-window-behaviour
                                'classicist-window-behaviour "0.1")

(provide 'classicist-obsolete)

;;; classicist-obsolete.el ends here
