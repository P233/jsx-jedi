;;; jsx-jedi-test.el --- Structural editing regression tests -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests use the real TSX grammar and major mode.  Configure the grammar
;; and Avy load paths before loading this file; see scripts/test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'pulse)
(require 'typescript-ts-mode)
(require 'jsx-jedi)

(defmacro jsx-jedi-test--with-buffer (source &rest body)
  "Run BODY in a TSX buffer containing SOURCE, with | marking point."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (unless (treesit-ready-p 'tsx t)
       (error "The TSX tree-sitter grammar is required"))
     (let* ((source ,source)
            (position (string-match "|" source))
            (pulse-flag nil)
            (kill-ring '("previous kill"))
            (kill-ring-yank-pointer kill-ring)
            (last-command nil))
       (unless position (error "Test source must mark point with |"))
       (insert (substring source 0 position) (substring source (1+ position)))
       (tsx-ts-mode)
       (goto-char (1+ position))
       (buffer-enable-undo)
       (setq buffer-undo-list nil)
       (set-buffer-modified-p nil)
       ,@body)))

(defun jsx-jedi-test--text ()
  "Return current buffer text without properties."
  (buffer-substring-no-properties (point-min) (point-max)))

(defun jsx-jedi-test--assert-valid ()
  "Assert that the TSX parser reports no error or missing syntax."
  (should-not (treesit-node-check (treesit-buffer-root-node 'tsx) 'has-error)))

(defun jsx-jedi-test--unchanged (command &optional error-type)
  "Assert COMMAND preserves editing state, optionally raising ERROR-TYPE."
  (let ((text (jsx-jedi-test--text))
        (position (point))
        (mark-position (mark t))
        (region-active mark-active)
        (kills (copy-sequence kill-ring)))
    (if error-type
        (should-error (funcall command) :type error-type)
      (funcall command))
    (should (equal text (jsx-jedi-test--text)))
    (should (= position (point)))
    (should (equal mark-position (mark t)))
    (should (eq region-active mark-active))
    (should (equal kills kill-ring))))

(defun jsx-jedi-test--pair-texts ()
  "Return object pair texts in source order from the current TSX tree."
  (mapcar (lambda (node) (treesit-node-text node t))
          (treesit-query-capture (treesit-buffer-root-node 'tsx)
                                '((pair) @pair) nil nil t)))

(defun jsx-jedi-test--template-texts ()
  "Return template strings verbatim from the current TSX tree."
  (mapcar (lambda (node) (treesit-node-text node t))
          (treesit-query-capture (treesit-buffer-root-node 'tsx)
                                '((template_string) @template) nil nil t)))

(ert-deftest jsx-jedi-test-empty-boolean-attribute ()
  (jsx-jedi-test--with-buffer "const x = <Button dis|abled />;"
    (jsx-jedi-test--unchanged #'jsx-jedi-empty)))

(ert-deftest jsx-jedi-test-empty-self-closing-tag ()
  (jsx-jedi-test--with-buffer "const x = <But|ton value={x} />;"
    (jsx-jedi-test--unchanged #'jsx-jedi-empty)))

(ert-deftest jsx-jedi-test-empty-string-keeps-delimiters ()
  (jsx-jedi-test--with-buffer "const x = \"he|llo\";"
    (jsx-jedi-empty)
    (should (equal (jsx-jedi-test--text) "const x = \"\";"))
    (should (eq (char-before) ?\"))
    (should (eq (char-after) ?\"))
    (should (equal (car kill-ring) "hello"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-empty-jsx-children ()
  (jsx-jedi-test--with-buffer "const x = <Di|v>hello<A /></Div>;"
    (jsx-jedi-empty)
    (should (equal (jsx-jedi-test--text) "const x = <Div></Div>;"))
    (should (looking-at-p "</Div>"))
    (should (equal (car kill-ring) "hello<A />"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-empty-fragment ()
  (jsx-jedi-test--with-buffer "const x = <|><A /></>;"
    (jsx-jedi-empty)
    (should (equal (jsx-jedi-test--text) "const x = <></>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-empty-attribute-values ()
  (dolist (case '(("const x = <A tit|le=\"hello\" />;"
                   "const x = <A title=\"\" />;" "hello")
                  ("const x = <A val|ue={value} />;"
                   "const x = <A value={} />;" "value")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-empty)
      (should (equal (jsx-jedi-test--text) (nth 1 case)))
      (should (equal (car kill-ring) (nth 2 case))))))

(ert-deftest jsx-jedi-test-empty-non-jsx-content-contracts ()
  ;; Limit selection to the named target so nested values do not intercept it.
  ;; Emptying a value can intentionally leave an incomplete expression to edit.
  (dolist (case
           '(("arguments" "call(|a, b);" "call();")
             ("array" "const x = [|a, b];" "const x = [];")
             ("array_pattern" "const [|a, b] = x;" "const [] = x;")
             ("assignment_expression" "x = |value;" "x = ;")
             ("call_expression" "ca|ll(a, b);" "call();")
             ("export_clause" "export {| a, b };" "export {};")
             ("formal_parameters" "function f(|a, b) {}" "function f() {}")
             ("interface_declaration" "interface |X { a: number }" "interface X {}")
             ("lexical_declaration" "const |x = value;" "const x = ;")
             ("named_imports" "import {| a, b } from 'm';" "import {} from 'm';")
             ("object" "const x = {| a: 1 };" "const x = {};")
             ("object_pattern" "const {| a, b } = x;" "const {} = x;")
             ("pair" "const x = { a|: value };" "const x = { a:  };")
             ("parenthesized_expression" "const x = (|a + b);" "const x = ();")
             ("property_signature" "interface X { a|: number }" "interface X { a:  }")
             ("return_statement" "function f() { return |value; }"
              "function f() { return ; }")
             ("statement_block" "function f() {| work(); }" "function f() {}")
             ("string" "const x = 'he|llo';" "const x = '';")
             ("tuple_type" "type T = [|string, number];" "type T = [];")
             ("type_alias_declaration" "type |T = string;" "type T = ;")
             ("type_parameters" "function f<|T, U>() {}" "function f<>() {}")
             ("variable_declaration" "var |x = value;" "var x = ;")
             ("template_string" "const x = `he|llo`;" "const x = ``;")))
    (jsx-jedi-test--with-buffer (nth 1 case)
      (let ((jsx-jedi-empty-node-types (list (car case))))
        (ert-info ((car case))
          (jsx-jedi-empty)
          (should (equal (jsx-jedi-test--text) (nth 2 case))))))))

(ert-deftest jsx-jedi-test-substitute-string ()
  (jsx-jedi-test--with-buffer "const x = \"he|llo\";"
    (setq kill-ring '(" replacement "))
    (jsx-jedi-substitute)
    (should (equal (jsx-jedi-test--text) "const x = \"replacement\";"))
    (should (eq (char-after) ?\"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-substitute-empty-string ()
  (jsx-jedi-test--with-buffer "const x = \"|\";"
    (setq kill-ring '("replacement"))
    (jsx-jedi-substitute)
    (should (equal (jsx-jedi-test--text) "const x = \"replacement\";"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-substitute-no-content-is-noop ()
  (dolist (source '("const x = <Button dis|abled />;"
                    "const x = <But|ton value={x} />;"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-substitute))))

(ert-deftest jsx-jedi-test-zap-in-closing-tag-is-noop ()
  (jsx-jedi-test--with-buffer "const x = <div>hello</di|v>;"
    (jsx-jedi-test--unchanged #'jsx-jedi-zap)))

(ert-deftest jsx-jedi-test-zap-jsx-content ()
  (jsx-jedi-test--with-buffer "const x = <div>he|llo</div>;"
    (jsx-jedi-zap)
    (should (equal (jsx-jedi-test--text) "const x = <div>he</div>;"))
    (should (looking-at-p "</div>"))
    (should (equal kill-ring '("previous kill")))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-zap-tag-name-is-noop ()
  (dolist (source '("const x = <But|ton value={x} />;"
                    "const x = <But|ton value={x}></Button>;"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-zap))))

(ert-deftest jsx-jedi-test-zap-opening-attributes-preserves-tag ()
  (dolist (case '(("const x = <Button |value={x} />;" "const x = <Button />;")
                  ("const x = <Button |value={x}></Button>;"
                   "const x = <Button ></Button>;")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-zap)
      (should (equal (jsx-jedi-test--text) (nth 1 case)))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-zap-empty-content-boundaries ()
  (dolist (source '("const x = \"|\";" "const x = <div>|</div>;"
                    "const x = <Button |/>;"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-zap))))

(ert-deftest jsx-jedi-test-duplicate-first-pair ()
  (jsx-jedi-test--with-buffer "const x = { a|: 1, b: 2 };"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (equal (jsx-jedi-test--pair-texts) '("a: 1" "a: 1" "b: 2")))))

(ert-deftest jsx-jedi-test-duplicate-middle-pair ()
  (jsx-jedi-test--with-buffer "const x = { a: 1, b|: 2, c: 3 };"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (equal (jsx-jedi-test--pair-texts)
                   '("a: 1" "b: 2" "b: 2" "c: 3")))))

(ert-deftest jsx-jedi-test-duplicate-last-pair ()
  (jsx-jedi-test--with-buffer "const x = { a: 1, b|: 2 };"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (equal (jsx-jedi-test--pair-texts) '("a: 1" "b: 2" "b: 2")))))

(ert-deftest jsx-jedi-test-duplicate-pair-with-trailing-comma ()
  (jsx-jedi-test--with-buffer "const x = { a|: 1, };"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (equal (jsx-jedi-test--pair-texts) '("a: 1" "a: 1")))
    (should (string-match-p ", *};\\'" (jsx-jedi-test--text)))))

(ert-deftest jsx-jedi-test-duplicate-entire-comment-block ()
  (jsx-jedi-test--with-buffer "// o|ne\n// two\nconst x = 1;"
    (jsx-jedi-duplicate)
    (should (equal (jsx-jedi-test--text)
                   "// one\n// two\n// one\n// two\nconst x = 1;"))
    (should (equal kill-ring '("previous kill")))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-duplicate-rejects-expression-positions ()
  (dolist (source '("const x = <Di|v />;"
                    "const x = <Di|v>hello</Div>;"
                    "const x = <Div value={val|ue} />;"
                    "const x = {| a: 1 };"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-duplicate 'user-error))))

(ert-deftest jsx-jedi-test-duplicate-object-in-array ()
  (jsx-jedi-test--with-buffer "const x = [{| a: 1 }, { b: 2 }];"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (equal (jsx-jedi-test--pair-texts) '("a: 1" "a: 1" "b: 2")))))

(ert-deftest jsx-jedi-test-duplicate-object-argument ()
  (jsx-jedi-test--with-buffer "call({| a: 1 });"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (equal (jsx-jedi-test--pair-texts) '("a: 1" "a: 1")))))

(ert-deftest jsx-jedi-test-duplicate-jsx-child ()
  (jsx-jedi-test--with-buffer "const x = <p><A| /></p>;"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (should (= 2 (length (treesit-query-capture
                         (treesit-buffer-root-node 'tsx)
                         '((jsx_self_closing_element) @tag) nil nil t))))))

(ert-deftest jsx-jedi-test-duplicate-preserves-template-string-content ()
  (jsx-jedi-test--with-buffer "const| x = `one\n   two\n zero`;"
    (jsx-jedi-duplicate)
    (should (equal (jsx-jedi-test--text)
                   "const x = `one\n   two\n zero`;\nconst x = `one\n   two\n zero`;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-duplicate-preserves-function-body-indentation ()
  (jsx-jedi-test--with-buffer
      "function |example() {\n  if (ok) {\n    work();\n  }\n}"
    (let ((original (jsx-jedi-test--text)))
      (jsx-jedi-duplicate)
      (should (equal (jsx-jedi-test--text) (concat original "\n" original)))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-duplicate-preserves-multiline-object-body ()
  (jsx-jedi-test--with-buffer "const x = [\n  {|\n    a: 1,\n    b: 2\n  }\n];"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (let ((objects (mapcar (lambda (node) (treesit-node-text node t))
                           (treesit-query-capture (treesit-buffer-root-node 'tsx)
                                                 '((object) @object) nil nil t))))
      (should (equal objects '("{\n    a: 1,\n    b: 2\n  }"
                               "{\n    a: 1,\n    b: 2\n  }"))))))

(ert-deftest jsx-jedi-test-duplicate-preserves-jsx-text-content ()
  (jsx-jedi-test--with-buffer
      "const x = <p>\n  <di|v>one\n   two\n zero</div>\n</p>;"
    (jsx-jedi-duplicate)
    (jsx-jedi-test--assert-valid)
    (let ((children
           (cl-remove-if-not
            (lambda (text) (string-prefix-p "<div>" text))
            (mapcar (lambda (node) (treesit-node-text node t))
                    (treesit-query-capture (treesit-buffer-root-node 'tsx)
                                          '((jsx_element) @tag) nil nil t)))))
      (should (equal children '("<div>one\n   two\n zero</div>"
                                "<div>one\n   two\n zero</div>"))))))

(ert-deftest jsx-jedi-test-fragment-tag-commands-reject ()
  (dolist (command '(jsx-jedi-rename-tag jsx-jedi-toggle-self-closing-tag
                    jsx-jedi-add-attribute))
    (jsx-jedi-test--with-buffer "const x = <|><A /></>;"
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "New")))
        (jsx-jedi-test--unchanged command 'user-error)))))

(ert-deftest jsx-jedi-test-rename-paired-tag ()
  (jsx-jedi-test--with-buffer "const x = <A| n={1}>hello</A>;"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Long")))
      (jsx-jedi-rename-tag))
    (should (equal (jsx-jedi-test--text) "const x = <Long n={1}>hello</Long>;"))
    (should (looking-at-p " n="))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-toggle-self-closing-tag ()
  (jsx-jedi-test--with-buffer "const x = <A| n={1} />;"
    (jsx-jedi-toggle-self-closing-tag)
    (should (equal (jsx-jedi-test--text) "const x = <A n={1}></A>;"))
    (should (looking-at-p "</A>"))
    (jsx-jedi-toggle-self-closing-tag)
    (should (equal (jsx-jedi-test--text) "const x = <A n={1} />;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-toggle-preserves-template-attribute-content ()
  (jsx-jedi-test--with-buffer "const x = <A| title={`one\n   two\n zero`} />;"
    (jsx-jedi-toggle-self-closing-tag)
    (should (equal (jsx-jedi-test--text)
                   "const x = <A title={`one\n   two\n zero`}></A>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-add-attribute-point-inside-value ()
  (jsx-jedi-test--with-buffer "const x = <A|></A>;"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "value")))
      (jsx-jedi-add-attribute))
    (should (equal (jsx-jedi-test--text) "const x = <A value={}></A>;"))
    (should (eq (char-before) ?{))
    (should (eq (char-after) ?}))))

(ert-deftest jsx-jedi-test-wrap-tag ()
  (jsx-jedi-test--with-buffer "const x = <A| />;"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "B")))
      (jsx-jedi-wrap-tag))
    (should (equal (jsx-jedi-test--text) "const x = <B><A /></B>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-wrap-preserves-template-attribute-content ()
  (jsx-jedi-test--with-buffer "const x = <A| title={`one\n   two\n zero`} />;"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "B")))
      (jsx-jedi-wrap-tag))
    (should (string-match-p "<B>" (jsx-jedi-test--text)))
    (should (equal (jsx-jedi-test--template-texts) '("`one\n   two\n zero`")))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-unwrap-preserves-inline-text-whitespace ()
  (jsx-jedi-test--with-buffer "const x = <p>Hello<sp|an> world </span>!</p>;"
    (jsx-jedi-unwrap-tag)
    (should (equal (jsx-jedi-test--text) "const x = <p>Hello world !</p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-unwrap-preserves-multiline-jsx-text ()
  (jsx-jedi-test--with-buffer "const x = <p>Hello<sp|an> \n  world \n </span>!</p>;"
    (jsx-jedi-unwrap-tag)
    (should (equal (jsx-jedi-test--text)
                   "const x = <p>Hello \n  world \n !</p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-unwrap-rejects-non-jsx-expression-results ()
  (dolist (content '("{value}" "{getValue()}" "<A /><B />" "hello" ""))
    (jsx-jedi-test--with-buffer (concat "const x = <di|v>" content "</div>;")
      (jsx-jedi-test--unchanged #'jsx-jedi-unwrap-tag 'user-error))))

(ert-deftest jsx-jedi-test-unwrap-rejects-self-closing-expression ()
  (jsx-jedi-test--with-buffer "const x = <Di|v />;"
    (jsx-jedi-test--unchanged #'jsx-jedi-unwrap-tag 'user-error)))

(ert-deftest jsx-jedi-test-unwrap-single-jsx-expression ()
  (jsx-jedi-test--with-buffer "const x = <di|v><A /></div>;"
    (jsx-jedi-unwrap-tag)
    (should (equal (jsx-jedi-test--text) "const x = <A />;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-unwrap-fragment-with-one-jsx-child ()
  (jsx-jedi-test--with-buffer "const x = <|><A /></>;"
    (jsx-jedi-unwrap-tag)
    (should (equal (jsx-jedi-test--text) "const x = <A />;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-unwrap-self-closing-jsx-child ()
  (jsx-jedi-test--with-buffer "const x = <p>Hello<Di|v />!</p>;"
    (jsx-jedi-unwrap-tag)
    (should (equal (jsx-jedi-test--text) "const x = <p>Hello!</p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-hoist-rejects-jsx-expression-into-javascript ()
  (dolist (source '("const x = <div>{val|ue}</div>;"
                    "const x = <div>{getVal|ue()}</div>;"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-hoist-tag 'user-error))))

(ert-deftest jsx-jedi-test-hoist-single-jsx-element ()
  (jsx-jedi-test--with-buffer "const x = <div><A| /></div>;"
    (jsx-jedi-hoist-tag)
    (should (equal (jsx-jedi-test--text) "const x = <A />;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-hoist-expression-within-jsx ()
  (jsx-jedi-test--with-buffer "const x = <p><div>{val|ue}</div></p>;"
    (jsx-jedi-hoist-tag)
    (should (equal (jsx-jedi-test--text) "const x = <p>{value}</p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-hoist-preserves-template-expression-content ()
  (jsx-jedi-test--with-buffer "const x = <p><div>{`one|\n   two\n zero`}</div></p>;"
    (jsx-jedi-hoist-tag)
    (should (equal (jsx-jedi-test--text)
                   "const x = <p>{`one\n   two\n zero`}</p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-hoist-preserves-surrounding-literal-whitespace ()
  (dolist (case '(("const x = `one\n   two ${<div><A| /></div>}\n zero`;"
                   "const x = `one\n   two ${<A />}\n zero`;")
                  ("const x = <A title={`one\n   two ${<div><B| /></div>}\n zero`} />;"
                   "const x = <A title={`one\n   two ${<B />}\n zero`} />;")
                  ("const x = <p>\n     literal <div><A| /></div></p>;"
                   "const x = <p>\n     literal <A /></p>;")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-hoist-tag)
      (should (equal (jsx-jedi-test--text) (cadr case)))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-comment-rejects-nested-block-comment ()
  (jsx-jedi-test--with-buffer "const x = <p><di|v>{/* hi */}</div></p>;"
    (jsx-jedi-test--unchanged #'jsx-jedi-comment-uncomment 'user-error)))

(ert-deftest jsx-jedi-test-comment-rejects-jsx-in-expression-position ()
  (jsx-jedi-test--with-buffer "const x = <Di|v />;"
    (jsx-jedi-test--unchanged #'jsx-jedi-comment-uncomment 'user-error)))

(ert-deftest jsx-jedi-test-uncomment-rejects-mixed-comment-expression ()
  (dolist (source '("const x = <A>{/* h|i */ value}</A>;"
                    "const x = <A>{value /* h|i */}</A>;"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-comment-uncomment 'user-error))))

(ert-deftest jsx-jedi-test-uncomment-spaced-jsx-comment ()
  (jsx-jedi-test--with-buffer "const x = <A>{ /* h|i */ }</A>;"
    (jsx-jedi-comment-uncomment)
    (should (equal (jsx-jedi-test--text) "const x = <A>hi</A>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-uncomment-preserves-multiline-jsx-text ()
  (jsx-jedi-test--with-buffer "const x = <p>Hello{/*\n wor|ld\n */}!</p>;"
    (jsx-jedi-comment-uncomment)
    (should (equal (jsx-jedi-test--text)
                   "const x = <p>Hello\n world\n!</p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-comment-uncomment-jsx-child ()
  (jsx-jedi-test--with-buffer "const x = <p><Di|v /></p>;"
    (jsx-jedi-comment-uncomment)
    (should (equal (jsx-jedi-test--text) "const x = <p>{/* <Div /> */}</p>;"))
    (jsx-jedi-test--assert-valid)
    (goto-char (point-min))
    (search-forward "Div")
    (jsx-jedi-comment-uncomment)
    (should (equal (jsx-jedi-test--text) "const x = <p><Div /></p>;"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-copy-and-mark-comment-block ()
  (jsx-jedi-test--with-buffer "// o|ne\n// two\nconst x = 1;"
    (jsx-jedi-copy)
    (should (equal (car kill-ring) "// one\n// two"))
    (jsx-jedi-mark)
    (should mark-active)
    (should (= (point) (point-min)))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "// one\n// two"))))

(ert-deftest jsx-jedi-test-kill-object-pair ()
  (jsx-jedi-test--with-buffer "const x = { a|: 1, b: 2 };"
    (jsx-jedi-kill)
    (should (equal (jsx-jedi-test--text) "const x = { b: 2 };"))
    (should (equal (car kill-ring) "a: 1, "))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-rename-is-one-undo-step ()
  (jsx-jedi-test--with-buffer "const x = <A|>hello</A>;"
    (let ((original (jsx-jedi-test--text)))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Long")))
        (jsx-jedi-rename-tag))
      (undo-boundary)
      (undo-only 1)
      (should (equal (jsx-jedi-test--text) original))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-unwrap-is-one-undo-step ()
  (jsx-jedi-test--with-buffer "const x = <p><sp|an> world </span></p>;"
    (let ((original (jsx-jedi-test--text)))
      (jsx-jedi-unwrap-tag)
      (undo-boundary)
      (undo-only 1)
      (should (equal (jsx-jedi-test--text) original))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-read-only-rejects-without-changing-state ()
  (jsx-jedi-test--with-buffer "const x = <p><sp|an> world </span></p>;"
    (setq buffer-read-only t)
    (jsx-jedi-test--unchanged #'jsx-jedi-unwrap-tag 'buffer-read-only)))

(ert-deftest jsx-jedi-test-rename-rolls-back-partial-read-only-edit ()
  (jsx-jedi-test--with-buffer "const x = <A|>hello</A>;"
    ;; Renaming normally changes the closing name first.  Protect the opening
    ;; name to ensure failure of a later edit restores the earlier one.
    (put-text-property (- (point) 1) (point) 'read-only t)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Long")))
      (jsx-jedi-test--unchanged #'jsx-jedi-rename-tag 'text-read-only))))

(provide 'jsx-jedi-test)
;;; jsx-jedi-test.el ends here
