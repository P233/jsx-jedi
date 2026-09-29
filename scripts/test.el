;;; test.el --- Run JSX Jedi regression tests -*- lexical-binding: t; -*-

;; From the repository root, after bash scripts/setup-test-deps.sh:
;; JSX_JEDI_AVY_DIR=.test-deps/avy \
;; JSX_JEDI_GRAMMAR_DIR=.test-deps/grammars \
;;   emacs -Q --batch -l scripts/test.el
;;
;; The suite requires javascript, typescript, tsx and jsdoc grammars.
;; It loads source by default.  For bytecode, run scripts/compile.el first,
;; then set JSX_JEDI_TEST_MODE=compiled (and the same JSX_JEDI_BUILD_DIR
;; if overridden).  Missing dependencies or bytecode fail the run.

(require 'ert)
(load (expand-file-name "support.el" (file-name-directory load-file-name)) nil t)
(jsx-jedi-script-setup '(javascript typescript tsx jsdoc))
(defvar jsx-jedi-test-package-file (jsx-jedi-script-load-package))
(dolist (test-file '("jsx-jedi-test.el" "configuration-test.el" "interaction-test.el"))
  (load (expand-file-name (concat "tests/" test-file) jsx-jedi-script-root) nil t))

(ert-run-tests-batch-and-exit)

;;; test.el ends here
