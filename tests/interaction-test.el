;;; interaction-test.el --- Mode and command-loop regressions -*- lexical-binding: t; -*-

;; Run via scripts/test.el, which loads the shared buffer helpers first.
;; Avy uses its own key-reading path; undo/redo runs through keyboard macros.
;; Prompt cancellation replaces read-string and does not exercise a real
;; minibuffer.  Visual labels, focus and themes still need GUI validation.

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

(ert-deftest jsx-jedi-test-avy-scope-stays-in-selected-window ()
  (dolist (window-setting '(nil t all-frames))
    (dolist (prefix '(nil (4)))
      (save-window-excursion
        (jsx-jedi-test--with-buffer "const outside = <A|>alpha beta</A>; const beyond = 1;"
          (switch-to-buffer (current-buffer))
          (delete-other-windows)
          (let* ((origin-window (selected-window))
                 (other-window (split-window-below))
                 (avy-all-windows window-setting)
                 (avy-all-windows-alt 'all-frames)
                 (current-prefix-arg prefix)
                 (info (jsx-jedi--find-node-info jsx-jedi-avy-node-types))
                 candidates)
            (with-temp-buffer
              (insert "const foreign = <Other>foreign destination</Other>;")
              (set-window-buffer other-window (current-buffer))
              (with-selected-window origin-window
                ;; Keep Avy's real candidate search; inspect before key selection.
                (cl-letf (((symbol-function 'avy-process)
                           (lambda (found &rest _) (setq candidates found))))
                  (jsx-jedi-avy-word))
                (should candidates)
                (dolist (candidate candidates)
                  (should (eq (avy-candidate-wnd candidate) origin-window))
                  (should (<= (nth 1 info) (avy-candidate-beg candidate)))
                  (should (< (avy-candidate-beg candidate) (nth 2 info))))
                (should (eq avy-all-windows window-setting))
                (should (eq avy-all-windows-alt 'all-frames))
                (should (eq (selected-window) origin-window))))))))))

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

(ert-deftest jsx-jedi-test-optional-content-command-loop-undo-redo ()
  (dolist (case '((jsx-jedi-empty "type T = |{a: number};" "type T = {};")
                  (jsx-jedi-substitute "type T = |{a: number};" "type T = {b: boolean};")
                  (jsx-jedi-empty "function f() { thr|ow error; after(); }"
                   "function f() { throw ; after(); }")
                  (jsx-jedi-substitute "function f() { thr|ow error; after(); }"
                   "function f() { throw replacement; after(); }")))
    (save-window-excursion
      (jsx-jedi-test--with-buffer (nth 1 case)
        (switch-to-buffer (current-buffer))
        (let ((before (jsx-jedi-test--text))
              (jsx-jedi-empty-node-types
               (append jsx-jedi-empty-node-types '("object_type" "throw_statement"))))
          (setq kill-ring (list (if (string-prefix-p "type" before)
                                   "b: boolean" "replacement")))
          (use-local-map (make-sparse-keymap))
          (local-set-key (kbd "<f5>") (car case))
          (local-set-key (kbd "<f6>") #'undo-only)
          (local-set-key (kbd "<f7>") #'undo-redo)
          (execute-kbd-macro (kbd "<f5>"))
          (should (equal (jsx-jedi-test--text) (nth 2 case)))
          (execute-kbd-macro (kbd "<f6>"))
          (should (equal (jsx-jedi-test--text) before))
          (execute-kbd-macro (kbd "<f7>"))
          (should (equal (jsx-jedi-test--text) (nth 2 case))))))))

(ert-deftest jsx-jedi-test-editing-boundaries-across-major-modes ()
  (dolist (mode '((js-ts-mode javascript)
                  (typescript-ts-mode typescript)
                  (tsx-ts-mode tsx)))
    (dolist (case
             '((jsx-jedi-substitute "function f() { ret|urn original; }"
                "function f() { return 1 +\n2; }" "1 +\n2")
               (jsx-jedi-substitute "const x = `or|iginal`;"
                "const x = `first\n  second`;" "first\n  second")
               (jsx-jedi-duplicate "let count = 0;\n(|count++)"
                "let count = 0;\n(count++);\n(count++)")
               (jsx-jedi-substitute "const x = { a: f(1) \t|\n, b: 2 };"
                "const x = { a: 3 \t\n, b: 2 };" "3")
               (jsx-jedi-comment-uncomment "const x = {\n  a: 1 |,\n  b: 2\n};"
                "const x = {\n  // a: 1 ,\n  b: 2\n};")
               (jsx-jedi-kill "const xs = [{| a: 1 } /* note */, 2];"
                "const xs = [ /* note */ 2];")))
      (with-temp-buffer
        (let* ((source (nth 1 case))
               (position (string-match "|" source))
               (kill-ring (list (or (nth 3 case) "previous kill")))
               (kill-ring-yank-pointer kill-ring)
               (last-command nil)
               (pulse-flag nil))
          (insert (substring source 0 position) (substring source (1+ position)))
          (funcall (car mode))
          (goto-char (1+ position))
          (funcall (car case))
          (should (equal (jsx-jedi-test--text) (nth 2 case)))
          (should-not (treesit-node-check
                       (treesit-buffer-root-node (cadr mode)) 'has-error)))))))

(ert-deftest jsx-jedi-test-editing-boundaries-command-loop-undo-redo ()
  (dolist (case
           '((jsx-jedi-substitute "function f() { ret|urn original; }"
              "function f() { return 1 +\n2; }" "1 +\n2")
             (jsx-jedi-duplicate "let count = 0;\n(|count++)"
              "let count = 0;\n(count++);\n(count++)")
             (jsx-jedi-kill "f({| a: 1 } /* note */, 2);"
              "f( /* note */ 2);")
             (jsx-jedi-kill "f(1, /* note */ {| a: 1 });"
              "f(1 /* note */ );")))
    (save-window-excursion
      (jsx-jedi-test--with-buffer (nth 1 case)
        (switch-to-buffer (current-buffer))
        (let ((before (jsx-jedi-test--text)))
          (when (nth 3 case) (setq kill-ring (list (nth 3 case))))
          (use-local-map (make-sparse-keymap))
          (local-set-key (kbd "<f5>") (car case))
          (local-set-key (kbd "<f6>") #'undo-only)
          (local-set-key (kbd "<f7>") #'undo-redo)
          (execute-kbd-macro (kbd "<f5>"))
          (should (equal (jsx-jedi-test--text) (nth 2 case)))
          (execute-kbd-macro (kbd "<f6>"))
          (should (equal (jsx-jedi-test--text) before))
          (execute-kbd-macro (kbd "<f7>"))
          (should (equal (jsx-jedi-test--text) (nth 2 case)))
          (jsx-jedi-test--assert-valid))))))

(ert-deftest jsx-jedi-test-duplicate-typescript-assertions-stay-separate ()
  (with-temp-buffer
    (insert "<number>value")
    (typescript-ts-mode)
    (goto-char 2)
    (let ((pulse-flag nil))
      (jsx-jedi-duplicate))
    (should (equal (jsx-jedi-test--text) "<number>value;\n<number>value"))
    (should (= 2 (length (treesit-query-capture
                         (treesit-buffer-root-node 'typescript)
                         '((expression_statement) @statement) nil nil t))))
    (should-not (treesit-node-check
                 (treesit-buffer-root-node 'typescript) 'has-error))))

;;; interaction-test.el ends here
