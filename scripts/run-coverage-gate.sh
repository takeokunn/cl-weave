#!/bin/sh
set -eu

: "${CL_WEAVE_COVERAGE_FILE:=cl-weave.coverage}"
: "${CL_WEAVE_COVERAGE_REPORT_DIR:=cl-weave-coverage-report/}"
: "${CL_WEAVE_COVERAGE_SUMMARY:=cl-weave-coverage-summary.json}"
: "${CL_WEAVE_COVERAGE_TIMEOUT:=300}"
: "${CL_WEAVE_SBCL_DYNAMIC_SPACE_SIZE:=4096}"
case "$CL_WEAVE_COVERAGE_TIMEOUT" in
  ''|*[!0-9]*)
    echo "CL_WEAVE_COVERAGE_TIMEOUT must be a positive integer number of seconds" >&2
    exit 2
    ;;
  0)
    echo "CL_WEAVE_COVERAGE_TIMEOUT must be greater than zero" >&2
    exit 2
    ;;
esac
case "$CL_WEAVE_SBCL_DYNAMIC_SPACE_SIZE" in
  ''|*[!0-9]*)
    echo "CL_WEAVE_SBCL_DYNAMIC_SPACE_SIZE must be a positive integer number of megabytes" >&2
    exit 2
    ;;
  0)
    echo "CL_WEAVE_SBCL_DYNAMIC_SPACE_SIZE must be greater than zero" >&2
    exit 2
    ;;
esac
export CL_WEAVE_COVERAGE=1
export CL_WEAVE_COVERAGE_FILE
export CL_WEAVE_COVERAGE_REPORT_DIR

timeout -k 5 "$CL_WEAVE_COVERAGE_TIMEOUT" \
  sbcl --dynamic-space-size "$CL_WEAVE_SBCL_DYNAMIC_SPACE_SIZE" \
  --noinform --non-interactive --load scripts/run-tests.lisp
perl scripts/coverage-gate.pl \
  --report-dir "$CL_WEAVE_COVERAGE_REPORT_DIR" \
  --source-dir src \
  --threshold 87 \
  --output "$CL_WEAVE_COVERAGE_SUMMARY"
