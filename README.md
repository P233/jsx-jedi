# JSX Jedi

Enlightened JS/TS/JSX editing powers for Emacs.

JSX Jedi streamlines editing by providing context-aware operations for JavaScript, TypeScript, and JSX/TSX code. Leveraging tree-sitter's precise syntax analysis, it intelligently identifies relevant code structures based on cursor position—eliminating the need for exact cursor placement or manual selection of complete statements.

> **Note**: JSX Jedi uses Emacs's built-in tree-sitter support and works with `js-ts-mode`, `typescript-ts-mode`, and `tsx-ts-mode`. Use `tsx-ts-mode` for both JSX and TSX files.

## Requirements

- Emacs 29.1 or later, built with tree-sitter support
- [avy](https://github.com/abo-abo/avy)
- The grammar required by the active major mode:

| Major mode | Grammar | Source |
| --- | --- | --- |
| `js-ts-mode` | `javascript` | [tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) |
| `typescript-ts-mode` | `typescript` | [tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) |
| `tsx-ts-mode` | `tsx` | [tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) |

Install the grammars for the modes you use and ensure Emacs can load them. For grammars installed outside Emacs's standard search directories, add their directory to `treesit-extra-load-path`.

Emacs 29.1 is the package's declared minimum; the regression suite has not yet been verified on that version.

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
- **`jsx-jedi-duplicate`**: Duplicate the current node or comment block. Adds separators for object properties and objects in arrays or argument lists. JSX nodes require a JSX children position; unsupported expression positions are rejected. Existing body indentation is preserved.
- **`jsx-jedi-empty`**: Empty the content of the node.
  - For JSX attributes: clears the value.
  - For JSX elements: removes children.
  - For Objects/Arrays: removes properties/items.
  - Nodes without editable content, such as boolean attributes, remain unchanged.
- **`jsx-jedi-substitute`**: Replace the content of the node with the text from the kill ring (yank).
- **`jsx-jedi-zap`**: Delete from the cursor position to the end of the node's content. Does nothing when the cursor is outside that content.
- **`jsx-jedi-comment-uncomment`**: Context-aware commenting.
  - Toggles standard comments in JS/TS.
  - Toggles standalone `{/* ... */}` comments inside JSX children. Expressions containing both code and comments are rejected.
  - Wraps JSX child elements in `{/* ... */}` when commenting them out. Rejects elements outside JSX children and content containing an existing block-comment terminator.

### JSX Tag Operations

- **`jsx-jedi-rename-tag`**: Rename the current JSX tag. Automatically updates both the opening and closing tags.
- **`jsx-jedi-wrap-tag`**: Wrap the current element with a new parent tag.
- **`jsx-jedi-unwrap-tag`**: Remove the current tag but keep its content (promote children).
- **`jsx-jedi-hoist-tag`**: Hoist the current element, replacing its parent element with itself.
- **`jsx-jedi-toggle-self-closing-tag`**: Convert between `<Tag>...</Tag>` and `<Tag />`.
- **`jsx-jedi-add-attribute`**: Quickly add a new attribute to the current element.

Renaming, adding attributes, and toggling self-closing tags require a named tag; fragments are rejected without changing the buffer. When unwrap or hoist replaces an element in a JavaScript expression, it requires a single JSX element to promote. Other content is rejected without changing the buffer.

Unwrap preserves child text, including whitespace. Tag operations preserve existing multiline literal content and limit automatic indentation to the affected boundaries.

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

Use `M-x customize-group RET jsx-jedi RET` to edit and save the ten node-selection options. Existing `setq` configuration and temporary `let` bindings continue to work.

Each operation has its own target list (for example, `jsx-jedi-kill-node-types`). Adding a type changes selection; it does not add support for editing that syntax. The option descriptions state the limits of each operation.

`jsx-jedi-tag-node-types` supports paired elements/fragments and self-closing elements. Tag commands reject other node types even when assigned through Lisp. Grammar safety checks remain independent of this preference: changing the list cannot make a JSX expression safe to promote into JavaScript.

The lists are initialized independently when the package loads. Changing the tag list afterward does not update other lists. An explicit Customize reset to a standard value evaluates its default expression again, using the current tag list. Saved values and values set before loading are preserved.

## Running tests

The ERT regression suite uses a real TSX parser. Install `avy` and the `tsx` grammar before running it; the test runner does not download dependencies.

From the repository root:

```sh
JSX_JEDI_GRAMMAR_DIR=/path/to/grammars \
  emacs -Q --batch -L /path/to/avy -l scripts/test.el
```

Pass the directory containing `avy.el` with `-L`. Set `JSX_JEDI_GRAMMAR_DIR` to the directory containing the compiled TSX grammar, or omit it if Emacs already finds that grammar in its standard search directories. Missing dependencies and grammar load failures stop the run with an error; tests are not silently skipped.

`test-jedi.tsx` remains a sample file for manual editing checks.

## License

GPL-3.0
