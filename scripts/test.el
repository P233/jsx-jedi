;;; test.el --- Run JSX Jedi regression tests -*- lexical-binding: t; -*-

;; Run from the repository root:
;; JSX_JEDI_GRAMMAR_DIR=/path/to/grammars \
;;   emacs -Q --batch -L /path/to/avy -l scripts/test.el

(require 'ert)
(require 'treesit)

(defvar jsx-jedi-test-package-file)

(let* ((root (file-name-directory
              (directory-file-name
               (file-name-directory load-file-name))))
       (grammar-directory (getenv "JSX_JEDI_GRAMMAR_DIR")))
  (add-to-list 'load-path root)
  (when grammar-directory
    (unless (file-directory-p grammar-directory)
      (error "JSX_JEDI_GRAMMAR_DIR is not a directory: %s"
             grammar-directory))
    (add-to-list 'treesit-extra-load-path
                 (expand-file-name grammar-directory)))
  (unless (treesit-available-p)
    (error "JSX Jedi tests require Emacs with tree-sitter support"))
  (unless (require 'avy nil t)
    (error "JSX Jedi tests require avy; add its directory with -L /path/to/avy"))
  (let ((availability (treesit-language-available-p 'tsx t)))
    (unless (car availability)
      (error "Cannot load the TSX grammar; set JSX_JEDI_GRAMMAR_DIR: %S"
             (cdr availability))))
  ;; Always exercise the working source, even when an older .elc exists.
  (setq jsx-jedi-test-package-file (expand-file-name "jsx-jedi.el" root))
  (load jsx-jedi-test-package-file nil t t)
  (load (expand-file-name "tests/jsx-jedi-test.el" root) nil t)
  (load (expand-file-name "tests/configuration-test.el" root) nil t))

(ert-run-tests-batch-and-exit)

;;; test.el ends here
