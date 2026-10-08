# Changelog

## 0.1.0 — Unreleased

- Added Customize support for the ten node-selection options, preserving existing `setq` and saved settings. Default node-type lists are unchanged.
- Added optional `object_type` and `throw_statement` content ranges for empty/substitute.
- Kept entry endings and trailing whitespace before delimiters on the current entry across structural commands; commenting also includes commas separated by whitespace or comments.
- Limited empty/substitute to the statement or comment at point, so a nested statement no longer empties its enclosing block, and reported when there is no content instead of doing nothing. A block statement's header now empties its own block, and an unclosed block is never emptied to the end of the buffer.
- Hardened JSX tag, comment and duplication operations, preserving literal whitespace and grouping multi-step tag edits for undo.
- Fixed content selection when comments precede return/throw values or variable declarators.
- Limited comment blocks to consecutive standalone `//` lines, so trailing comments, block comments and blank-line-separated runs are no longer merged.
- Kept Avy word navigation inside the current window's selected node, regardless of Avy's global window settings or prefix arguments.
- Preserved multiline substitution text without adding line breaks or reindenting literals.
- Rejected duplication in single-statement control-flow positions and separated semicolonless expressions when needed.
- Prevented duplication from expanding abbreviations or auto-filling the original statement.
- Removed list separators across comments without deleting the comments, with atomic undo and rollback.
- Fixed ancestor selection through nodes with equal source ranges.
- Added parser-backed regression tests, pinned test dependencies, source/bytecode validation, an Emacs CI matrix and batch performance samples.
- Simplified the README and expanded command help and script usage documentation.
- Included the full GPL v3 license and clarified the GPL-3.0-or-later license grant.
