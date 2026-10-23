#!/bin/sh
# Prints the plugin marketplace file the public repository carries at .claude-plugin/marketplace.json.
#
# Usage:  sh Distribution/marketplace-file.sh <product>
#
# The marketplace is named <product>-plugins, never the product word itself: the legacy local marketplace
# that install and uninstall remove already used the bare word. The plugin's root is Distribution/plugin/,
# so the install is `claude plugin install <product>@<product>-plugins`. Distribution/cut-public-repo.sh
# writes the output into the cut; nothing is published here.
#
# Exit codes:  0 printed   1 refused (no product word)
set -eu

PRODUCT="${1:-}"
printf '%s' "$PRODUCT" | grep -Eqx '[a-z][a-z0-9-]*' || { echo "usage: sh Distribution/marketplace-file.sh <product>"; exit 1; }

cat <<JSON
{
  "name": "$PRODUCT-plugins",
  "owner": { "name": "Agulhas Labs" },
  "plugins": [
    {
      "name": "$PRODUCT",
      "source": "./Distribution/plugin",
      "description": "Swift code index for coding agents: type digests, symbol lookup, structural search."
    }
  ]
}
JSON
