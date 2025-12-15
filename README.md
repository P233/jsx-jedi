# JSX Jedi

Enlightened JS/TS/JSX editing powers for Emacs.

JSX Jedi streamlines editing by providing context-aware operations for JavaScript, TypeScript, and JSX/TSX code. Leveraging tree-sitter's precise syntax analysis, it intelligently identifies relevant code structures based on cursor position—eliminating the need for exact cursor placement or manual selection of complete statements.

> **Note**: JSX Jedi is specifically designed for the [tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) parser and works with the built-in `js-ts-mode`, `typescript-ts-mode`, and `tsx-ts-mode` in Emacs 29 and later versions.

## Requirements

- Emacs 29.1 or later
- [avy](https://github.com/abo-abo/avy)

## Installation

Using `straight.el` and `use-package`:

```elisp
(use-package jsx-jedi
  :straight (:type git :host github :repo "p233/jsx-jedi"))
```

## Features & Commands

JSX Jedi provides a suite of commands that automatically target the most relevant syntax node at your cursor.

### Editing & Manipulation

- **`jsx-jedi-kill`**: Kill the syntax node at point. Smartly handles trailing commas for objects and arrays.
- **`jsx-jedi-copy`**: Copy the syntax node at point to the kill ring.
- **`jsx-jedi-duplicate`**: Duplicate the current node (e.g., duplicate a function, a JSX element, or a line).
- **`jsx-jedi-empty`**: Empty the content of the node.
  - For JSX attributes: clears the value.
  - For JSX elements: removes children.
  - For Objects/Arrays: removes properties/items.
- **`jsx-jedi-substitute`**: Replace the content of the node with the text from the kill ring (yank).
- **`jsx-jedi-zap`**: Delete from the cursor position to the end of the node's content.
- **`jsx-jedi-comment-uncomment`**: Context-aware commenting.
  - Toggles standard comments in JS/TS.
  - Toggles `{/* ... */}` comments inside JSX expressions.
  - Wraps JSX elements in `{/* ... */}` when commenting them out.

### JSX Tag Operations

- **`jsx-jedi-rename-tag`**: Rename the current JSX tag. Automatically updates both the opening and closing tags.
- **`jsx-jedi-wrap-tag`**: Wrap the current element with a new parent tag.
- **`jsx-jedi-unwrap-tag`**: Remove the current tag but keep its content (promote children).
- **`jsx-jedi-hoist-tag`**: Hoist the current element, replacing its parent element with itself.
- **`jsx-jedi-toggle-self-closing-tag`**: Convert between `<Tag>...</Tag>` and `<Tag />`.
- **`jsx-jedi-add-attribute`**: Quickly add a new attribute to the current element.

### Navigation & Selection

- **`jsx-jedi-mark`**: Mark (select) the current syntax node.
- **`jsx-jedi-move-to-opening-tag`**: Jump to the opening tag of the current element.
- **`jsx-jedi-move-to-closing-tag`**: Jump to the closing tag of the current element.
- **`jsx-jedi-avy-word`**: Use Avy to jump to any word _within_ the current syntax node scope.

## Configuration

JSX Jedi does not define default keybindings to avoid conflicts. You can set up your own bindings. Here is a suggested configuration using standard `define-key`:

```elisp
(use-package jsx-jedi
  :straight (:type git :host github :repo "p233/jsx-jedi")
  :config
  ;; Example keybindings
  (define-key jsx-jedi-mode-map (kbd "C-c j k") #'jsx-jedi-kill)
  (define-key jsx-jedi-mode-map (kbd "C-c j w") #'jsx-jedi-copy)
  (define-key jsx-jedi-mode-map (kbd "C-c j d") #'jsx-jedi-duplicate)
  (define-key jsx-jedi-mode-map (kbd "C-c j r") #'jsx-jedi-rename-tag)
  ;; ... add other bindings as needed
  )
```

## How it works

### Smart Node Selection

When you execute a command like `jsx-jedi-kill`, JSX Jedi:

1.  Examines your current cursor position.
2.  Identifies the syntax node at that position.
3.  Traverses up the tree-sitter syntax tree, searching for a matching node type from a predefined list (e.g., `jsx-jedi-kill-node-types`).
4.  Applies the requested operation to the most appropriate node.

This intelligent selection means you can place your cursor _anywhere_ within a structure—whether inside a JSX element, attribute, expression, or tag name—and JSX Jedi will act on the most logical enclosing Node.

### Customizable Node Types

Each operation has a customizable variable defining valid target nodes (e.g., `jsx-jedi-kill-node-types`, `jsx-jedi-tag-node-types`). You can modify these lists to tune the behavior to your liking.

## License

GPL-3.0
