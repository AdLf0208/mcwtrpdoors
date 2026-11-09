# Macaw's Trapdoors — Horizon port

A port of [Macaw's Trapdoors](https://github.com/sketchmacaw/Trapdoors) by
Sketch Macaw and Peachy Macaw for Horizon: all 179 trapdoors — the
vanilla-matched woods plus the glass, metal, barn, beach, cottage and themed
sets — with their blockstates, models, textures, recipes, loot, advancements and
language files.

- Every trapdoor is declared from its vanilla trapdoor template with all 64
  states and its own model; the 191 recipes (179 trapdoors plus 12 prints) and
  179 loot tables are the mod's own.
- The 12 print items are carried with their recipes, and the lang files name all
  179 blocks.

This is a data-tier carry: no native code and no hooks. MIT — original copyright
and licence notices are kept in the port repository; see LICENSE and
LICENSE-NOTICE.md there.

**Original:** [Macaw's Trapdoors](https://github.com/sketchmacaw/Trapdoors) 1.1.5 by
Sketch Macaw, Peachy Macaw, **MIT**. The original
copyright and licence notices are kept in [LICENSE](LICENSE), and
[LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each was read from.

**Horizon:** a port for [Horizon](https://github.com/horizon-rust/horizon), Minecraft:
Java Edition 26.3 rewritten in Rust. The exact Horizon and horizon-mixins
revisions this port builds against are pinned in `compatibility.json`.

## Install

1. Take `mcwtrpdoors.hmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-mods` folder — the game folder is the one
   holding `options.txt`.
3. Mods are off by default: enable this one in the game's mod list.

To try it without installing, start the game with
`--dev-mod mcwtrpdoors.hmod`.

## Build

This is a content-only mod: `content/horizon-mod.toml` plus `assets/` and
`data/`, with the 26.3 re-spellings in `content/patches/`.

```sh
cd content && cargo horizon-mod build    # packs content/ into the .hmod and checks it
bash content/patches/apply.sh           # re-applies the 26.3 block/tab patches
```

`cargo-horizon-mod` comes from the Horizon repository
(`cargo install --git https://github.com/horizon-rust/horizon cargo-horizon-mod`).
`tools/e2e.sh` is the in-game harness and expects a campaign checkout
(`$CAMPAIGN_ROOT`) with the prepared 26.3 resources (`$HORIZON_RES`, default
`.local/horizon-client/26.3`).

## Layout

`content/` is the whole port: 179 declared blocks, the carried assets and data, and the 26.3 patch set in `content/patches/`.

This is an unofficial port: Horizon is not affiliated with the original author.
The licence above is the original's and travels with every copy; see
[LICENSE](LICENSE) and [LICENSE-NOTICE.md](LICENSE-NOTICE.md).
