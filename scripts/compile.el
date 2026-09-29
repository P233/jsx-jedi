;;; compile.el --- Strict package byte compilation -*- lexical-binding: t; -*-

;; Run from the repository root: emacs -Q --batch -l scripts/compile.el
;; Set JSX_JEDI_AVY_DIR to the Avy directory and JSX_JEDI_GRAMMAR_DIR to
;; compiled javascript, typescript and tsx grammars, unless already on
;; Emacs's search paths.  scripts/setup-test-deps.sh supplies these files.
;; Warnings fail compilation.  Output is .build/jsx-jedi.elc; override the
;; directory with JSX_JEDI_BUILD_DIR, also used by tests and benchmarks.

(load (expand-file-name "support.el" (file-name-directory load-file-name)) nil t)
(require 'bytecomp)
(jsx-jedi-script-setup '(javascript typescript tsx))
(let* ((directory (jsx-jedi-script-build-directory))
       (destination (expand-file-name "jsx-jedi.elc" directory))
       (byte-compile-error-on-warn t)
       (byte-compile-dest-file-function (lambda (_) destination)))
  (make-directory directory t)
  (unless (byte-compile-file (expand-file-name "jsx-jedi.el" jsx-jedi-script-root))
    (error "Package compilation failed"))
  (princ (format "Compiled without warnings: %s\n" destination)))

;;; compile.el ends here
