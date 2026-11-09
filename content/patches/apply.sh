#!/usr/bin/env bash
# Re-apply the hand patches after a fresh `horizon-port-pack carry` (it deletes
# and rewrites carry/, and the port copies that tree into content/). Run from
# ports/mcwtrpdoors/content.
#
# What the raw carry needed — and what it did not:
#   * the template guess and the state space were already right for the 176
#     wooden blocks: the carry picked `minecraft:oak_trapdoor` for all 179,
#     which has facing/half/open/powered/waterlogged = 64 states, so nothing is
#     patched on that axis. `tools/e2e.sh` proves the states in game.
#   * the three metal blocks are `BlockSetType.IRON` upstream (redstone only),
#     so they are re-templated on vanilla `minecraft:iron_trapdoor`.
#   * the jar puts its own 16 block tags in the pre-1.21 plural folder
#     `data/mcwtrpdoors/tags/blocks/` while the rest of its data is 1.21-shaped,
#     so the carry (which upgrades a jar only when the old layout is the
#     majority) leaves them there. 26.3 reads `tags/block/` only, so they are
#     moved.
#   * the creative tab upstream registers in Java (`TabInit`) is code; a
#     data-tier port has no code, so it is mirrored as a 26.3 `creative_tab/`.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Upstream's own block tags: `tags/blocks/` (1.20 layout) -> `tags/block/`.
if [ -d data/mcwtrpdoors/tags/blocks ]; then
    mkdir -p data/mcwtrpdoors/tags/block
    mv data/mcwtrpdoors/tags/blocks/*.json data/mcwtrpdoors/tags/block/
    rmdir data/mcwtrpdoors/tags/blocks
fi

# 2. The three IRON BlockSetType trapdoors (redstone only upstream).
for f in patches/block/*.json; do
    cp "$f" "data/mcwtrpdoors/horizon/block/$(basename "$f")"
done

# 3. The Java creative tab (`TabInit`) as 26.3 data.
mkdir -p data/mcwtrpdoors/horizon/creative_tab
cp patches/tab/trapdoors.json data/mcwtrpdoors/horizon/creative_tab/trapdoors.json

# 4. The port owns the manifest (description, authors), not the carry's stub.
cp patches/horizon-mod.toml horizon-mod.toml

echo "patches applied: 16 tag files moved, 3 iron templates, 1 creative tab, 1 manifest"
