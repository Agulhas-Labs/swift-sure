# SwiftSure mod (experimental)

An experimental Claude Code mod prototype (TypeScript hooks), used for benchmarking:
`Benchmarks/run.sh --mod-b Distribution/mod` runs an arm with it.

It is not part of any install: not the release bundle or Homebrew. It is unsupported and may
change or go away without notice.

Check it with `claude plugin validate Distribution/mod` and `claude plugin test Distribution/mod`.

Switches: `SWIFT_SURE_MOD=off` turns it off and `SWIFT_SURE_MOD_BASH=on` adds the Bash paragraph; a `mod-off`
file in `$SWIFT_SURE_HOME` (else `~/.swift-sure`) also turns it off. The old names (`SIFT_MOD`, `SIFT_MOD_BASH`,
`SIFT_HOME`, `~/.sift`) are still honoured, and the `sift` alias counts as the binary being on PATH.
