# Pull Request Template

Use this template when opening a pull request for `cl-weave`.

## Summary

What changed and why:

## Related Issue Or Policy

Link the issue, policy, or contract that motivated the change:

## Validation

List the commands you ran:

- `timeout 360s nix run . -- run cl-weave/tests`
- `timeout 600s nix flake check --print-build-logs`
- any narrower command that directly exercises the change

## Public Surface Impact

State whether this is additive, behavior-preserving, or intentionally
breaking for the public surface:

## Follow-up Risk

Call out any remaining risk, unsupported edge case, or intentional follow-up:

## Notes For Reviewers

Use this space for implementation details, migration notes, or follow-up work:
