;;; test.el --- Run JSX Jedi regression tests -*- lexical-binding: t; -*-

;; Run from the repository root:
;; JSX_JEDI_GRAMMAR_DIR=/path/to/grammars \
;;   emacs -Q --batch -L /path/to/avy -l scripts/test.el

(require 'ert)
(load (expand-file-name "support.el" (file-name-directory load-file-name)) nil t)
(jsx-jedi-script-setup '(javascript typescript tsx jsdoc))
(defvar jsx-jedi-test-package-file (jsx-jedi-script-load-package))
(dolist (test-file '("jsx-jedi-test.el" "configuration-test.el" "interaction-test.el"))
  (load (expand-file-name (concat "tests/" test-file) jsx-jedi-script-root) nil t))

(ert-run-tests-batch-and-exit)

;;; test.el ends here
