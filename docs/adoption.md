# Adoption Guide

This guide covers the shortest path from an existing Common Lisp test setup to
`cl-weave`.

## Recommended Shape

Keep the integration surface small:

1. Add `cl-weave` to the ASDF dependencies of the system that owns the tests.
2. Import only the symbols you use, usually `describe`, `it`, `expect`, and
   focused helpers such as `it-property`, `it-isolated`, or `with-snapshot-updates`.
3. Keep one non-interactive command for local use and CI.
4. Keep one machine-readable command for automation and AI tooling.
5. Expose both through Nix if the project already uses flakes.

## Minimal ASDF Wiring

Do not migrate a downstream project until `cl-weave` itself passes the ASDF load
gate documented in [runtime-support.md](runtime-support.md). A targeted source
check is not enough evidence for adoption because downstream projects load the
framework through ASDF.

```lisp
(asdf:defsystem #:my-project-tests
  :depends-on (#:cl-weave)
  :components ((:file "tests/package")
               (:file "tests/main")))
```

```lisp
(defpackage #:my-project/tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:expect
                #:it
                #:it-property
                #:it-isolated))
```

## Minimal Test Migration

FiveAM-style tests usually map cleanly to the core DSL:

```lisp
;;;; before
(fiveam:test math/adds)

;;;; after
(describe "math"
  (it "adds numbers"
    (expect (+ 1 1) :to-be 2)))
```

Migrate suite-by-suite rather than rewriting everything at once. That lets you
keep existing test investment while introducing snapshots, properties, mutation
checks, or isolation only where they help.

## Native Migration Surface

`cl-weave` no longer carries a compatibility registration layer. Migrations
should move directly onto the native suite DSL:

- `describe`
- `it`
- `test`
- `describe-each`
- `it-each`
- `test-each`
- `before-all`
- `before-each`
- `around-each`
- `after-each`
- `after-all`
- `expect`
- `expect.not`
- `run`
- `explain!`
- `results-status`

The assertion and fixture helpers below remain part of the supported API
because they encode reusable testing semantics rather than framework-specific
compatibility:

- `assert-true`
- `assert-false`
- `assert-equal`
- `assert-eq`
- `assert-eql`
- `assert-=`
- `assert-bool`
- `assert-set-equal`
- `assert-string=`
- `assert-string-contains`
- `assert-list-contains`
- `assert-monotonic-increasing`
- `assert-monotonic-decreasing`
- `assert-null`
- `assert-not-null`
- `assert-type`
- `assert-type-equal`
- `assert-values`
- `assert-signals`
- `assert-no-signals`
- `assert-within-tolerance`
- `assert-within-tolerance-percent`
- `with-replaced-function`
- `with-restored-binding`
- `with-restored-bindings`
- `with-restored-hash-table`
- `with-cleared-hash-table`

Predicate-style helper aliases remain exported as thin matcher wrappers for
suites migrating from assertion-per-predicate frameworks:

- `is-equal`
- `is-not-equal`
- `is-eq`
- `is-not-eq`
- `is-real`
- `is-keyword`
- `is-integer`
- `is-number`
- `is-float`
- `is-symbol`
- `is-double-float`
- `is-near`
- `is-list`
- `is-member`
- `is-not-member`
- `is-fact`
- `is-nil`
- `is-non-nil`
- `is-positive`
- `is-negative`
- `is-zero`
- `is-between`
- `is-empty`
- `is-finite`
- `is-string`
- `is-string-contains`
- `is-type`
- `is-record`
- `is-every`

Property-style migrations should target `cl-weave`'s native property surface
directly:

- `it-property`
- `gen-integer`
- `gen-string`
- `gen-list`
- `gen-map`
- `gen-vector`
- `gen-state-machine`

If an existing suite still depends on legacy registration macros, migrate it by
rewriting registration shape first and preserving only semantic metadata such as
timeouts, tags, and dependency labels. In native `cl-weave`, `:timeout-ms`,
`tags`, and `dependsOn` remain descriptive metadata; they do not enforce
execution ordering or filtering. Keep behavior-sensitive ordering in the suite
structure or runner command until those semantics are explicitly redesigned.

The state-restoration helpers above stay in scope because they encode generic
test-fixture semantics rather than project logic: temporary function
replacement, dynamic binding restoration, and hash-table snapshot/reset flows
can migrate directly onto `cl-weave` without preserving a downstream wrapper
layer.

The compatibility layer intentionally stops at generic testing semantics.
Project-specific helpers, such as compiler assertions or domain fixtures,
should remain in the downstream project and call `cl-weave` assertions
internally during migration.

## Nix Entry Points

For flakes, expose the same test entrypoint through both local shells and CI.
The repository already demonstrates the pattern:

```sh
nix develop
nix run . -- --help
nix run . -- run cl-weave-tests --reporter json --output cl-weave-results.json
```

If a project already has a flake, mirror those commands for the project's test
system name so `nix develop` and CI execute the same path.

## CI And Agents

Prefer the metadata command in automation instead of scraping README prose or
reporter examples:

```sh
nix run . -- metadata cl-weave-tests --reporter json --output cl-weave-metadata.json
```

Use the machine-readable reporters for CI gates:

```sh
nix run . -- run cl-weave-tests --reporter json --output cl-weave-results.json
nix run . -- watch cl-weave-tests --once --reporter json --output cl-weave-watch-once.json
nix run . -- list cl-weave-tests --reporter json --output cl-weave-plan.json
```
