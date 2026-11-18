#!/bin/sh
# Builds the MCP registry bundle for a published release from the release's own tarball, and makes sure
# the release carries it. The registry workflow (.github/workflows/registry.yml) runs this, then publishes
# the server.json it leaves beside the bundle; run by hand it is the fallback if that workflow fails.
#
# Usage:  sh Distribution/registry-release.sh [--dry-run] <tag> <work-directory>
#
# The release's `swift-sure-*-arm64.tar.gz` is downloaded, its binary unpacked (never run), and
# registry-files.sh turns that binary into <work-directory>/out/swift-sure-mcp-<version>.mcpb and
# server.json. The same binary gives the same bundle on this machine, so:
#   - a release without the bundle gets it uploaded;
#   - a release that has it already keeps it, never replaced: the registry entry's checksum is of the bundle
#     the release holds, so server.json is written with the release's own bundle's SHA-256, which is the
#     rebuilt one's where the bytes are identical and the one that matters where a zip tool made them differ.
# --dry-run uploads nothing. `gh` must be authenticated (GH_TOKEN); the repository is $GITHUB_REPOSITORY,
# else the public one.
#
# Exit codes:  0 the bundle is on the release and server.json is written   1 refused or a step failed
set -eu

USAGE="usage: sh Distribution/registry-release.sh [--dry-run] <tag> <work-directory>"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
DRY_RUN=no
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=yes
    shift
fi
TAG="${1:-}"
WORK="${2:-}"
[ -n "$TAG" ] && [ -n "$WORK" ] || { echo "$USAGE" >&2; exit 1; }
printf '%s' "$TAG" | grep -Eqx 'v[0-9]+\.[0-9]+\.[0-9]+' || { echo "error: '$TAG' is not a release tag (vX.Y.Z)" >&2; exit 1; }
VERSION="${TAG#v}"
SLUG="${GITHUB_REPOSITORY:-Agulhas-Labs/swift-sure}"

mkdir -p "$WORK/download" "$WORK/unpacked" "$WORK/existing"
WORK="$(cd "$WORK" && pwd -P)"
gh release download "$TAG" -R "$SLUG" --pattern 'swift-sure-*-arm64.tar.gz' --dir "$WORK/download" --clobber
set -- "$WORK"/download/swift-sure-*-arm64.tar.gz
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "error: $TAG does not have exactly one swift-sure-*-arm64.tar.gz asset" >&2; exit 1; }
tar -xzf "$1" -C "$WORK/unpacked"

BIN="$WORK/unpacked/swift-sure-dist/swift-sure"
[ -x "$BIN" ] || { echo "error: no swift-sure-dist/swift-sure inside $(basename "$1")" >&2; exit 1; }
# The tarball says which version it is, so a tag pointed at the wrong build fails here rather than in the registry.
BUILT="$(sed -n 's/^version=//p' "$WORK/unpacked/swift-sure-dist/BUILD_INFO" 2>/dev/null | head -1)"
[ "$BUILT" = "$VERSION" ] || { echo "error: the tarball is version '$BUILT', the tag is $VERSION" >&2; exit 1; }

sh "$REPO/Distribution/registry-files.sh" "$BIN" "$VERSION" "$WORK/out" > /dev/null
ASSET="swift-sure-mcp-$VERSION.mcpb"
LOCAL="$(shasum -a 256 "$WORK/out/$ASSET" | cut -d' ' -f1)"

if gh release view "$TAG" -R "$SLUG" --json assets --jq '.assets[].name' | grep -Fqx "$ASSET"; then
    gh release download "$TAG" -R "$SLUG" --pattern "$ASSET" --dir "$WORK/existing" --clobber
    PUBLISHED="$(shasum -a 256 "$WORK/existing/$ASSET" | cut -d' ' -f1)"
    if [ "$PUBLISHED" = "$LOCAL" ]; then
        echo "$ASSET is already on $TAG, identical"
    else
        sed -i.bak "s/\"fileSha256\": \"$LOCAL\"/\"fileSha256\": \"$PUBLISHED\"/" "$WORK/out/server.json"
        rm -f "$WORK/out/server.json.bak"
        grep -q "\"fileSha256\": \"$PUBLISHED\"" "$WORK/out/server.json" || { echo "error: could not set the release's bundle checksum in server.json" >&2; exit 1; }
        echo "$ASSET is already on $TAG and differs from the rebuilt one; server.json carries the release's own checksum ($PUBLISHED)"
    fi
elif [ "$DRY_RUN" = yes ]; then
    echo "dry run: would upload $ASSET ($LOCAL) to $TAG"
else
    gh release upload "$TAG" "$WORK/out/$ASSET" -R "$SLUG"
    echo "uploaded $ASSET ($LOCAL) to $TAG"
fi
echo "$WORK/out/server.json"
