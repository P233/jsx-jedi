;;; configuration-test.el --- Customize lifecycle tests -*- lexical-binding: t; -*-

;; Run via scripts/test.el so child Emacs processes load the same exact
;; source or bytecode file as the parent suite, with fresh Customize state.

(require 'ert)
(require 'cl-lib)

(defvar jsx-jedi-test-package-file)

(defun jsx-jedi-test--fresh-emacs (before after)
  "Evaluate BEFORE, load the selected package, then evaluate AFTER.
Use a fresh process so Customize properties and initial values cannot leak
between tests or hide source versus bytecode initialization differences."
  (with-temp-buffer
    (let* ((form `(progn
                   (setq load-path ',load-path)
                   (require 'ert)
                   ,@before
                   (load ,jsx-jedi-test-package-file nil t t)
                   ,@after))
           (status (call-process
                    (expand-file-name invocation-name invocation-directory)
                    nil t nil "-Q" "--batch" "--eval" (prin1-to-string form))))
      (ert-info ((buffer-string))
        (should (eql status 0))))))

(ert-deftest jsx-jedi-test-configuration-before-load ()
  (jsx-jedi-test--fresh-emacs
   '((setq jsx-jedi-tag-node-types '("jsx_element")
           jsx-jedi-copy-node-types '("string")))
   '((should (equal jsx-jedi-tag-node-types '("jsx_element")))
     (should (equal jsx-jedi-copy-node-types '("string")))
     (should (member "jsx_element" jsx-jedi-kill-node-types))
     (should-not (member "jsx_self_closing_element" jsx-jedi-kill-node-types)))))

(ert-deftest jsx-jedi-test-configuration-independent-and-dynamic ()
  (jsx-jedi-test--fresh-emacs
   nil
   '((let ((original jsx-jedi-kill-node-types))
       (setq jsx-jedi-tag-node-types '("jsx_element"))
       (should (equal jsx-jedi-kill-node-types original))
       (let ((jsx-jedi-kill-node-types '("string")))
         (should (equal (symbol-value 'jsx-jedi-kill-node-types) '("string"))))
       (should (equal jsx-jedi-kill-node-types original))))))

(ert-deftest jsx-jedi-test-configuration-reset-evaluates-current-default ()
  (jsx-jedi-test--fresh-emacs
   nil
   '((setq jsx-jedi-tag-node-types '("jsx_element"))
     ;; A default is an expression, not a frozen copy from first load.
     (custom-reevaluate-setting 'jsx-jedi-kill-node-types)
     (should (member "jsx_element" jsx-jedi-kill-node-types))
     (should-not (member "jsx_self_closing_element" jsx-jedi-kill-node-types)))))

(ert-deftest jsx-jedi-test-configuration-saved-values-before-load ()
  (jsx-jedi-test--fresh-emacs
   '((custom-set-variables
      '(jsx-jedi-tag-node-types '("jsx_self_closing_element"))
      '(jsx-jedi-copy-node-types '("string"))))
   '((should (equal jsx-jedi-tag-node-types '("jsx_self_closing_element")))
     (should (equal jsx-jedi-copy-node-types '("string")))
     (should-not (member "jsx_element" jsx-jedi-kill-node-types)))))

(ert-deftest jsx-jedi-test-configuration-save-and-restore ()
  (let ((file (make-temp-file "jsx-jedi-custom-" nil ".el")))
    (unwind-protect
        (progn
          (jsx-jedi-test--fresh-emacs
           `((require 'cus-edit)
             ;; -Q otherwise suppresses saving even to an explicit custom-file.
             (setq custom-file ,file user-init-file ,file make-backup-files nil))
           '((customize-save-variable 'jsx-jedi-tag-node-types '("jsx_element"))
             (customize-save-variable 'jsx-jedi-copy-node-types '("string"))))
          (jsx-jedi-test--fresh-emacs
           `((load ,file nil t t))
           '((should (equal jsx-jedi-tag-node-types '("jsx_element")))
             (should (equal jsx-jedi-copy-node-types '("string")))
             (should-not (member "jsx_self_closing_element"
                                 jsx-jedi-kill-node-types)))))
      (delete-file file))))

;;; configuration-test.el ends here
