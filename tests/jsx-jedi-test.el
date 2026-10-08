;;; jsx-jedi-test.el --- Structural editing regression tests -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests use the real TSX grammar and major mode.  Configure the grammar
;; and Avy load paths before loading this file; see scripts/test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'abbrev)
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

(ert-deftest jsx-jedi-test-edit-commands-ignore-prefix-arguments ()
  (dolist (source '("function f() { const value = 4|2; return value; }"
                    "const view = <main><but|ton>Ready</button><aside /></main>;"))
    (dolist (command '(jsx-jedi-kill jsx-jedi-copy jsx-jedi-duplicate jsx-jedi-mark
                       jsx-jedi-empty jsx-jedi-comment-uncomment))
      (let (baseline)
        (dolist (prefix '(nil (4) (16) -))
          (jsx-jedi-test--with-buffer source
            (let ((current-prefix-arg prefix))
              (call-interactively command)
              (let ((result (list (jsx-jedi-test--text) (point) (mark t)
                                  mark-active kill-ring)))
                (if prefix (should (equal result baseline)) (setq baseline result))))))))))

(ert-deftest jsx-jedi-test-empty-boolean-attribute ()
  (jsx-jedi-test--with-buffer "const x = <Button dis|abled />;"
    (jsx-jedi-test--unchanged #'jsx-jedi-empty 'user-error)))

(ert-deftest jsx-jedi-test-empty-self-closing-tag ()
  (jsx-jedi-test--with-buffer "const x = <But|ton value={x} />;"
    (jsx-jedi-test--unchanged #'jsx-jedi-empty 'user-error)))

(ert-deftest jsx-jedi-test-content-search-stops-at-the-statement ()
  ;; A statement or comment without content never selects its enclosing block.
  (dolist (source '("function f() { x| += 1; y(); }"
                    "function f() { if (a) { b|reak; } }"
                    "function f() { work();| }"
                    "function f() {\n  // no|te\n  work();\n}"
                    "items.map((x) => { x|++; });"
                    "function f() { re|turn; }"
                    "imp|ort x from 'y';"
                    "namespace N { func|tion f(): void; }"
                    "declare module \"x\" { imp|ort a = M.b; }"))
    (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
      (jsx-jedi-test--with-buffer source
        (ert-info ((format "%s in %s" command source))
          (jsx-jedi-test--unchanged command 'user-error)))))
  (jsx-jedi-test--with-buffer "function f() { x| += 1; }"
    (should (equal (cadr (should-error (jsx-jedi-empty) :type 'user-error))
                   "Nothing to empty here")))
  ;; Blank space and braces still belong to the block itself.
  (dolist (source '("function f() { | x += 1; }" "function f() { x += 1; |}"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-empty)
      (should (equal (jsx-jedi-test--text) "function f() {}")))))

(ert-deftest jsx-jedi-test-empty-block-statement-from-its-header ()
  (dolist (case '(("func|tion g() { x; }" "function g() {}")
                  ("function g|o() { x; }" "function go() {}")
                  ("cla|ss A { m() {} }" "class A {}")
                  ("class A { ren|der() { x; } }" "class A { render() {} }")
                  ("i|f (a) { x; } else { y; }" "if (a) {} else { y; }")
                  ("if (a) { x; } el|se { y; }" "if (a) { x; } else {}")
                  ("whi|le (a) { x; }" "while (a) {}")
                  ("tr|y { x; } catch (e) { y; }" "try {} catch (e) { y; }")
                  ("try { x; } cat|ch (e) { y; }" "try { x; } catch (e) {}")
                  ("swi|tch (a) { case 1: x; }" "switch (a) {}")
                  ("exp|ort function g() { x; }" "export function g() {}")
                  ("names|pace N { const x = 1; }" "namespace N {}")
                  ;; Object methods empty their body, as pairs empty their value.
                  ("const o = { |m() { return 1; }, n: 2 };" "const o = { m() {}, n: 2 };")
                  ;; Conditions and parameters keep their own content.
                  ("if (a|) { x; }" "if () { x; }")
                  ;; Expressions are not statements with headers.
                  ("const f = () =|> { x; };" "const f = ;")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-empty)
      (should (equal (jsx-jedi-test--text) (cadr case)))))
  ;; An unclosed block would extend to the end of the buffer.
  (dolist (source '("export function Ap|p() {\n  if (x) {\n    y();\n}\nexport function B() {}\n"
                    "function f() { | x;\nfoo();"))
    (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
      (jsx-jedi-test--with-buffer source
        (jsx-jedi-test--unchanged command 'user-error)))))

(ert-deftest jsx-jedi-test-empty-keyword-types-like-named-types ()
  ;; The `string' and `object' type keywords are not string or object nodes.
  (dolist (case '(("interface I { a: str|ing }" "interface I { a:  }")
                  ("let x: obj|ect = {};" "let x: object = ;")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-empty)
      (should (equal (jsx-jedi-test--text) (cadr case))))))

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

(ert-deftest jsx-jedi-test-empty-declaration-preserves-leading-comments ()
  (dolist (keyword '("const" "let" "var"))
    (jsx-jedi-test--with-buffer
        (concat "|" keyword " /* why */ /* detail */ x = original, y = keep;")
      (jsx-jedi-empty)
      (should (equal (jsx-jedi-test--text)
                     (concat keyword " /* why */ /* detail */ x = , y = keep;")))
      (should (equal (car kill-ring) "original"))
      (should (looking-at-p ", y = keep;")))))

(ert-deftest jsx-jedi-test-substitute-declaration-preserves-leading-comments ()
  (dolist (keyword '("const" "let" "var"))
    (jsx-jedi-test--with-buffer
        (concat "|" keyword " /* why */ /* detail */ x = original, y = keep;")
      (setq kill-ring '("replacement"))
      (jsx-jedi-substitute)
      (should (equal (jsx-jedi-test--text)
                     (concat keyword " /* why */ /* detail */ x = replacement, y = keep;")))
      (should (equal (car kill-ring) "original"))
      (should (looking-at-p ", y = keep;"))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-declaration-without-first-initializer-is-unchanged ()
  (dolist (keyword '("let" "var"))
    (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
      (jsx-jedi-test--with-buffer
          (concat "|" keyword " /* why */ first, second = keep;")
        (jsx-jedi-test--unchanged command 'user-error)))))

(ert-deftest jsx-jedi-test-substitute-empty-string ()
  (jsx-jedi-test--with-buffer "const x = \"|\";"
    (setq kill-ring '("replacement"))
    (jsx-jedi-substitute)
    (should (equal (jsx-jedi-test--text) "const x = \"replacement\";"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-substitute-without-content-is-rejected ()
  (dolist (source '("const x = <Button dis|abled />;"
                    "const x = <But|ton value={x} />;"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-test--unchanged #'jsx-jedi-substitute 'user-error))))

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

(ert-deftest jsx-jedi-test-duplicate-does-not-expand-abbrevs ()
  (dolist (case '(("const| x = token"
                   "const x = token\nconst x = token")
                  ("function f() {\n  const| x = token\n}"
                   "function f() {\n  const x = token\n  const x = token\n}")))
    (jsx-jedi-test--with-buffer (car case)
      (let ((expansions 0))
        (setq-local local-abbrev-table (make-abbrev-table))
        (define-abbrev local-abbrev-table "token" "replacement"
          (lambda () (cl-incf expansions)) :system t)
        (abbrev-mode 1)
        (jsx-jedi-duplicate)
        (should (equal (jsx-jedi-test--text) (cadr case)))
        (should (zerop expansions))
        (should (equal kill-ring '("previous kill")))
        (jsx-jedi-test--assert-valid)))))

(ert-deftest jsx-jedi-test-duplicate-does-not-auto-fill ()
  (jsx-jedi-test--with-buffer "const| value = first + second"
    (setq-local fill-column 10)
    (auto-fill-mode 1)
    (jsx-jedi-duplicate)
    (should (equal (jsx-jedi-test--text)
                   "const value = first + second\nconst value = first + second"))
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

(ert-deftest jsx-jedi-test-comment-block-boundaries ()
  (dolist (case '(("const x = 1; // trailing\n// hea|der\nconst y = 2;" "// header")
                  ("const x = 1; // trai|ling\n// header\nconst y = 2;" "// trailing")
                  ("// one\n\n// tw|o\nx;" "// two")
                  ("/** doc */\n// eslint-disable-|next-line\nf();"
                   "// eslint-disable-next-line")
                  ("/** d|oc */\n// eslint-disable-next-line\nf();" "/** doc */")
                  ("/* a\n   b */\n// |c\nx;" "// c")
                  ("// |a\n/* b */ foo();" "// a")
                  ("function f() {\n  work()\n  // o|ne\n  // two\n}" "// one\n  // two")
                  ("f(\n  x,\n  // o|ne\n  // two\n  y,\n);" "// one\n  // two")
                  ("const x = <p>\n  {\n    // o|ne\n    // two\n  }\n</p>;"
                   "// one\n    // two")
                  ("// one  \n// tw|o\t\nx;" "// one  \n// two\t")
                  ("// one\r\n// tw|o\r\nx;" "// one\r\n// two")))
    (jsx-jedi-test--with-buffer (car case)
      (ert-info ((car case))
        (jsx-jedi-copy)
        (should (equal (car kill-ring) (cadr case)))))))

(ert-deftest jsx-jedi-test-kill-comment-keeps-trailing-comment ()
  (jsx-jedi-test--with-buffer "const x = 1; // trailing\n// hea|der\nconst y = 2;"
    (jsx-jedi-kill)
    (should (equal (jsx-jedi-test--text) "const x = 1; // trailing\nconst y = 2;"))
    (should (equal (car kill-ring) "// header"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-uncomment-keeps-trailing-comment ()
  (jsx-jedi-test--with-buffer "const x = 1; // trailing\n// hea|der\nconst y = 2;"
    (jsx-jedi-comment-uncomment)
    (should (equal (jsx-jedi-test--text)
                   "const x = 1; // trailing\nheader\nconst y = 2;"))
    (jsx-jedi-test--assert-valid)))

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

(ert-deftest jsx-jedi-test-tag-preference-cannot-enable-expression-promotion ()
  (let ((jsx-jedi-tag-node-types
         (append jsx-jedi-tag-node-types '("jsx_expression"))))
    (jsx-jedi-test--with-buffer "const x = <div>{val|ue}</div>;"
      (jsx-jedi-test--unchanged #'jsx-jedi-hoist-tag 'user-error))
    (jsx-jedi-test--with-buffer "const x = <di|v>{value}</div>;"
      (jsx-jedi-test--unchanged #'jsx-jedi-unwrap-tag 'user-error))))

(ert-deftest jsx-jedi-test-tag-preference-does-not-change-jsx-shapes ()
  (let ((jsx-jedi-tag-node-types '("jsx_element")))
    (jsx-jedi-test--with-buffer "const x = <div><A| /></div>;"
      (jsx-jedi-hoist-tag)
      (should (equal (jsx-jedi-test--text) "const x = <A />;")))
    (jsx-jedi-test--with-buffer "const x = <di|v><A /></div>;"
      (jsx-jedi-unwrap-tag)
      (should (equal (jsx-jedi-test--text) "const x = <A />;")))
    (jsx-jedi-test--with-buffer "const x = <p><A| /></p>;"
      (jsx-jedi-comment-uncomment)
      (should (equal (jsx-jedi-test--text) "const x = <p>{/* <A /> */}</p>;")))))

(ert-deftest jsx-jedi-test-tag-commands-reject-custom-non-tag-types ()
  (let ((jsx-jedi-tag-node-types '("jsx_expression")))
    (dolist (command '(jsx-jedi-rename-tag jsx-jedi-wrap-tag jsx-jedi-unwrap-tag
                       jsx-jedi-move-to-opening-tag jsx-jedi-move-to-closing-tag
                       jsx-jedi-toggle-self-closing-tag jsx-jedi-add-attribute))
      (jsx-jedi-test--with-buffer "const x = <A>{val|ue}</A>;"
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "New")))
          (jsx-jedi-test--unchanged command 'user-error))))))

(ert-deftest jsx-jedi-test-unwrap-rejects-whitespace-text-in-expression-slot ()
  (dolist (content '(" <A /> " "\t<A />" " \n  <A /> \n "))
    (jsx-jedi-test--with-buffer (concat "const x = <di|v>" content "</div>;")
      (jsx-jedi-test--unchanged #'jsx-jedi-unwrap-tag 'user-error))))

(ert-deftest jsx-jedi-test-unwrap-formatting-newlines-preserve-return-expression ()
  (jsx-jedi-test--with-buffer "function f() { return <di|v>\n  <A />\n</div>; }"
    (jsx-jedi-unwrap-tag)
    (should (equal (jsx-jedi-test--text) "function f() { return <A />; }"))
    (jsx-jedi-test--assert-valid)))

(ert-deftest jsx-jedi-test-copy-and-mark-optional-declaration-ranges ()
  (let ((jsx-jedi-copy-node-types
         (append jsx-jedi-copy-node-types '("variable_declaration" "enum_declaration")))
        (jsx-jedi-mark-node-types
         (append jsx-jedi-mark-node-types '("variable_declaration" "enum_declaration"))))
    (dolist (case '(("va|r count = 1;" "var count = 1;")
                    ("function f() { va|r count = 1; return count; }" "var count = 1;")
                    ("for (va|r i = 0; i < 3; i++) work();" "var i = 0;")
                    ("export en|um Status { Ready, Done }" "enum Status { Ready, Done }")))
      (jsx-jedi-test--with-buffer (car case)
        (let ((before (jsx-jedi-test--text)) (position (point)))
          (jsx-jedi-copy)
          (should (= (point) position))
          (should (equal (car kill-ring) (cadr case)))
          (dotimes (_ 2)
            (jsx-jedi-mark)
            (should mark-active)
            (should (equal (buffer-substring-no-properties (point) (mark))
                           (cadr case))))
          (should (equal (jsx-jedi-test--text) before))
          (should-not (buffer-modified-p)))))))

(ert-deftest jsx-jedi-test-empty-optional-object-type-range ()
  (let ((jsx-jedi-empty-node-types (cons "object_type" jsx-jedi-empty-node-types)))
    (dolist (case '(("type T = {| a: number; b: boolean };" "type T = {};"
                     " a: number; b: boolean ")
                    ("type T = { nested: |{a: number}; keep: boolean };"
                     "type T = { nested: {}; keep: boolean };" "a: number")
                    ("type T = { keep: boolean } & {| a: number };"
                     "type T = { keep: boolean } & {};" " a: number ")))
      (jsx-jedi-test--with-buffer (car case)
        (jsx-jedi-empty)
        (should (equal (jsx-jedi-test--text) (nth 1 case)))
        (should (equal (car kill-ring) (nth 2 case)))
        (should (eq (char-before) ?{))
        (should (eq (char-after) ?}))
        (jsx-jedi-test--assert-valid)))))

(ert-deftest jsx-jedi-test-substitute-optional-object-type-range ()
  (let ((jsx-jedi-empty-node-types (cons "object_type" jsx-jedi-empty-node-types)))
    (jsx-jedi-test--with-buffer "type T = |{a: number};\nconst keep = 1;"
      (setq kill-ring '("b: boolean"))
      (jsx-jedi-substitute)
      (should (equal (jsx-jedi-test--text) "type T = {b: boolean};\nconst keep = 1;"))
      (should (equal (car kill-ring) "a: number"))
      (should (eq (char-after) ?}))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-optional-object-type-keeps-inner-property-selection ()
  (let ((jsx-jedi-empty-node-types (cons "object_type" jsx-jedi-empty-node-types)))
    (jsx-jedi-test--with-buffer "type T = { va|lue: number; keep: boolean };"
      (setq kill-ring '("boolean"))
      (jsx-jedi-substitute)
      (should (equal (jsx-jedi-test--text)
                     "type T = { value: boolean; keep: boolean };"))
      (should (equal (car kill-ring) "number"))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-empty-optional-throw-value ()
  (let ((jsx-jedi-empty-node-types (cons "throw_statement" jsx-jedi-empty-node-types)))
    (dolist (case '(("function f() { thr|ow original; after(); }"
                     "function f() { throw ; after(); }" "original" "; after(); }")
                    ("function f() { thr|ow /* why */ /* detail */ error(code) /* keep */; after(); }"
                     "function f() { throw /* why */ /* detail */  /* keep */; after(); }"
                     "error(code)" " /* keep */; after(); }")))
      (jsx-jedi-test--with-buffer (car case)
        (jsx-jedi-empty)
        ;; Emptying an operand intentionally leaves an incomplete throw to edit.
        (should (equal (jsx-jedi-test--text) (nth 1 case)))
        (should (equal (car kill-ring) (nth 2 case)))
        (should (looking-at-p (regexp-quote (nth 3 case))))))))

(ert-deftest jsx-jedi-test-substitute-optional-throw-value ()
  (let ((jsx-jedi-empty-node-types (cons "throw_statement" jsx-jedi-empty-node-types)))
    (jsx-jedi-test--with-buffer "function f() { thr|ow /* why */ original /* keep */; after(); }"
      (setq kill-ring '("replacement"))
      (jsx-jedi-substitute)
      (should (equal (jsx-jedi-test--text)
                     "function f() { throw /* why */ replacement /* keep */; after(); }"))
      (should (equal (car kill-ring) "original"))
      (should (looking-at-p " /\\* keep \\*/; after(); }"))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-return-value-preserves-leading-comments ()
  (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
    (jsx-jedi-test--with-buffer "function f() { ret|urn /* why */ /* detail */ original; }"
      (setq kill-ring '("replacement"))
      (funcall command)
      (should (equal (jsx-jedi-test--text)
                     (format "function f() { return /* why */ /* detail */ %s; }"
                             (if (eq command 'jsx-jedi-empty) "" "replacement"))))
      (should (equal (car kill-ring) "original"))
      (should (eq (char-after) ?\;))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-bare-return-comment-has-no-value ()
  (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
    (jsx-jedi-test--with-buffer "function f() { ret|urn /* explanation */; }"
      (jsx-jedi-test--unchanged command 'user-error))))

(ert-deftest jsx-jedi-test-substitute-preserves-multiline-text ()
  (let ((jsx-jedi-empty-node-types (cons "throw_statement" jsx-jedi-empty-node-types)))
    (dolist (case
             '(("function f() { ret|urn original; }" "1 +\n2"
                "function f() { return 1 +\n2; }" "original")
               ("function f() { thr|ow original; }" "new Error(\n'message'\n)"
                "function f() { throw new Error(\n'message'\n); }" "original")
               ("const x = `or|iginal`;" "first\n  second"
                "const x = `first\n  second`;" "original")
               ("const x = <A|>original</A>;" "first\n  second"
                "const x = <A>first\n  second</A>;" "original")
               ("const x = {| a: 1 };" "text: `one\n   two\n zero`"
                "const x = {text: `one\n   two\n zero`};" " a: 1 ")
               ("const x = 'or|iginal';" "first\\\nsecond"
                "const x = 'first\\\nsecond';" "original")))
      (jsx-jedi-test--with-buffer (car case)
        (setq kill-ring (list (nth 1 case)))
        (jsx-jedi-substitute)
        (should (equal (jsx-jedi-test--text) (nth 2 case)))
        (should (equal (car kill-ring) (nth 3 case)))
        (jsx-jedi-test--assert-valid)))))

(ert-deftest jsx-jedi-test-duplicate-rejects-single-statement-contexts ()
  (dolist (source '("if (ok) wo|rk();"
                    "if (ok) wo|rk(); else other();"
                    "if (ok) other(); else wo|rk();"
                    "for (le|t i = 0; i < 3; i++) work();"
                    "for (const x of xs) wo|rk(x);"
                    "while (ok) wo|rk();"
                    "do wo|rk(); while (ok);"
                    "label: wo|rk();"
                    "with (obj) wo|rk();"))
    (jsx-jedi-test--with-buffer source
      (let ((transient-mark-mode t))
        (set-mark (point-min))
        (setq mark-active t)
        (jsx-jedi-test--unchanged #'jsx-jedi-duplicate 'user-error)))))

(ert-deftest jsx-jedi-test-duplicate-keeps-statement-list-support ()
  (dolist (source '("wo|rk();"
                    "if (ok) { wo|rk(); }"
                    "while (ok) { wo|rk(); }"
                    "switch (x) { case 1: wo|rk(); break; }"
                    "switch (x) { default: wo|rk(); }"))
    (jsx-jedi-test--with-buffer source
      (jsx-jedi-duplicate)
      (should (= 2 (length (treesit-query-capture
                           (treesit-buffer-root-node 'tsx)
                           '((expression_statement) @statement) nil nil t))))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-duplicate-preserves-automatic-semicolon-boundaries ()
  (dolist (case '(("(|value)" "(value);\n(value)")
                  ("[|1].forEach(work)" "[1].forEach(work);\n[1].forEach(work)")
                  ("`he|llo`" "`hello`;\n`hello`")
                  ("/te|xt/.test(value)" "/text/.test(value);\n/text/.test(value)")
                  ("+va|lue" "+value;\n+value")
                  ("-va|lue" "-value;\n-value")
                  ("(|value);" "(value);\n(value);")
                  ("wo|rk()" "work()\nwork()")
                  ("!va|lue" "!value\n!value")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-duplicate)
      (should (equal (jsx-jedi-test--text) (cadr case)))
      (should (= 2 (length (treesit-query-capture
                           (treesit-buffer-root-node 'tsx)
                           '((expression_statement) @statement) nil nil t))))
      (should (equal kill-ring '("previous kill")))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-kill-separators-preserves-intervening-comments ()
  (dolist (case
           '(("const x = { a|: 1 /* note */, b: 2 };"
              "const x = {  /* note */ b: 2 };" "a: 1")
             ("const x = { a|: 1 /* one */ /* two */, /* three */ b: 2 };"
              "const x = {  /* one */ /* two */ /* three */ b: 2 };" "a: 1")
             ("function f(a|: number /* note */, b: number) {}"
              "function f( /* note */ b: number) {}" "a: number")
             ("const x = [{| a: 1 } /* note */, 2];"
              "const x = [ /* note */ 2];" "{ a: 1 }")
             ("f({| a: 1 } /* note */, 2);"
              "f( /* note */ 2);" "{ a: 1 }")
             ("f(1, /* note */ {| a: 1 });"
              "f(1 /* note */ );" "{ a: 1 }")
             ("const x = { a: 1, /* note */ b|: 2 };"
              "const x = { a: 1 /* note */  };" "b: 2")
             ("const x = { a|: 1 // note\n, b: 2 };"
              "const x = {  // note\n b: 2 };" "a: 1")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-kill)
      (should (equal (jsx-jedi-test--text) (nth 1 case)))
      (should (equal (car kill-ring) (nth 2 case)))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-selection-climbs-through-equal-span-ancestors ()
  (dolist (text '("42" "'literal'"))
    (jsx-jedi-test--with-buffer (concat "function f() {\n | " text "\n}")
      (let ((before (jsx-jedi-test--text)) (position (point)))
        (should (equal (car (jsx-jedi--find-node-info jsx-jedi-mark-node-types))
                       "statement_block"))
        (jsx-jedi-mark)
        (should (equal (buffer-substring-no-properties (point) (mark))
                       (concat "{\n  " text "\n}")))
        (goto-char position)
        (jsx-jedi-copy)
        (should (equal (car kill-ring) before))
        (should (equal (jsx-jedi-test--text) before))))))

(ert-deftest jsx-jedi-test-kill-separated-comma-rolls-back-on-read-only-node ()
  (dolist (source '("f({| a: 1 } /* note */, 2);"
                    "f(1, /* note */ {| a: 1 });"))
    (jsx-jedi-test--with-buffer source
      (let* ((before (jsx-jedi-test--text))
             (position (point))
             (info (jsx-jedi--find-node-info jsx-jedi-kill-node-types)))
        (put-text-property (nth 1 info) (nth 2 info) 'read-only t)
        (should-error (jsx-jedi-kill) :type 'text-read-only)
        (should (equal (jsx-jedi-test--text) before))
        (should (= (point) position))))))


(ert-deftest jsx-jedi-test-entry-tail-entity-boundaries ()
  (dolist (value '("1" "{ inner: 1 }" "f(1)" "\"text\""))
    (dolist (tail '("|" "| " " |" " \t|\r\n "))
      (dolist (ending '(", b: 2 };" "};" ",};"))
        (dolist (command '(jsx-jedi-copy jsx-jedi-mark jsx-jedi-kill
                           jsx-jedi-duplicate jsx-jedi-comment-uncomment))
          (let* ((source (concat "const x = { a: " value tail ending))
                 (plain (string-replace "|" "" source))
                 expected)
            (jsx-jedi-test--with-buffer (string-replace "a:" "|a:" plain)
              (funcall command)
              (setq expected (list (jsx-jedi-test--text) kill-ring
                                   (and (eq command 'jsx-jedi-mark)
                                        (buffer-substring (region-beginning) (region-end))))))
            (jsx-jedi-test--with-buffer source
              (funcall command)
              (should (equal (list (jsx-jedi-test--text) kill-ring
                                   (and (eq command 'jsx-jedi-mark)
                                        (buffer-substring (region-beginning) (region-end))))
                             expected))
              (jsx-jedi-test--assert-valid))))))))

(ert-deftest jsx-jedi-test-entry-tail-content-boundaries ()
  (dolist (value '("1" "{ inner: 1 }" "f(1)" "\"text\""))
    (dolist (tail '("|" "| " " |" " \t|\r\n "))
      (dolist (ending '(", b: 2 };" "};" ",};"))
        (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
          (jsx-jedi-test--with-buffer (concat "const x = { a: " value tail ending)
            (setq kill-ring '("3"))
            (funcall command)
            (should (equal (car kill-ring) value))
            (should (equal (jsx-jedi-test--text)
                           (concat "const x = { a: "
                                   (if (eq command 'jsx-jedi-substitute) "3" "")
                                   (string-replace "|" "" tail) ending)))
            (when (eq command 'jsx-jedi-substitute)
              (jsx-jedi-test--assert-valid))))))))

(ert-deftest jsx-jedi-test-entry-tail-other-supported-entries ()
  (dolist (case '(("function f(a = 1 |, b = 2) {}" "required_parameter" "a = 1")
                  ("function f(a = f(1) |) {}" "required_parameter" "a = f(1)")
                  ("function f(a?: number |) {}" "optional_parameter" "a?: number")
                  ("type T = { a: number |; b: string };" "property_signature" "a: number")
                  ("interface T { a: number |, b: string }" "property_signature" "a: number")
                  ("type T = { a: number | };" "property_signature" "a: number")
                  ("const xs = [{ a: 1 } |, { b: 2 }];" "object" "{ a: 1 }")
                  ("f({ a: 1 } |);" "object" "{ a: 1 }")))
    (jsx-jedi-test--with-buffer (car case)
      (let ((jsx-jedi-copy-node-types (list (nth 1 case))))
        (jsx-jedi-copy)
        (should (equal (car kill-ring) (nth 2 case)))))))

(ert-deftest jsx-jedi-test-entry-tail-keeps-container-and-comment-boundaries ()
  (dolist (case '(("const x = { a: 1,| b: 2 };" " a: 1, b: 2 ")
                  ("const x = { a: 1, |};" " a: 1, ")
                  ("const x = { a: 1 /* keep */ |, b: 2 };" " a: 1 /* keep */ , b: 2 ")
                  ("const x = { a: f(1 |), b: 2 };" "1 ")
                  ("const x = { a: \"text |\", b: 2 };" "text ")
                  ("function f(a = 1 |, b = 2) {}" "a = 1 , b = 2")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-empty)
      (should (equal (car kill-ring) (cadr case)))))
  (jsx-jedi-test--with-buffer "const x = { a: 1 /* ke|ep */, b: 2 };"
    (jsx-jedi-test--unchanged #'jsx-jedi-empty 'user-error))
  (jsx-jedi-test--with-buffer "const x = { a: 1 |, b: 2 };"
    (let ((jsx-jedi-copy-node-types '("object")))
      (jsx-jedi-copy)
      (should (equal (car kill-ring) "{ a: 1 , b: 2 }"))))
  (jsx-jedi-test--with-buffer "const x = { a: 1 |, b: 2 };"
    (let ((jsx-jedi-empty-node-types '("object")))
      (jsx-jedi-empty)
      (should (equal (car kill-ring) " a: 1 , b: 2 ")))))

(ert-deftest jsx-jedi-test-entry-tail-content-for-types-and-list-objects ()
  (dolist (case '(("type T = { a: number |; b: string };" "number")
                  ("interface T { a: number |, b: string }" "number")
                  ("const xs = [{ a: 1 } |, { b: 2 }];" " a: 1 ")
                  ("f({ a: 1 } |);" " a: 1 ")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-empty)
      (should (equal (car kill-ring) (cadr case))))))

(ert-deftest jsx-jedi-test-entry-tail-keeps-undo ()
  (dolist (command '(jsx-jedi-kill jsx-jedi-duplicate jsx-jedi-comment-uncomment
                     jsx-jedi-empty jsx-jedi-substitute))
    (jsx-jedi-test--with-buffer "const x = { a: { inner: 1 } \t|\n, b: 2 };"
      (insert " ")
      (setq buffer-undo-list nil)
      (let ((original (jsx-jedi-test--text)))
        (funcall command)
        (undo-boundary)
        (undo 1)
        (should (equal (jsx-jedi-test--text) original))))))

(ert-deftest jsx-jedi-test-entry-tail-comment-includes-separated-comma ()
  (dolist (case '(("const x = { a: 1 |, b: 2 };"
                   "const x = { // a: 1 ,\n  b: 2 };")
                  ("const x = { a|: 1 , b: 2 };"
                   "const x = { // a: 1 ,\n  b: 2 };")
                  ("const x = {\n  a: 1 |,\n  b: 2\n};"
                   "const x = {\n  // a: 1 ,\n  b: 2\n};")))
    (jsx-jedi-test--with-buffer (car case)
      (jsx-jedi-comment-uncomment)
      (should (equal (jsx-jedi-test--text) (cadr case)))
      (should (equal (jsx-jedi-test--pair-texts) '("b: 2")))
      (jsx-jedi-test--assert-valid))))

(ert-deftest jsx-jedi-test-empty-unclosed-interface-preserves-following-code ()
  (dolist (source '("interface |I {\n a: number;\nconst keep = 1;"
                    "interface I { | a: number;"))
    (dolist (command '(jsx-jedi-empty jsx-jedi-substitute))
      (jsx-jedi-test--with-buffer source
        (jsx-jedi-test--unchanged command 'user-error)))))

(ert-deftest jsx-jedi-test-comment-pair-includes-comma-after-comments ()
  (jsx-jedi-test--with-buffer "const x = { a|: 1 /* keep */, b: 2 };"
    (jsx-jedi-comment-uncomment)
    (should (equal (jsx-jedi-test--text)
                   "const x = { // a: 1 /* keep */,\n  b: 2 };"))
    (should (equal (jsx-jedi-test--pair-texts) '("b: 2")))
    (jsx-jedi-test--assert-valid)
    (undo-boundary)
    (undo 1)
    (should (equal (jsx-jedi-test--text) "const x = { a: 1 /* keep */, b: 2 };"))))

(provide 'jsx-jedi-test)
;;; jsx-jedi-test.el ends here
