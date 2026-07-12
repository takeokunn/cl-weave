# Test Execution

## Filtering

```lisp
(cl-weave:run-all :name-filter "math > adds")
```

`name-filter` is a case-insensitive substring matched against the rendered test
path, for example `suite > nested suite > case`. Filtering composes with
`describe-only` and `it-only`: focus narrows the candidate set first, then the
name filter selects matching paths.

For command-line and CI usage, use `--filter`:

```sh
perl -e 'alarm 120; exec @ARGV' -- nix run . -- run cl-weave/tests --filter 'math > adds'
```

Suites with no selected descendants do not run `before-all` or `after-all`, so
filtered runs do not leak fixture side effects from unrelated suites.
By default, a filter that selects zero tests exits successfully. CI jobs that
must reject empty selections can pass `--fail-with-no-tests`, set
`CL_WEAVE_PASS_WITH_NO_TESTS=false`, or call
`(cl-weave:run-all :pass-with-no-tests nil)`.

## Sharding

```lisp
(cl-weave:run-all :shard '(1 3))
(cl-weave:list-tests :reporter :json :shard '(2 3))
```

Shard indexes are one-based and use `(INDEX COUNT)`. cl-weave first applies
focus and `name-filter`, then assigns a stable discovery ordinal to the selected
tests. A test belongs to shard `INDEX` when its ordinal maps to that slot.

For command-line and CI usage, `--shard` uses `INDEX/COUNT`:

```sh
perl -e 'alarm 120; exec @ARGV' -- nix run . -- run cl-weave/tests --shard 1/3 --reporter json
```

Sharding composes with filtering, list mode, bail, ASDF `run-system`, and watch
mode. Suites with no descendants in the requested shard do not run
`before-all` or `after-all`.

## Sequence Ordering

```lisp
(cl-weave:run-all :order :random :seed 12345)
(cl-weave:list-tests :reporter :json :order :random :seed 12345)
```

The default order is `:defined`. `:order :random` applies a deterministic,
seeded order inside each suite while preserving suite hook boundaries. The same
seed produces the same execution order and list-mode order across SBCL
processes.

Selection is resolved before ordering: focus, `name-filter`, and shard choose
the test set first, then sequence ordering decides the order of the remaining
children. This keeps CI shard membership stable when teams rotate seeds to
reproduce order-dependent failures.

For command-line and CI usage:

```sh
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --sequence random --seed 12345
```

## Test Listing

```lisp
(cl-weave:list-tests :reporter :json :name-filter "math")
(cl-weave:collect-test-plan (cl-weave::root-suite) :name-filter "math")
```

List mode discovers selected tests without executing suite hooks or test
bodies. It composes with focus, filtering, skipped suites, and todo suites, and
emits `:run`, `:skip`, or `:todo` plan entries with `path`, `pathString`,
`location`, `reason`, `focused`, `retry`, `timeout-ms`, `concurrent`, `tags`,
and `dependsOn` metadata. `location` records the macro source file when
available; JSON emits `null` for manually constructed tests without source
metadata. `tags` and `dependsOn` are descriptive metadata only; cl-weave does
not infer filtering or dependency ordering from them.

For command-line and CI usage, `list` prints the selected test plan
and exits with status `0`:

```sh
perl -e 'alarm 120; exec @ARGV' -- nix run . -- list cl-weave/tests --reporter json --filter 'math'
```

List mode supports `spec`, `sexp`, `json`, and `jsonl` reporters. `--output FILE`
writes the plan payload to an artifact file.

AI agents can also query plans as plain Lisp facts:

```lisp
(cl-weave:test-plan-where
 (cl-weave:collect-test-plan (cl-weave::root-suite))
 (:status ?test :run)
 (:focused ?test)
 (:concurrent ?test))
;; => (((?test . ("suite" "case"))))
```

`test-plan-facts` emits data such as `(:test path)`, `(:status path status)`,
`:focused`, `:reason`, `:retry`, `:timeout-ms`, `:concurrent`, and `:location`.
`logic-where`, `logic-program`, `logic-run`, and `test-plan-where` keep data and
logic separate: relations stay plain lists, while query and rule syntax stays in
macros. Variables are symbols whose names start with `?`, clauses are matched
left-to-right, and `(:limit n)` caps backtracking results.

Rules use a Prolog-style `(:- head goal...)` form:

```lisp
(let ((program (cl-weave:logic-program
                (:parent "grand" "parent")
                (:parent "parent" "child")
                (:- (:ancestor ?left ?right)
                    (:parent ?left ?right))
                (:- (:ancestor ?left ?right)
                    (:parent ?left ?middle)
                    (:ancestor ?middle ?right)))))
  (cl-weave:logic-run program
    (:ancestor ?left "child")))
;; => (((?left . "parent"))
;;     ((?left . "grand")))
```

`query-test-plan` and `test-plan-where` accept either collected plan entries or
an already-expanded logic program, so derived views can be layered on top of
`test-plan-facts` without a second adapter:

```lisp
(let* ((plan (cl-weave:collect-test-plan (cl-weave::root-suite)))
       (program (append
                 (cl-weave:test-plan-facts plan)
                 (cl-weave:logic-program
                  (:- (:selected ?test)
                      (:status ?test :run)
                      (:focused ?test))))))
  (cl-weave:test-plan-where program
    (:selected ?test)))
```

## Bail

```lisp
(cl-weave:run-all :bail t)
(cl-weave:run-all :bail 2)
```

`:bail t` stops after the first `:fail` or `:error` event. A positive integer
stops after that many failing or errored events. Skips and todos do not count
toward the bail limit.

For command-line and CI usage, `--bail` accepts `true`, `yes`, `on`,
`t`, `false`, `no`, `off`, `0`, `nil`, or a positive integer:

```sh
perl -e 'alarm 120; exec @ARGV' -- nix run . -- run cl-weave/tests --bail 1
```

Bail composes with focus and filtering. Reporters emit only the events that were
selected and executed before the runner stopped.

## Subprocess Isolation

```lisp
(it-isolated "ffi parser rejects invalid input"
    (:systems ("my-project-tests") :timeout 5 :keep-files :on-failure)
  (expect (parse-native-buffer #(0 1 2)) :to-equal :invalid))

(let ((result (run-isolated
               '(error "native boundary failed")
               :systems '("my-project-tests")
               :package "MY-PROJECT/TESTS"
               :timeout 5
               :keep-files :on-failure)))
  (expect (isolated-result-status result) :to-be :fail))
```

`it-isolated` runs the body in a fresh SBCL subprocess and reports non-zero
exits or timeouts as normal structured assertion failures. Use it around FFI,
native parser, and crash-boundary tests where the parent REPL or CI process
must stay alive. `run-isolated` returns captured stdout/stderr strings in all
cases. `:keep-files` accepts `nil`, `t`, or `:on-failure`; the last option keeps
artifacts only for non-passing child processes. When files are retained, the
generated script, stdout, stderr, and temporary HOME directory paths are exposed
via
`isolated-result-script-path`, `isolated-result-stdout-path`,
`isolated-result-stderr-path`, and `isolated-result-home-path`. With the
default `:keep-files nil`, those path accessors return `nil` and the temporary
artifacts are deleted before control returns to the parent process.

## ASDF System Runner And Watch Mode

```lisp
(cl-weave:asdf-system-files "my-project-tests" :include-dependencies t)
(cl-weave:run-system "my-project-tests" :reporter :spec)
(cl-weave:watch-system "my-project-tests"
                       :reporter :json
                       :name-filter "parser"
                       :shard '(1 2)
                       :bail 1
                       :coverage t
                       :coverage-output "my-project-tests.coverage"
                       :pass-with-no-tests t
                       :include-dependencies t
                       :interval 0.5)
```

`asdf-system-files` returns the existing source files declared by an ASDF
system. `run-system` reloads the system with ASDF, then runs the currently
registered cl-weave tests. `watch-system` uses ASDF dependency information and
file write dates to rerun only after declared source files change. When every
changed file is already a registered test-definition file, watch mode narrows
the rerun to those files only. Changes to non-test files, newly added files, or
deleted files fall back to a full-suite rerun so implementation edits cannot
silently skip affected tests.
Coverage collection and `:pass-with-no-tests` policy are forwarded on every
watch rerun, so local watch sessions exercise the same success criteria and
coverage artifact path as an equivalent one-shot `run-all`.
Reporter output goes to `:stream`; watch status goes to `:status-stream`, which
defaults to `*error-output*`.

The script runner enables watch mode with environment variables:

```sh
perl -e 'alarm 360; exec @ARGV' -- nix run . -- watch cl-weave/tests
perl -e 'alarm 360; exec @ARGV' -- nix run . -- watch cl-weave/tests --once
perl -e 'alarm 360; exec @ARGV' -- nix run . -- watch cl-weave/tests --watch-interval 0.25
```

CI should use `run` rather than `watch`, with `--reporter junit`, `tap`,
`json`, or `jsonl` as appropriate.
