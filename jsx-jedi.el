;;; jsx-jedi.el --- Structural JS/TS/JSX editing  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Version: 0.1.0
;; Created: 20 May 2024
;; Keywords: languages convenience tools tree-sitter javascript typescript jsx react
;; URL: https://github.com/p233/jsx-jedi
;; Compatibility: emacs-version >= 29.1
;; Package-Requires: ((emacs "29.1") (avy "0.5"))

;;; This file is NOT part of GNU Emacs

;;; License

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Structural editing commands for `js-ts-mode', `typescript-ts-mode' and
;; `tsx-ts-mode'.  Use `tsx-ts-mode' for both JSX and TSX files.  Emacs must
;; have built-in tree-sitter support and the grammars for the active mode.
;; Avy provides word navigation within the selected syntax range.
;;
;; Loading this package enables `jsx-jedi-mode' on the three major-mode
;; hooks.  Its keymap is empty; bind commands in `jsx-jedi-mode-map' or call
;; them with M-x.  Enable the minor mode manually in already-open buffers.
;;
;; Each command selects the closest node in its node-type option.  Use
;; M-x customize-group RET jsx-jedi RET to configure these independent lists.
;;
;; Installation, command reference and development instructions:
;; https://github.com/p233/jsx-jedi#readme

;;; Code:

(require 'avy)
(require 'pulse)
(require 'subr-x)
(require 'treesit)

;;; Variables

(defgroup jsx-jedi nil
  "Structural JavaScript, TypeScript and JSX editing.
Node-type options select the closest matching node at point; their
list order does not set priority.  Adding a type does not implement
syntax or separator handling for that type."
  :group 'languages
  :prefix "jsx-jedi-")

(defcustom jsx-jedi-tag-node-types       '("jsx_element"
                                        "jsx_self_closing_element")
  "JSX node types selected by tag commands.
Only the two built-in element shapes are supported.  Fragments share
jsx_element with named tags; this option cannot distinguish them.
Other command defaults read this list at initialization or explicit
Customize reset.  Changing this option does not synchronize them."
  :type '(set (const :tag "Paired elements and fragments" "jsx_element")
              (const :tag "Self-closing elements" "jsx_self_closing_element"))
  :group 'jsx-jedi)

(defcustom jsx-jedi-kill-node-types      (append jsx-jedi-tag-node-types
                                              '("comment"
                                                "class_declaration"
                                                "export_statement"
                                                "expression_statement"
                                                "function_declaration"
                                                "if_statement"
                                                "import_statement"
                                                "interface_declaration"
                                                "jsx_attribute"
                                                "jsx_expression"
                                                "lexical_declaration"
                                                "object"
                                                "pair"
                                                "required_parameter"
                                                "return_statement"
                                                "throw_statement"
                                                "type_alias_declaration"))
  "Node types selected for killing.
Adjacent commas are handled only for objects, object properties and
required parameters."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-empty-node-types     (append jsx-jedi-tag-node-types
                                              '("arguments"
                                                "array"
                                                "array_pattern"
                                                "assignment_expression"
                                                "call_expression"
                                                "export_clause"
                                                "formal_parameters"
                                                "interface_declaration"
                                                "jsx_attribute"
                                                "jsx_expression"
                                                "lexical_declaration"
                                                "named_imports"
                                                "object"
                                                "object_pattern"
                                                "pair"
                                                "parenthesized_expression"
                                                "property_signature"
                                                "return_statement"
                                                "statement_block"
                                                "string"
                                                "tuple_type"
                                                "type_alias_declaration"
                                                "type_parameters"
                                                "variable_declaration"
                                                "template_string"))
  "Node types selected by `jsx-jedi-empty' and `jsx-jedi-substitute'.
Only nodes with supported content bounds can be changed.  Optional
object_type selects type members inside braces; throw_statement selects
the thrown expression.  Neither is enabled by default.  Closer matches,
such as property_signature, still take precedence.  Boolean attributes and
self-closing elements remain selection stops despite having no content.
The search stops at the statement or comment containing point."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-zap-node-types       (append jsx-jedi-tag-node-types
                                              '("arguments"
                                                "array"
                                                "array_pattern"
                                                "formal_parameters"
                                                "jsx_expression"
                                                "jsx_opening_element"
                                                "named_imports"
                                                "object_pattern"
                                                "string"
                                                "template_string"))
  "Node types selected for deleting to the end of content.
Only supported content ranges can be changed.  Adding a container type
can make `jsx-jedi-zap' delete following members in that container."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-copy-node-types      (append jsx-jedi-tag-node-types
                                              '("comment"
                                                "class_declaration"
                                                "export_statement"
                                                "expression_statement"
                                                "function_declaration"
                                                "if_statement"
                                                "import_statement"
                                                "interface_declaration"
                                                "jsx_attribute"
                                                "jsx_expression"
                                                "lexical_declaration"
                                                "object"
                                                "pair"
                                                "required_parameter"
                                                "return_statement"
                                                "string"
                                                "template_string"
                                                "throw_statement"
                                                "type_alias_declaration"))
  "Node types selected for copying.
Any grammar node may be selected; comments use the whole comment block.
Add variable_declaration or enum_declaration to select those declarations
directly."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-duplicate-node-types (append jsx-jedi-tag-node-types
                                              '("comment"
                                                "class_declaration"
                                                "export_statement"
                                                "expression_statement"
                                                "function_declaration"
                                                "if_statement"
                                                "import_statement"
                                                "interface_declaration"
                                                "jsx_attribute"
                                                "jsx_expression"
                                                "lexical_declaration"
                                                "object"
                                                "pair"
                                                "return_statement"
                                                "throw_statement"
                                                "type_alias_declaration"))
  "Node types selected for duplication.
Selection does not add support for new syntax or insertion contexts."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-mark-node-types      (append jsx-jedi-tag-node-types
                                              '("comment"
                                                "class_declaration"
                                                "export_statement"
                                                "expression_statement"
                                                "function_declaration"
                                                "if_statement"
                                                "import_statement"
                                                "interface_declaration"
                                                "jsx_attribute"
                                                "jsx_expression"
                                                "lexical_declaration"
                                                "object"
                                                "pair"
                                                "required_parameter"
                                                "return_statement"
                                                "statement_block"
                                                "throw_statement"
                                                "type_alias_declaration"))
  "Node types selected for marking.
Any grammar node may be selected; comments use the whole comment block.
Add variable_declaration or enum_declaration to select those declarations.
Repeating `jsx-jedi-mark' does not expand the selection to a parent."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-comment-node-types   (append jsx-jedi-tag-node-types
                                              '("class_declaration"
                                                "export_statement"
                                                "expression_statement"
                                                "function_declaration"
                                                "if_statement"
                                                "import_statement"
                                                "interface_declaration"
                                                "lexical_declaration"
                                                "pair"
                                                "return_statement"
                                                "throw_statement"
                                                "type_alias_declaration"))
  "Node types selected when commenting code.
Do not include comment.  This does not change uncomment detection or
the syntax rules for JSX comments."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-avy-node-types       (append jsx-jedi-tag-node-types
                                              '("class_declaration"
                                                "export_statement"
                                                "expression_statement"
                                                "function_declaration"
                                                "if_statement"
                                                "import_statement"
                                                "interface_declaration"
                                                "jsx_attribute"
                                                "jsx_expression"
                                                "lexical_declaration"
                                                "object"
                                                "pair"
                                                "return_statement"
                                                "statement_block"
                                                "string"
                                                "template_string"
                                                "throw_statement"
                                                "type_alias_declaration"))
  "Node types defining the scope of Avy word navigation.
Any grammar node may provide a navigation scope.  Adding a smaller target
limits word candidates to that node instead of its enclosing scope."
  :type '(repeat string)
  :group 'jsx-jedi)

(defcustom jsx-jedi-hoist-node-types     (append jsx-jedi-tag-node-types
                                              '("jsx_expression"))
  "Node types selected for hoisting.
Selection does not redefine JSX element shapes or valid destination syntax."
  :type '(repeat string)
  :group 'jsx-jedi)


;;; Helpers

(defun jsx-jedi--kill-region-and-goto-start (start end)
  "Kill region from START to END and move point to START."
  (kill-region start end)
  (goto-char start))


(defun jsx-jedi--standalone-line-comment-p (node)
  "Return non-nil when NODE is a // comment alone on its line."
  (save-excursion
    (goto-char (treesit-node-start node))
    (and (looking-at-p "//")
         (progn (skip-chars-backward " \t") (bolp))
         (progn (goto-char (treesit-node-end node))
                (skip-chars-forward " \t\r")
                (eolp)))))

(defun jsx-jedi--adjacent-line-comment (node direction)
  "Return the comment joining NODE's block in DIRECTION, or nil.
DIRECTION is negative for the previous line and positive for the next."
  (let* ((before (< direction 0))
         (sibling (if before
                      (treesit-node-prev-sibling node)
                    (treesit-node-next-sibling node))))
    (and (equal (treesit-node-type sibling) "comment")
         (jsx-jedi--standalone-line-comment-p sibling)
         ;; Exactly one line break: a blank line ends the block.
         (string-match-p "\\`[ \t\r]*\n[ \t]*\\'"
                         (buffer-substring-no-properties
                          (treesit-node-end (if before sibling node))
                          (treesit-node-start (if before node sibling))))
         sibling)))

(defun jsx-jedi--find-comment-block-bounds (node)
  "Return (START . END) of the comment block containing NODE.
A block is a run of // comments on consecutive lines, each alone on its
line.  Block comments, trailing comments and runs separated by a blank
line stand alone."
  (let ((first node)
        (last node)
        next)
    (when (jsx-jedi--standalone-line-comment-p node)
      (while (setq next (jsx-jedi--adjacent-line-comment first -1))
        (setq first next))
      (while (setq next (jsx-jedi--adjacent-line-comment last 1))
        (setq last next)))
    (cons (treesit-node-start first) (treesit-node-end last))))


(defun jsx-jedi--find-node-at-point (node position)
  "Find first ancestor of NODE (inclusive) containing POSITION."
  (when node
    (let ((start (treesit-node-start node))
          (end (treesit-node-end node)))
      (if (and (<= start position) (<= position end))
          node
        (jsx-jedi--find-node-at-point (treesit-node-parent node) position)))))


(defun jsx-jedi--entry-at-point ()
  "Return the entry whose tail before a direct delimiter contains point.
Support object pairs, parameters, type properties and objects in lists.
Only whitespace may follow the entry, up to its comma, semicolon or closing
bracket.  Never cross a comment, a passed separator or a nested delimiter."
  (let* ((end (save-excursion (skip-chars-backward " \t\r\n\f") (point)))
         (node (and (> end (point-min)) (treesit-node-at (1- end))))
         entry)
    (while (and node (not entry) (<= (treesit-node-end node) end))
      (when (and (= (treesit-node-end node) end)
                 (pcase (treesit-node-type (treesit-node-parent node))
                   ("object" (equal (treesit-node-type node) "pair"))
                   ("formal_parameters"
                    (member (treesit-node-type node) '("required_parameter" "optional_parameter")))
                   ((or "object_type" "interface_body")
                    (equal (treesit-node-type node) "property_signature"))
                   ((or "array" "arguments") (equal (treesit-node-type node) "object"))))
        (when-let* ((next (treesit-node-next-sibling node))
                    ((member (treesit-node-type next) '("," ";" ")" "]" "}")))
                    ((not (treesit-node-check next 'missing)))
                    ((<= (point) (treesit-node-start next))))
          (setq entry node)))
      (setq node (treesit-node-parent node)))
    entry))

(defun jsx-jedi--find-node-info (valid-types)
  "Find the closest node at point whose type is in VALID-TYPES.
Search the node and its ancestors.
Return (TYPE START END NODE), or nil if no node matches.  For comments,
START and END span the block from `jsx-jedi--find-comment-block-bounds',
while NODE remains the individual comment at point.  Otherwise NODE is
the selected ancestor."
  (let ((node (treesit-node-at (point))))
    (if (and (string= (treesit-node-type node) "comment")
             (member "comment" valid-types))
        (let ((bounds (jsx-jedi--find-comment-block-bounds node)))
          (list "comment" (car bounds) (cdr bounds) node))
      (when-let* ((node-at-point (or (jsx-jedi--entry-at-point)
                                   (jsx-jedi--find-node-at-point node (point))))
                  (found-node (treesit-parent-until node-at-point (lambda (n)
                                                                    (member (treesit-node-type n) valid-types)) t)))
        (list (treesit-node-type found-node)
              (treesit-node-start found-node)
              (treesit-node-end found-node)
              found-node)))))

(defun jsx-jedi--statement-boundary-p (node)
  "Return non-nil when NODE is a statement, declaration or comment."
  (let ((type (treesit-node-type node)))
    (and (treesit-node-check node 'named)
         (or (member type '("comment" "function_signature" "import_alias" "module"))
             (string-match-p "_\\(?:statement\\|declaration\\)\\'" type)))))

(defun jsx-jedi--header-body-bounds (node)
  "Return the brace interior of NODE's block when point precedes the block.
NODE is a statement, declaration, method or clause; expressions such as
arrow functions keep their own content ranges."
  (if-let* (((string= (treesit-node-type node) "export_statement"))
            (declaration (treesit-node-child-by-field-name node "declaration")))
      (jsx-jedi--header-body-bounds declaration)
    (when-let* (((or (jsx-jedi--statement-boundary-p node)
                     (member (treesit-node-type node)
                             '("method_definition" "internal_module"
                               "else_clause" "catch_clause" "finally_clause"))))
                (body (or (treesit-node-child-by-field-name node "body")
                          (treesit-node-child-by-field-name node "consequence")
                          (and (string= (treesit-node-type node) "else_clause")
                               (treesit-node-child node 0 t))))
                ((< (point) (treesit-node-start body)))
                (opening (treesit-node-child body 0))
                (closing (treesit-node-child body -1))
                ((and (string= (treesit-node-type opening) "{")
                      (string= (treesit-node-type closing) "}")
                      (not (treesit-node-check closing 'missing)))))
      (cons (treesit-node-end opening) (treesit-node-start closing)))))

(defun jsx-jedi--content-at-point (message)
  "Return the content bounds selected by `jsx-jedi-empty-node-types'.
Search from point no further than the statement or comment containing it,
so a nested statement never selects its enclosing block.  A statement's
header selects its own block.  Signal `user-error' with MESSAGE when no
selected node has editable content."
  (let ((node (or (jsx-jedi--entry-at-point)
                  (jsx-jedi--find-node-at-point (treesit-node-at (point)) (point))))
        header-bounds)
    ;; Keyword leaves such as a type's `string' are anonymous namesakes.
    (while (and node
                (not (and (treesit-node-check node 'named)
                          (member (treesit-node-type node) jsx-jedi-empty-node-types)))
                (not (setq header-bounds (jsx-jedi--header-body-bounds node)))
                (not (jsx-jedi--statement-boundary-p node)))
      (setq node (treesit-node-parent node)))
    (or header-bounds
        (and node
             (member (treesit-node-type node) jsx-jedi-empty-node-types)
             (jsx-jedi--content-bounds (treesit-node-type node) node))
        (user-error "%s" message))))

(defun jsx-jedi--jsx-child-p (node)
  "Return non-nil when NODE is in a JSX children position."
  (string= (treesit-node-type (treesit-node-parent node)) "jsx_element"))

(defun jsx-jedi--jsx-element-p (node)
  "Return non-nil for the supported JSX element shapes of NODE.
Selection preferences must not redefine these grammar facts."
  (member (treesit-node-type node) '("jsx_element" "jsx_self_closing_element")))

(defun jsx-jedi--find-tag-info ()
  "Select a JSX element using `jsx-jedi-tag-node-types'.
Return node info or nil as in `jsx-jedi--find-node-info'.  Signal
`user-error' if a custom type selects a non-element.  Fragments count as
elements; commands needing a name must also use `jsx-jedi--tag-name-node'."
  (when-let* ((info (jsx-jedi--find-node-info jsx-jedi-tag-node-types)))
    (unless (jsx-jedi--jsx-element-p (nth 3 info))
      (user-error "This operation requires a JSX element"))
    info))

(defun jsx-jedi--tag-name-node (node)
  "Return the name node for JSX NODE, rejecting unnamed fragments."
  (or (treesit-node-child-by-field-name
       (if (string= (treesit-node-type node) "jsx_element")
           (treesit-node-child-by-field-name node "open_tag")
         node)
       "name")
      (user-error "This operation requires a named JSX tag")))

(defun jsx-jedi--first-non-comment-child (node)
  "Return the first named child of NODE that is not a comment, or nil.
Comments are named children and can precede operands and declarators."
  (let ((child (treesit-node-child node 0 t)))
    (while (equal (treesit-node-type child) "comment")
      (setq child (treesit-node-next-sibling child t)))
    child))

(defun jsx-jedi--content-bounds (type node)
  "Return editable (START . END) for NODE of TYPE, excluding delimiters.
Containers select their interior; other supported nodes select a value
or operand.  Variable declarations use only the first declarator.
Return and throw operands exclude adjacent comments.
Return nil for unsupported types or absent content, including boolean
attributes and self-closing elements.  Equal bounds mean an editable
empty range, allowing `jsx-jedi-substitute' to insert there."
  (let ((bounds
         (pcase type
           ("jsx_attribute"
            (let ((value-node (treesit-node-child node -1)))
              (when (member (treesit-node-type value-node)
                            '("string" "jsx_expression"))
                (jsx-jedi--content-bounds
                 (treesit-node-type value-node) value-node))))
           ("jsx_element"
            (when-let* ((opening (treesit-node-child-by-field-name node "open_tag"))
                        (closing (treesit-node-child-by-field-name node "close_tag")))
              (cons (treesit-node-end opening) (treesit-node-start closing))))
           ("interface_declaration"
            (when-let* ((body (treesit-node-child-by-field-name node "body")))
              (jsx-jedi--content-bounds (treesit-node-type body) body)))
           ("property_signature"
            (when-let* ((annotation (treesit-node-child-by-field-name node "type"))
                        (value (treesit-node-child annotation -1)))
              (cons (treesit-node-start value) (treesit-node-end value))))
           ((or "pair" "type_alias_declaration" "assignment_expression")
            (when-let* ((value (treesit-node-child-by-field-name
                               node (if (string= type "assignment_expression")
                                        "right" "value"))))
              (cons (treesit-node-start value) (treesit-node-end value))))
           ("call_expression"
            (when-let* ((args (treesit-node-child-by-field-name node "arguments")))
              (jsx-jedi--content-bounds "arguments" args)))
           ((or "lexical_declaration" "variable_declaration")
            (when-let* ((declarator (jsx-jedi--first-non-comment-child node))
                        (value (treesit-node-child-by-field-name declarator "value")))
              (cons (treesit-node-start value) (treesit-node-end value))))
           ((or "return_statement" "throw_statement")
            (when-let* ((value (jsx-jedi--first-non-comment-child node)))
              (cons (treesit-node-start value) (treesit-node-end value))))
           ((or "arguments" "array" "array_pattern" "export_clause"
                "formal_parameters" "jsx_expression" "named_imports"
                "object" "object_pattern" "object_type" "interface_body" "parenthesized_expression"
                "statement_block" "string" "tuple_type" "type_parameters"
                "template_string")
            (when-let* ((opening (treesit-node-child node 0))
                        (closing (treesit-node-child node -1))
                        ;; An unclosed container would extend to the end of the buffer.
                        ((not (or (treesit-node-check opening 'missing)
                                  (treesit-node-check closing 'missing)))))
              (cons (treesit-node-end opening) (treesit-node-start closing)))))))
    (when (and bounds (<= (car bounds) (cdr bounds)))
      bounds)))


;;; Commands

(defun jsx-jedi-kill ()
  "Kill the closest node selected by `jsx-jedi-kill-node-types'.
Consecutive standalone // comment lines are killed together.  For objects,
object properties and required parameters, include an adjacent comma when
present.  If comments separate the node from its comma, preserve those
comments and delete the comma separately without adding it to the kill ring."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-kill-node-types))
              (type (nth 0 node-info))
              (start (nth 1 node-info))
              (end (nth 2 node-info))
              (node (nth 3 node-info)))
    (let ((kill-start start)
          (kill-end end)
          separate-comma)
      (when (member type '("object" "pair" "required_parameter"))
        (let* ((next-node (treesit-node-next-sibling node))
               (prev-node (treesit-node-prev-sibling node))
               (next-comment-p (equal (treesit-node-type next-node) "comment"))
               (prev-comment-p (equal (treesit-node-type prev-node) "comment")))
          (while (equal (treesit-node-type next-node) "comment")
            (setq next-node (treesit-node-next-sibling next-node)))
          (while (equal (treesit-node-type prev-node) "comment")
            (setq prev-node (treesit-node-prev-sibling prev-node)))
          (cond
           ((and next-node (string= (treesit-node-text next-node t) ","))
            (if next-comment-p
                (setq separate-comma next-node)
              (setq kill-end (save-excursion
                               (goto-char (treesit-node-end next-node))
                               (skip-chars-forward " \t")
                               (point)))))
           ((and prev-node (string= (treesit-node-text prev-node t) ","))
            (if prev-comment-p
                (setq separate-comma prev-node)
              (setq kill-start (save-excursion
                                 (goto-char (treesit-node-start prev-node))
                                 (skip-chars-backward " \t")
                                 (point))))))))
      (atomic-change-group
        (when separate-comma
          (let ((comma-start (treesit-node-start separate-comma))
                (comma-end (treesit-node-end separate-comma)))
            (delete-region comma-start comma-end)
            (when (< comma-start kill-start)
              (setq kill-start (- kill-start (- comma-end comma-start))
                    kill-end (- kill-end (- comma-end comma-start))))))
        (kill-region kill-start kill-end)
        (when (save-excursion
                (beginning-of-line)
                (looking-at-p "^[[:space:]]*$"))
          (delete-blank-lines)
          (indent-for-tab-command))))))


(defun jsx-jedi-empty ()
  "Kill the selected node's content and leave point at its start.
Select using `jsx-jedi-empty-node-types' within the statement or comment
at point, retaining delimiters or the surrounding statement; on a block
statement's header, such as `function f()' or `if (x)', select its block.
Removing a required value can leave incomplete code for further editing.
Signal `user-error' when nothing there has editable content."
  (interactive)
  (let ((bounds (jsx-jedi--content-at-point "Nothing to empty here")))
    (jsx-jedi--kill-region-and-goto-start (car bounds) (cdr bounds))))

(defun jsx-jedi-substitute ()
  "Replace selected content with the current `kill-ring' entry.
Use the same ranges as `jsx-jedi-empty'.  Trim the replacement's outer
whitespace, preserving its internal line breaks and indentation.  Insert
without extra line breaks or reindentation, which could alter return/throw
operands or literal text.  Save the removed content to the kill ring and
group the replacement into one undo step.  Signal `user-error' when
nothing has editable content."
  (interactive)
  (let ((bounds (jsx-jedi--content-at-point "Nothing to substitute here"))
        (text (string-trim (current-kill 0))))
    (atomic-change-group
      (jsx-jedi--kill-region-and-goto-start (car bounds) (cdr bounds))
      (insert text))))


(defun jsx-jedi-zap ()
  "Delete from point to the selected content's end, without killing it.
Select using `jsx-jedi-zap-node-types'; leave the kill ring unchanged.
For selected JSX opening or self-closing tags, cover attributes after
the tag name.  Do nothing if point is outside the editable content."
  (interactive)
  (when-let* ((info (jsx-jedi--find-node-info jsx-jedi-zap-node-types)))
    (pcase-let* ((`(,type ,_start ,_end ,node) info)
                (bounds
                 (if (member type '("jsx_opening_element" "jsx_self_closing_element"))
                     (when-let* ((name (treesit-node-child-by-field-name node "name")))
                       (cons (treesit-node-end name)
                             (treesit-node-start (treesit-node-child node -1))))
                   (jsx-jedi--content-bounds type node))))
      (when (and bounds (<= (car bounds) (point)) (<= (point) (cdr bounds)))
        (delete-region (point) (cdr bounds))
        t))))


(defun jsx-jedi-copy ()
  "Copy and highlight the node selected by `jsx-jedi-copy-node-types'.
Copy to the kill ring without moving point or editing the buffer.
Consecutive standalone // comment lines are copied together."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-copy-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    (kill-ring-save start end)
    (pulse-momentary-highlight-region start end)))


(defun jsx-jedi-duplicate ()
  "Duplicate the range selected by `jsx-jedi-duplicate-node-types'.
Insert after the original without changing the kill ring.  Add commas
for object properties and for objects in arrays or argument lists.
JSX nodes require a JSX children position.  Reject statements in single
statement branches, loop bodies and loop headers.  Separate expressions
with a semicolon when a newline alone could join them.  Preserve body
indentation, leave point at the inserted range's end and highlight the copy."
  (interactive)
  (when-let* ((info (jsx-jedi--find-node-info jsx-jedi-duplicate-node-types)))
    (pcase-let* ((`(,type ,start ,end ,node) info)
                (parent-type (treesit-node-type (treesit-node-parent node)))
                (comma-p (or (string= type "pair")
                             (and (string= type "object")
                                  (member parent-type '("array" "arguments")))))
                (text (buffer-substring-no-properties start end))
                (semicolon-p
                 (and (string= type "expression_statement")
                      (memq (aref text 0) '(?\( ?\[ ?` ?/ ?+ ?- ?<))
                      (not (string-suffix-p ";" text)))))
      (when (or (and (member type '("jsx_element" "jsx_self_closing_element"
                                   "jsx_expression"))
                     (not (jsx-jedi--jsx-child-p node)))
                (and (string= type "object") (not comma-p)))
        (user-error "This expression cannot be duplicated in its current context"))
      (when (and (or (string-suffix-p "_statement" type)
                     (string-suffix-p "_declaration" type))
                 (member parent-type '("if_statement" "else_clause"
                                       "for_statement" "for_in_statement"
                                       "while_statement" "do_statement"
                                       "labeled_statement" "with_statement")))
        (user-error "This statement has no sibling position in its current context"))
      (atomic-change-group
        (goto-char end)
        (when comma-p (insert ","))
        (when semicolon-p (insert ";"))
        ;; `newline' would expand abbrevs and auto-fill the original statement.
        (insert "\n")
        (let ((insert-start (point)))
          (insert text)
          ;; Reindent only the sibling's first line: reindenting its body can
          ;; change literal whitespace in JSX and template strings.
          (save-excursion
            (goto-char insert-start)
            (indent-according-to-mode))
          (let ((highlight-start (save-excursion
                                   (goto-char insert-start)
                                   (skip-chars-forward " \t")
                                   (point))))
            (pulse-momentary-highlight-region highlight-start (point))))))))


(defun jsx-jedi-mark ()
  "Select the node chosen by `jsx-jedi-mark-node-types'.
Leave point at its start and the active mark at its end.  Consecutive
standalone // comment lines are marked together.  Repeating does not
expand to a parent."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-mark-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    (goto-char start)
    (set-mark end)
    (activate-mark)))


(defun jsx-jedi-comment-uncomment ()
  "Toggle a comment at point or comment the closest matching code node.
Use `jsx-jedi-comment-node-types' for code selection; existing comments
are detected independently.  Uncomment a JS/TS comment, or its block of
consecutive standalone // lines, or a standalone JSX block comment.  JSX
elements must be in a children position.  Reject mixed code/comment JSX
expressions and attempts to comment out JSX content containing a
block-comment terminator."
  (interactive)
  (let* ((node (treesit-node-at (point)))
         (comment-p (string= (treesit-node-type node) "comment"))
         (in-jsx-expression-p (string= (treesit-node-type (treesit-node-parent node)) "jsx_expression"))
         (js-comment-p (and comment-p
                            (not in-jsx-expression-p)))
         (jsx-comment-p (and in-jsx-expression-p
                             (or comment-p
                                 (string= (treesit-node-type (treesit-node-prev-sibling node)) "comment")
                                 (string= (treesit-node-type (treesit-node-next-sibling node)) "comment")))))
    (cond
     (js-comment-p
      (let* ((bounds (jsx-jedi--find-comment-block-bounds node))
             (start (car bounds))
             (end (cdr bounds)))
        (uncomment-region start end)))

     (jsx-comment-p
      (let* ((comment-node (treesit-node-parent node))
             (beg (treesit-node-start comment-node))
             (end (treesit-node-end comment-node))
             (comment (treesit-node-child comment-node 0 t))
             (text (treesit-node-text comment t)))
        (unless (and (= (treesit-node-child-count comment-node t) 1)
                     (string= (treesit-node-type comment) "comment")
                     (string-prefix-p "/*" text)
                     (string-suffix-p "*/" text)
                     (jsx-jedi--jsx-child-p comment-node))
          (user-error "This JSX expression is not a standalone block comment"))
        (atomic-change-group
          (delete-region beg end)
          (goto-char beg)
          (insert (string-trim (substring text 2 -2) "[ \t]*" "[ \t]*")))))

     (t
      (when-let* ((element (nth 3 (jsx-jedi--find-node-info jsx-jedi-comment-node-types)))
                  (start (treesit-node-start element))
                  (end (treesit-node-end element)))
        (if (jsx-jedi--jsx-element-p element)
            (let ((text (buffer-substring-no-properties start end)))
              (unless (jsx-jedi--jsx-child-p element)
                (user-error "JSX comments require a JSX children position"))
              (when (string-match-p "\\*/" text)
                (user-error "This element contains a block-comment terminator"))
              (atomic-change-group
                (delete-region start end)
                (goto-char start)
                (insert "{/* " text " */}")))
          (let ((next (treesit-node-next-sibling element)))
            (while (equal (treesit-node-type next) "comment")
              (setq next (treesit-node-next-sibling next)))
            (comment-region start
                            (if (equal (treesit-node-type next) ",")
                                (treesit-node-end next)
                              end)))))))))

(defun jsx-jedi-avy-word ()
  "Use Avy to jump to a word in the selected syntax range.
`jsx-jedi-avy-node-types' selects the scope; smaller matching nodes limit
which word destinations are available.  Search only the selected window,
independent of Avy's window settings or prefix arguments."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-avy-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    ;; These bounds belong to this buffer, not to other visible buffers.
    (let ((avy-all-windows nil)
          (avy-all-windows-alt nil))
      (avy-goto-word-0 nil start end))))


(defun jsx-jedi-hoist-tag ()
  "Replace the enclosing JSX element with the selected node's text.
Select using `jsx-jedi-hoist-node-types'.  A JSX expression can be promoted
within JSX children; replacing a JavaScript expression requires a JSX
element.  Preserve the selected text without reindenting it."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-hoist-node-types))
              (node (nth 3 node-info))
              (text (treesit-node-text node t))
              (parent (treesit-parent-until node (lambda (n)
                                                   (string= (treesit-node-type n) "jsx_element"))))
              (start (treesit-node-start parent))
              (end (treesit-node-end parent)))
    (unless (or (jsx-jedi--jsx-child-p parent)
                (jsx-jedi--jsx-element-p node))
      (user-error "Hoisting here requires a JSX element"))
    (atomic-change-group
      (delete-region start end)
      (goto-char start)
      (insert text))))


(defun jsx-jedi-rename-tag ()
  "Prompt for a new name for the JSX element at point.
Update opening and closing names together as one undo step.  Require a
named tag selected by `jsx-jedi-tag-node-types'; fragments are rejected."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (let* ((name-node (jsx-jedi--tag-name-node node))
           (current-tag-name (treesit-node-text name-node t))
           (start (treesit-node-start name-node))
           (end (treesit-node-end name-node))
           (closing-name
            (unless (string= type "jsx_self_closing_element")
              (or (treesit-node-child-by-field-name
                   (treesit-node-child-by-field-name node "close_tag") "name")
                  (user-error "This element has no closing tag name"))))
           (closing-start (and closing-name (treesit-node-start closing-name)))
           (closing-end (and closing-name (treesit-node-end closing-name)))
           (new-tag (read-string (format "Rename %s to: " current-tag-name) current-tag-name)))
      (atomic-change-group
        (when closing-name
          (save-excursion
            (delete-region closing-start closing-end)
            (goto-char closing-start)
            (insert new-tag)))
        (delete-region start end)
        (goto-char start)
        (insert new-tag)))))


(defun jsx-jedi-wrap-tag ()
  "Wrap the selected JSX element in a new parent tag.
Select using `jsx-jedi-tag-node-types'.  Prompt for a tag name with optional
attributes; use its first word as the closing name.  Preserve existing
literal content and indent only the new multiline boundaries."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (start (nth 1 node-info))
              (end (nth 2 node-info))
              (node (nth 3 node-info))
              (text (treesit-node-text node t))
              (tag-input (read-string "Enter wrapping tag name: "))
              (tag-name (car (split-string tag-input))))
    (let ((wrapped-text (if (string-match-p "\n" text)
                            (concat "<" tag-input ">\n" text "\n</" tag-name ">")
                          (concat "<" tag-input ">" text "</" tag-name ">"))))
      (atomic-change-group
        (delete-region start end)
        (goto-char start)
        (insert wrapped-text)
        (when (string-match-p "\n" text)
          ;; Indent only the new boundaries, preserving literal text inside.
          (save-excursion
            (goto-char start)
            (forward-line 1)
            (indent-according-to-mode))
          (save-excursion
            (beginning-of-line)
            (indent-according-to-mode)))))))


(defun jsx-jedi-unwrap-tag ()
  "Remove the selected JSX wrapper, preserving its children.
Select using `jsx-jedi-tag-node-types'.  In JSX children positions, keep
child text verbatim.  In JavaScript expression positions, require exactly
one JSX element with no JSX text or expression siblings; formatting-only
newlines outside that child are discarded to preserve return semantics."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (let* ((start (treesit-node-start node))
           (end (treesit-node-end node))
           (bounds (jsx-jedi--content-bounds type node))
           (content
            (if (jsx-jedi--jsx-child-p node)
                (if bounds (buffer-substring (car bounds) (cdr bounds)) "")
              ;; Only a single JSX child is unambiguous in an expression slot.
              ;; Leading newlines after return could trigger automatic semicolon
              ;; insertion, so promote the child node without that whitespace.
              (let (children)
                (when bounds
                  (dotimes (i (treesit-node-child-count node t))
                    (let ((child (treesit-node-child node i t)))
                      (when (and (>= (treesit-node-start child) (car bounds))
                                 (<= (treesit-node-end child) (cdr bounds)))
                        (push child children)))))
                (unless (and (= (length children) 1)
                             (jsx-jedi--jsx-element-p (car children)))
                  (user-error "Unwrapping here requires a single JSX element"))
                (treesit-node-text (car children) t)))))
      (atomic-change-group
        (delete-region start end)
        (goto-char start)
        (insert content)))))


(defun jsx-jedi-move-to-opening-tag ()
  "Move point to the selected JSX element's opening < character.
Select using `jsx-jedi-tag-node-types'."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (node (nth 3 node-info))
              (opening-node (treesit-node-child node 0))
              (start (treesit-node-start opening-node)))
    (goto-char start)))


(defun jsx-jedi-move-to-closing-tag ()
  "Move point to the selected JSX element's closing > character.
For a self-closing element, use its own >.  Select using
`jsx-jedi-tag-node-types'."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (type (nth 0 node-info))
              (node (nth 3 node-info))
              (closing-node (treesit-node-child node -1)))
    (if (string= type "jsx_self_closing_element")
        (goto-char (1+ (treesit-node-start closing-node)))
      (goto-char (1- (treesit-node-end closing-node))))))


(defun jsx-jedi-toggle-self-closing-tag ()
  "Toggle the selected named JSX tag between paired and self-closing.
Select using `jsx-jedi-tag-node-types'; fragments are rejected.
Converting a paired element to self-closing deletes its children.
Converting back creates an empty element, retaining its attributes."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (type (nth 0 node-info))
              (node (nth 3 node-info))
              (name-node (jsx-jedi--tag-name-node node)))
    (atomic-change-group
      (if (string= type "jsx_self_closing_element")
          (let* ((tag-name (treesit-node-text name-node t))
                 (end (treesit-node-end node)))
            (goto-char end)
            (delete-char -2)
            (when (eq (char-before) ?\s)
              (delete-char -1))
            (insert ">")
            (save-excursion
              (insert "</" tag-name ">")))
        (let* ((opening-node (treesit-node-child-by-field-name node "open_tag"))
               (closing-node (treesit-node-child-by-field-name node "close_tag"))
               (opening-text (treesit-node-text opening-node t))
               (start (treesit-node-start node))
               (end (treesit-node-end node))
               (new-text (concat (substring opening-text 0 -1) " />")))
          (unless closing-node
            (user-error "This element has no closing tag"))
          (delete-region start end)
          (goto-char start)
          (insert new-text))))))


(defun jsx-jedi-add-attribute ()
  "Prompt for an attribute name and add it with an empty expression value.
Leave point between the braces.  Require a named tag selected by
`jsx-jedi-tag-node-types'; fragments are rejected."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (jsx-jedi--tag-name-node node)
    (let ((attr-name (read-string "Attribute name: ")))
      (unless (string-empty-p attr-name)
        (if (string= type "jsx_self_closing_element")
            (goto-char (- (treesit-node-end node) 2))
          (goto-char (- (treesit-node-end (treesit-node-child node 0)) 1)))
        (insert " " attr-name "={}")
        (backward-char 1)
        t))))



;;; Mode

;;;###autoload
(define-minor-mode jsx-jedi-mode
  "Enable structural JavaScript, TypeScript and JSX editing bindings.
Use with `js-ts-mode', `typescript-ts-mode' or `tsx-ts-mode' and their
tree-sitter grammars.  The package adds this mode to those major-mode
hooks.  `jsx-jedi-mode-map' is empty by default; bind commands there or
invoke them with \\[execute-extended-command]."
  :lighter " JSX Jedi"
  :keymap (make-sparse-keymap))

;;;###autoload
(add-hook 'js-ts-mode-hook #'jsx-jedi-mode)

;;;###autoload
(add-hook 'tsx-ts-mode-hook #'jsx-jedi-mode)

;;;###autoload
(add-hook 'typescript-ts-mode-hook #'jsx-jedi-mode)



(provide 'jsx-jedi)

;;; jsx-jedi.el ends here
