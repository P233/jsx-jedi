;;; interaction-test.el --- Mode and command-loop regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'js)
(require 'typescript-ts-mode)
(require 'jsx-jedi)

(ert-deftest jsx-jedi-test-supported-major-modes ()
  (dolist (case '((js-ts-mode javascript "const x = 'hello';")
                  (typescript-ts-mode typescript "const x: string = 'hello';")
                  (tsx-ts-mode tsx "const x = <A label='hello' />;")))
    (with-temp-buffer
      (insert (nth 2 case))
      (funcall (car case))
      (goto-char (point-min))
      (search-forward "hello")
      (let ((jsx-jedi-empty-node-types '("string")))
        (call-interactively #'jsx-jedi-empty))
      (should-not (string-match-p "hello" (buffer-string)))
      (should-not (treesit-node-check
                   (treesit-buffer-root-node (nth 1 case)) 'has-error)))))

(ert-deftest jsx-jedi-test-prompt-cancellation-preserves-selection ()
  (dolist (command '(jsx-jedi-rename-tag jsx-jedi-wrap-tag jsx-jedi-add-attribute))
    (jsx-jedi-test--with-buffer "const x = <A|>text</A>;"
      (let ((transient-mark-mode t))
        (set-mark (+ (point) 3))
        (setq mark-active t)
        (cl-letf (((symbol-function 'read-string)
                   (lambda (&rest _) (signal 'quit nil))))
          (jsx-jedi-test--unchanged
           (lambda ()
             (should (eq (condition-case nil
                             (progn (call-interactively command) 'completed)
                           (quit 'cancelled))
                         'cancelled)))))))))

(ert-deftest jsx-jedi-test-rejection-preserves-selection ()
  (jsx-jedi-test--with-buffer "const x = <di|v> <A /> </div>;"
    (let ((transient-mark-mode t))
      (set-mark (+ (point) 4))
      (setq mark-active t)
      (jsx-jedi-test--unchanged #'jsx-jedi-unwrap-tag 'user-error))))

(ert-deftest jsx-jedi-test-real-avy-selection-and-cleanup ()
  (save-window-excursion
    (jsx-jedi-test--with-buffer "const outside = <A|>alpha beta</A>;"
      (switch-to-buffer (current-buffer))
      (delete-other-windows)
      (let ((avy-keys '(?a ?s ?d ?f))
            (avy-all-windows t)
            (avy-style 'at-full)
            (unread-command-events '(?d)))
        ;; Exercise Avy's real candidate construction, key reading and cleanup.
        (call-interactively #'jsx-jedi-avy-word)
        (should (looking-at "beta"))
        (should-not (cl-find-if (lambda (overlay)
                                 (eq (overlay-get overlay 'category) 'avy))
                               (overlays-in (point-min) (point-max))))))))

(ert-deftest jsx-jedi-test-copy-highlight-cleans-up-on-next-command ()
  (save-window-excursion
    (jsx-jedi-test--with-buffer "const x = <A| />;"
      (switch-to-buffer (current-buffer))
      (let ((pulse-flag t))
        (unwind-protect
            (progn
              (call-interactively #'jsx-jedi-copy)
              (should (equal (car kill-ring) "<A />"))
              (let ((overlay pulse-momentary-overlay))
                (should (overlayp overlay))
                (should (equal (buffer-substring-no-properties
                                (overlay-start overlay) (overlay-end overlay))
                               "<A />"))
                (execute-kbd-macro (kbd "C-f"))
                (should-not (overlay-buffer overlay))))
          (pulse-momentary-unhighlight))))))

(ert-deftest jsx-jedi-test-command-loop-multiple-edits-undo-redo ()
  (save-window-excursion
    (jsx-jedi-test--with-buffer "const x = <A| />;"
      (switch-to-buffer (current-buffer))
      (use-local-map (make-sparse-keymap))
      (local-set-key (kbd "<f5>") #'jsx-jedi-toggle-self-closing-tag)
      (local-set-key (kbd "<f6>") #'undo-only)
      (local-set-key (kbd "<f7>") #'undo-redo)
      ;; Two real command-loop edits, with no manually inserted undo boundary.
      (execute-kbd-macro (kbd "<f5> <f5>"))
      (should (equal (jsx-jedi-test--text) "const x = <A />;"))
      (execute-kbd-macro (kbd "<f6>"))
      (should (equal (jsx-jedi-test--text) "const x = <A></A>;"))
      (execute-kbd-macro (kbd "<f6>"))
      (should (equal (jsx-jedi-test--text) "const x = <A />;"))
      (execute-kbd-macro (kbd "<f7> <f7>"))
      (should (equal (jsx-jedi-test--text) "const x = <A />;"))
      (jsx-jedi-test--assert-valid))))

;;; interaction-test.el ends here
