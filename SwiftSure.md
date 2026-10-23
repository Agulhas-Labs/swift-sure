---
paths:
  - "**/*.swift"
---

**Prefer SwiftSure over grepping, globbing or reading Swift source by hand: answer from the index before reading a file,
`where` instead of grep, every build and test through `swift-sure run --`.**

| Reach for | When |
|---|---|
| `digest` | before the first look at a Swift file: a type, path, module or `Type.member`, several per call |
| `where` | where X is defined, who conforms, what calls or overrides it; `where --refs` for a rename or delete sweep (code sites, then `not code`); `where --files` for only which files; `where --decl` for only where it is declared |
| `search` | code by shape, not name (`swift-sure help queries`) |
| `strings` | UI text, to its key or Swift literal |
| `swift-sure run --` | any build or test, from Bash, bare, never piped |
| `swift-sure test` | package or scheme tests, sharded: `--shards N` |

Also `swift-sure affected` (which tests a change could break), `similar`/`dupes`, `build --analyse`, `audit`: `<verb> --help`; `swift-sure help` lists the topics.

Before you report a Swift change done: `swift-sure checkup` (what the change left unproved, and callers it left behind, ranked; it builds and runs nothing).

A cited `File.swift:120` or `:95-135` goes to `digest File.swift:120`, not a guessed `sed -n` window; then Read only the members that matter. Below about 60 lines `digest` returns the source.

The hook answers a Swift lookup in place or lets it through. A denial is not a wall: re-run the same lookup and it is allowed, and a re-run is never held against you.

In a git worktree, pass `--root` to lookups and `swift-sure run` alike, not `cd`. No `swift-sure` tools present: use the CLI if it is on PATH.
