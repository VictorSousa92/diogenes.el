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


;;; The browser, renamed
;; `diogenes-browser.el' is `classicist-browser.el' and its sixty names
;; went with it.  32 public ones answered here.

(define-obsolete-variable-alias 'diogenes-browser-add-lines
                                'classicist-browser-add-lines "0.1")
(define-obsolete-variable-alias 'diogenes-browser-addition-face
                                'classicist-browser-addition-face "0.1")
(define-obsolete-function-alias 'diogenes-browser-backward
                                'classicist-browser-backward "0.1")
(define-obsolete-function-alias 'diogenes-browser-backward-line
                                'classicist-browser-backward-line "0.1")
(define-obsolete-function-alias 'diogenes-browser-beginning-of-buffer
                                'classicist-browser-beginning-of-buffer "0.1")
(define-obsolete-function-alias 'diogenes-browser-end-of-buffer
                                'classicist-browser-end-of-buffer "0.1")
(define-obsolete-function-alias 'diogenes-browser-forward
                                'classicist-browser-forward "0.1")
(define-obsolete-function-alias 'diogenes-browser-forward-line
                                'classicist-browser-forward-line "0.1")
(define-obsolete-variable-alias 'diogenes-browser-goto-by-level
                                'classicist-browser-goto-by-level "0.1")
(define-obsolete-function-alias 'diogenes-browser-goto-passage
                                'classicist-browser-goto-passage "0.1")
(define-obsolete-variable-alias 'diogenes-browser-header-button
                                'classicist-browser-header-button "0.1")
(define-obsolete-variable-alias 'diogenes-browser-header-line
                                'classicist-browser-header-line "0.1")
(define-obsolete-function-alias 'diogenes-browser-header-line
                                'classicist-browser-header-line "0.1")
(define-obsolete-function-alias 'diogenes-browser-install-mouse-keys
                                'classicist-browser-install-mouse-keys "0.1")
(define-obsolete-function-alias 'diogenes-browser-install-turn-keys
                                'classicist-browser-install-turn-keys "0.1")
(define-obsolete-variable-alias 'diogenes-browser-join-broken-words
                                'classicist-browser-join-broken-words "0.1")
(define-obsolete-variable-alias 'diogenes-browser-key-page-fraction
                                'classicist-browser-key-page-fraction "0.1")
(define-obsolete-function-alias 'diogenes-browser-lookup
                                'classicist-browser-lookup "0.1")
(define-obsolete-function-alias 'diogenes-browser-mode
                                'classicist-browser-mode "0.1")
(define-obsolete-variable-alias 'diogenes-browser-mode-map
                                'classicist-browser-mode-map "0.1")
(define-obsolete-variable-alias 'diogenes-browser-mouse-keys
                                'classicist-browser-mouse-keys "0.1")
(define-obsolete-function-alias 'diogenes-browser-page-backward
                                'classicist-browser-page-backward "0.1")
(define-obsolete-function-alias 'diogenes-browser-page-forward
                                'classicist-browser-page-forward "0.1")
(define-obsolete-variable-alias 'diogenes-browser-page-lines
                                'classicist-browser-page-lines "0.1")
(define-obsolete-variable-alias 'diogenes-browser-page-margin
                                'classicist-browser-page-margin "0.1")
(define-obsolete-function-alias 'diogenes-browser-quit
                                'classicist-browser-quit "0.1")
(define-obsolete-function-alias 'diogenes-browser-reinsert-hyphenation
                                'classicist-browser-reinsert-hyphenation "0.1")
(define-obsolete-function-alias 'diogenes-browser-remove-hyphenation
                                'classicist-browser-remove-hyphenation "0.1")
(define-obsolete-variable-alias 'diogenes-browser-show-citations
                                'classicist-browser-show-citations "0.1")
(define-obsolete-function-alias 'diogenes-browser-toggle-citations
                                'classicist-browser-toggle-citations "0.1")
(define-obsolete-variable-alias 'diogenes-browser-turn-keys
                                'classicist-browser-turn-keys "0.1")
(define-obsolete-function-alias 'diogenes-open-passage
                                'classicist-open-passage "0.1")


;;; The variants layer, moved
;; `classicist-variants.el' holds them now.  Options a reader may have
;; set, so aliased rather than dropped.

(define-obsolete-variable-alias 'diogenes-latin-analysis-corrections
                                'classicist-latin-analysis-corrections "0.1")
(define-obsolete-variable-alias 'diogenes-latin-assimilate-prefixes
                                'classicist-latin-assimilate-prefixes "0.1")
(define-obsolete-variable-alias 'diogenes-latin-expand-contractions
                                'classicist-latin-expand-contractions "0.1")
(define-obsolete-variable-alias 'diogenes-latin-extra-lemmata
                                'classicist-latin-extra-lemmata "0.1")
(define-obsolete-variable-alias 'diogenes-latin-fold-letters
                                'classicist-latin-fold-letters "0.1")
(define-obsolete-variable-alias 'diogenes-latin-mark-corrections
                                'classicist-latin-mark-corrections "0.1")
(define-obsolete-variable-alias 'diogenes-latin-prefix-variants
                                'classicist-latin-prefix-variants "0.1")
(define-obsolete-variable-alias 'diogenes-latin-spelling-rules
                                'classicist-latin-spelling-rules "0.1")
(define-obsolete-variable-alias 'diogenes-latin-try-spelling-variants
                                'classicist-latin-try-spelling-variants "0.1")


;;; The lexicon layer, moved
;; `classicist-lexicon.el' holds them now.

(define-obsolete-function-alias 'diogenes-perseus-action
                                'classicist-perseus-action "0.1")
(define-obsolete-variable-alias 'diogenes-perseus-action-map
                                'classicist-perseus-action-map "0.1")


;;; The lookup layer, moved
;; `classicist-lookup.el' holds them now.  The registry among them,
;; which fifteen dictionary modules call.

(define-obsolete-function-alias 'diogenes-declared-dictionaries
                                'classicist-declared-dictionaries "0.1")
(define-obsolete-function-alias 'diogenes-list-dictionaries
                                'classicist-list-dictionaries "0.1")
(define-obsolete-function-alias 'diogenes-lookup-always-ask-dictionary
                                'classicist-lookup-always-ask-dictionary "0.1")
(define-obsolete-function-alias 'diogenes-lookup-backward-line
                                'classicist-lookup-backward-line "0.1")
(define-obsolete-function-alias 'diogenes-lookup-beginning-of-buffer
                                'classicist-lookup-beginning-of-buffer "0.1")
(define-obsolete-function-alias 'diogenes-lookup-dictionary-here
                                'classicist-lookup-dictionary-here "0.1")
(define-obsolete-function-alias 'diogenes-lookup-dictionary-keys
                                'classicist-lookup-dictionary-keys "0.1")
(define-obsolete-function-alias 'diogenes-lookup-end-of-buffer
                                'classicist-lookup-end-of-buffer "0.1")
(define-obsolete-function-alias 'diogenes-lookup-forward-line
                                'classicist-lookup-forward-line "0.1")
(define-obsolete-function-alias 'diogenes-lookup-in-dictionary
                                'classicist-lookup-in-dictionary "0.1")
(define-obsolete-function-alias 'diogenes-lookup-install-dictionary-keys
                                'classicist-lookup-install-dictionary-keys "0.1")
(define-obsolete-function-alias 'diogenes-lookup-keys
                                'classicist-lookup-keys "0.1")
(define-obsolete-function-alias 'diogenes-lookup-lewis
                                'classicist-lookup-lewis "0.1")
(define-obsolete-function-alias 'diogenes-lookup-link-key
                                'classicist-lookup-link-key "0.1")
(define-obsolete-function-alias 'diogenes-lookup-mode
                                'classicist-lookup-mode "0.1")
(define-obsolete-function-alias 'diogenes-lookup-mode-map
                                'classicist-lookup-mode-map "0.1")
(define-obsolete-function-alias 'diogenes-lookup-next
                                'classicist-lookup-next "0.1")
(define-obsolete-function-alias 'diogenes-lookup-previous
                                'classicist-lookup-previous "0.1")
(define-obsolete-function-alias 'diogenes-lookup-register-dictionary
                                'classicist-lookup-register-dictionary "0.1")
(define-obsolete-function-alias 'diogenes-lookup-sense-here
                                'classicist-lookup-sense-here "0.1")
(define-obsolete-function-alias 'diogenes-lookup-show-all-entries
                                'classicist-lookup-show-all-entries "0.1")
(define-obsolete-function-alias 'diogenes-lookup-show-analysis
                                'classicist-lookup-show-analysis "0.1")


;;; The morphology, renamed
;; `diogenes-perseus.el' is `classicist-morphology.el': what was left of perseus
;; once the variants, the lexicon and the lookup buffer had
;; gone is the morphology.

(define-obsolete-function-alias 'diogenes-analysis-cycle
                                'classicist-analysis-cycle "0.1")
(define-obsolete-function-alias 'diogenes-analysis-mode
                                'classicist-analysis-mode "0.1")
(define-obsolete-variable-alias 'diogenes-analysis-mode-map
                                'classicist-analysis-mode-map "0.1")
(define-obsolete-variable-alias 'diogenes-greek-analysis-corrections
                                'classicist-greek-analysis-corrections "0.1")
(define-obsolete-variable-alias 'diogenes-greek-extra-lemmata
                                'classicist-greek-extra-lemmata "0.1")
(define-obsolete-variable-alias 'diogenes-lookup-expand-homographs
                                'classicist-lookup-expand-homographs "0.1")
(define-obsolete-function-alias 'diogenes-lookup-open-tll-or-tgl
                                'classicist-lookup-open-tll-or-tgl "0.1")
(define-obsolete-function-alias 'diogenes-morpheus-available-p
                                'classicist-morpheus-available-p "0.1")
(define-obsolete-variable-alias 'diogenes-morpheus-directory
                                'classicist-morpheus-directory "0.1")
(define-obsolete-variable-alias 'diogenes-morpheus-lemma-markers
                                'classicist-morpheus-lemma-markers "0.1")
(define-obsolete-variable-alias 'diogenes-morpheus-timeout
                                'classicist-morpheus-timeout "0.1")

(provide 'classicist-obsolete)

;;; classicist-obsolete.el ends here
