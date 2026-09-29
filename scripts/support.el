;;; support.el --- Shared local validation setup -*- lexical-binding: t; -*-

;; Loaded by the test, compile and benchmark entry points.  Dependency
;; setup is explicit: this helper checks availability and never downloads
;; grammars.  Paths and diagnostics are shared so runs use the same inputs.

(require 'treesit)
(require 'subr-x)

(defconst jsx-jedi-script-root
  (file-name-directory
   (directory-file-name (file-name-directory load-file-name)))
  "Repository root used by validation entry points.")

(defun jsx-jedi-script-build-directory ()
  "Return the absolute output directory selected by JSX_JEDI_BUILD_DIR.
Default to .build; resolve relative paths against the repository root."
  (expand-file-name (or (getenv "JSX_JEDI_BUILD_DIR") ".build")
                    jsx-jedi-script-root))

(defun jsx-jedi-script-setup (languages)
  "Load Avy and require real parsers for LANGUAGES.
Add JSX_JEDI_AVY_DIR and JSX_JEDI_GRAMMAR_DIR to Emacs's search paths when
set.  Missing dependencies signal an error; grammar downloads are disabled.
Print runtime, dependency and available revision details to standard output."
  (add-to-list 'load-path jsx-jedi-script-root)
  (dolist (setting '(("JSX_JEDI_AVY_DIR" . load-path)
                     ("JSX_JEDI_GRAMMAR_DIR" . treesit-extra-load-path)))
    (when-let* ((directory (getenv (car setting))))
      (unless (file-directory-p directory)
        (error "%s is not a directory: %s" (car setting) directory))
      (set (cdr setting) (cons (expand-file-name directory)
                              (symbol-value (cdr setting))))))
  (unless (treesit-available-p)
    (error "Validation requires Emacs with tree-sitter support"))
  ;; Newer major modes may offer optional grammars (for example JSDoc).
  ;; Validation is offline after setup; required grammars are checked below.
  (when (boundp 'treesit-auto-install-grammar)
    (setq treesit-auto-install-grammar nil))
  (unless (require 'avy nil t)
    (error "Set JSX_JEDI_AVY_DIR or add the Avy directory with -L"))
  (dolist (language languages)
    (let ((availability (treesit-language-available-p language t)))
      (unless (car availability)
        (error "Cannot load %s grammar; set JSX_JEDI_GRAMMAR_DIR: %S"
               language (cdr availability)))))
  (princ (format "Emacs %s; %s; tree-sitter ABI %s..%s\n"
                 emacs-version system-configuration
                 (treesit-library-abi-version t) (treesit-library-abi-version)))
  (dolist (language languages)
    (princ (format "%s grammar ABI: %s\n" language
                   (if (fboundp 'treesit-language-abi-version)
                       (treesit-language-abi-version language) "not reported"))))
  (princ (format "Avy: %s\n" (symbol-file 'avy-goto-word-0 'defun)))
  (when-let* ((directory (getenv "JSX_JEDI_GRAMMAR_DIR"))
              (manifest (expand-file-name "../versions.txt" directory))
              (_ (file-readable-p manifest)))
    (princ (with-temp-buffer (insert-file-contents manifest) (buffer-string)))))

(defun jsx-jedi-script-load-package ()
  "Load the requested package and return its exact path.
JSX_JEDI_TEST_MODE selects source (the default) or compiled bytecode.
Bytecode comes from `jsx-jedi-script-build-directory'.  A missing file
signals an error; never fall back to another source or compiled file."
  (let* ((mode (or (getenv "JSX_JEDI_TEST_MODE") "source"))
         (file (pcase mode
                 ("source" (expand-file-name "jsx-jedi.el" jsx-jedi-script-root))
                 ("compiled" (expand-file-name "jsx-jedi.elc"
                                               (jsx-jedi-script-build-directory)))
                 (_ (error "Unknown JSX_JEDI_TEST_MODE: %s" mode)))))
    (unless (file-readable-p file)
      (error "Missing %s package: %s; run scripts/compile.el first" mode file))
    (princ (format "Loading %s: %s\n" mode file))
    (load file nil t t)
    file))

(provide 'jsx-jedi-script-support)
;;; support.el ends here
