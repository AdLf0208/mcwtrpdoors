#!/usr/bin/env python3
"""Compare the carried mcwtrpdoors content against the 1.21.1 jar it came from.

Data-level fidelity check for the Macaw's Trapdoors content port. It reads the
jar (read-only), the carried folder mod and the prepared 26.3 tables, and
asserts that every carried block/item/recipe/loot/advancement/lang/model/
texture/tag matches what the jar declares, that the three IRON-set metal blocks
are the only ones re-templated on `minecraft:iron_trapdoor`, and — the part that
matters most for a directional block — that all 64 states of every carried
block are covered by its blockstate once it carries the template's state space.

Exit 0 on success, 1 with the failures printed.

Usage:
    python3 tools/verify_content.py \
        [--jar ../../_shared/carry-work/mcwtrpdoors/jars/...jar] \
        [--content content] [--resources /path/to/26.3]
"""
from __future__ import annotations

import argparse
import glob
import itertools
import json
import os
import sys
import zipfile

OAK = "minecraft:oak_trapdoor"
IRON = "minecraft:iron_trapdoor"
AXES = ("facing", "half", "open")
METAL = ("metal_trapdoor", "metal_warning_trapdoor", "metal_full_trapdoor")


def load(path: str):
    with open(path, encoding="utf-8-sig") as handle:
        return json.load(handle)


def blockstate_props(raw: str) -> set[str]:
    """The property names a blockstate file mentions (variants or multipart)."""
    doc = json.loads(raw)
    props: set[str] = set()
    for key in doc.get("variants", {}):
        for part in key.split(","):
            if part:
                props.add(part.split("=")[0])
    for part in doc.get("multipart", []):
        when = part.get("when", {})
        for cond in [when, *when.get("OR", []), *when.get("AND", [])]:
            props.update(cond)
    return props


def bind(blockstate: dict, states: list[dict[str, str]]) -> tuple[list[list[str] | None], list[str]]:
    """Horizon's `BlockStateDefinition::bind` over a template's state space.

    A variant selector may name fewer properties than the state has (a trapdoor
    blockstate names facing/half/open; the model ignores powered/waterlogged),
    so a selector matches every state whose named properties agree. Returns the
    model references selected for each state (None = no model) and the selectors
    that name an unknown property value.
    """
    bound: list[list[str] | None] = [None] * len(states)
    bad: list[str] = []

    def predicate(key: str) -> dict[str, str] | None:
        out: dict[str, str] = {}
        for clause in key.split(","):
            name, _, value = clause.partition("=")
            if not name:
                continue
            if value and not any(state.get(name) == value for state in states):
                return None
            out[name] = value
        return out

    for key, variant in (blockstate.get("variants") or {}).items():
        pred = predicate(key)
        if pred is None:
            bad.append(key)
            continue
        models = apply_models(variant)
        for index, state in enumerate(states):
            if all(state.get(name) == value for name, value in pred.items()):
                if bound[index] is not None:
                    bad.append(f"overlapping selector {key}")
                bound[index] = models

    parts = []
    for part in blockstate.get("multipart") or []:
        when = part.get("when") or {}
        parts.append((when, apply_models(part.get("apply") or {})))

    def matches(when: dict, state: dict[str, str]) -> bool:
        if "OR" in when:
            return any(matches(w, state) for w in when["OR"])
        if "AND" in when:
            return all(matches(w, state) for w in when["AND"])
        return all(state.get(name) == value for name, value in when.items())

    for index, state in enumerate(states):
        if bound[index] is None:
            bound[index] = [
                model for when, models in parts if matches(when, state) for model in models
            ]
    return bound, bad


def apply_models(apply: dict) -> list[str]:
    entries = apply if isinstance(apply, list) else [apply]
    return [entry["model"] for entry in entries if "model" in entry]


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    port = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--jar",
        default=os.path.join(
            port,
            "../_shared/carry-work/mcwtrpdoors/jars/"
            "mcw-trapdoors-1.1.5-mc1.21.1neoforge.jar",
        ),
    )
    ap.add_argument("--content", default=os.path.join(port, "content"))
    ap.add_argument(
        "--resources",
        default=os.environ.get(
            "HORIZON_RES", ".local/horizon-client/26.3"
        ),
    )
    args = ap.parse_args()

    failures: list[str] = []

    def check(ok: bool, msg: str) -> None:
        if not ok:
            failures.append(msg)

    def say(msg: str) -> None:
        print(f"ok: {msg}")

    z = zipfile.ZipFile(args.jar)
    names = {n for n in z.namelist() if not n.endswith("/")}

    # --- jar census ---------------------------------------------------------
    jar_blocks = {}
    for n in sorted(names):
        if n.startswith("assets/mcwtrpdoors/blockstates/") and n.endswith(".json"):
            jar_blocks[n.rsplit("/", 1)[-1][:-5]] = blockstate_props(
                z.read(n).decode("utf-8-sig")
            )
    check(len(jar_blocks) == 179, f"expected 179 jar blockstates, found {len(jar_blocks)}")
    odd = {b: sorted(p) for b, p in jar_blocks.items() if p != set(AXES)}
    check(not odd, f"blockstates with properties other than {AXES}: {odd}")
    say(
        f"jar: {len(jar_blocks)} blockstates, every one `facing,half,open` "
        "(the models ignore `powered`/`waterlogged`)"
    )

    jar_item_models = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("assets/mcwtrpdoors/models/item/") and n.endswith(".json")
    }
    prints = sorted(jar_item_models - set(jar_blocks))
    check(len(jar_item_models) == 191, f"expected 191 jar item models, found {len(jar_item_models)}")
    check(len(prints) == 12, f"expected 12 print item models, found {len(prints)}: {prints}")
    check(
        all(p.startswith("print_") for p in prints),
        f"non-print item models outside the block set: {prints}",
    )
    say(f"jar: {len(jar_item_models)} item models = {len(jar_blocks)} blocks + {len(prints)} prints")

    jar_recipes = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("data/mcwtrpdoors/recipe/") and n.endswith(".json")
    }
    jar_loot = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("data/mcwtrpdoors/loot_table/") and n.endswith(".json")
    }
    jar_adv = {
        n.split("data/mcwtrpdoors/advancement/", 1)[-1][:-5]
        for n in names
        if n.startswith("data/mcwtrpdoors/advancement/") and n.endswith(".json")
    }
    jar_textures = {
        n.rsplit("/", 1)[-1][:-4]
        for n in names
        if n.startswith("assets/mcwtrpdoors/textures/") and n.endswith(".png")
    }
    jar_lang = {
        n.rsplit("/", 1)[-1]
        for n in names
        if n.startswith("assets/mcwtrpdoors/lang/") and n.endswith(".json")
    }
    check(len(jar_recipes) == 191, f"expected 191 jar recipes, found {len(jar_recipes)}")
    check(len(jar_loot) == 179, f"expected 179 jar loot tables, found {len(jar_loot)}")
    check(len(jar_adv) == 180, f"expected 180 jar advancements, found {len(jar_adv)}")
    check(len(jar_textures) == 169, f"expected 169 jar textures, found {len(jar_textures)}")
    check(len(jar_lang) == 15, f"expected 15 jar lang files, found {len(jar_lang)}")
    say(
        f"jar: {len(jar_recipes)} recipes, {len(jar_loot)} loot tables, "
        f"{len(jar_adv)} advancements, {len(jar_textures)} textures, {len(jar_lang)} lang files"
    )

    # --- block declarations -------------------------------------------------
    decl = {
        os.path.basename(p)[:-5]: load(p)
        for p in glob.glob(os.path.join(args.content, "data/mcwtrpdoors/horizon/block/*.json"))
    }
    carried = set(jar_blocks)
    check(
        set(decl) == carried,
        f"declared blocks != jar blocks: {sorted(set(decl) ^ carried)[:8]}",
    )
    say(f"content: {len(decl)} block declarations, exactly the jar's 179 trapdoors")

    # --- templates ----------------------------------------------------------
    iron = {b for b, d in decl.items() if d["template"] == IRON}
    oak = {b for b, d in decl.items() if d["template"] == OAK}
    check(iron == set(METAL), f"iron_trapdoor blocks are {sorted(iron)}, expected {METAL}")
    check(oak == carried - set(METAL), f"{len(oak)} oak_trapdoor blocks, expected {len(carried) - 3}")
    check(not (set(decl) - iron - oak), "a block has a template other than oak/iron trapdoor")
    say(
        f"templates: {len(oak)} x minecraft:oak_trapdoor + {len(iron)} x "
        "minecraft:iron_trapdoor (the IRON BlockSetType set upstream)"
    )

    # --- every state of every block has a model -----------------------------
    facts = load(os.path.join(args.resources, "facts.json"))
    schema: dict[str, dict[str, set[str]]] = {}
    for entry in facts["states"]:
        name = entry[0]
        props = entry[-1].get("properties", {})
        for prop, value in props.items():
            schema.setdefault(name, {}).setdefault(prop, set()).add(value)
    for template, count in ((OAK, len(oak)), (IRON, len(iron))):
        states = 1
        for values in schema[template].values():
            states *= len(values)
        check(states == 64, f"{template}: state space is {states}, expected 64")
    universe = {
        template: [
            dict(zip(sorted(schema[template]), values))
            for values in itertools.product(
                *(sorted(schema[template][p]) for p in sorted(schema[template]))
            )
        ]
        for template in (OAK, IRON)
    }

    uncovered: list[str] = []
    bad_keys: list[str] = []
    model_refs: set[str] = set()
    for block in sorted(carried):
        template = decl[block]["template"]
        raw = os.path.join(args.content, "assets/mcwtrpdoors/blockstates", block + ".json")
        check(os.path.isfile(raw), f"missing blockstate asset for {block}")
        if not os.path.isfile(raw):
            continue
        bound, bad = bind(load(raw), universe[template])
        bad_keys.extend(f"{block}: {key}" for key in bad)
        state_count = len(universe[template])
        uncovered.extend(
            f"{block} {json.dumps(state, sort_keys=True)}"
            for state, models in zip(universe[template], bound)
            if not models
        )
        for models in bound:
            model_refs.update(models or [])
    check(not bad_keys, f"variant selectors naming unknown values: {bad_keys[:5]}")
    check(
        not uncovered,
        f"{len(uncovered)} block states have no model (a missing model in game): {uncovered[:4]}",
    )
    say(
        f"state space: {len(carried) * 64} states ({len(carried)} x 64: facing x half x "
        "open x powered x waterlogged), all covered"
    )

    # --- models and item definitions ---------------------------------------
    model_files = {
        p.rsplit("models/", 1)[-1][:-5]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwtrpdoors/models/**/*.json"), recursive=True
        )
    }
    item_defs = {
        p.rsplit("/items/", 1)[-1][:-5]
        for p in glob.glob(os.path.join(args.content, "assets/mcwtrpdoors/items/*.json"))
    }
    check(item_defs == carried | set(prints), f"item definitions differ: {sorted(item_defs ^ (carried | set(prints)))[:8]}")
    for name in sorted(carried | set(prints)):
        path = os.path.join(args.content, "assets/mcwtrpdoors/items", name + ".json")
        if not os.path.isfile(path):
            continue
        model = load(path).get("model")
        if isinstance(model, dict):
            model_refs.add(model.get("model", ""))
        elif isinstance(model, str):
            model_refs.add(model)

    def resolves_model(ref: str) -> bool:
        ns, _, path = ref.partition(":")
        if ns == "minecraft":
            return os.path.isfile(
                os.path.join(args.resources, "assets/minecraft/models", path + ".json")
            )
        if ns and ns != "mcwtrpdoors":
            return False
        return path in model_files

    missing_models = sorted(m for m in model_refs if m and not resolves_model(m))
    check(not missing_models, f"referenced models missing: {missing_models[:8]}")
    say(
        f"models: {len(model_files)} present, {len(model_refs)} referenced by the "
        "carried blockstates and item definitions, 0 missing"
    )

    textures = {
        p.rsplit("textures/", 1)[-1][:-4]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwtrpdoors/textures/**/*.png"), recursive=True
        )
    }
    check(len(textures) == 169, f"{len(textures)} textures carried, expected 169")

    def split_ref(ref: str) -> tuple[str, str]:
        if ":" in ref:
            ns, _, path = ref.partition(":")
            return ns, path
        return "minecraft", ref

    def model_doc(ref: str) -> dict | None:
        ns, path = split_ref(ref)
        if ns == "minecraft":
            path = os.path.join(args.resources, "assets/minecraft/models", path + ".json")
        elif ns == "mcwtrpdoors":
            path = os.path.join(args.content, "assets/mcwtrpdoors/models", path + ".json")
        else:
            return None
        return load(path) if os.path.isfile(path) else None

    def composed_textures(ref: str, seen: frozenset[str] = frozenset()) -> dict[str, str]:
        if ref in seen:
            return {}
        doc = model_doc(ref)
        if doc is None:
            return {}
        out: dict[str, str] = {}
        parent = doc.get("parent")
        if isinstance(parent, str):
            out.update(composed_textures(parent, seen | {ref}))
        for key, value in (doc.get("textures") or {}).items():
            if isinstance(value, str):
                out[key] = value
        return out

    def resolves_texture(ref: str) -> bool:
        ns, path = split_ref(ref)
        if ns == "minecraft":
            return os.path.isfile(
                os.path.join(args.resources, "assets/minecraft/textures", path + ".png")
            )
        if ns != "mcwtrpdoors":
            return False
        return path in textures

    direct = sorted(m for m in model_refs if m.startswith("mcwtrpdoors:"))
    untextured: set[str] = set()
    parents: set[str] = set()
    for ref in direct:
        for value in composed_textures(ref).values():
            if isinstance(value, str) and not value.startswith("#"):
                untextured.add(value)
        parent = (model_doc(ref) or {}).get("parent")
        while isinstance(parent, str) and split_ref(parent)[0] == "mcwtrpdoors":
            parents.add(parent)
            parent = (model_doc(parent) or {}).get("parent")

    missing_textures = sorted(t for t in untextured if not resolves_texture(t))
    check(not missing_textures, f"missing textures: {missing_textures[:8]}")
    say(
        f"textures: {len(textures)} present, {len(direct)} models named by the carried "
        f"blockstates/items (+{len(parents)} mod parents), every texture resolves after "
        "parent inheritance"
    )

    # --- recipes ------------------------------------------------------------
    recipes = {
        os.path.basename(p)[:-5]: load(p)
        for p in glob.glob(os.path.join(args.content, "data/mcwtrpdoors/recipe/*.json"))
    }
    check(
        set(recipes) == jar_recipes,
        f"recipes differ from the jar: {sorted(set(recipes) ^ jar_recipes)[:8]}",
    )
    registered = {f"mcwtrpdoors:{b}" for b in carried} | {f"mcwtrpdoors:{p}" for p in prints}
    bad_result = [
        r for r, d in recipes.items() if d.get("result", {}).get("id") not in registered
    ]
    check(not bad_result, f"recipes with an unregistered result: {bad_result[:8]}")
    tag_uses = json.dumps(list(recipes.values()))
    check(
        "#c:" not in tag_uses and "forge:" not in tag_uses,
        "recipes still use NeoForge c:/forge: tags",
    )
    say(
        f"recipes: {len(recipes)} carried ({len(jar_recipes)} in the jar), every result "
        "registered, no NeoForge tags"
    )

    # --- loot ---------------------------------------------------------------
    loot = {
        os.path.basename(p)[:-5]
        for p in glob.glob(os.path.join(args.content, "data/mcwtrpdoors/loot_table/blocks/*.json"))
    }
    check(loot == jar_loot == carried, f"loot tables differ: {sorted(loot ^ carried)[:8]}")
    say(f"loot: {len(loot)} tables, one per carried block")

    # --- advancements -------------------------------------------------------
    adv = {
        p.rsplit("advancement/", 1)[-1][:-5]
        for p in glob.glob(
            os.path.join(args.content, "data/mcwtrpdoors/advancement/**/*.json"), recursive=True
        )
    }
    check(adv == jar_adv, f"advancements differ: {sorted(adv ^ jar_adv)[:8]}")
    bad_adv = []
    orphan_adv = []
    for path in glob.glob(
        os.path.join(args.content, "data/mcwtrpdoors/advancement/**/*.json"), recursive=True
    ):
        for recipe in load(path).get("rewards", {}).get("recipes", []):
            name = recipe.split(":", 1)[-1]
            if name in recipes:
                continue
            # The jar itself ships an advancement that rewards a recipe it does
            # not have (bamboo_ranch_trapdoor); it never triggers and is inert.
            if name in jar_recipes:
                bad_adv.append(f"{os.path.basename(path)}: {recipe}")
            else:
                orphan_adv.append(f"{os.path.basename(path)}: {recipe}")
    check(not bad_adv, f"advancements naming uncarried recipes: {bad_adv[:5]}")
    say(
        f"advancements: {len(adv)} carried, every rewarded recipe is carried"
        + (f" (1 upstream orphan kept: {orphan_adv[0]})" if orphan_adv else "")
    )

    # --- lang ---------------------------------------------------------------
    lang_files = {
        os.path.basename(p)
        for p in glob.glob(os.path.join(args.content, "assets/mcwtrpdoors/lang/*.json"))
    }
    check(
        lang_files == jar_lang - {"ko_kr.json"},
        f"lang files carried: {sorted(lang_files ^ (jar_lang - {'ko_kr.json'}))}",
    )
    lang = load(os.path.join(args.content, "assets/mcwtrpdoors/lang/en_us.json"))
    unnamed = [b for b in carried if f"block.mcwtrpdoors.{b}" not in lang]
    unnamed += [p for p in prints if f"item.mcwtrpdoors.{p}" not in lang]
    check(not unnamed, f"blocks/items without an en_us name: {unnamed[:8]}")
    check("itemGroup.mcwtrpdoors" in lang, "itemGroup.mcwtrpdoors is missing")
    stale = sorted(
        k[len("block.mcwtrpdoors."):]
        for k in lang
        if k.startswith("block.mcwtrpdoors.") and k[len("block.mcwtrpdoors."):] not in carried
    )
    say(
        f"lang: {len(lang_files)} files carried (15 in the jar, ko_kr.json is malformed "
        f"upstream and skipped), all {len(carried)} blocks and {len(prints)} prints named; "
        f"{len(stale)} stale upstream keys kept: {stale}"
    )

    # --- tags ---------------------------------------------------------------
    tag_files = sorted(
        p
        for p in glob.glob(
            os.path.join(args.content, "data/**/tags/**/*.json"), recursive=True
        )
    )
    check(len(tag_files) == 22, f"{len(tag_files)} tag files carried, expected 22 (16 mod + 6 vanilla)")
    renamed = []
    for path in tag_files:
        rel = os.path.relpath(path, os.path.join(args.content, "data")).replace(os.sep, "/")
        raw = "data/" + rel
        if raw not in names:
            # the mod's own tags were in the pre-1.21 plural folder in the jar
            raw = raw.replace("/tags/block/", "/tags/blocks/")
            renamed.append(rel)
        check(raw in names, f"tag {rel} is not in the jar")
        if raw in names:
            check(
                load(path).get("values", []) == json.loads(z.read(raw).decode("utf-8-sig")).get("values", []),
                f"tag {rel} differs from the jar",
            )
    check(len(renamed) == 16, f"{len(renamed)} tags were renamed from tags/blocks, expected 16")
    say(
        f"tags: {len(tag_files)} files, values byte-equal to the jar's; 16 mod tags moved "
        "from the jar's pre-1.21 `tags/blocks/` to 26.3's `tags/block/`"
    )

    # --- creative tab -------------------------------------------------------
    tab = load(os.path.join(args.content, "data/mcwtrpdoors/horizon/creative_tab/trapdoors.json"))
    tab_ids = [i.split(":", 1)[1] for i in tab["items"]]
    check(len(tab_ids) == 191, f"creative tab lists {len(tab_ids)} items, expected 191")
    check(
        set(tab_ids) == carried | set(prints),
        f"creative tab != carried blocks + prints: {sorted(set(tab_ids) ^ (carried | set(prints)))[:8]}",
    )
    check(tab["title"] in lang, "the tab title key is not in en_us")
    check(
        tab["icon"].split(":", 1)[-1] in carried,
        f"the tab icon {tab['icon']} is not a carried block",
    )
    say("creative tab: 191 items = 12 prints + 179 trapdoors, title key and icon carried")

    if failures:
        print("\nFAILURES:")
        for failure in failures:
            print(f"  FAIL: {failure}")
        return 1
    print(
        f"\nPASS: {len(carried)} trapdoor blocks ({len(oak)} oak + {len(iron)} iron) and "
        f"{len(recipes)} recipes match the 1.21.1 jar; all {len(carried) * 64} states have a "
        f"model, every texture resolves, and the {len(prints)} print items, {len(loot)} loot "
        f"tables, {len(adv)} advancements and {len(tag_files)} tags are carried"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
