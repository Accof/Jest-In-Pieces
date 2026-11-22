# Operation Drowned Front — Implementation tracker

Read first in every session, update at the end of every milestone. One milestone is authorised
at a time; **the next one starts only when the user says so**. Milestone 4 is a hard visual gate.

## Status board

| # | Milestone | Status | Checkpoint | Approval |
|---|---|---|---|---|
| 0 | Preservation and planning | **done, awaiting review** | commit `a5376f1`; tag `legacy-drowned-trenches-baseline` (= `0772251`) | user review |
| 1 | Objective separation (`ELIMINATION` / `SURVIVAL`) | not started | | user review |
| 2 | New battlefield geometry (two networks, No Man's Land, H.Q. exit) | not started | | **user playtest** |
| 3 | Terrain and functional cover (craters, wire, routes, enemy navigation) | not started | | user review |
| 4 | Reference atmosphere (green-grey fog, sky, wet mud, silhouettes) | not started | | **HARD VISUAL APPROVAL — STOP** |
| 5 | Physical impacts (surface-aware holes, mud, dust, wood, metal, water) | not started | | user review |
| 6 | Core combat hazards (MG nests, suppression, artillery) | not started | | user playtest |
| 7 | Director foundation (tension/alertness, event points, budgets, overlay) | not started | | user review |
| 8 | Initial director events (silhouette, bridge reinforcements, parapet firefight) | not started | | user playtest |
| 9 | Expanded battlefield activity | not started | | user review |
| 10 | Enemy trench suspense | not started | | user playtest |
| 11 | Procedural variants | not started | | user review |
| 12 | Performance and polish | not started | | user review |
| 13 | Final integration | not started | | final approval |

**Next action:** user reviews Milestone 0 (this document, `DROWNED_FRONT_ARCHITECTURE.md`,
`DROWNED_FRONT_DECISIONS.md`, `archive/legacy_drowned_trenches/RESTORE.md`), answers the open
questions below, and authorises Milestone 1.

### Open questions for the user (before Milestone 1–2)
1. **Performance budget** (D-10): which Mac, what resolution, and is 60 fps the bar?
2. **Legacy level objective** (D-03): the legacy scene keeps the old kill-all rule, yes?
3. **Crossing length** (C2): start at ~90 m of No Man's Land and tune after the first playtest?
4. **Should the field soldiers** (today cosmetic, never fight) become real combatants in the new
   front, or stay as battlefield dressing with the director adding real ones? (Leaning: dressing
   stays cosmetic; the director spawns real ones with duties.)

---

## Milestone 0 — Preservation and planning (Session Zero, 22 Nov 2026)

### Acceptance (from the package, B1/F)
- [x] Repository inspected: Git clean at `0772251`, no stash, no untracked user work; `.godot/` ignored.
- [x] Full baseline: tag `legacy-drowned-trenches-baseline` → `0772251`.
- [x] `archive/legacy_drowned_trenches/` with snapshot (34 files, 828 KB), `files.tsv`, two hash
      manifests (34 snapshot files; 89 originals incl. 81 art files), `check.sh`, `restore.sh`, `RESTORE.md`.
- [x] Runnable legacy scene: `scenes/legacy_drowned_trenches.tscn` (`seed=`, `floor=`, `god`,
      `LEGACY_QUIT_AFTER` for a headless smoke test).
- [x] Baseline tests run and recorded (below); rendered legacy check (below).
- [x] Restoration proven **from the archive alone** in a damaged scratch copy (below).
- [x] Docs: `DROWNED_FRONT_MASTER_PLAN.md`, this tracker, `DROWNED_FRONT_ARCHITECTURE.md`,
      `DROWNED_FRONT_DECISIONS.md`; the package itself at `docs/DROWNED_FRONT_PACKAGE_v1.0.md`;
      the reference image at `docs/reference/no_mans_land_reference.png`.
- [x] No change to the trench generator, the battlefield, enemies, weapons or any protected system.

### Files added (nothing modified, nothing deleted)
```
archive/legacy_drowned_trenches/{RESTORE.md,files.tsv,SNAPSHOT.sha256,ORIGINALS.sha256,check.sh,restore.sh}
archive/legacy_drowned_trenches/snapshot/{.gdignore,trench/*,shared/*,tests/*,tools/*,docs/*}
scenes/legacy_drowned_trenches.tscn, scripts/dev/legacy_drowned_trenches.gd (+ .uid)
docs/DROWNED_FRONT_{MASTER_PLAN,IMPLEMENTATION_TRACKER,ARCHITECTURE,DECISIONS}.md
docs/DROWNED_FRONT_PACKAGE_v1.0.md, docs/reference/no_mans_land_reference.png
```

### Baseline test run (headless, container, Godot 4.7.2.stable, `--headless --fixed-fps 60`, 2 cores)
Command for each: `godot --headless --fixed-fps 60 --path . res://scenes/<scene>.tscn [-- args]`.
Script: `/tmp/baseline/run_suite.sh` (logs in `/tmp/baseline/*.log`, not committed).

| Scene | Time | Result | Notes |
|---|---|---|---|
| test_game | 7 s | observations only, no FAIL | 40 mazes ok; one loop round the game |
| test_trench | 4 s | **0 failed** | 30 layouts connected, 260–290 m |
| test_trench_level | 591 s | 1 failed | `men cross the player's way ahead of him` (suspense; known flaky, see below) |
| test_events | 28 s | observations only, no FAIL | every event room played by the bot |
| test_cover | 3 s | 0 FAIL | |
| test_nav | 47 s | 0 FAIL | |
| test_nav -- trench | 70 s | 0 FAIL | crowd on trench floors 3, 6, 9 |
| test_killcam | 63 s | 1 failed | `a body going off a 5 m drop gets a tracking or elevated shot (low_side)` |
| test_curse | 23 s | 2 failed, 1 script error | `witzsoldat/rattlejack: the neck snaps over (49/50 deg)`; the `_place_marksman` freed-object error (below) |
| test_death, test_legs, test_joints, test_smg, test_blast, test_mp18, test_arms, test_anim_ref, test_stairs_walk, test_wander, test_base, test_locker, test_witz_looks, test_pools, test_drum_clear, test_rifle, test_grenade | 1–36 s | 0 FAIL | |
| test_limbs | 13 s | 1 failed | `gun: a pistol out and shooting (0 shots)` |
| test_revolver | 4 s | 1 failed | `about two shots a second` |
| test_crossbow | 9 s | 1 failed | `both hands on the bolt (84 of 120 frames)` |
| test_motion | 9 s | 1 failed | `stop: the planted feet hold the ground (0.44 m/s)` (passes on other runs: 0.31) |
| test_rattlejack | 46 s | 5 failed, 1 script error | `changes the pan when it runs dry`; 4 × `headshot: planted feet do not slide (0.07 m)` |
| test_throat | 10 s | 2 failed | `witzsoldat/rattlejack: both hands go to the throat (0.22/0.34 m)` |
| test_zornhauptmann | 53 s | 2 failed, 2 script errors | `step_back/step_round: a wind-up you can see (0.00 m)` |
| test_klapper | 23 s | 1 failed, 4 script errors | `and still has meat and bone inside` |
| test_stake | — | **scene missing** | README lists `scenes/test_stake.tscn`; it does not exist in the tree (stale README) |

**Known baseline failures and flakiness (pre-existing at `0772251`; not to be "fixed" by the
front work, but not to get worse).** Earlier on 22 Nov the same scenes were run on the previous
commit `1f9b556`: the Rattlejack planted-feet and pan failures, the officer's sabre wind-up, the
Klappersoldat's "meat and bone" and the `kind` script errors were all already there. The Rattlejack
fire test and the officer's combat section vary run to run (0 to 17 shots) because they build an
**unseeded** level and sometimes spawn the man behind a wall; the suspense encounter check in
`test_trench_level` has failed on and off across the last several commits for the same reason. The
killcam `low_side` failure was first seen in this run and is not yet classified (re-run before
Milestone 1 touches `game.gd`). `SCRIPT ERROR: Invalid access to property or key 'kind' on a base
object of type 'previously freed'` at `TrenchBattle._place_marksman` (`trench_battle.gd:322`)
appears whenever a test tears a trench floor down within two physics frames of building it: the
function awaits two frames and then reads a `BattleDuty` that has been freed. Harmless in play;
worth a validity guard when Milestone 2 reuses the duty code. The throat, curse neck, limbs pistol,
revolver rate and crossbow hands failures are animation/weapon details outside this project's scope.

### Rendered legacy check (Forward+, llvmpipe, 960 × 540)
`xvfb-run -a -s "-screen 0 960x540x24" godot --path . --resolution 960x540 --rendering-driver vulkan --rendering-method forward_plus res://scenes/test_trench_level.tscn -- views render`
→ the trench floor built in 4.2 s; six frames in about 3 minutes: `/tmp/tr_top.png` (the whole
layout from above) and `/tmp/tr_eye_0..4.png` (eye height along the route: the way in, a
communication trench, the fire trench with its sandbags and duckboards, the H.Q. bunker portal).
Kept at `docs/reference/legacy/legacy_top.png` and `legacy_route_0..4.png` as the "before"
pictures for Milestone 4's comparison. (The HUD and the floor banner are in frame: these are
real in-game renders.) Earlier renders of the same build (battle views, fog banks, cinematic
corners) exist in the project notes from 17–21 Nov.

### Restoration test (from the archive alone)
In a scratch copy of the project: deleted `scripts/world/trench_maze.gd`, overwrote
`scripts/world/trench_art.gd` and `shaders/mud_terrain.gdshader` with junk, deleted the archive
directory, then copied **only** `archive/legacy_drowned_trenches/` back in.
```
archive/legacy_drowned_trenches/check.sh --live   → reported exactly the 3 damaged files, exit 3
archive/legacy_drowned_trenches/restore.sh         → "restored" × 3
archive/legacy_drowned_trenches/check.sh --live   → ok (every legacy file byte-identical)
godot --headless --path . --import
LEGACY_QUIT_AFTER=3 godot --headless --fixed-fps 60 --path . res://scenes/legacy_drowned_trenches.tscn -- seed=1916
   → legacy Drowned Trenches: floor 3, TrenchMaze, 15 enemies, seed 1916 / ok (trench)
godot --headless --fixed-fps 60 --path . res://scenes/test_trench.tscn   → TRENCH: 0 failed
```

### Finding: the cloud working copy had stale generated art
Hashing the Mac's tree against the cloud container's copy showed every script, scene, shader and
every `art/trench` file identical, but 106 **generated** files differed (`art/level/*`, `art/blood/*`,
`art/oil/*`, `art/klapper/sfx/*.wav`, two Klappersoldat colour maps): older outputs of the
`tools/gen_*.py` generators that had never been re-synced. The archive's `ORIGINALS.sha256` was
therefore recomputed **on the Mac** (the git tree is the authority) and the 106 files were copied
from the Mac into the container, which now matches the repository for everything the game loads
(only Blender/Tripo source files, which the game never reads, are absent in the container). Rule from
here: manifests are computed on the Mac; renders made in the container are of the same bytes as
the Mac's. The baseline renders above were made before this sync; `art/level/fx_fire.png`,
`fx_smoke.png` and `wall_conc.png` (the only trench-loaded files affected) differed, so the
smoke/fire sprites and the H.Q. portal's concrete in those six frames are the older generator
output. The "before" set will be re-rendered at the start of Milestone 4 from the synced bytes.

### Risks carried forward
See `DROWNED_FRONT_ARCHITECTURE.md` §9 and the package's Part J. The three that shape Milestone 2:
`TrenchArt`–`TrenchMaze` coupling (D-02), the fixed 32 × 28 grid and heightfield size (D-04), and
navigation over open ground (D-05).

---

## Milestone 1 — Objective separation (not started)
**Scope:** `Game.objective` (D-03); SURVIVAL on trench floors; HUD/banners/exit light; no finale
on SURVIVAL; legacy scene keeps ELIMINATION via a flag. **Files:** `scripts/game/game.gd` (the
hunks in Architecture §2), `scripts/dev/legacy_drowned_trenches.gd`, new `scripts/dev/test_objective.gd`
+ scene. **Tests:** new objective test (bunker floor still needs all kills and runs the killcam once;
trench floor exit usable with enemies alive, no killcam, tickets/kills/curse still counted, death and
return to base, upgrades offered at the exit); re-run `test_killcam`, `test_game`, `test_curse`,
`test_base`, `test_trench_level game`. **Acceptance:** package F, row 1.

## Milestone 2 — New battlefield geometry (not started)
**Scope:** `FrontMaze` + builders (D-02, D-04): two networks, No Man's Land strip, H.Q. exit in the
enemy network; seeded connectivity test over many seeds; a route the player can walk end to end
(the route-walker from `test_trench_level game` extended). **Gate:** user playtest on the Mac.

(Milestones 3–13: scope as in the package; detailed when authorised.)
