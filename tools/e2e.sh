#!/usr/bin/env bash
# In-game check for the Macaw's Trapdoors content port (179 blocks -> 176 on the
# vanilla oak-trapdoor template + 3 IRON metal ones on vanilla iron trapdoor,
# plus 12 print items), Minecraft 26.3 on the campaign pin 1d63e0a.
#
# Default run (offscreen renderer, creative, The End, shared unmodded game +
# `--dev-mod content/`):
#   0. tools/verify_content.py compares the carried folder mod with the 1.21.1
#      jar first (blockstate/model/texture/recipe/loot/advancement/lang/tag
#      fidelity and all 11456 states covered), so a broken asset never reaches
#      the game;
#   1. the mod loads (no "content mods not loaded");
#   2. all 179 carried ids `setblock` and read back, so every registry entry and
#      its default state binds;
#   3. all 64 states of `oak_barn_trapdoor` (facing x half x open x powered x
#      waterlogged) are set and read back, so the template's whole state space
#      binds, not only the model's 16-variant blockstate;
#   4. a trapdoor item places with a horizontal facing and a half, right-click
#      opens and closes it, and a redstone block opens it (`powered=true,
#      open=true`) and removing it closes it - the vanilla trapdoor behaviour
#      the template carries;
#   5. the three metal trapdoors are IRON set: the hand does not open them
#      (`changed:false`, open stays false), redstone does, exactly like vanilla
#      `minecraft:iron_trapdoor`, checked in the same run;
#   6. in survival a placed trapdoor drops itself (the carried loot table), the
#      one thing a data carry owns end to end;
#   7. screenshots: a trapdoor scene (bottom/top, open/closed, metal) differs
#      from the same frame with the blocks removed, and the log carries no
#      mcwtrpdoors missing-model or missing-texture warning;
#   8. the creative tab lists all 179 blocks + 12 prints (191);
#   9. controls: an unknown id, an impossible state and a plain stick are
#      refused, and a vanilla oak_trapdoor opens/closes the same way.
#
# NEGATIVE=1 keeps the scenario but expects the wooden trapdoor to stay closed
# after the right-click: the run MUST fail at that assertion, proving the open
# check is not vacuous. `SKIP_VERIFY=1` skips the jar comparison (debugging only).
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:?set CAMPAIGN_ROOT to a checkout of the ATM10-Horizon campaign tree}
PORT=$CLONE/ports/mcwtrpdoors
SHARED=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$SHARED/horizon-client}
RES=${RES:-${HORIZON_RES:-.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/mcwtrpdoors-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
SKIP_VERIFY=${SKIP_VERIFY:-0}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

BLOCK_DIR=$PORT/content/data/mcwtrpdoors/horizon/block
mapfile -t BLOCKS < <(find "$BLOCK_DIR" -name '*.json' -printf '%f\n' | sed 's/\.json$//' | sort)
[ "${#BLOCKS[@]}" -eq 179 ] || { echo "expected 179 carried blocks, found ${#BLOCKS[@]}" >&2; exit 1; }
BLOCK_DECL=$BLOCK_DIR

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }
template_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["template"])' \
    "$BLOCK_DECL/$1.json"; }

if [ "$SKIP_VERIFY" = 1 ]; then
    echo "== jar comparison skipped (SKIP_VERIFY=1) =="
else
    say "data fidelity: carried content vs the 1.21.1 jar"
    python3 "$PORT/tools/verify_content.py" --content "$PORT/content" --resources "$RES" \
        || fail "verify_content.py failed"
fi

SCRATCH=$(mktemp -d /tmp/opencode/mcwtrpdoors-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
prop() { echo "$1" | grep -o "$2=[a-z]*" | head -1 | cut -d= -f2 || true; }
assert_prop() {
    local state=$1 key=$2 want=$3 got
    got=$(prop "$state" "$key")
    [ "$got" = "$want" ] || fail "$state: $key is '$got', expected '$want'"
}
mean_rgb() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
crop = im.crop((w * 3 // 10, h * 3 // 10, w * 7 // 10, h * 7 // 10))
px = list(crop.getdata())
n = len(px)
print(sum(p[0] for p in px) / n, sum(p[1] for p in px) / n, sum(p[2] for p in px) / n)
PY
}
pixel_fraction() { # file-a file-b -> the share of pixels that changed (max channel > 12)
    python3 - "$1" "$2" <<'PY'
import sys
from PIL import Image
a = list(Image.open(sys.argv[1]).convert("RGB").getdata())
b = list(Image.open(sys.argv[2]).convert("RGB").getdata())
changed = sum(
    1
    for p, q in zip(a, b)
    if max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2])) > 12
)
print(f"{changed / len(a):.5f}")
PY
}
frame_differs() { # file-a file-b label min-fraction
    local fraction
    fraction=$(pixel_fraction "$1" "$2")
    echo "share of pixels changed by $3: $fraction (mean RGB $(mean_rgb "$1") vs $(mean_rgb "$2"))"
    awk -v f="$fraction" -v m="$4" 'BEGIN { exit !(f >= m) }' \
        || fail "the frame did not change when $3 was removed (no model drawn?)"
}

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
}
trap cleanup EXIT

say "launch (offscreen renderer, creative, The End, content --dev-mod content/)"
"$CTL" --socket "$SOCK" launch \
    --game "$GAME" --world McwTrapdoorsE2E --seed 20261107 --creative --offscreen --wait \
    --game-dir "$SCRATCH/game" --resources "$RES" --dev-mod "$PORT/content"
ctl wait-ready 180
if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
    ctl logs --lines 4000 | grep "content mods not loaded" >&2
    fail "the content mod did not load"
fi
echo "content mod loaded (no 'content mods not loaded')"

say "The End arena: floor at y=79, clear above"
end "forceload add -8 -8 72 72"
end "tp @s 8.5 80 8.5"
ctl wait 40
end "fill -8 79 -8 72 79 32 minecraft:stone"
end "fill -8 80 -8 72 88 32 minecraft:air"
end "difficulty peaceful"
end "gamerule spawn_mobs false"
ctl wait 10
ctl close >/dev/null 2>&1 || true
ctl wait 2

# ------------------------------------------------------------------ registry
say "all ${#BLOCKS[@]} carried ids bind their default state"
PER=25
for i in "${!BLOCKS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    ctl setblock "$x" 80 "$z" "mcwtrpdoors:${BLOCKS[$i]}" >/dev/null \
        || fail "setblock mcwtrpdoors:${BLOCKS[$i]} failed"
done
ctl wait 10
for i in "${!BLOCKS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    got=$(block_name "$x" 80 "$z")
    [ "$got" = "mcwtrpdoors:${BLOCKS[$i]}" ] \
        || fail "x=$x z=$z reads '$got', expected mcwtrpdoors:${BLOCKS[$i]}"
done
echo "${#BLOCKS[@]}/${#BLOCKS[@]} ids registered and their default state bound"

say "the metal trapdoors are the IRON template, the rest the wooden one"
iron_count=0
for b in "${BLOCKS[@]}"; do
    [ "$(template_of "$b")" = minecraft:iron_trapdoor ] && iron_count=$((iron_count + 1))
done
[ "$iron_count" -eq 3 ] || fail "$iron_count blocks on the iron template, expected 3"
for b in metal_trapdoor metal_warning_trapdoor metal_full_trapdoor; do
    [ "$(template_of "$b")" = minecraft:iron_trapdoor ] || fail "$b is not on iron_trapdoor"
done
[ "$(template_of oak_barn_trapdoor)" = minecraft:oak_trapdoor ] || fail "oak_barn_trapdoor is not on oak_trapdoor"
echo "176 x minecraft:oak_trapdoor + 3 x minecraft:iron_trapdoor"

# ------------------------------------------------------ the 64-state space
say "all 64 states of oak_barn_trapdoor bind (facing x half x open x powered x waterlogged)"
# Spaced two apart so no neighbour update from one placement reaches the next
# (a powered=true state with no signal would be reset by neighbourChanged).
idx=0
for facing in north south east west; do
  for half in bottom top; do
    for open in false true; do
      for powered in false true; do
        for waterlogged in false true; do
          x=$((30 + 2 * (idx % 8))); z=$((2 + 2 * (idx / 8)))
          state="mcwtrpdoors:oak_barn_trapdoor[facing=$facing,half=$half,open=$open,powered=$powered,waterlogged=$waterlogged]"
          ctl setblock "$x" 82 "$z" "$state" >/dev/null || fail "setblock $state failed"
          idx=$((idx + 1))
        done
      done
    done
  done
done
ctl wait 10
idx=0
for facing in north south east west; do
  for half in bottom top; do
    for open in false true; do
      for powered in false true; do
        for waterlogged in false true; do
          x=$((30 + 2 * (idx % 8))); z=$((2 + 2 * (idx / 8)))
          got=$(block_state "$x" 82 "$z")
          assert_prop "$got" facing "$facing"
          assert_prop "$got" half "$half"
          assert_prop "$got" open "$open"
          assert_prop "$got" powered "$powered"
          assert_prop "$got" waterlogged "$waterlogged"
          idx=$((idx + 1))
        done
      done
    done
  done
done
echo "64/64 states read back every property (waterlogged=true included)"

# ------------------------------------------------------------------- swings
say "a trapdoor item places with a facing and a half"
ctl command "clear @s" >/dev/null
ctl give mcwtrpdoors:oak_barn_trapdoor 2 >/dev/null || fail "cannot give mcwtrpdoors:oak_barn_trapdoor"
ctl wait 3
ctl select mcwtrpdoors:oak_barn_trapdoor >/dev/null || fail "cannot select mcwtrpdoors:oak_barn_trapdoor"
ctl wait 2
ctl tp 40.5 80 14.5
ctl wait 3
ctl look-at-block 40 80 12 >/dev/null 2>&1 || true
ctl wait 2
reply=$(ctl place 40 80 12 --item mcwtrpdoors:oak_barn_trapdoor 2>&1) || { echo "place reply: $reply"; fail "cannot place the trapdoor"; }
echo "place reply: $reply"
ctl wait 3
placed=$(block_state 40 80 12)
case "$placed" in mcwtrpdoors:oak_barn_trapdoor*) ;; *) fail "the placed trapdoor is '$placed'" ;; esac
assert_prop "$placed" open false
case "$(prop "$placed" facing)" in
    north | south | east | west) ;;
    *) fail "the placed trapdoor's facing is '$(prop "$placed" facing)'" ;;
esac
case "$(prop "$placed" half)" in
    bottom | top) ;;
    *) fail "the placed trapdoor's half is '$(prop "$placed" half)'" ;;
esac
echo "placed facing=$(prop "$placed" facing) half=$(prop "$placed" half) open=false"

say "right-click opens and closes the wooden trapdoor"
ctl look-at-block 40 80 12 >/dev/null 2>&1 || true
reply=$(ctl interact 40 80 12)
echo "open click: $reply"
ctl wait 3
want_open=true
[ "$NEGATIVE" = 1 ] && want_open=false
[ "$(prop "$(block_state 40 80 12)" open)" = "$want_open" ] \
    || fail "open=$(prop "$(block_state 40 80 12)" open), expected $want_open after the right-click"
echo "right-click set open=$want_open"
ctl look-at-block 40 80 12 >/dev/null 2>&1 || true
ctl interact 40 80 12 >/dev/null
ctl wait 3
[ "$(prop "$(block_state 40 80 12)" open)" = false ] \
    || fail "the second click did not close the trapdoor (open=$(prop "$(block_state 40 80 12)" open))"
echo "second right-click closed it"

say "redstone opens the wooden trapdoor and its removal closes it"
ctl command "clear @s" >/dev/null
ctl setblock 44 80 12 "mcwtrpdoors:oak_glass_trapdoor[facing=east,open=false,powered=false]" >/dev/null
ctl wait 3
assert_prop "$(block_state 44 80 12)" open false
ctl setblock 44 80 11 minecraft:redstone_block >/dev/null
ctl wait 5
powered=$(block_state 44 80 12)
assert_prop "$powered" powered true
assert_prop "$powered" open true
echo "redstone block beside it: $powered"
ctl setblock 44 80 11 minecraft:air >/dev/null
ctl wait 5
assert_prop "$(block_state 44 80 12)" open false
echo "removing the redstone closed it (open=false)"

# -------------------------------------------------------------------- metal
say "a metal trapdoor ignores the hand and opens on redstone (IRON set)"
ctl command "clear @s" >/dev/null
ctl wait 2
ctl setblock 48 80 12 "mcwtrpdoors:metal_trapdoor[facing=east,open=false,powered=false]" >/dev/null
ctl wait 3
ctl tp 48.5 80 14.5
ctl wait 2
ctl look-at-block 48 80 12 >/dev/null 2>&1 || true
reply=$(ctl interact 48 80 12)
echo "hand click reply: $reply"
ctl wait 3
[ "$(prop "$(block_state 48 80 12)" open)" = false ] \
    || fail "the metal trapdoor opened by hand (open=$(prop "$(block_state 48 80 12)" open))"
echo "hand: open=false (IRON set, like vanilla iron_trapdoor)"
ctl setblock 48 80 11 minecraft:redstone_block >/dev/null
ctl wait 5
metal=$(block_state 48 80 12)
assert_prop "$metal" powered true
assert_prop "$metal" open true
echo "redstone: $metal"
ctl setblock 48 80 11 minecraft:air >/dev/null
ctl wait 5
assert_prop "$(block_state 48 80 12)" open false
echo "removing the redstone closed it"

say "vanilla iron_trapdoor baseline in the same harness"
ctl command "clear @s" >/dev/null
ctl setblock 52 80 12 "minecraft:iron_trapdoor[facing=east,open=false,powered=false]" >/dev/null
ctl wait 3
ctl look-at-block 52 80 12 >/dev/null 2>&1 || true
reply=$(ctl interact 52 80 12)
echo "vanilla hand click reply: $reply"
ctl wait 3
[ "$(prop "$(block_state 52 80 12)" open)" = false ] || fail "vanilla iron_trapdoor opened by hand"
ctl setblock 52 80 11 minecraft:redstone_block >/dev/null
ctl wait 5
assert_prop "$(block_state 52 80 12)" open true
echo "vanilla iron_trapdoor: hand no, redstone yes - the same as the carried metal blocks"

# ------------------------------------------------------------------- drops
say "in survival a placed trapdoor drops itself (the carried loot table)"
ctl command "gamemode survival @s" >/dev/null
ctl wait 2
ctl command "clear @s" >/dev/null
ctl give mcwtrpdoors:oak_barn_trapdoor 2 >/dev/null || fail "cannot give mcwtrpdoors:oak_barn_trapdoor"
ctl wait 3
ctl select mcwtrpdoors:oak_barn_trapdoor >/dev/null || fail "cannot select mcwtrpdoors:oak_barn_trapdoor"
ctl wait 2
ctl tp 56.5 80 14.5
ctl wait 3
ctl place 56 80 12 --item mcwtrpdoors:oak_barn_trapdoor >/dev/null || fail "cannot place the survival trapdoor"
ctl wait 3
before=$(count_item mcwtrpdoors:oak_barn_trapdoor)
echo "trapdoors in the inventory after placing: $before"
reply=$(ctl break 56 80 12 --timeout 30)
echo "break reply: $reply"
ctl wait 10
dropped=$(echo "$reply" | jq '[
    .drops["mcwtrpdoors:oak_barn_trapdoor"] // 0,
    .picked_up["mcwtrpdoors:oak_barn_trapdoor"] // 0,
    ([.on_ground[]? | select(.item == "mcwtrpdoors:oak_barn_trapdoor") | .count] | add // 0)
] | max')
[ "$dropped" -ge 1 ] || fail "breaking the trapdoor dropped $dropped of it (the loot table did not run)"
[ "$(block_name 56 80 12)" = minecraft:air ] || fail "the trapdoor is still at 56 80 12"
after=$(count_item mcwtrpdoors:oak_barn_trapdoor)
echo "the broken trapdoor dropped itself: $dropped item(s), inventory $before -> $after"
ctl command "gamemode creative @s" >/dev/null
ctl wait 2

# --------------------------------------------------------------- screenshot
say "screenshots: the carried models are drawn, the empty frames are not"
ctl setblock 60 80 12 "mcwtrpdoors:oak_barn_trapdoor[facing=south,half=bottom,open=false]" >/dev/null
ctl setblock 61 80 12 "mcwtrpdoors:oak_glass_trapdoor[facing=south,half=top,open=true]" >/dev/null
ctl setblock 62 80 13 "mcwtrpdoors:metal_trapdoor[facing=north,half=bottom,open=false]" >/dev/null
ctl tp 61.5 80 16.5
ctl look-at-block 61 80 12 >/dev/null 2>&1 || true
ctl wait 12
ctl screenshot "$SCRATCH/scene.png" >/dev/null
for x in 60 61 62; do ctl setblock "$x" 80 12 minecraft:air >/dev/null; done
ctl setblock 62 80 13 minecraft:air >/dev/null
ctl wait 12
ctl screenshot "$SCRATCH/scene-empty.png" >/dev/null
frame_differs "$SCRATCH/scene.png" "$SCRATCH/scene-empty.png" "the trapdoor scene" 0.004

say "no missing model/texture warnings for mcwtrpdoors"
ctl logs --lines 6000 > "$SCRATCH/game.log" 2>/dev/null || true
if grep -iE "missing texture for mcwtrpdoors|block models incomplete.*mcwtrpdoors|no model.*mcwtrpdoors|mcwtrpdoors.*missing (model|texture)" "$SCRATCH/game.log"; then
    fail "the log reports a missing model/texture for mcwtrpdoors"
fi
echo "the log has no mcwtrpdoors missing-model/missing-texture warning"

# -------------------------------------------------------------- creative tab
say "the creative tab lists all 191 items (179 blocks + 12 prints)"
CREATIVE=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name creative-inventory.json -print -quit 2>/dev/null || true)
[ -n "$CREATIVE" ] && [ -f "$CREATIVE" ] || fail "no creative-inventory.json (content mod not loaded)"
python3 "$PORT/tools/tab_check.py" "$CREATIVE" 191 \
    mcwtrpdoors:oak_barn_trapdoor mcwtrpdoors:oak_glass_trapdoor mcwtrpdoors:metal_trapdoor \
    mcwtrpdoors:print_classic mcwtrpdoors:print_whispering \
    || fail "the creative tab check failed"

# ---------------------------------------------------------------- controls
say "unknown ids, impossible states and a plain stick are refused"
if ctl give mcwtrpdoors:not_a_trapdoor 1 >/dev/null 2>&1; then
    fail "give mcwtrpdoors:not_a_trapdoor succeeded"
fi
ctl setblock 66 80 12 mcwtrpdoors:bogus_trapdoor >/dev/null 2>&1 || true
[ "$(block_name 66 80 12)" = minecraft:air ] || fail "mcwtrpdoors:bogus_trapdoor became a block"
if ctl setblock 68 80 12 \
    "mcwtrpdoors:oak_barn_trapdoor[facing=up]" >/dev/null 2>&1; then
    got=$(block_state 68 80 12)
    case "$got" in *facing=up*) fail "an impossible trapdoor state was accepted: $got" ;; esac
fi
ctl give minecraft:stick 1 >/dev/null
ctl wait 2
ctl select minecraft:stick >/dev/null
ctl tp 70.5 80 14.5
ctl wait 2
ctl place 70 80 12 --item minecraft:stick >/dev/null 2>&1 || true
ctl wait 3
[ "$(block_name 70 80 12)" = minecraft:air ] || fail "a stick placed $(block_name 70 80 12)"
echo "unknown ids and impossible states refused; a stick placed nothing"

say "vanilla oak_trapdoor baseline in the same harness"
ctl command "clear @s" >/dev/null
ctl setblock 72 80 20 "minecraft:oak_trapdoor[facing=east,open=false,powered=false]" >/dev/null
ctl tp 72.5 80 22.5
ctl wait 3
ctl look-at-block 72 80 20 >/dev/null 2>&1 || true
ctl interact 72 80 20 >/dev/null
ctl wait 3
[ "$(prop "$(block_state 72 80 20)" open)" = true ] || fail "vanilla oak_trapdoor did not open on right-click"
ctl look-at-block 72 80 20 >/dev/null 2>&1 || true
ctl interact 72 80 20 >/dev/null
ctl wait 3
[ "$(prop "$(block_state 72 80 20)" open)" = false ] || fail "vanilla oak_trapdoor did not close again"
echo "vanilla oak_trapdoor opens and closes the same way"

# ---------------------------------------------------------------- evidence
cp "$SCRATCH/scene.png" "$PORT/tools/.e2e-last-scene.png" 2>/dev/null || true
echo "PASS: ${#BLOCKS[@]}/179 ids bind, 176 ride minecraft:oak_trapdoor and the 3 metal ones minecraft:iron_trapdoor, all 64 states of oak_barn_trapdoor read back every property (waterlogged included), a trapdoor item places with a facing and half and opens/closes on right-click and on redstone, the metal trapdoors ignore the hand and open on redstone like vanilla iron_trapdoor, a placed trapdoor drops itself in survival, the trapdoor scene renders (screenshot differs from the empty frame, no missing texture), the creative tab lists 191 items, and unknown ids, impossible states and a stick are refused"
echo "EXIT:0"
exit 0
