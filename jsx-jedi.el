;;; jsx-jedi.el --- Minor mode for JSX-related editing commands.  -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Created: 20 May 2024
;; URL: https://github.com/P233/jsx-jedi
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

;; Please check the README.

;;; Code:

(require 'avy)

(defun jsx/kill-region-and-goto-start (start end)
  "Kill the region between START and END, and move point to START."
  (kill-region start end)
  (goto-char start))


(defun jsx/find-comment-block-bounds (node)
  "Get the bounds of the comment block containing NODE.
Return a cons cell (START . END) representing the bounds."
  (let ((start-node node)
        (end-node node))
    (while (string= (treesit-node-type (treesit-node-prev-sibling start-node)) "comment")
      (setq start-node (treesit-node-prev-sibling start-node)))
    (while (and end-node (string= (treesit-node-type (treesit-node-next-sibling end-node)) "comment"))
      (setq end-node (treesit-node-next-sibling end-node)))
    (cons (treesit-node-start start-node) (treesit-node-end end-node))))


(defun jsx/kill ()
  "Kill the suitable syntax node at point."
  (interactive)
  (let* ((node (treesit-node-at (point)))
         (parent (treesit-parent-until node (lambda (n)
                                              (member (treesit-node-type n)
                                                      '("import_statement"
                                                        "expression_statement"
                                                        "function_declaration"
                                                        "lexical_declaration"
                                                        "type_alias_declaration"
                                                        "jsx_element"
                                                        "jsx_self_closing_element"
                                                        "pair")))))
         (start (treesit-node-start parent))
         (end (treesit-node-end parent)))
    (kill-region start end)
    (delete-blank-lines)
    (indent-for-tab-command)))


(defun jsx/empty ()
  "Empty the content of the JSX element or other suitable syntax node at point.

The function intentionally skips JSX attribute nodes, as the
jsx/kill-attribute-value function is specifically designed for emptying
attribute values, providing a clearer separation of concerns."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (treesit-parent-until node (lambda (n)
                                                    (let ((node-type (treesit-node-type n)))
                                                      (if (string= node-type "jsx_expression")
                                                          (not (treesit-parent-until n (lambda (m)
                                                                                         (string= (treesit-node-type m) "jsx_attribute"))))
                                                        (member node-type
                                                                '("jsx_element"
                                                                  "array"
                                                                  "array_pattern"
                                                                  "arguments"
                                                                  "named_imports"
                                                                  "object_pattern"
                                                                  "formal_parameters"
                                                                  "statement_block")))))))
              (opening-node (treesit-node-child element 0))
              (closing-node (treesit-node-child element -1))
              (start (treesit-node-end opening-node))
              (end (treesit-node-start closing-node)))
    (jsx/kill-region-and-goto-start start end)))


(defun jsx/zap ()
  "Zap the suitable syntax node at point to the end."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (parent (treesit-parent-until node (lambda (n)
                                                   (member (treesit-node-type n)
                                                           '("array"
                                                             "array_pattern"
                                                             "string"
                                                             "arguments"
                                                             "named_imports"
                                                             "object_pattern"
                                                             "formal_parameters"
                                                             "jsx_expression"
                                                             "jsx_opening_element")))))
              (end (1- (treesit-node-end parent))))
    (delete-region (point) end)))


(defun jsx/copy ()
  "Copy the suitable syntax node at point to the kill ring."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (parent (treesit-parent-until node (lambda (n)
                                                   (member (treesit-node-type n)
                                                           '("import_statement"
                                                             "expression_statement"
                                                             "function_declaration"
                                                             "lexical_declaration"
                                                             "type_alias_declaration"
                                                             "jsx_element"
                                                             "jsx_self_closing_element"
                                                             "pair")))))
              (start (treesit-node-start parent))
              (end (treesit-node-end parent)))
    (kill-ring-save start end)
    (pulse-momentary-highlight-region start end)))


(defun jsx/duplicate ()
  "Duplicate the suitable syntax node at point."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (treesit-parent-until node (lambda (n)
                                                    (member (treesit-node-type n)
                                                            '("function_declaration"
                                                              "lexical_declaration"
                                                              "jsx_element"
                                                              "jsx_self_closing_element"
                                                              "pair")))))
              (element-text (treesit-node-text element t))
              (end (treesit-node-end element)))
    (goto-char end)
    (newline)
    (insert element-text)
    (indent-region end (point))
    (let ((position (save-excursion
                      (goto-char end)
                      (skip-chars-forward " \t\n")
                      (point))))
      (pulse-momentary-highlight-region position (point)))))

(defun jsx/mark ()
  "Select the suitable syntax node at point."
  (interactive)
  (let ((node (treesit-node-at (point))))
    (if (string= (treesit-node-type node) "comment")
        (when-let* ((bounds (jsx/find-comment-block-bounds node))
                    (start (car bounds))
                    (end (cdr bounds)))
          (goto-char start)
          (set-mark end)
          (activate-mark))
      (when-let* ((parent (treesit-parent-until node (lambda (n)
                                                       (member (treesit-node-type n)
                                                               '("import_statement"
                                                                 "expression_statement"
                                                                 "function_declaration"
                                                                 "lexical_declaration"
                                                                 "type_alias_declaration"
                                                                 "jsx_element"
                                                                 "jsx_self_closing_element"
                                                                 "pair")))))
                  (start (treesit-node-start parent))
                  (end (treesit-node-end parent)))
        (goto-char start)
        (set-mark end)
        (activate-mark)))))


(defun jsx/comment-uncomment ()
  "Comment or uncomment the suitable syntax node at point."
  (interactive)
  (let* ((node (treesit-node-at (point)))
         (is-node-comment (string= (treesit-node-type node) "comment"))
         (is-parent-jsx-expression (string= (treesit-node-type (treesit-node-parent node)) "jsx_expression"))
         (is-normal-comment (and is-node-comment
                                 (not is-parent-jsx-expression)))
         (is-jsx-comment (and is-parent-jsx-expression
                              (or is-node-comment
                                  (string= (treesit-node-type (treesit-node-prev-sibling node)) "comment")
                                  (string= (treesit-node-type (treesit-node-next-sibling node)) "comment")))))
    (cond
     (is-normal-comment
      (let* ((bounds (jsx/find-comment-block-bounds node))
             (start (car bounds))
             (end (cdr bounds)))
        (uncomment-region start end)))
     (is-jsx-comment
      (let* ((comment (treesit-parent-until node (lambda (n)
                                                   (string= (treesit-node-type n) "jsx_expression")) t))
             (comment-text (treesit-node-text comment t))
             (uncomment-text (replace-regexp-in-string "{/\\*[[:space:]]*" "" (replace-regexp-in-string "[[:space:]]*\\*/}" "" comment-text)))
             (start (treesit-node-start comment))
             (end (treesit-node-end comment)))
        (delete-region start end)
        (insert uncomment-text)
        (goto-char start)))
     ((not (or is-normal-comment is-jsx-comment))
      (when-let* ((parent (treesit-parent-until node (lambda (n)
                                                       (member (treesit-node-type n)
                                                               '("import_statement"
                                                                 "expression_statement"
                                                                 "function_declaration"
                                                                 "lexical_declaration"
                                                                 "type_alias_declaration"
                                                                 "jsx_element"
                                                                 "jsx_self_closing_element")))))
                  (start (treesit-node-start parent))
                  (end (treesit-node-end parent)))
        (if (member (treesit-node-type parent) '("jsx_element" "jsx_self_closing_element"))
            (let ((comment-text (concat "{/* " (treesit-node-text parent t) " */}"))
                  (start (treesit-node-start parent))
                  (end (treesit-node-end parent)))
              (kill-region start end)
              (insert comment-text))
          (comment-region start end)))))))


(defun jsx/avy-word ()
  "Jump to a word within the nearest suitable parent node at point using Avy."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (parent (treesit-parent-until node (lambda (n)
                                                   (member (treesit-node-type n)
                                                           '("import_statement"
                                                             "expression_statement"
                                                             "function_declaration"
                                                             "lexical_declaration"
                                                             "type_alias_declaration"
                                                             "jsx_element"
                                                             "jsx_self_closing_element")))))
              (start (treesit-node-start parent))
              (end (treesit-node-end parent)))
    (avy-goto-word-0 t start end)))


(defun jsx/raise-element ()
  "Raise the JSX element at point."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (treesit-parent-until node (lambda (n)
                                                    (member (treesit-node-type n)
                                                            '("jsx_element"
                                                              "jsx_self_closing_element"
                                                              "jsx_expression")))))
              (element-text (treesit-node-text element t))
              (element-parent (treesit-parent-until element (lambda (n)
                                                              (string= (treesit-node-type n) "jsx_element"))))
              (start (treesit-node-start element-parent))
              (end (treesit-node-end element-parent)))
    (delete-region start end)
    (insert element-text)
    (indent-region start (point))))


(defun jsx/move-to-opening-tag ()
  "Move point to the opening tag of the JSX element at point."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (treesit-parent-until node (lambda (n)
                                                    (string= (treesit-node-type n) "jsx_element"))))
              (opening-node (treesit-node-child element 0))
              (position (1- (treesit-node-end opening-node))))
    (goto-char position)))


(defun jsx/move-to-closing-tag ()
  "Move point to the closing tag of the JSX element at point."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (treesit-parent-until node (lambda (n)
                                                    (string= (treesit-node-type n) "jsx_element"))))
              (closing-node (treesit-node-child element -1))
              (position (+ 2 (treesit-node-start closing-node))))
    (goto-char position)))


(defun jsx/kill-attribute ()
  "Kill the JSX attribute at point."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (attribute (treesit-parent-until node (lambda (n)
                                                      (string= (treesit-node-type n) "jsx_attribute"))))
              (start (treesit-node-start attribute))
              (end (treesit-node-end attribute)))
    (if (string= (buffer-substring-no-properties (1- start) start) " ")
        (kill-region (1- start) end)
      (kill-region start end))))


(defun jsx/copy-attribute ()
  "Copy the JSX attribute at point to the kill ring."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (attribute (treesit-parent-until node (lambda (n)
                                                      (string= (treesit-node-type n) "jsx_attribute"))))
              (start (treesit-node-start attribute))
              (end (treesit-node-end attribute)))
    (kill-ring-save start end)
    (pulse-momentary-highlight-region start end)))


(defun jsx/kill-attribute-value ()
  "Kill the value of the JSX attribute at point."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (attribute (treesit-parent-until node (lambda (n)
                                                      (string= (treesit-node-type n) "jsx_attribute"))))
              (value (treesit-node-child attribute -1)))
    (let ((start (1+ (treesit-node-start value)))
          (end (1- (treesit-node-end value))))
      (jsx/kill-region-and-goto-start start end))))


(defun jsx/move-to-prev-attribute ()
  "Move point to the previous JSX attribute."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (if (member (treesit-node-text node t) '(">" "/>"))
                           node
                         (treesit-parent-until node (lambda (n)
                                                      (string= (treesit-node-type n) "jsx_attribute")))))
              (prev-element (treesit-node-prev-sibling element))
              (is-attribute (string= (treesit-node-type prev-element) "jsx_attribute")))
    (goto-char (treesit-node-start prev-element))))


(defun jsx/move-to-next-attribute ()
  "Move point to the next JSX attribute."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (element (if (string= (treesit-node-type node) "identifier")
                           node
                         (treesit-parent-until node (lambda (n)
                                                      (string= (treesit-node-type n) "jsx_attribute")))))
              (next-element (treesit-node-next-sibling element))
              (is-attribute (string= (treesit-node-type next-element) "jsx_attribute")))
    (goto-char (treesit-node-start next-element))))


(defun jsx/declaration-to-if-statement ()
  "Convert the variable declaration at point to an if statement."
  (interactive)
  (when-let* ((node (treesit-node-at (point)))
              (parent (treesit-parent-until node (lambda (n)
                                                   (string= (treesit-node-type n) "lexical_declaration"))))
              (value (treesit-search-subtree parent (lambda (n)
                                                      (string= (treesit-node-type n) "call_expression"))))
              (value-text (treesit-node-text value t))
              (start (treesit-node-start parent))
              (end (treesit-node-end parent)))
    (delete-region start end)
    (insert (format "if (%s) {\n\n}" value-text))
    (indent-region start (point))
    (forward-line -1)
    (indent-for-tab-command)))


;;;###autoload
(define-minor-mode jsx-jedi-mode
  "Minor mode for JSX-related editing commands, specifically designed for
tsx-ts-mode and typescript-ts-mode."
  :lighter " JSX Jedi"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-k") 'jsx/kill)
            (define-key map (kbd "C-c C-e") 'jsx/empty)
            (define-key map (kbd "C-c C-z") 'jsx/zap)
            (define-key map (kbd "C-c C-w") 'jsx/copy)
            (define-key map (kbd "C-c C-x") 'jsx/duplicate)
            (define-key map (kbd "C-c C-SPC") 'jsx/mark)
            (define-key map (kbd "C-c C-;") 'jsx/comment-uncomment)
            (define-key map (kbd "C-c C-j") 'jsx/avy-word)
            (define-key map (kbd "C-c C-t C-r") 'jsx/raise-element)
            (define-key map (kbd "C-c C-t C-,") 'jsx/move-to-opening-tag)
            (define-key map (kbd "C-c C-t C-.") 'jsx/move-to-closing-tag)
            (define-key map (kbd "C-c C-a C-k") 'jsx/kill-attribute)
            (define-key map (kbd "C-c C-a C-w") 'jsx/copy-attribute)
            (define-key map (kbd "C-c C-a C-v") 'jsx/kill-attribute-value)
            (define-key map (kbd "C-c C-a C-p") 'jsx/move-to-prev-attribute)
            (define-key map (kbd "C-c C-a C-n") 'jsx/move-to-next-attribute)
            map))


;;;###autoload
(add-hook 'tsx-ts-mode-hook #'jsx-jedi-mode)

;;;###autoload
(add-hook 'typescript-ts-mode-hook #'jsx-jedi-mode)


(provide 'jsx-jedi)

;;; jsx-jedi.el ends here