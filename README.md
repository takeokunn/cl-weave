# cl-weave

`cl-weave` is a modern Common Lisp testing framework inspired by Vitest and
designed around Lisp's strengths: macros, conditions, dynamic bindings, and
reproducible Nix workflows.

The project is intentionally dependency-free at the core. It should be easy to
run in CI, embed in ASDF projects, and extend from the REPL.

## Status

Early MVP. The current focus is a solid core:

- `describe` / `it` hierarchical test DSL
- `expect` matcher assertions with readable failure reports
- `it-each` compile-time table tests
- `before-all` / `after-all` and `before-each` / `after-each` dynamic fixtures
- `it-skip` / `test-skip` skipped cases
- ASDF system definitions
- spec and S-expression reporters
- non-zero process exit on failure for CI
- safe dynamic global function mocking with `with-mocked-functions`

## Quick Start

```lisp
(defpackage #:example/tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:expect #:it))

(in-package #:example/tests)

(describe "math"
  (it "adds numbers"
    (expect (+ 1 1) :to-be 2))

  (it "compares structures"
    (expect (list :ok 42) :to-equal (list :ok 42))))
```

Run the self-test suite:

```sh
sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

With Nix:

```sh
nix develop
nix flake check
```

## API

### Suites And Cases

```lisp
(describe "suite name"
  (it "case name"
    (expect ...)))
```

`describe` forms can be nested. Tests are registered when the file is loaded.
Because Common Lisp already exports `CL:DESCRIBE`, test packages should import
`cl-weave:describe` with `:shadowing-import-from`.

### Assertions

```lisp
(expect actual :to-be expected)
(expect actual :to-equal expected)
(expect value :to-be-greater-than 10)
(expect value :not :to-be nil)
```

`expect` captures the original S-expression and reports matcher, actual,
expected, negation, and pass metadata through conditions and reporters.

Built-in matchers:

- `:to-be`
- `:to-equal`
- `:to-equalp`
- `:to-be-truthy`
- `:to-be-falsy`
- `:to-be-null`
- `:to-satisfy`
- `:to-be-type-of`
- `:to-contain`
- `:to-be-greater-than`
- `:to-be-greater-than-or-equal`
- `:to-be-less-than`
- `:to-be-less-than-or-equal`
- `:to-throw`
- `:to-expand-to`

### Table Tests

```lisp
(it-each ((1 2 3)
          (13 21 34))
    "adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))
```

`it-each` expands into independent `it` forms at macro expansion time.

### Fixtures

```lisp
(defvar *state*)

(describe "with fixture"
  (before-all
    (setf *state* (make-hash-table)))

  (before-each
    (setf (gethash :trace *state*) nil))

  (after-each
    (remhash :trace *state*))

  (after-all
    (setf *state* nil))

  (it "uses dynamic state"
    (setf (gethash :x *state*) 1)
    (expect (gethash :x *state*) :to-be 1)))
```

`before-all` / `after-all` bodies run once around a suite. `before-each` /
`after-each` bodies run around every test in the current suite and nested suites.

### Skipping

```lisp
(it-skip "documents a pending case" "waiting for upstream behavior")
(test-skip "alias for it-skip")
```

Skipped cases are reported as `:skip` and do not fail `run-all`.

### Mocking

```lisp
(with-mocked-functions (((symbol-function 'now) (lambda () 0)))
  (expect (now) :to-be 0))
```

The original function cells are restored with `unwind-protect`.

### Reporters

```lisp
(cl-weave:run-all :reporter :spec)
(cl-weave:run-all :reporter :sexp)
```

`run-all` returns true when the suite passed and false otherwise.

The `:sexp` reporter is the stable AI-friendly interface. See
`docs/ai-contract.md`.

## Roadmap

MVP quality comes first. The intended direction is:

- structured JSON/JUnit reporters
- snapshot testing
- property-based testing and shrinking
- watch mode based on ASDF dependency information
- subprocess isolation for FFI crash tests
- allocation and performance assertions
- MOP-based architecture checks

## License

MIT
