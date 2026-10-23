#!/bin/sh
# Proves two builds of `swift-sure` install, uninstall, plan and diagnose identically, byte for byte: the safety
# net for a change that moves the agent-install code without meaning to change what it does.
#
# Usage:  sh Distribution/agent-parity.sh <base-binary> <candidate-binary>
#
# Every case runs twice, once per binary, each in its own fresh scratch directory under one temporary
# directory that is removed on exit (set AGENT_PARITY_KEEP=1 to keep it and print where it is). A scratch
# directory holds a fake home (with `.claude`, `.cursor` and `.codex` seeded by the case), a copy of the
# binary under test with a stub `SwiftSure.md` beside it (and a stub `Sift.md`, which a base binary from before
# the rename installs instead), and a `bin/` first on PATH whose fake `claude` and
# `codex` record their arguments and keep their registrations where the real ones do (`.claude.json`,
# `config.toml`), so the success paths run and no real agent does. The environment is built from nothing
# (`env -i`): HOME, CFFIXED_USER_HOME, CLAUDE_CONFIG_DIR, CODEX_HOME, TMPDIR and every SWIFT_SURE_* path switch
# the tool reads point inside the scratch directory; some cases move CLAUDE_CONFIG_DIR, CODEX_HOME or
# CFFIXED_USER_HOME elsewhere inside it, or leave the first two unset. The real ~/.claude, ~/.claude.json,
# ~/.cursor, ~/.codex and ~/.swift-sure are never named.
#
# Compared per case: stdout, stderr and exit code of every step, the fakes' argument logs, and every entry
# under the scratch directory except the binary copy (path, mode, bytes, symlink target). Only two things
# are normalised before comparing:
#   - each run's own scratch root, plain and as JSON escapes slashes (`\/`), replaced by a fixed token,
#     since the two runs cannot share a directory;
#   - the doctor probe's scratch directory name (`swift-sure-doctor-<UUID>`), random on every run.
# The version string is deliberately not normalised: two builds are expected to share one version, and a
# difference there is a finding.
#
# Exit:  0  no case differs
#        1  at least one case differs (its name and a unified diff are printed)
#        2  usage or setup error
set -eu

die() {
    echo "agent-parity: $*" >&2
    exit 2
}

[ "$#" -eq 2 ] || die "usage: sh Distribution/agent-parity.sh <base-binary> <candidate-binary>"
for b in "$1" "$2"; do
    [ -f "$b" ] && [ -x "$b" ] || die "not an executable file: $b"
done
BASE_BIN="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
CAND_BIN="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"

T="$(mktemp -d "${TMPDIR:-/tmp}/agent-parity.XXXXXX")" || die "could not make a scratch directory"
T="$(cd "$T" && pwd -P)" || die "could not enter the scratch directory"
cleanup() {
    if [ -n "${AGENT_PARITY_KEEP-}" ]; then
        echo "agent-parity: kept $T" >&2
    else
        rm -rf "$T"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

W=""
H=""
# The environment a case hands the tool, reset for every side: where CLAUDE_CONFIG_DIR, CODEX_HOME and
# CFFIXED_USER_HOME point, and which of them are left out altogether (`-u NAME` words for env).
ENV_CLAUDE_DIR=""
ENV_CODEX_HOME=""
ENV_CFFIXED=""
ENV_UNSET=""

# Lays out a fresh scratch directory for one side of one case: $W is its root, $H the fake home.
setup_side() {
    W="$T/$1/$2"
    H="$W/home"
    mkdir -p "$H/.claude" "$H/.cursor" "$H/.codex" "$H/.swift-sure" "$W/bin" "$W/swift-sure" "$W/rec" "$W/tmp" || die "setup failed: $W"
    cp "$3" "$W/swift-sure/swift-sure" || die "setup failed: could not copy $3"
    printf '# SwiftSure (parity stub rule)\n' > "$W/swift-sure/SwiftSure.md" || die "setup failed: $W/swift-sure/SwiftSure.md"
    printf '# Sift (parity stub rule)\n' > "$W/swift-sure/Sift.md" || die "setup failed: $W/swift-sure/Sift.md"
    : > "$W/rec/out" && : > "$W/rec/err" && : > "$W/rec/code" || die "setup failed: $W/rec"
    ENV_CLAUDE_DIR="$H/.claude"
    ENV_CODEX_HOME="$H/.codex"
    ENV_CFFIXED="$H"
    ENV_UNSET=""
    write_fakes || die "setup failed: could not write the fakes in $W/bin"
}

# The fake `claude` and `codex`: they record their arguments and keep the registration where the real ones
# do (`.claude.json` under CLAUDE_CONFIG_DIR or HOME; `config.toml` under CODEX_HOME), so a registration
# made by one step is seen by the next, and by the tool's own reading of the file.
write_fakes() {
    cat > "$W/bin/claude" <<'FAKE'
#!/bin/sh
rec="$(dirname "$0")/../rec"
{
    printf 'claude'
    for a in "$@"; do printf ' [%s]' "$a"; done
    printf ' CLAUDE_CONFIG_DIR=%s CODEX_HOME=%s HOME=%s\n' "${CLAUDE_CONFIG_DIR-}" "${CODEX_HOME-}" "${HOME-}"
} >> "$rec/claude.log"
cfg="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
name="${3-swift-sure}"
case "$name" in -*) name=swift-sure ;; esac
absent() { echo "No MCP server found with name: $name" >&2; exit 1; }
case "${1-} ${2-}" in
    "mcp add")
        bin=""
        seen=0
        for a in "$@"; do
            if [ "$seen" = 1 ]; then bin="$a"; break; fi
            if [ "$a" = "--" ]; then seen=1; fi
        done
        printf '{"mcpServers":{"swift-sure":{"type":"stdio","command":"%s","args":["mcp"],"env":{}}}}\n' "$bin" > "$cfg"
        echo "Added stdio MCP server swift-sure to user config"
        ;;
    "mcp remove")
        [ -f "$cfg" ] && grep -q "\"$name\"" "$cfg" || absent
        printf '{"mcpServers":{}}\n' > "$cfg"
        echo "Removed MCP server $name from user config"
        ;;
    "mcp get" | "mcp list")
        [ -f "$cfg" ] && grep -q "\"$name\"" "$cfg" || absent
        echo "$name: registered"
        ;;
esac
exit 0
FAKE
    cat > "$W/bin/codex" <<'FAKE'
#!/bin/sh
rec="$(dirname "$0")/../rec"
{
    printf 'codex'
    for a in "$@"; do printf ' [%s]' "$a"; done
    printf ' CLAUDE_CONFIG_DIR=%s CODEX_HOME=%s HOME=%s\n' "${CLAUDE_CONFIG_DIR-}" "${CODEX_HOME-}" "${HOME-}"
} >> "$rec/codex.log"
home="${CODEX_HOME:-$HOME/.codex}"
cfg="$home/config.toml"
absent() { echo "Error: No MCP server named 'swift-sure' found." >&2; exit 1; }
case "${1-} ${2-}" in
    "mcp add")
        bin=""
        seen=0
        for a in "$@"; do
            if [ "$seen" = 1 ]; then bin="$a"; break; fi
            if [ "$a" = "--" ]; then seen=1; fi
        done
        mkdir -p "$home"
        printf '[mcp_servers.swift-sure]\ncommand = "%s"\nargs = ["mcp"]\n' "$bin" > "$cfg"
        echo "Added global MCP server 'swift-sure'."
        ;;
    "mcp remove")
        [ -f "$cfg" ] && grep -q 'mcp_servers.swift-sure' "$cfg" || absent
        : > "$cfg"
        echo "Removed global MCP server 'swift-sure'."
        ;;
    "mcp get")
        [ -f "$cfg" ] && grep -q 'mcp_servers.swift-sure' "$cfg" || absent
        bin="$(sed -n 's/^command = "\(.*\)"$/\1/p' "$cfg")"
        printf '{"name":"swift-sure","enabled":true,"transport":{"type":"stdio","command":"%s","args":["mcp"],"env":null,"env_vars":[],"cwd":null}}\n' "$bin"
        ;;
esac
exit 0
FAKE
    chmod +x "$W/bin/claude" "$W/bin/codex" || return 1
    : > "$W/rec/claude.log" && : > "$W/rec/codex.log"
}

# Runs the binary under test with the scratch environment, recording one step's output and status.
# ENV_UNSET is deliberately unquoted: it is a list of `-u NAME` words.
sx() {
    echo "\$ swift-sure $*" >> "$W/rec/out"
    echo "\$ swift-sure $*" >> "$W/rec/err"
    code=0
    # shellcheck disable=SC2086
    env -i \
        PATH="$W/bin:/usr/bin:/bin" \
        HOME="$H" \
        CFFIXED_USER_HOME="$ENV_CFFIXED" \
        CLAUDE_CONFIG_DIR="$ENV_CLAUDE_DIR" \
        CODEX_HOME="$ENV_CODEX_HOME" \
        TMPDIR="$W/tmp" \
        SWIFT_SURE_HOME="$H/.swift-sure" \
        SWIFT_SURE_ADVICE_DIR="$H/.swift-sure/advice" \
        SWIFT_SURE_USAGE_LOG="$H/.swift-sure/usage.jsonl" \
        SWIFT_SURE_RUN_LOG="$H/.swift-sure/run.jsonl" \
        SWIFT_SURE_SERVER_LOG="$H/.swift-sure/server.log" \
        SWIFT_SURE_RUN_LEDGER="$H/.swift-sure/ledger.jsonl" \
        /usr/bin/env $ENV_UNSET \
        "$W/swift-sure/swift-sure" "$@" < /dev/null >> "$W/rec/out" 2>> "$W/rec/err" || code=$?
    echo "swift-sure $* -> $code" >> "$W/rec/code"
}

# A file's permission bits, as octal.
mode_of() {
    stat -f '%Lp' "$1" 2> /dev/null || stat -c '%a' "$1"
}

# Everything under the scratch directory except the copy of the binary under test: path, kind, mode, and
# bytes or link target. The fake home, the fakes' state, the tool's temporary directory and anything else a
# run left are all in it.
dump_tree() {
    (cd "$W" && find . -path ./swift-sure -prune -o -print | LC_ALL=C sort) | while IFS= read -r p; do
        if [ -L "$W/$p" ]; then
            echo "L $p -> $(readlink "$W/$p")"
        elif [ -d "$W/$p" ]; then
            echo "D $p $(mode_of "$W/$p")"
        else
            echo "F $p $(mode_of "$W/$p")"
            cat "$W/$p"
            echo "<end $p>"
        fi
    done
}

# $1 escaped for use as a sed pattern between `|` delimiters.
sed_escape() {
    printf '%s' "$1" | sed 's#[].\\*^$|/[]#\\&#g'
}

# One side's results as a single normalised text, ready to diff.
collect() {
    plain="$(sed_escape "$W")"
    json="$(sed_escape "$(printf '%s' "$W" | sed 's#/#\\/#g')")"
    {
        for part in out err code claude.log codex.log; do
            echo "=== $part ==="
            cat "$W/rec/$part"
        done
        echo "=== tree ==="
        dump_tree
    } | sed -E -e "s|$plain|<scratch>|g" -e "s|$json|<scratch>|g" \
        -e 's/(swift-sure|sift)-doctor-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/swift-sure-doctor-<uuid>/g'
}

# ---- cases -------------------------------------------------------------------------------------------

FOREIGN_SETTINGS='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/other-hook"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"/usr/local/bin/other-start"}]}]},"statusLine":{"type":"command","command":"/usr/local/bin/other-status"},"permissions":{"allow":["Bash(ls:*)"]}}'

case_claude_install_empty() {
    echo '{}' > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
}

case_claude_install_rerun() {
    echo '{}' > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
}

case_claude_install_foreign() {
    echo "$FOREIGN_SETTINGS" > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --allow-lookups
}

case_claude_install_over_older() {
    echo '{}' > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --command /opt/old/bin/sift --allow-run
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
}

case_claude_install_symlinked_settings() {
    mkdir -p "$H/elsewhere"
    echo "$FOREIGN_SETTINGS" > "$H/elsewhere/real-settings.json"
    ln -s "$H/elsewhere/real-settings.json" "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --no-allow-run
}

case_claude_install_over_npx_server() {
    echo '{}' > "$H/.claude/settings.json"
    echo '{"mcpServers":{"sift":{"type":"stdio","command":"npx","args":["-y","@agulhas-labs/sift","mcp"],"env":{}}}}' > "$ENV_CLAUDE_DIR/.claude.json"
    sx install --agent claude --dry-run
}

case_cursor_install_empty() {
    sx install-hook --agent cursor --cursor-dir "$H/.cursor"
}

case_cursor_install_foreign() {
    echo '{"mcpServers":{"other":{"command":"/usr/local/bin/other","args":["serve"]}}}' > "$H/.cursor/mcp.json"
    echo '{"version":1,"hooks":{"preToolUse":[{"command":"/usr/local/bin/other-hook"}]}}' > "$H/.cursor/hooks.json"
    sx install-hook --agent cursor --cursor-dir "$H/.cursor"
}

case_codex_install() {
    sx install-hook --agent codex --codex-dir "$H/.codex"
}

case_uninstall_after_install() {
    echo "$FOREIGN_SETTINGS" > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
    sx uninstall-hook --settings "$H/.claude/settings.json"
}

case_uninstall_nothing_installed() {
    echo "$FOREIGN_SETTINGS" > "$H/.claude/settings.json"
    sx uninstall-hook --settings "$H/.claude/settings.json"
}

case_uninstall_cursor_after_install() {
    sx install-hook --agent cursor --cursor-dir "$H/.cursor"
    sx uninstall-hook --agent cursor --cursor-dir "$H/.cursor"
}

case_install_dry_run_all() {
    echo "$FOREIGN_SETTINGS" > "$H/.claude/settings.json"
    sx install --dry-run --all
}

case_install_all() {
    echo '{}' > "$H/.claude/settings.json"
    sx install --all --allow-run
}

case_doctor_json_after_claude_install() {
    echo '{}' > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
    sx doctor --agent claude --json
}

case_doctor_text_after_claude_install() {
    echo '{}' > "$H/.claude/settings.json"
    sx install-hook --settings "$H/.claude/settings.json" --allow-run
    sx doctor --agent claude
}

case_env_claude_config_dir_elsewhere() {
    ENV_CLAUDE_DIR="$H/elsewhere-claude"
    mkdir -p "$ENV_CLAUDE_DIR"
    echo "$FOREIGN_SETTINGS" > "$ENV_CLAUDE_DIR/settings.json"
    sx install --all --allow-run
    sx doctor --agent claude
}

case_env_claude_config_dir_unset() {
    ENV_UNSET="-u CLAUDE_CONFIG_DIR"
    echo '{}' > "$H/.claude/settings.json"
    sx install --all --allow-run
    sx uninstall-hook
}

case_env_codex_home_elsewhere() {
    ENV_CODEX_HOME="$H/elsewhere-codex"
    mkdir -p "$ENV_CODEX_HOME"
    sx install-hook --agent codex
    sx uninstall-hook --agent codex
}

case_env_codex_home_unset() {
    ENV_UNSET="-u CODEX_HOME"
    sx install-hook --agent codex
}

case_env_cffixed_differs_from_home() {
    ENV_CFFIXED="$W/cffixed-home"
    mkdir -p "$ENV_CFFIXED/.claude" "$ENV_CFFIXED/.cursor" "$ENV_CFFIXED/.codex"
    echo '{}' > "$ENV_CFFIXED/.claude/settings.json"
    echo '{}' > "$H/.claude/settings.json"
    sx install --all --allow-run
}

CASES="
claude_install_empty
claude_install_rerun
claude_install_foreign
claude_install_over_older
claude_install_symlinked_settings
claude_install_over_npx_server
cursor_install_empty
cursor_install_foreign
codex_install
uninstall_after_install
uninstall_nothing_installed
uninstall_cursor_after_install
install_dry_run_all
install_all
doctor_json_after_claude_install
doctor_text_after_claude_install
env_claude_config_dir_elsewhere
env_claude_config_dir_unset
env_codex_home_elsewhere
env_codex_home_unset
env_cffixed_differs_from_home
"

TOTAL=0
DIFFER=0
REPORT="$T/report"
: > "$REPORT"

for c in $CASES; do
    TOTAL=$((TOTAL + 1))
    setup_side "$c" base "$BASE_BIN"
    "case_$c" || die "case $c failed to run"
    collect > "$T/$c.base" || die "case $c: could not collect"
    setup_side "$c" cand "$CAND_BIN"
    "case_$c" || die "case $c failed to run"
    collect > "$T/$c.cand" || die "case $c: could not collect"
    if ! cmp -s "$T/$c.base" "$T/$c.cand"; then
        DIFFER=$((DIFFER + 1))
        {
            echo "--- differs: $c"
            diff -u -L "base/$c" -L "candidate/$c" "$T/$c.base" "$T/$c.cand" || true
        } >> "$REPORT"
    fi
done

echo "parity: $TOTAL cases, $DIFFER differ"
if [ "$DIFFER" -gt 0 ]; then
    cat "$REPORT"
    exit 1
fi
