# Agent Notes

This repository's `devShell` (see [flake.nix](flake.nix)) provides
[`paredit-cli`](https://github.com/takeokunn/paredit-cli), a structure-editing
CLI for safe S-expression refactoring. When editing `.lisp`/`.asd` files in
this repository — renaming symbols, moving or extracting definitions,
removing unused code, or any other structural change — prefer `paredit
inspect ...` / `paredit refactor ...` over hand-editing balanced delimiters.
Validate with `paredit inspect check --file <path>` after manual edits.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development loop and
[docs/ai-contract.md](docs/ai-contract.md) for this project's own
machine-readable CLI/reporter contracts.
