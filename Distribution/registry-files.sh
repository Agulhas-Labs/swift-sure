#!/bin/sh
# Prepares the two files the public MCP registry takes for a release: the bundle and the entry describing it.
#
# Usage:  sh Distribution/registry-files.sh <binary> <version> <output-directory>
#
# Writes <product>-mcp-<version>.mcpb (a zip: manifest.json at its root, the binary at bin/<product> with
# its executable bit kept) and server.json (the registry entry, carrying the bundle's SHA-256 and the URL
# the release asset will have). The product word is the binary's own file name, as make-dist.sh names it.
# It publishes nothing and runs no validator: the upload and `mcp-publisher publish` are a person's steps,
# after the asset exists at its URL.
#
# Refusals go to stderr, so a caller that captures stdout still shows them.
# Exit codes:  0 both files written   1 refused (bad arguments) or a step failed
set -eu

BIN="${1:-}"
VERSION="${2:-}"
OUT="${3:-}"
[ -n "$BIN" ] && [ -n "$VERSION" ] && [ -n "$OUT" ] \
    || { echo "usage: sh Distribution/registry-files.sh <binary> <version> <output-directory>" >&2; exit 1; }
[ -f "$BIN" ] && [ -x "$BIN" ] || { echo "error: $BIN is not an executable file" >&2; exit 1; }
printf '%s' "$VERSION" | grep -Eqx '[0-9A-Za-z.+-]+' || { echo "error: '$VERSION' is not a version" >&2; exit 1; }

PRODUCT="$(basename "$BIN")"
ORG=Agulhas-Labs
# The release scripts name the public repository by the product word (Distribution/homebrew/build.sh).
REPO_NAME="$PRODUCT"
ASSET="$PRODUCT-mcp-$VERSION.mcpb"
URL="https://github.com/$ORG/$REPO_NAME/releases/download/v$VERSION/$ASSET"
SERVER_DESCRIPTION="Swift code index for coding agents: type digests, symbol lookup, structural search."
# The format has no architecture field, so the bundle's description says it.
DESCRIPTION="$SERVER_DESCRIPTION The bundle is arm64 only; an Intel Mac is not served by it."
[ "${#SERVER_DESCRIPTION}" -le 100 ] || { echo "error: the registry description is over 100 characters" >&2; exit 1; }

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 1' INT TERM

mkdir -p "$STAGE/bin"
cp "$BIN" "$STAGE/bin/$PRODUCT"
chmod 755 "$STAGE/bin/$PRODUCT"
cat > "$STAGE/manifest.json" <<JSON
{
  "manifest_version": "0.3",
  "name": "$PRODUCT",
  "version": "$VERSION",
  "description": "$DESCRIPTION",
  "author": { "name": "Agulhas Labs" },
  "server": {
    "type": "binary",
    "entry_point": "bin/$PRODUCT",
    "mcp_config": {
      "command": "\${__dirname}/bin/$PRODUCT",
      "args": ["mcp"]
    }
  },
  "compatibility": { "platforms": ["darwin"] }
}
JSON

rm -f "$OUT/$ASSET"
# -X leaves out the extra file attributes; the mode (755) stays in the entry itself.
(cd "$STAGE" && zip -X -q "$OUT/$ASSET" manifest.json "bin/$PRODUCT")

SHA256="$(shasum -a 256 "$OUT/$ASSET" | cut -d' ' -f1)"
cat > "$OUT/server.json" <<JSON
{
  "\$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  "name": "io.github.$ORG/$PRODUCT",
  "description": "$SERVER_DESCRIPTION",
  "version": "$VERSION",
  "packages": [
    {
      "registryType": "mcpb",
      "identifier": "$URL",
      "fileSha256": "$SHA256",
      "transport": { "type": "stdio" }
    }
  ]
}
JSON

echo "$OUT/$ASSET"
echo "$OUT/server.json"
