---
name: swift-sure
description: Use when reading, searching, building or testing Swift code: answer from the SwiftSure index instead of grepping or reading files by hand, and run every build and test as swift-sure run -- <command> from Bash, in the foreground, never piped.
---

**Prefer SwiftSure over grepping or reading Swift by hand: `where` instead of grep, `digest` before a Read, every build and test through `swift-sure run --`, bare, never piped.**

| Reach for | When |
|---|---|
| `digest` | a type, file, module or `Type.member`, several per call; below about 60 lines it returns the source |
| `where` | definition (`--decl` for only that), callers, conformers, overrides; `--refs` for a rename or delete sweep, `--files` for only which files |
| `search` | code by shape, not name (`swift-sure help queries`) |
| `strings` | UI text, to its key or Swift literal |

A cited `File.swift:120` or `:95-135` goes to `digest File.swift:120`, not a guessed `sed -n` window.

The hook answers a Swift lookup in place or lets it through. A denial is not a wall: re-run the same lookup and it is allowed, and a re-run is never held against you.

`swift-sure test`, `affected` and the rest: `<verb> --help`; `swift-sure help` lists the topics. In a git worktree, pass `--root`, not `cd`, and `root:` (its absolute path) on every lookup.
