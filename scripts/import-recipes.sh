#!/usr/bin/env bash
# Mirror recipe notes (front matter `type: recipe`) into recipes/.
# Usage: scripts/import-recipes.sh <path to the vault's Reference/Recipes>
#
# recipes/ is replaced wholesale, so recipes deleted from the vault disappear
# from the site too. Review `git diff` before committing.
set -euo pipefail

src=${1:?usage: $0 <recipes folder>}
dest="$(dirname "$0")/../recipes"

[ -d "$src" ] || { echo "not a folder: $src" >&2; exit 1; }

rm -f "$dest"/*.md
count=0
for f in "$src"/*.md; do
    # Front matter: from the opening --- on line 1 to the next ---.
    if [ "$(head -n1 "$f")" = "---" ] \
        && sed -n '2,/^---$/p' "$f" | grep -qx 'type: recipe'; then
        cp "$f" "$dest/"
        count=$((count + 1))
    fi
done
echo "imported $count recipes into recipes/"
