;;; diogenes-presets.el --- Settings kept in files, and switched between -*- lexical-binding: t -*-

;; Author: Victor Sousa
;; Keywords: languages, tools

;;; Commentary:

;; A preset is an ordinary Emacs Lisp file that sets Diogenes options.  There
;; is nothing else to it: `load' is what loads it, and anything you could
;; write in an init file you can write in one.
;;
;;     ;;; reading.el --- Diogenes preset
;;     ;; Description: entries beside the text, dictionaries in their own frame
;;     (setq diogenes-window-behaviour 'split)
;;     (setq diogenes-lookup-show-all-entries t)
;;
;; Put it in `diogenes-preset-directory' and `M-x diogenes-load-preset' offers
;; it by name, with that Description line as the annotation.
;;
;; Why a directory of files rather than more options.  The settings a reader
;; wants are not one set but several, and which they want depends on what they
;; are doing: a preset for reading at length, a preset for looking one word up
;; in the middle of writing, a preset for the machine with the small screen.
;; Those differ in a dozen variables at once, which is not a thing a defcustom
;; can express, and shuffling them by hand in an init file loses whichever one
;; is not currently pasted in.
;;
;; Nothing here validates or restricts what a preset may set.  It is Lisp, it
;; is yours, and a preset that sets `line-spacing' or turns off a minor mode
;; is doing something reasonable.

;;; Code:

(require 'cl-lib)

(defcustom diogenes-preset-directory nil
  "Directory holding preset files, or nil for none.
Each `.el\=' file in it is a preset, offered by `M-x diogenes-load-preset\='
under its file name.

Nil by default, because a reader needs no directory in order to have presets:
the four behaviours are presets already, and are offered whether this is set
or not.  Set it when there is something of your own to keep -- the same
arrangement the dictionaries have, where an unset path means one fewer thing
rather than a broken one."
  :type '(choice (const :tag "None" nil) directory)
  :group 'diogenes)

(defcustom diogenes-builtin-presets
  '(("defer"  . "windows as whatever you have installed decides")
    ("reuse"  . "one window for entries, each replacing the last")
    ("split"  . "an entry beside the text, later entries sharing it")
    ("frames" . "each kind in a frame of its own, entries gathered"))
  "The four behaviours, offered as presets.
An alist of (NAME . DESCRIPTION), each NAME a value of
`diogenes-window-behaviour\='; loading one sets that and nothing else.

Here so that presets work with nothing written and no directory set.  What a
reader most often wants to switch between is exactly these four, and asking
them to write four files saying one thing each would be a poor beginning.

A FILE of the same name in `diogenes-preset-directory\=' REPLACES the builtin:
`split.el\=' of your own is then what `split\=' means, and the builtin steps
aside rather than arguing with it."
  :type '(alist :key-type string :value-type string)
  :group 'diogenes)

(defcustom diogenes-preset nil
  "A preset to load when Diogenes loads, or nil for none.
The file name without its extension, as `M-x diogenes-load-preset\\=' shows it.

Loaded AFTER the package, so a preset can set anything the package defines --
and after an init file has had its say, so a preset wins over it.  That order
is deliberate: an init file holds what is true of this machine, a preset what
is true of what you are doing now, and the second is the more particular."
  :type '(choice (const :tag "None" nil) string)
  :group 'diogenes)

(defvar diogenes-preset--loaded nil
  "The preset loaded last, as a file name without extension.")

(defun diogenes-preset--files ()
  "Every preset file in `diogenes-preset-directory\\=', which may be unset."
  (when (and diogenes-preset-directory
             (file-directory-p diogenes-preset-directory))
    (directory-files diogenes-preset-directory t "\\.el\\'")))

(defun diogenes-preset--description (file)
  "The Description line of FILE, if it has one.
Read from the first twenty lines, so that reading it costs nothing on a
preset which is mostly settings."
  (with-temp-buffer
    (insert-file-contents file nil 0 2000)
    (goto-char (point-min))
    (when (re-search-forward "^;+[ \t]*Description:[ \t]*\\(.*\\)$"
                             (save-excursion (forward-line 20) (point))
                             t)
      (string-trim (match-string 1)))))

(defun diogenes-preset--alist ()
  "Every preset, as (NAME FILE DESCRIPTION); FILE is nil for a builtin.
Files first, and a builtin of the same name is dropped -- a reader who has
written `split.el\=' means that by `split\=', and a builtin arguing with it
would be worse than useless."
  (let* ((files (mapcar (lambda (file)
                          (list (file-name-base file) file
                                (diogenes-preset--description file)))
                        (diogenes-preset--files)))
         (taken (mapcar #'car files)))
    (append files
            (cl-remove-if (lambda (entry) (member (car entry) taken))
                          (mapcar (lambda (cell)
                                    (list (car cell) nil (cdr cell)))
                                  diogenes-builtin-presets)))))

(defun diogenes-preset--load-builtin (name)
  "Load the builtin preset NAME, which is to say set the behaviour."
  (setq diogenes-window-behaviour (intern name)))

;;;###autoload
(defun diogenes-load-preset (name)
  "Load the preset called NAME from `diogenes-preset-directory\\='.
Interactively, offers what is there, annotated with each file's Description
line."
  (interactive
   (let* ((presets (diogenes-preset--alist))
          (completion-extra-properties
           (list :annotation-function
                 (lambda (candidate)
                   (when-let* ((entry (assoc candidate presets))
                               (description (nth 2 entry)))
                     (concat "  " description))))))
     (unless presets
       (user-error "No presets in %s" diogenes-preset-directory))
     (list (completing-read "Preset: " (mapcar #'car presets) nil t))))
  (let ((entry (assoc name (diogenes-preset--alist))))
    (unless entry
      (user-error "No preset called %s in %s" name diogenes-preset-directory))
    (if (nth 1 entry)
        (load (nth 1 entry) nil t)
      (diogenes-preset--load-builtin name))
    (setq diogenes-preset--loaded name)
    (message "Diogenes preset: %s%s" name
             (if (nth 2 entry) (format " -- %s" (nth 2 entry)) ""))))

;;;###autoload
(defun diogenes-list-presets ()
  "Show the presets that are available, and which was loaded last."
  (interactive)
  (let ((presets (diogenes-preset--alist)))
    (with-current-buffer (get-buffer-create "*Diogenes Presets*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (if diogenes-preset-directory
                    (format "Presets, and the files in %s\n\n"
                            diogenes-preset-directory)
                  (concat "Presets.  `diogenes-preset-directory' is unset, so "
                          "these are the builtin\nones; set it to keep presets "
                          "of your own, and a file named after a\nbuiltin "
                          "replaces it.\n\n")))
        (dolist (entry presets)
          (insert (format "%-20s %-50s %s%s\n"
                          (nth 0 entry)
                          (or (nth 2 entry) "")
                          (if (nth 1 entry) "file" "builtin")
                          (if (equal (nth 0 entry) diogenes-preset--loaded)
                              "  [loaded]" ""))))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

;;;###autoload
(defun diogenes-preset-write-current (name)
  "Write the Diogenes settings of this session to a preset called NAME.
What you have arrived at by experiment, kept.  Only the options this package
defines are written, and only those differing from their standard value --
a preset should say what is particular about it and nothing else."
  (interactive "sName for this preset: ")
  (unless diogenes-preset-directory
    (user-error "Set `diogenes-preset-directory' first: there is nowhere to \
write a preset to"))
  (make-directory diogenes-preset-directory t)
  (let ((file (expand-file-name (concat name ".el") diogenes-preset-directory))
        (changed nil))
    (mapatoms
     (lambda (symbol)
       (when (and (string-prefix-p "diogenes-" (symbol-name symbol))
                  (custom-variable-p symbol)
                  (boundp symbol))
         (let ((standard (eval (car (get symbol 'standard-value)) t)))
           (unless (equal (symbol-value symbol) standard)
             (push (cons symbol (symbol-value symbol)) changed))))))
    (with-temp-file file
      (insert (format ";;; %s.el --- Diogenes preset  -*- lexical-binding: t -*-\n"
                      name))
      (insert ";; Description: written by `diogenes-preset-write-current'\n\n")
      (dolist (cell (sort changed (lambda (a b)
                                    (string< (symbol-name (car a))
                                             (symbol-name (car b))))))
        (insert (format "(setq %s %S)\n" (car cell) (cdr cell))))
      (insert (format "\n;;; %s.el ends here\n" name)))
    (setq diogenes-preset--loaded name)
    (message "Wrote %d setting%s to %s"
             (length changed) (if (= (length changed) 1) "" "s") file)))

;; The preset named in `diogenes-preset' is loaded once everything it might
;; set exists.
(with-eval-after-load 'diogenes
  (when diogenes-preset
    (ignore-errors (diogenes-load-preset diogenes-preset))))

(provide 'diogenes-presets)
;;; diogenes-presets.el ends here
