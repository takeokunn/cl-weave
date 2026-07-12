# Installation

## With Nix

```sh
nix develop
nix run . -- --help
nix profile install .
perl -e 'alarm 600; exec @ARGV' -- nix flake check
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter spec
```

## Without Cloning The Repository

```sh
nix run github:takeokunn/cl-weave -- --help
nix profile install github:takeokunn/cl-weave
```

The packaged CLI is intended for local use, CI, and AI agents.

## Supported Runtime

`cl-weave` targets SBCL first. Linux and macOS are supported platforms, and
SBCL-specific features such as subprocess isolation and coverage handling are
documented in [Runtime Support](runtime-support.md). A platform is
release-ready only when the ASDF load gate and the relevant CI entrypoints
pass there.

### Capability Matrix

Runtime metadata exposes `capabilityMatrix` so humans and agents can evaluate
framework readiness without guessing from examples. Every advertised
capability has a corresponding readiness entry; highlighted areas include
`vitest-dsl`, `expect-matchers`, `fixtures-and-restarts`, `mocks-and-spies`,
`property-and-mutation`, `structured-reporting`, `watch-and-parallelism`,
`isolation-and-cps`, and `ai-discovery-metadata`.
