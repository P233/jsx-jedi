# JSX Jedi

Structural editing for JavaScript, TypeScript and JSX/TSX in Emacs, powered by built-in tree-sitter.

See [CHANGELOG.md](CHANGELOG.md) for version changes.

## Setup

Requires Emacs 29.1+ with tree-sitter support, [Avy](https://github.com/abo-abo/avy) 0.5+, and the grammar for your major mode:

| Major mode | Grammar | Source |
| --- | --- | --- |
| `js-ts-mode` | `javascript` | [tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) |
| `typescript-ts-mode` | `typescript` | [tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) |
| `tsx-ts-mode` (JSX and TSX) | `tsx` | [tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) |

Add grammars outside Emacs's standard directories to `treesit-extra-load-path`. Emacs 31's `js-ts-mode` also uses the [JSDoc grammar](https://github.com/tree-sitter/tree-sitter-jsdoc) for fontification.

No keybindings are assigned by default. Invoke commands with `M-x` or bind them in `jsx-jedi-mode-map`.

Install with `straight.el` and `use-package`; the keybindings below are optional examples:

```elisp
(use-package jsx-jedi
  :straight (:type git :host github :repo "p233/jsx-jedi")
  :config
  (define-key jsx-jedi-mode-map (kbd "C-c j k") #'jsx-jedi-kill)
  (define-key jsx-jedi-mode-map (kbd "C-c j w") #'jsx-jedi-copy)
  (define-key jsx-jedi-mode-map (kbd "C-c j d") #'jsx-jedi-duplicate)
  (define-key jsx-jedi-mode-map (kbd "C-c j r") #'jsx-jedi-rename-tag))
```

The package enables `jsx-jedi-mode` when entering the supported major modes. For an already-open buffer, use `M-x jsx-jedi-mode`.

## Commands

Commands act on the closest matching syntax node at point, using their configurable `jsx-jedi-*-node-types` lists.

### Editing and navigation

| Command | Action |
| --- | --- |
| `jsx-jedi-kill` | Kill a node; handle adjacent commas for objects, properties and required parameters, preserving intervening comments. |
| `jsx-jedi-copy` | Copy a node or comment block to the kill ring. |
| `jsx-jedi-duplicate` | Duplicate a node or comment block, adding separators for properties and objects in arrays or argument lists. |
| `jsx-jedi-empty` | Kill a node's content to the kill ring, retaining its delimiters. Boolean attributes and self-closing elements are unchanged. |
| `jsx-jedi-substitute` | Replace a node's content with text from the kill ring, saving the removed content to the kill ring. |
| `jsx-jedi-zap` | Delete from point to the content's end; do nothing when point is outside that content. |
| `jsx-jedi-comment-uncomment` | Toggle JS/TS comments or standalone JSX child comments. |
| `jsx-jedi-mark` | Select a node. Repeating the command does not expand the selection. |
| `jsx-jedi-avy-word` | Use Avy to jump within the selected node's scope in the current window. |

A comment block is a run of `//` comments on consecutive lines, each alone on its line. Block comments, trailing comments and runs separated by a blank line are handled on their own.

Emptying a required value can leave incomplete code, such as `const value = ;`, for further editing.

JSX duplication and commenting require a JSX children position. Mixed code/comment expressions cannot be uncommented; JSX content containing `*/` cannot be commented out.

Statement duplication rejects unbraced branch and loop bodies, and loop initializers. Use a braced statement block to duplicate within a branch or loop. Expressions receive a separating semicolon when a newline alone would join the original and its copy.

Substitution trims outer whitespace from the kill-ring entry, then inserts it without adding line breaks or changing internal indentation. This preserves return/throw operands and literal content, including nested template strings.

### JSX tags

| Command | Action |
| --- | --- |
| `jsx-jedi-rename-tag` | Rename both opening and closing tags. |
| `jsx-jedi-wrap-tag` | Wrap an element in a new parent tag. |
| `jsx-jedi-unwrap-tag` | Remove the wrapper, preserving child text. |
| `jsx-jedi-hoist-tag` | Replace the parent JSX element with the selected node. |
| `jsx-jedi-toggle-self-closing-tag` | Toggle paired/self-closing form; converting to self-closing removes children. |
| `jsx-jedi-add-attribute` | Add an attribute and place point inside its value. |
| `jsx-jedi-move-to-opening-tag` | Move to the opening tag. |
| `jsx-jedi-move-to-closing-tag` | Move to the closing tag. |

Rename, attributes and self-closing conversion require a named tag. Unwrap and hoist into JavaScript expression positions require a single JSX element; unsupported content is rejected without editing the buffer.

## Configuration

Use `M-x customize-group RET jsx-jedi RET` to edit and save node-selection options. Existing `setq` configuration and temporary `let` bindings also work.

List order does not give a node higher priority. Adding types changes selection, not the command's syntax or separator support. `jsx-jedi-tag-node-types` supports only paired elements/fragments and self-closing elements.

The lists are independent: changing the tag list does not update other lists. Their default expressions read it on initial load or an explicit Customize reset; saved and preconfigured values are preserved.

These additional ranges are supported but disabled by default:

| Option | Add node type | Effect |
| --- | --- | --- |
| `jsx-jedi-copy-node-types`, `jsx-jedi-mark-node-types` | `variable_declaration`, `enum_declaration` | Select `var` or enum declarations instead of a larger enclosing node. |
| `jsx-jedi-empty-node-types` | `object_type` | From the opening `{`, edit type members while keeping the braces. Property names still select their own type. |
| `jsx-jedi-empty-node-types` | `throw_statement` | Edit the thrown expression, preserving adjacent comments and statements. Empty leaves `throw ;` for further editing. |

For example:

```elisp
(with-eval-after-load 'jsx-jedi
  (add-to-list 'jsx-jedi-empty-node-types "object_type"))
```

`empty` and `substitute` share these ranges. Adding smaller Avy targets narrows navigation scope; adding zap containers can delete following members. Enable ranges according to the editing behavior you want.

## Development

From the repository root on macOS or Linux, provision test dependencies once (requires Git, a C compiler and an empty `.test-deps/`):

```sh
bash scripts/setup-test-deps.sh
export JSX_JEDI_AVY_DIR="$PWD/.test-deps/avy"
export JSX_JEDI_GRAMMAR_DIR="$PWD/.test-deps/grammars"

emacs -Q --batch -l scripts/test.el
emacs -Q --batch -l scripts/compile.el
JSX_JEDI_TEST_MODE=compiled emacs -Q --batch -l scripts/test.el
```

Each [script](scripts/) documents its requirements, environment variables and output in its header comment. Tests cover real parsers, configuration save/restore, cancellation, Avy, highlights and command-loop undo/redo. The [CI workflow](.github/workflows/test.yml) defines the Emacs version matrix.

For GUI validation, use [test-jedi.tsx](test-jedi.tsx) with your normal configuration to check prompts and `C-g`, undo/redo, Avy labels and focus, highlight cleanup, and Customize save/reload.

### Performance samples

With the dependency environment above set and bytecode compiled:

```sh
mkdir -p .build
emacs -Q --batch -l scripts/benchmark.el > .build/benchmark-source.jsonl
JSX_JEDI_TEST_MODE=compiled emacs -Q --batch -l scripts/benchmark.el \
  > .build/benchmark-compiled.jsonl
```

The benchmark measures mark, copy and duplicate across file and subtree sizes. Compare runs only on matching machines and dependencies; [scripts/benchmark.el](scripts/benchmark.el) documents sample settings, output and measurement limits.

## License

[GNU General Public License v3.0 or later](LICENSE) (`GPL-3.0-or-later`).
