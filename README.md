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

Emacs 31's `js-ts-mode` also uses the [JSDoc grammar](https://github.com/tree-sitter/tree-sitter-jsdoc) for fontification.

Emacs 29.1 is the package's declared minimum. The CI matrix targets 29.1, 30.2 and 31.1; see the workflow results for versions actually verified. Local validation of this change used Emacs 31.1 on macOS.

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

### Optional Node Ranges

The default lists keep their existing selection scopes. Selection uses the closest matching node; list order does not give a node higher priority. Adding a type can therefore select a smaller part of the code. Repeating `jsx-jedi-mark` keeps that range rather than expanding to its parent.

For declaration-level copy/mark and additional empty/substitute ranges, enable the options you want after loading the package:

```elisp
(with-eval-after-load 'jsx-jedi
  ;; Select a var or enum declaration without selecting its enclosing function.
  (dolist (node-type '("variable_declaration" "enum_declaration"))
    (add-to-list 'jsx-jedi-copy-node-types node-type t)
    (add-to-list 'jsx-jedi-mark-node-types node-type t))
  ;; Edit object-type members or the expression following throw.
  (dolist (node-type '("object_type" "throw_statement"))
    (add-to-list 'jsx-jedi-empty-node-types node-type t)))
```

With `object_type` enabled, emptying at the opening `{` in `type T = { a: number };` leaves `type T = {};`. From a property name, the closer `property_signature` still selects only that property's type. With `throw_statement` enabled, emptying from the `throw` keyword leaves `throw ;` for further editing; substitute replaces its expression directly. Adjacent comments and following statements are preserved.

These examples do not change kill, duplicate, comment, Avy or zap scopes. Extending the first three also requires support for each parent context and its separators. Adding smaller Avy scopes reduces the available destinations; adding zap containers can delete following members in that container. Keep those ranges unchanged unless that behavior is wanted.

## Running tests

The ERT suite uses real JavaScript, TypeScript and TSX modes and parsers. It also checks configuration loading/saving in fresh Emacs processes, command-loop undo/redo, cancellation, Avy selection and highlight cleanup. No parser mocks or missing-dependency skips are used.

To obtain the same dependency revisions as CI, run this once from the repository root with Git and a C compiler installed:

```sh
bash scripts/setup-test-deps.sh
export JSX_JEDI_AVY_DIR="$PWD/.test-deps/avy"
export JSX_JEDI_GRAMMAR_DIR="$PWD/.test-deps/grammars"
```

The helper downloads pinned Avy 0.5.0 and grammar source commits, builds their checked-in C sources, and records the revisions in `.test-deps/versions.txt`. It supports macOS and Linux, requires an empty destination, and accepts an alternative destination as its first argument. It does not install anything into your Emacs configuration.

Run source and bytecode checks in separate processes:

```sh
emacs -Q --batch -l scripts/test.el
emacs -Q --batch -l scripts/compile.el
JSX_JEDI_TEST_MODE=compiled emacs -Q --batch -l scripts/test.el
```

Compilation treats warnings as errors and writes to `.build/`, leaving the source tree free of bytecode. Override the output directory with `JSX_JEDI_BUILD_DIR`. Compiled-mode tests load that exact `.elc` file and fail if it is absent.

Existing dependencies also work: pass the directory containing `avy.el` with `-L` or `JSX_JEDI_AVY_DIR`, and set `JSX_JEDI_GRAMMAR_DIR` to your grammar directory. The full suite requires `javascript`, `typescript`, `tsx` and `jsdoc`; omit the environment variable if Emacs finds them in its standard search paths. Validation never downloads missing grammars implicitly.

The GitHub Actions workflow repeats these checks on Ubuntu for each matrix version. Actions and dependency sources are pinned to commits; the setup action still relies on its upstream Emacs build service, so the entire toolchain is not bit-for-bit pinned.

### Interactive checks

Batch tests do not prove visual behavior. In a graphical Emacs session, load the package and use `test-jedi.tsx` or a disposable buffer to check:

- Rename a paired tag through the real minibuffer, then undo and redo; both names should change together.
- Cancel rename, wrap and add-attribute with `C-g`; text and the current selection should remain unchanged.
- Use `jsx-jedi-avy-word`; verify labels, destination, focus and label removal.
- Copy and duplicate a JSX child; verify the momentary highlight and its removal on the next command.
- Open the Customize group, save an option to a disposable custom file, restart, and reset it to its standard value.

Repeat with your normal configuration when checking integration with completion, keybindings, themes or other editing packages.

### Performance samples

With the dependency environment above set, run:

```sh
mkdir -p .build
emacs -Q --batch -l scripts/benchmark.el > .build/benchmark-source.jsonl
JSX_JEDI_TEST_MODE=compiled emacs -Q --batch -l scripts/benchmark.el \
  > .build/benchmark-compiled.jsonl
```

The benchmark varies file size and selected-subtree size independently and measures mark, copy and duplicate. Each case has one warm-up and seven recorded samples; set `JSX_JEDI_BENCH_SAMPLES` to an integer from 1 to 100 to change that count. JSON lines contain environment details, source/loaded-file hashes, dependency revisions, raw timings, GC counts/time and medians. Setup diagnostics go to stderr.

Fixture setup, initial parsing and syntax preparation are outside the timed command. The parser is warm before each sample; pulse, font-lock and undo recording are disabled. A separate timing forces parsing after each command to expose deferred work. Results are checked for syntax errors and expected duplication. Compare runs on the same machine with matching dependencies and settings. These are batch timings, not GUI latency or proof of a speedup; CI does not impose absolute timing thresholds.

## License

GPL-3.0
