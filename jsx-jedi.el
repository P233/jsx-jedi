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

;;; Variables

(defvar jsx-jedi-tag-node-types       '("jsx_element"
                                        "jsx_self_closing_element"))

(defvar jsx-jedi-kill-node-types      (append jsx-jedi-tag-node-types
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
                                                "type_alias_declaration")))

(defvar jsx-jedi-empty-node-types     (append jsx-jedi-tag-node-types
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
                                                "template_string")))

(defvar jsx-jedi-zap-node-types       (append jsx-jedi-tag-node-types
                                              '("arguments"
                                                "array"
                                                "array_pattern"
                                                "formal_parameters"
                                                "jsx_expression"
                                                "jsx_opening_element"
                                                "named_imports"
                                                "object_pattern"
                                                "string"
                                                "template_string")))

(defvar jsx-jedi-copy-node-types      (append jsx-jedi-tag-node-types
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
                                                "type_alias_declaration")))

(defvar jsx-jedi-duplicate-node-types (append jsx-jedi-tag-node-types
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
                                                "type_alias_declaration")))

(defvar jsx-jedi-mark-node-types      (append jsx-jedi-tag-node-types
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
                                                "type_alias_declaration")))

(defvar jsx-jedi-comment-node-types   (append jsx-jedi-tag-node-types
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
  "This list is used to find nodes that can be commented. No need to include `comment' here.")

(defvar jsx-jedi-avy-node-types       (append jsx-jedi-tag-node-types
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
                                                "type_alias_declaration")))

(defvar jsx-jedi-hoist-node-types     (append jsx-jedi-tag-node-types
                                              '("jsx_expression")))


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
Return list (TYPE START END NODE) or nil."
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
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-empty-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (let ((bounds
           (pcase type
             ("jsx_attribute"
              (when-let ((value-node (or (treesit-node-child-by-field-name node "value")
                                         (treesit-node-child node -1))))
                (cons (1+ (treesit-node-start value-node))
                      (1- (treesit-node-end value-node)))))
             ("interface_declaration"
              (when-let ((body-node (treesit-node-child-by-field-name node "body")))
                (cons (1+ (treesit-node-start body-node))
                      (1- (treesit-node-end body-node)))))
             ("property_signature"
              (when-let* ((type-annotation-node (treesit-node-child-by-field-name node "type"))
                          (type-node (treesit-node-child type-annotation-node -1)))
                (cons (treesit-node-start type-node)
                      (treesit-node-end type-node))))
             ((or "pair" "type_alias_declaration")
              (when-let ((value-node (treesit-node-child-by-field-name node "value")))
                (cons (treesit-node-start value-node)
                      (treesit-node-end value-node))))
             ("assignment_expression"
              (when-let ((value-node (treesit-node-child-by-field-name node "right")))
                (cons (treesit-node-start value-node)
                      (treesit-node-end value-node))))
             ("call_expression"
              (when-let ((args-node (treesit-node-child-by-field-name node "arguments")))
                (cons (1+ (treesit-node-start args-node))
                      (1- (treesit-node-end args-node)))))
             ((or "lexical_declaration" "variable_declaration")
              (when-let* ((declarator-node (treesit-node-child node 0 t))
                          (value-node (treesit-node-child-by-field-name declarator-node "value")))
                (cons (treesit-node-start value-node)
                      (treesit-node-end value-node))))
             ("return_statement"
              (when-let ((value-node (treesit-node-child node 0 t)))
                (cons (treesit-node-start value-node)
                      (treesit-node-end value-node))))
             (_
              (when-let ((opening-node (treesit-node-child node 0))
                         (closing-node (treesit-node-child node -1)))
                (cons (treesit-node-end opening-node)
                      (treesit-node-start closing-node)))))))
      (when bounds
        (jsx-jedi--kill-region-and-goto-start (car bounds) (cdr bounds))))))

(defun jsx-jedi-substitute ()
  "Substitute content of the syntax node at point with yanked text."
  (interactive)
  (let ((text (string-trim (current-kill 0))))
    (when (jsx-jedi-empty)
      (if (string-match-p "\n" text)
          (progn
            (newline)
            (let ((start (point)))
              (insert text)
              (newline)
              (indent-region start (point))
              (indent-according-to-mode)))
        (insert text)))))


(defun jsx-jedi-zap ()
  "Delete from point to the end of the content of the syntax node."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-zap-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info))
              (end (nth 2 node-info)))
    (let ((zap-end (cond
                    ((string= type "jsx_element")
                     (treesit-node-start (treesit-node-child node -1)))
                    ((string= type "jsx_self_closing_element")
                     (- end 2))
                    (t
                     (1- end)))))
      (delete-region (point) zap-end)
      t)))


(defun jsx-jedi-copy ()
  "Copy syntax node at point to kill ring."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-copy-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info)))
    (kill-ring-save start end)
    (pulse-momentary-highlight-region start end)))


(defun jsx-jedi-duplicate ()
  "Duplicate syntax node at point."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-duplicate-node-types))
              (end (nth 2 node-info))
              (node (nth 3 node-info))
              (text (treesit-node-text node t)))
    (goto-char end)
    (newline)
    (insert text)
    (indent-region end (point))
    (let ((highlight-start (save-excursion
                             (goto-char end)
                             (skip-chars-forward " \t\n")
                             (point))))
      (pulse-momentary-highlight-region highlight-start (point)))))


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
             (text (buffer-substring-no-properties beg end))
             (new-text (string-trim text "[ \t\n]*{/\\*[ \t]*" "[ \t]*\\*/}[ \t\n]*")))
        (delete-region beg end)
        (insert new-text)))

     ;; Case 3: Current node is code -> Comment it
     (t
      (when-let* ((element (treesit-parent-until node (lambda (n)
                                                        (member (treesit-node-type n) jsx-jedi-comment-node-types)) t))
                  (start (treesit-node-start element))
                  (end (treesit-node-end element)))
        (if (member (treesit-node-type element) jsx-jedi-tag-node-types)
            (let ((text (buffer-substring-no-properties start end)))
              (delete-region start end)
              (insert "{/* " text " */}"))
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
    (delete-region start end)
    (insert text)
    (indent-region start (point))))


(defun jsx-jedi-rename-tag ()
  "Rename JSX element at point."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (let* ((current-tag-name (if (string= type "jsx_self_closing_element")
                                 (treesit-node-text (treesit-node-child node 1) t)
                               (treesit-node-text (treesit-node-child (treesit-node-child node 0) 1) t)))
           (new-tag (read-string (format "Rename %s to: " current-tag-name) current-tag-name)))
      (atomic-change-group
        (if (string= type "jsx_self_closing_element")
            (let* ((name-node (treesit-node-child node 1))
                   (start (treesit-node-start name-node))
                   (end (treesit-node-end name-node)))
              (delete-region start end)
              (goto-char start)
              (insert new-tag))
          (let* ((opening-node (treesit-node-child node 0))
                 (closing-node (treesit-node-child node -1))
                 (opening-name-node (treesit-node-child opening-node 1))
                 (closing-name-node (treesit-node-child closing-node 1)))
            (save-excursion
              (let ((start (treesit-node-start closing-name-node))
                    (end (treesit-node-end closing-name-node)))
                (delete-region start end)
                (goto-char start)
                (insert new-tag)))
            (let ((start (treesit-node-start opening-name-node))
                  (end (treesit-node-end opening-name-node)))
              (delete-region start end)
              (goto-char start)
              (insert new-tag))))))))


(defun jsx-jedi-wrap-tag ()
  "Wrap JSX element at point with new tag."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (start (nth 1 node-info))
              (end (nth 2 node-info))
              (node (nth 3 node-info))
              (text (treesit-node-text node t))
              (tag-input (read-string "Enter wrapping tag name: "))
              (tag-name (car (split-string tag-input))))
    (let ((wrapped-text (if (string-match-p "\n" text)
                            (concat "<" tag-input ">\n" text "\n</" tag-name ">")
                          (concat "<" tag-input ">" text "</" tag-name ">"))))
      (delete-region start end)
      (insert wrapped-text)
      (indent-region start (point)))))


(defun jsx-jedi-unwrap-tag ()
  "Unwrap content of JSX element at point."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (if (string= type "jsx_self_closing_element")
        (delete-region (treesit-node-start node) (treesit-node-end node))
      (let* ((opening-node (treesit-node-child node 0))
             (closing-node (treesit-node-child node -1))
             (start (treesit-node-start node))
             (end (treesit-node-end node))
             (inner-start (treesit-node-end opening-node))
             (inner-end (treesit-node-start closing-node))
             (content (string-trim (buffer-substring inner-start inner-end))))
        (delete-region start end)
        (insert content)
        (indent-region start (point))))))


(defun jsx-jedi-move-to-opening-tag ()
  "Move point to opening tag of JSX element."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (node (nth 3 node-info))
              (opening-node (treesit-node-child node 0))
              (start (treesit-node-start opening-node)))
    (goto-char start)))


(defun jsx-jedi-move-to-closing-tag ()
  "Move point to closing tag of JSX element."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info))
              (closing-node (treesit-node-child node -1)))
    (if (string= type "jsx_self_closing_element")
        (goto-char (1+ (treesit-node-start closing-node)))
      (goto-char (1- (treesit-node-end closing-node))))))


(defun jsx-jedi-toggle-self-closing-tag ()
  "Toggle JSX element between self-closing and normal."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
    (atomic-change-group
      (if (string= type "jsx_self_closing_element")
          (let* ((name-node (treesit-node-child node 1))
                 (tag-name (treesit-node-text name-node t))
                 (end (treesit-node-end node))
                 (start (treesit-node-start node)))
            (goto-char end)
            (delete-char -2)
            (when (eq (char-before) ?\s)
              (delete-char -1))
            (insert ">")
            (save-excursion
              (insert "</" tag-name ">")
              (indent-region start (point))))
        (let* ((opening-node (treesit-node-child node 0))
               (closing-node (treesit-node-child node -1))
               (opening-text (treesit-node-text opening-node t))
               (new-text (concat (substring opening-text 0 -1) " />")))
          (delete-region (treesit-node-end opening-node) (treesit-node-end closing-node))
          (delete-region (treesit-node-start opening-node) (treesit-node-end opening-node))
          (insert new-text))))))


(defun jsx-jedi-add-attribute ()
  "Add attribute to JSX element at point."
  (interactive)
  (when-let* ((node-info (jsx-jedi--find-node-info jsx-jedi-tag-node-types))
              (type (nth 0 node-info))
              (node (nth 3 node-info)))
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
