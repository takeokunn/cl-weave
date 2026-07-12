# Distribution Policy

`cl-weave` publishes a small set of canonical distribution channels. This
document defines what each channel is for, how maintainers verify it, and which
integrity guarantees are intentionally out of scope.

## Canonical Channels

The machine-readable source of truth is `distributionChannels` in
`cl-weave metadata`. Human-facing documentation should describe the same three
channels:

- `source-self-test`: run `nix run . -- run cl-weave/tests` from a source
  checkout to validate the bundled ASDF test suite.
- `nix-local-cli`: install with `nix profile install .` from the current
  checkout root, then run `nix run . -- --help` to validate the packaged CLI.
- `nix-remote-cli`: run `nix profile install github:takeokunn/cl-weave` and
  `nix run github:takeokunn/cl-weave -- --help` to validate the packaged CLI
  fetched from the repository reference.

## Verification Expectations

- Keep `README.md`, `docs/ai-contract.md`, and metadata `distributionChannels`
  synchronized when install or run commands change.
- Run the source checkout path before release so the repository still passes its
  bundled self-test suite.
- Run the local Nix packaging path before release so the packaged CLI still
  starts with the documented entrypoint.
- Run the remote Nix packaging path when validating release-facing install
  guidance or repository reference changes.
- Treat `nix flake check --print-build-logs` as the packaging regression gate
  when Nix is available.
- Do not describe a channel as release-ready while ASDF loading, source
  self-tests, or documented CLI entrypoints time out. Record the failing gate in
  `README.md` or `docs/runtime-support.md` before publishing adoption guidance.

## Integrity And Scope

- `cl-weave` does not currently publish separate signed tarballs, detached
  signatures, SBOMs, or provenance attestations outside the source repository
  and Nix build graph.
- The canonical integrity boundary is the version-controlled source tree plus
  the reproducible Nix packaging path defined in `flake.nix`.
- If maintainers add another public distribution channel later, update this
  document, the metadata contract, and release-process checks in the same patch.
