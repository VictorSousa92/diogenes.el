;;; diogenes-dict-faces.el --- Faces for the elements of TEI dictionaries -*- lexical-binding: t -*-

;;; Commentary:

;; Colour the parts of a dictionary entry: the Latin being illustrated, the
;; author cited, the work, the locus, the etymology, the grammatical
;; information.  The LSJ and Lewis & Short already arrive coloured, because
;; `diogenes--dict-handle-elt' gives <head> and <sense> faces of their own
;; and `diogenes--dict-xml-handlers-extra' carries `i' and `b'.  This file
;; extends the same treatment to the elements the converted dictionaries
;; use -- Bailly, Gaffiot, Georges -- which the Perseus files do not.
;;
;; ---------------------------------------------------------------------
;; WHY FACES AND NOT COLOURS
;; ---------------------------------------------------------------------
;;
;; Every face here inherits from a standard font-lock or shr face rather
;; than naming a colour.  A hard-coded #8b0000 is legible on one theme and
;; invisible on the next, and Diogenes has no way of knowing which you use;
;; inheriting means an author is drawn in whatever your theme already uses
;; for a function name, which is distinct from a string, which is distinct
;; from a comment.  Customise any of them if the mapping does not suit you:
;; M-x customize-group RET diogenes-dict-faces.
;;
;; ---------------------------------------------------------------------
;; WHAT CAN AND CANNOT BE COLOURED
;; ---------------------------------------------------------------------
;;
;; `diogenes--dict-xml-handlers-extra' is keyed on the ELEMENT NAME alone,
;; so it cannot distinguish <hi rend="italic"> from <hi rend="bold">: both
;; are `hi' and both would take one face.  The converted dictionaries
;; therefore rewrite <hi> into `i', `b', `sc' and `sup' when the dictionary
;; file is built -- see `diogenes-dict-flatten-hi' -- which is also how the
;; Perseus files mark emphasis, so `i' and `b' keep the appearance they
;; already have in the LSJ.
;;
;; Element names are case-sensitive here: the XML parser hands the
;; formatter `biblScope', not `biblscope', and an alist key that differs in
;; case simply never matches.

;;; Code:

(defvar diogenes--dict-xml-handlers-extra)

(defgroup diogenes-dict-faces nil
  "Faces for the parts of a dictionary entry."
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; FACES
;;;; --------------------------------------------------------------------

(defface diogenes-dict-quote
  '((t :inherit font-lock-string-face))
  "The words being illustrated: a phrase quoted from an ancient author.
Gaffiot's <cl>, which the conversion turns into <quote>."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-author
  '((t :inherit font-lock-function-name-face))
  "The author of a cited passage."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-title
  '((t :inherit font-lock-doc-face :slant italic))
  "The work a passage is cited from."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-scope
  '((t :inherit shadow))
  "The locus within a work: book, chapter, line."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-mentioned
  '((t :inherit font-lock-variable-name-face))
  "A word or form named rather than used -- Gaffiot's <lat> and its kin."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-etym
  '((t :inherit font-lock-comment-face))
  "An etymology."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-gram
  '((t :inherit font-lock-keyword-face))
  "Grammatical information: inflection, gender, part of speech."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-variant
  '((t :inherit font-lock-type-face))
  "A variant spelling or dialectal form of the headword."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-note
  '((t :inherit font-lock-comment-face :slant italic))
  "An editorial remark by the digitisers, not part of the dictionary."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-xref
  '((t :inherit link))
  "A cross-reference to another entry."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-prosody
  '((t :inherit font-lock-constant-face))
  "Vowel quantities and other prosodic marks -- Bailly's [ᾰῐ]."
  :group 'diogenes-dict-faces)

(defface diogenes-dict-smallcaps
  '((t :inherit font-lock-function-name-face :weight semi-bold))
  "Small capitals, which Gaffiot uses for the body of an author's siglum.
Emacs cannot render true small capitals, so weight stands in for them."
  :group 'diogenes-dict-faces)

;;;; --------------------------------------------------------------------
;;;; THE ELEMENT TABLE
;;;; --------------------------------------------------------------------

(defconst diogenes-dict-tei-faces
  '((quote     . (font-lock-face diogenes-dict-quote))
    (author    . (font-lock-face diogenes-dict-author))
    (title     . (font-lock-face diogenes-dict-title))
    (biblScope . (font-lock-face diogenes-dict-scope))
    (mentioned . (font-lock-face diogenes-dict-mentioned))
    (etym      . (font-lock-face diogenes-dict-etym))
    (gram      . (font-lock-face diogenes-dict-gram))
    (gen       . (font-lock-face diogenes-dict-gram))
    (pron      . (font-lock-face diogenes-dict-prosody))
    (orth      . (font-lock-face diogenes-dict-variant))
    (note      . (font-lock-face diogenes-dict-note))
    (ref       . (font-lock-face diogenes-dict-xref))
    (sc        . (font-lock-face diogenes-dict-smallcaps))
    (sup       . (font-lock-face diogenes-dict-scope)))
  "Faces for the TEI elements the converted dictionaries use.
An alist in the shape `diogenes--dict-xml-handlers-extra' expects.

Note what is NOT here.  <head> and <sense> have faces of their own from
`diogenes--dict-handle-elt', and <bibl> is drawn as a link because it is
one -- overriding either would change how the LSJ and Lewis & Short look.
`i' and `b' are left to the shared defaults for the same reason.  <orth>
appears because inside <form type=\"variant\"> it marks a variant spelling;
the headword itself is <head> by the time the formatter sees it.")

(defun diogenes-dict-install-faces ()
  "Teach the dictionary formatter the faces in `diogenes-dict-tei-faces'.
Idempotent, and never displaces an entry already present: a dictionary
module that wants its own face for an element registers it first and keeps
it."
  (dolist (handler diogenes-dict-tei-faces)
    (unless (assq (car handler) diogenes--dict-xml-handlers-extra)
      (push handler diogenes--dict-xml-handlers-extra))))

;;;; --------------------------------------------------------------------
;;;; <hi rend="..."> AT BUILD TIME
;;;; --------------------------------------------------------------------

(defconst diogenes-dict-hi-elements
  '(("italic" . "i") ("bold" . "b") ("smallcaps" . "sc") ("sup" . "sup"))
  "How a @rend value maps to an element the face table can key on.")

(defun diogenes-dict-flatten-hi (line)
  "Rewrite <hi rend=\"...\"> in LINE as `i', `b', `sc' or `sup'.
Called by a dictionary's builder, because the formatter keys its faces on
element names and cannot see attributes: left as <hi>, italic and bold and
small capitals would all be drawn alike.  A rend value not in
`diogenes-dict-hi-elements' -- `normal', `overline' -- loses its element
and keeps its text, which is what the print does with it anyway.

Nesting is preserved by counting: the closing </hi> of an unmapped rend
must be dropped, and of a mapped one renamed, so the tags cannot simply be
replaced one at a time.

Two things here are less obvious than they look.  The end of the tag is
read out of the match BEFORE anything else is matched, because match data
is global: the `string-match\=' that reads the rend attribute out of ATTRS
overwrites the match on LINE, and taking `match-end\=' afterwards yields the
end of `rend=\"italic\"\=' within the attributes -- around 13 -- rather than
the end of the tag.  POS would then jump backwards, the same tag would
match again, and the loop would never end.

And the pieces are collected in a list rather than appended to a string,
because `(setq out (concat out ...))\=' copies everything accumulated so far
on every tag: quadratic in the entry, which for a dictionary like Georges
-- 586,000 <hi> elements, single articles carrying 2,400 of them -- comes
to some 2 GB of copying over a conversion."
  (let ((pos 0) (stack nil) (parts nil))
    (while (string-match "<\\(/?\\)hi\\([^>]*\\)>" line pos)
      (let ((tag-end (match-end 0))
            (tag-start (match-beginning 0))
            (closing (string= (match-string 1 line) "/"))
            (attrs (match-string 2 line)))
        (push (substring line pos tag-start) parts)
        (if closing
            (let ((elt (pop stack)))
              (when elt (push (concat "</" elt ">") parts)))
          (let* ((rend (and (string-match "rend=\"\\([^\"]*\\)\"" attrs)
                            (match-string 1 attrs)))
                 (elt (cdr (assoc rend diogenes-dict-hi-elements))))
            (push elt stack)
            (when elt (push (concat "<" elt ">") parts))))
        (setq pos tag-end)))
    (push (substring line pos) parts)
    (apply #'concat (nreverse parts))))

(provide 'diogenes-dict-faces)
;;; diogenes-dict-faces.el ends here
