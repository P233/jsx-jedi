# Changelog

## 0.1.0 — Unreleased

- Added Customize support for the ten node-selection options, preserving existing `setq` and saved settings. Default node-type lists are unchanged.
- Added optional `object_type` and `throw_statement` content ranges for empty/substitute.
- Hardened JSX tag, comment and duplication operations, preserving literal whitespace and grouping multi-step tag edits for undo.
- Fixed content selection when comments precede return/throw values or variable declarators.
- Limited comment blocks to consecutive standalone `//` lines, so trailing comments, block comments and blank-line-separated runs are no longer merged.
- Kept Avy word navigation inside the current window's selected node, regardless of Avy's global window settings or prefix arguments.
- Preserved multiline substitution text without adding line breaks or reindenting literals.
- Rejected duplication in single-statement control-flow positions and separated semicolonless expressions when needed.
- Removed list separators across comments without deleting the comments, with atomic undo and rollback.
- Fixed ancestor selection through nodes with equal source ranges.
- Added parser-backed regression tests, pinned test dependencies, source/bytecode validation, an Emacs CI matrix and batch performance samples.
- Simplified the README and expanded command help and script usage documentation.
- Included the full GPL v3 license and clarified the GPL-3.0-or-later license grant.
