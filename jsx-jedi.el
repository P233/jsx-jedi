;;; jsx-jedi.el --- Enlightened JS/TS/JSX editing powers  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2025 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Version: 0.0.1
;; Created: 20 May 2024
;; Keywords: languages convenience tools tree-sitter javascript typescript jsx react
;; URL: https://github.com/p233-studio/jsx-jedi
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

;; JSX-Jedi brings enlightened editing powers to your JavaScript, TypeScript
;; and JSX development experience in Emacs.

;; For detailed documentation and usage instructions, visit:
;; https://github.com/p233-studio/jsx-jedi#readme

;;; Code:

(require 'avy)
(require 'pulse)
(require 'subr-x)
(require 'treesit)

;;; Variables

(defgroup jsx-jedi nil
  "Structural JavaScript, TypeScript and JSX editing."
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
This controls selection, not syntax support or separator handling."
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
  "Node types selected by empty and substitute.
Only nodes with supported content bounds can be changed.  The optional
object_type and throw_statement ranges are supported but not enabled
by default."
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
Only supported content ranges can be changed."
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
Any grammar node may be selected; comments use the whole comment block."
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
Any grammar node may be selected; comments use the whole comment block."
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
Any grammar node may provide a navigation scope."
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


(defun jsx-jedi--find-comment-block-bounds (node)
  "Return bounds (START . END) of the comment block containing NODE."
  (let ((start-node node)
        (end-node node))
    (while (string= (treesit-node-type (treesit-node-prev-sibling start-node)) "comment")
      (setq start-node (treesit-node-prev-sibling start-node)))
    (while (and end-node (string= (treesit-node-type (treesit-node-next-sibling end-node)) "comment"))
      (setq end-node (treesit-node-next-sibling end-node)))
    (cons (treesit-node-start start-node) (treesit-node-end end-node))))


(defun jsx-jedi--find-node-at-point (node position)
  "Find first ancestor of NODE (inclusive) containing POSITION."
  (when node
    (let ((start (treesit-node-start node))
          (end (treesit-node-end node)))
      (if (and (<= start position) (<= position end))
          node
        (let ((parent (treesit-node-parent node)))
          (when (and parent
                     (or (not (= start (treesit-node-start parent)))
                         (not (= end (treesit-node-end parent)))))
            (jsx-jedi--find-node-at-point parent position)))))))


(defun jsx-jedi--find-node-info (valid-types)
  "Find node at point matching VALID-TYPES.
Return list (TYPE START END NODE) or nil.
START and END delimit the operation range, which can span a comment block.
NODE is the syntax node at point, not necessarily the whole operation range."
  (let ((node (treesit-node-at (point))))
    (if (and (string= (treesit-node-type node) "comment")
             (member "comment" valid-types))
        (let ((bounds (jsx-jedi--find-comment-block-bounds node)))
          (list "comment" (car bounds) (cdr bounds) node))
      (when-let* ((node-at-point (jsx-jedi--find-node-at-point node (point)))
                  (found-node (treesit-parent-until node-at-point (lambda (n)
                                                                    (member (treesit-node-type n) valid-types)) t)))
        (list (treesit-node-type found-node)
              (treesit-node-start found-node)
              (treesit-node-end found-node)
              found-node)))))

(defun jsx-jedi--jsx-child-p (node)
  "Return non-nil when NODE is in a JSX children position."
  (string= (treesit-node-type (treesit-node-parent node)) "jsx_element"))

(defun jsx-jedi--jsx-element-p (node)
  "Return non-nil for the supported JSX element shapes of NODE.
Selection preferences must not redefine these grammar facts."
  (member (treesit-node-type node) '("jsx_element" "jsx_self_closing_element")))

(defun jsx-jedi--find-tag-info ()
  "Select a JSX tag using preferences, rejecting unsupported node types."
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

(defun jsx-jedi--content-bounds (type node)
  "Return the editable content bounds of NODE of TYPE, or nil.
Boolean attributes and self-closing elements have no editable content."
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
              (cons (1+ (treesit-node-start body)) (1- (treesit-node-end body)))))
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
            (when-let* ((declarator (treesit-node-child node 0 t))
                        (value (treesit-node-child-by-field-name declarator "value")))
              (cons (treesit-node-start value) (treesit-node-end value))))
           ((or "return_statement" "throw_statement")
            (let ((value (treesit-node-child node 0 t)))
              ;; Comments are named children too, but are not the operand.
              (while (equal (treesit-node-type value) "comment")
                (setq value (treesit-node-next-sibling value t)))
              (when value
                (cons (treesit-node-start value) (treesit-node-end value)))))
           ((or "arguments" "array" "array_pattern" "export_clause"
                "formal_parameters" "jsx_expression" "named_imports"
                "object" "object_pattern" "object_type" "parenthesized_expression"
                "statement_block" "string" "tuple_type" "type_parameters"
                "template_string")
            (when-let* ((opening (treesit-node-child node 0))
                        (closing (treesit-node-child node -1)))
              (cons (treesit-node-end opening) (treesit-node-start closing)))))))
    (when (and bounds (<= (car bounds) (cdr bounds)))
      bounds)))


;;; Commands

(defun jsx-jedi-kill ()
  "Kill the syntax node at point."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-kill-node-types))
              (type (nth 0 node-info))
              (start (nth 1 node-info))
              (end (nth 2 node-info))
              (node (nth 3 node-info)))
    (let ((kill-start start)
          (kill-end end))
      ;; For object, pair and other nodes, handle commas
      (when (member type '("object" "pair" "required_parameter"))
        (let ((next-node (treesit-node-next-sibling node))
              (prev-node (treesit-node-prev-sibling node)))
          (cond
           ;; Trailing comma
           ((and next-node (string= (treesit-node-text next-node t) ","))
            (setq kill-end (save-excursion
                             (goto-char (treesit-node-end next-node))
                             (skip-chars-forward " \t")
                             (point))))
           ;; Leading comma
           ((and prev-node (string= (treesit-node-text prev-node t) ","))
            (setq kill-start (save-excursion
                               (goto-char (treesit-node-start prev-node))
                               (skip-chars-backward " \t")
                               (point)))))))
      (kill-region kill-start kill-end)
      (when (save-excursion
              (beginning-of-line)
              (looking-at-p "^[[:space:]]*$"))
        (delete-blank-lines)
        (indent-for-tab-command)))))


(defun jsx-jedi-empty ()
  "Empty content of the syntax node at point."
  (interactive)
  (when-let* ((info (jsx-jedi--find-node-info jsx-jedi-empty-node-types))
              (bounds (jsx-jedi--content-bounds (nth 0 info) (nth 3 info))))
    (jsx-jedi--kill-region-and-goto-start (car bounds) (cdr bounds))))

(defun jsx-jedi-substitute ()
  "Substitute content of the syntax node at point with yanked text."
  (interactive)
  (when-let* ((info (jsx-jedi--find-node-info jsx-jedi-empty-node-types))
              (bounds (jsx-jedi--content-bounds (nth 0 info) (nth 3 info))))
    (let ((text (string-trim (current-kill 0))))
      (atomic-change-group
        (jsx-jedi--kill-region-and-goto-start (car bounds) (cdr bounds))
        (if (string-match-p "\n" text)
            (progn
              (newline)
              (let ((start (point)))
                (insert text)
                (newline)
                (indent-region start (point))
                (indent-according-to-mode)))
          (insert text))))))


(defun jsx-jedi-zap ()
  "Delete from point to the end of the content of the syntax node."
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
  "Copy syntax node at point to kill ring."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-copy-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    (kill-ring-save start end)
    (pulse-momentary-highlight-region start end)))


(defun jsx-jedi-duplicate ()
  "Duplicate the selected syntax range in its current sibling context."
  (interactive)
  (when-let* ((info (jsx-jedi--find-node-info jsx-jedi-duplicate-node-types)))
    (pcase-let* ((`(,type ,start ,end ,node) info)
                (parent-type (treesit-node-type (treesit-node-parent node)))
                (comma-p (or (string= type "pair")
                             (and (string= type "object")
                                  (member parent-type '("array" "arguments")))))
                (text (buffer-substring-no-properties start end)))
      (when (or (and (member type '("jsx_element" "jsx_self_closing_element"
                                   "jsx_expression"))
                     (not (jsx-jedi--jsx-child-p node)))
                (and (string= type "object") (not comma-p)))
        (user-error "This expression cannot be duplicated in its current context"))
      (atomic-change-group
        (goto-char end)
        (when comma-p (insert ","))
        (newline)
        (let ((insert-start (point)))
          (insert text)
          ;; Siblings share the original indentation context.  Reindenting the
          ;; body is costly and can change whitespace in JSX or template text.
          (save-excursion
            (goto-char insert-start)
            (indent-according-to-mode))
          (let ((highlight-start (save-excursion
                                   (goto-char insert-start)
                                   (skip-chars-forward " \t")
                                   (point))))
            (pulse-momentary-highlight-region highlight-start (point))))))))


(defun jsx-jedi-mark ()
  "Mark syntax node at point."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-mark-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    (goto-char start)
    (set-mark end)
    (activate-mark)))


(defun jsx-jedi-comment-uncomment ()
  "Comment or uncomment syntax node at point."
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
     ;; Case 1: Current node is a standard JS comment -> Uncomment it
     (js-comment-p
      (let* ((bounds (jsx-jedi--find-comment-block-bounds node))
             (start (car bounds))
             (end (cdr bounds)))
        (uncomment-region start end)))

     ;; Case 2: Current node is a JSX comment -> Uncomment it
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

     ;; Case 3: Current node is code -> Comment it
     (t
      (when-let* ((element (treesit-parent-until node (lambda (n)
                                                        (member (treesit-node-type n) jsx-jedi-comment-node-types)) t))
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
          (if (eq (char-after end) ?,)
              (comment-region start (1+ end))
            (comment-region start end))))))))

(defun jsx-jedi-avy-word ()
  "Jump to word in syntax node at point using Avy."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-avy-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    (avy-goto-word-0 t start end)))


(defun jsx-jedi-hoist-tag ()
  "Hoist JSX element at point, replacing parent."
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
  "Rename JSX element at point."
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
  "Wrap JSX element at point with new tag."
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
  "Unwrap content of JSX element at point."
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
              ;; Extract that node without leading whitespace to avoid return ASI.
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
  "Move point to opening tag of JSX element."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (node (nth 3 node-info))
              (opening-node (treesit-node-child node 0))
              (start (treesit-node-start opening-node)))
    (goto-char start)))


(defun jsx-jedi-move-to-closing-tag ()
  "Move point to closing tag of JSX element."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-tag-info))
              (type (nth 0 node-info))
              (node (nth 3 node-info))
              (closing-node (treesit-node-child node -1)))
    (if (string= type "jsx_self_closing_element")
        (goto-char (1+ (treesit-node-start closing-node)))
      (goto-char (1- (treesit-node-end closing-node))))))


(defun jsx-jedi-toggle-self-closing-tag ()
  "Toggle JSX element between self-closing and normal."
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
  "Add attribute to JSX element at point."
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
  "Minor mode for JSX-related editing commands, specifically designed for
tsx-ts-mode and typescript-ts-mode."
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
