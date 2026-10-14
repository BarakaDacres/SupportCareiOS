#!/usr/bin/env bash
# Regenerates SupportCareKit/Tests/SupportCareCoreTests/web_fixtures.json by running the web app's
# own TypeScript pay/invoice code under Node.
# Usage: scripts/generate_parity_fixtures.sh /path/to/supportcare (the Lovable web repo)
set -euo pipefail
WEB="${1:?path to supportcare web repo}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
cp "$HERE/web_parity_fixtures.ts" "$TMP/gen.ts"; cp "$HERE/web_parity_stub.ts" "$TMP/stub.ts"
cd "$TMP" && npm init -y >/dev/null && npm i -s esbuild >/dev/null
npx esbuild gen.ts --bundle --platform=node --alias:@/hooks/useShifts=./stub.ts --alias:@="$WEB/src" --outfile=gen.js --log-level=error
node gen.js > "$HERE/../SupportCareKit/Tests/SupportCareCoreTests/web_fixtures.json"
echo "fixtures updated"
