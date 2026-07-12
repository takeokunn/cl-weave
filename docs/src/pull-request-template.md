# Pull Request Template

Use this template when opening a pull request for `cl-weave`.

## Summary

What changed and why:

## Related Issue Or Policy

Link the issue, policy, or contract that motivated the change:

## Validation

List the commands you ran:

- `perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests`
- `perl -e 'alarm 600; exec @ARGV' -- nix flake check --print-build-logs`
- any narrower command that directly exercises the change

## Compatibility Impact

State whether this is additive, behavior-preserving, or intentionally
breaking:

## Follow-up Risk

Call out any remaining risk, unsupported edge case, or intentional follow-up:

## Notes For Reviewers

Use this space for implementation details, migration notes, or follow-up work:
