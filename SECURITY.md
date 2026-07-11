# Security Policy

`cl-weave` is a test framework. Security-sensitive areas include subprocess
isolation, filesystem output paths, snapshot updates, shell-facing CLI
arguments, and CI artifact generation.

## Reporting

Report vulnerabilities privately before publishing details:

1. Open a private vulnerability report through GitHub Security Advisories:
   <https://github.com/takeokunn/cl-weave/security/advisories/new>
2. If that link is unavailable, do not file a public issue with exploit details.
   Open a minimal public issue that asks for a private security contact path and
   omit the reproducer until a private channel is established.

If the issue can be demonstrated with a test case, include the smallest
reproducer, affected command, implementation, operating system, expected
impact, and whether any generated artifact paths or subprocess boundaries are
involved.

## Supported Versions

The project is pre-1.0. Security fixes target the main development line until
versioned release branches exist.
For the current support policy and release expectations, see
[docs/maintenance-policy.md](docs/maintenance-policy.md) and
[docs/support-policy.md](docs/support-policy.md).

## Handling Policy

- Treat arbitrary code execution through user-provided test forms as expected
  behavior of a Lisp test runner, not a vulnerability by itself.
- Treat unintended shell execution, path traversal in generated artifacts,
  unsafe snapshot writes, or subprocess isolation escapes as security issues.
- Keep fixes covered by regression tests whenever the behavior is reproducible.
