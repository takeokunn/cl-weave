# Community Health

`cl-weave` keeps its GitHub intake surfaces intentionally small and aligned with
the project policy documents. Use the templates under `.github/` as the default
entrypoints for bugs, feature proposals, and pull requests.

## Intake Surfaces

- Bug reports use
  [.github/ISSUE_TEMPLATE/bug_report.md](../../.github/ISSUE_TEMPLATE/bug_report.md)
  and must include `Summary`, `Reproduction`, `Expected Behavior`,
  `Actual Behavior`, `Validation`, and `Additional Context`.
- Feature requests use
  [.github/ISSUE_TEMPLATE/feature_request.md](../../.github/ISSUE_TEMPLATE/feature_request.md)
  and must include `Problem`, `Proposed Change`, `Validation Plan`,
  `Scope Check`, and `Compatibility Notes`.
- Pull requests use
  [.github/pull_request_template.md](../../.github/pull_request_template.md) and
  must include `Summary`, `Validation`, `Compatibility Impact`, and
  `Follow-up Risk`.
- Issue chooser routing lives in
  [.github/ISSUE_TEMPLATE/config.yml](../../.github/ISSUE_TEMPLATE/config.yml) and
  should keep support, security, and reproduction guidance pointed at canonical
  policy documents.
- Review ownership lives in
  [.github/CODEOWNERS](../../.github/CODEOWNERS) and is the default routing source
  for repository-wide review responsibility.

## Canonical References

- Bug intake is anchored to [docs/src/issue-reporting.md](issue-reporting.md).
- Feature intake is anchored to [docs/src/project-scope.md](project-scope.md) and
  [docs/src/support-policy.md](support-policy.md).
- Security-sensitive reports are anchored to [private GitHub security advisories](https://github.com/takeokunn/cl-weave/security/advisories/new).
- Pull request intake is anchored to
  [docs/src/pull-request-template.md](pull-request-template.md).
- Review ownership and process authority are anchored to
  [docs/src/governance.md](governance.md).

Keep these files synchronized with `cl-weave metadata` so agents can discover
the same intake contract without scraping GitHub UI state.
