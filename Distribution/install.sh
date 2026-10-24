#!/bin/sh
# Installs swift-sure on this machine and registers it with Claude Code where Claude Code is found.
# Safe to re-run: that is the upgrade path.
set -eu

# The name this bundle installs under, and the names earlier releases shipped under (space-separated, newest first): each is linked to $NAME so an old command keeps working.
# Pinned to ProductName by a test.
NAME=swift-sure
LEGACY_NAMES="sift"
# Further command names for the same binary (space-separated), linked like the legacy ones; not earlier products.
ALIAS_NAMES=""

# The only flags: --run-only (the build and test hooks alone; without it, the full set: server, rule, primer and lookup
# hooks) and the two that answer the allow-rule questions without a terminal, all handed to `install-hook` as given.
# Anything else is refused before a byte is written, and so is --allow-lookups with --run-only (run mode has no lookups).
index=1
lookups=0
for flag in "$@"; do
    case "$flag" in
        --run-only) index=0 ;;
        --allow-lookups) lookups=1 ;;
        --allow-run) ;;
        *) echo "error: unknown option $flag (usage: sh install.sh [--run-only] [--allow-run] [--allow-lookups])"; exit 2 ;;
    esac
done
if [ "$lookups" = 1 ] && [ "$index" = 0 ]; then
    echo "error: --allow-lookups adds the lookup rules and --run-only registers no lookups; drop one (usage: sh install.sh [--run-only] [--allow-run] [--allow-lookups])"
    exit 2
fi
# The install command the closing lines name for Cursor and Codex, in the mode this run installed.
install_command="swift-sure install"
if [ "$index" = 0 ]; then
    install_command="swift-sure install --run-only"
fi

# SIFT_DEST is the name an earlier release read; it applies where SWIFT_SURE_DEST is unset.
DEST="${SWIFT_SURE_DEST:-${SIFT_DEST:-$HOME/.local/bin}}"
RULES="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/$NAME"

[ -f "$SRC" ] || { echo "error: $NAME not found next to this script"; exit 1; }

mkdir -p "$DEST"

# Strip quarantine if the bundle arrived by download or AirDrop. The binary is
# ad-hoc signed (no Developer ID), so a quarantine flag makes Gatekeeper refuse it.
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

# NEVER cp over a running/installed binary in place — macOS caches code signatures by inode, so
# writing new bytes into the old inode gets the process SIGKILLed on launch (exit 137, no error
# message). Copy to a temp name in the same directory (so the final `mv` is same-volume and atomic),
# then rename it over the destination: the rename gives the new binary its own inode, and there is
# never a moment with no binary at all — unlike `rm` then `cp`, which has a window where $DEST/$NAME
# does not exist. Clean the temp file up if anything below fails.
TMP="$DEST/.$NAME.$$"
trap 'rm -f "$TMP"' EXIT
cp "$SRC" "$TMP"
chmod +x "$TMP"
mv -f "$TMP" "$DEST/$NAME"
trap - EXIT

echo "installed: $DEST/$NAME ($("$DEST/$NAME" --version))"
for legacy in $LEGACY_NAMES; do
    ln -sfn "$NAME" "$DEST/$legacy"
    echo "linked: $DEST/$legacy -> $NAME (the name an earlier release shipped under)"
done
for alias in $ALIAS_NAMES; do
    ln -sfn "$NAME" "$DEST/$alias"
    echo "linked: $DEST/$alias -> $NAME (another name for it)"
done

# One line in the deploy log for this install: when, which build, how big. Best effort by design: a missing
# BUILD_INFO writes null fields, and a log that cannot be written never fails the install. The state directory
# is resolved as the binary resolves it: SWIFT_SURE_HOME (else the earlier SIFT_HOME), else the hidden directory under
# CFFIXED_USER_HOME, else HOME. Of the hidden directories, the current name's where it exists, else a legacy name's
# where that exists, else the current name's: an old one is used, not moved.
record_deploy() {
    home_override="${SWIFT_SURE_HOME:-${SIFT_HOME:-}}"
    case "$home_override" in
        /*) state="$home_override" ;;
        *) case "${CFFIXED_USER_HOME:-}" in
            /*) base="$CFFIXED_USER_HOME" ;;
            *) base="$HOME" ;;
        esac
        state="$base/.$NAME"
        if [ ! -d "$state" ]; then
            for legacy in $LEGACY_NAMES; do
                if [ -d "$base/.$legacy" ]; then state="$base/.$legacy"; break; fi
            done
        fi ;;
    esac
    info="$HERE/BUILD_INFO"
    field() {
        value=""
        [ -f "$info" ] && value="$(sed -n "s/^$1=//p" "$info" | head -1 | tr -cd 'A-Za-z0-9._+-')"
        if [ -n "$value" ]; then printf '"%s"' "$value"; else printf 'null'; fi
    }
    size="$(wc -c < "$DEST/$NAME" | tr -d ' ')"
    case "$size" in '' | *[!0-9]*) size=null ;; esac
    mkdir -p "$state"
    printf '{"ts":"%s","version":%s,"commit":%s,"sourceTree":%s,"tree":%s,"binarySize":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(field version)" "$(field commit)" "$(field sourceTree)" "$(field tree)" "$size" \
        >> "$state/deploys.jsonl"
}
record_deploy 2>/dev/null || echo "note: could not record this install in the deploy log"

case ":$PATH:" in
    *":$DEST:"*) ;;
    *) echo "warning: $DEST is not on PATH — add it to your shell profile" ;;
esac

# Claude Code is found by the two signs `swift-sure install` uses: `claude` on PATH, or its configuration directory
# (CLAUDE_CONFIG_DIR when set and non-empty, else ~/.claude) already there. Decided once, before anything is written
# under that directory: writing the rule or the hooks would itself make a later `swift-sure install` count Claude Code as
# found on a machine that only has Cursor or Codex.
claude_found=0
if command -v claude >/dev/null 2>&1 || [ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ]; then
    claude_found=1
fi

if [ "$claude_found" = 1 ]; then

if [ "$index" = 0 ]; then
    # --run-only: no rule and no server. One an earlier (index) install left comes out; a symlink is the checkout's own file and stays.
    if [ -L "$RULES/$NAME.md" ]; then
        echo "rule: $RULES/$NAME.md is a symlink to $(readlink "$RULES/$NAME.md") — left as is"
    elif [ -f "$RULES/$NAME.md" ]; then
        rm -f "$RULES/$NAME.md"
        echo "rule: removed $RULES/$NAME.md (--run-only)"
    fi
    if command -v claude >/dev/null 2>&1; then
        removed=0
        claude mcp remove $NAME --scope user >/dev/null 2>&1 && removed=1
        claude mcp remove $NAME >/dev/null 2>&1 && removed=1
        if [ "$removed" = 1 ]; then
            echo "mcp: not registered (--run-only; the previous registration was removed)"
        else
            echo "mcp: not registered (--run-only; 'claude mcp remove' removed nothing, so a previous registration could not be confirmed gone: check 'claude mcp list')"
        fi
    else
        echo "note: 'claude' not on PATH — if the server was registered by an earlier install, remove it manually with:"
        echo "  claude mcp remove $NAME --scope user"
    fi
else

# Agent guidance as a path-scoped user rule: one install for every repo on this machine, no repo
# commits anything, and the `paths:` frontmatter keeps it out of context unless Swift is in play.
mkdir -p "$RULES"
if [ -L "$RULES/$NAME.md" ]; then
    # A symlink means this machine has the SwiftSure checkout and the rule IS the repo file.
    # `cp` would follow the link and write *through* it into the working tree — silently reverting
    # a newer checkout to whatever this bundle happens to carry. Leave it; the checkout is the
    # fresher source by construction.
    echo "rule: $RULES/$NAME.md is a symlink to $(readlink "$RULES/$NAME.md") — left as is"
else
    cp "$HERE/SwiftSure.md" "$RULES/$NAME.md"
    echo "rule: $RULES/$NAME.md (loads on **/*.swift)"
fi

# The server is registered before `install-hook` runs: `install-hook` also tidies what the earlier release left,
# and removes that release's server only once this one is registered, so the other order left both registered after one upgrade.
# Nothing else here depends on the order: the registration needs only the installed binary, and the hooks need only the rule.
if command -v claude >/dev/null 2>&1; then
    # `claude mcp add` FAILS when the name is already registered, so an upgrade must remove first.
    # Both removals are unconditional and swallowed: user scope is where this script registers, and
    # the scopeless pass clears a local- or project-scope registration left by an earlier manual
    # `claude mcp add`. Either failing means "wasn't there", which is exactly what we want.
    claude mcp remove $NAME --scope user >/dev/null 2>&1 || true
    claude mcp remove $NAME >/dev/null 2>&1 || true

    # --scope MUST come before the `--`, or it is passed through to the binary
    # as an argument instead of being read by claude.
    claude mcp add --transport stdio --scope user $NAME -- "$DEST/$NAME" mcp
    echo "mcp: registered at user scope (any previous registration was replaced)"
else
    echo "note: 'claude' not on PATH — register manually with:"
    echo "  claude mcp add --transport stdio --scope user $NAME -- '$DEST/$NAME' mcp"
fi

fi

# The SessionStart primer (index mode). The rule above cannot arrive in time on its own: `paths: ["**/*.swift"]`
# fires when a Swift file is *touched*, so "reach for a digest instead of reading the file" lands one
# step after the read it was meant to replace. A hook is the only delivery guaranteed to precede the
# model's first turn.
#
# Registered by the binary rather than by this script: settings.json holds the user's whole Claude Code
# configuration, it is shared with hooks this project does not own, and a corrupt write breaks every
# session on the machine. The merge is covered by the test suite and needs no python3/jq on the host.
#
# No allow-rule flag of its own: `install-hook` asks the lookups question (default yes, or no after a
# remembered no) and then the builds question (default no) on the terminal this script was started from.
# Where there is none it asks nothing and adds nothing, and its output names the command that adds them.
# Run as `sh install.sh --allow-run` (both blocks) or `--allow-lookups` (the lookups alone), the flags
# given here, checked above, answer for it.
"$DEST/$NAME" install-hook "$@"

else
    echo "Claude Code not found (no 'claude' on PATH, no Claude directory): its rule, hooks and server were skipped. Run '$install_command' to set swift-sure up in Cursor or Codex, or install Claude Code and re-run install.sh to set it up there."
    # --run-only is carried into the command named above; the allow flags are Claude Code's alone.
    for flag in "$@"; do
        [ "$flag" = "--run-only" ] && continue
        echo "note: $flag applies only to Claude Code and was ignored"
    done
fi

# An older install copied a Claude Code band (the `sift-band` plugin) to ~/.local/share/sift and served it from a local
# marketplace beside it. `install-hook` above has already uninstalled the plugin and that marketplace through
# `claude plugin`; what is left on disk is the folder and the marketplace file this script wrote. The one fixed
# path only, and only where its manifest names the band, so nothing else is ever deleted; the marketplace file
# likewise only where it is the one that named the band.
LEGACY_MOD="$HOME/.local/share/sift/sift-mod"
if [ -f "$LEGACY_MOD/.claude-plugin/plugin.json" ] && grep -q '"name": *"sift-band"' "$LEGACY_MOD/.claude-plugin/plugin.json"; then
    rm -rf "${LEGACY_MOD:?}"
    echo "band: removed $LEGACY_MOD (sift no longer draws a band; run 'swift-sure report' to see what it did)"
fi
LEGACY_MARKET="$(dirname "$LEGACY_MOD")/.claude-plugin/marketplace.json"
if [ -f "$LEGACY_MARKET" ] && grep -q '"sift-band"' "$LEGACY_MARKET"; then
    rm -f "$LEGACY_MARKET"
    rmdir "$(dirname "$LEGACY_MARKET")" 2>/dev/null || true
    echo "band: removed $LEGACY_MARKET"
fi

echo
if [ "$claude_found" = 1 ]; then
    if [ "$index" = 1 ]; then
        echo "Mode: index (the build and test hooks plus the index: server, rule, primer, lookups). Re-run with --run-only for build and test only."
        echo "Next: cd into a Swift repo and run 'swift-sure status'. The first query indexes it."
    else
        echo "Mode: run-only (the build and test hooks only: no server, no rule, no primer). Re-run without --run-only to add the index."
        echo "Next: build and test through 'swift-sure run -- <command>' in a Swift repo."
    fi
    echo "On an upgrade a running Claude Code session's server re-execs into the new binary and the hooks apply at once."
    if [ "$index" = 1 ]; then
        echo "After a first install, and for the session primer, the tool list and the rule file, start a NEW session."
    else
        echo "After a first install, start a NEW session for the hooks to apply."
    fi
    echo "Cursor and Codex: run '$install_command' to set swift-sure up in them as well (it finds each and asks once)."
else
    echo "Next: run '$install_command' to set swift-sure up in the agents found on this machine, then cd into a Swift repo and run 'swift-sure status'."
fi
echo "Read INSTALL.md for configuration and troubleshooting."
