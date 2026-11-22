# Operation Drowned Front — Implementation tracker

Read first in every session, update at the end of every milestone. One milestone is authorised
at a time; **the next one starts only when the user says so**. Milestone 4 is a hard visual gate.

## Status board

| # | Milestone | Status | Checkpoint | Approval |
|---|---|---|---|---|
| 0 | Preservation and planning | **approved 22 Nov** | commits `a5376f1`, `4a5f5a1`; tag `legacy-drowned-trenches-baseline` (= `0772251`) | approved |
| 1 | Objective separation (`ELIMINATION` / `SURVIVAL`) | **approved 22 Nov** (+ [E] door follow-up `b56bd54`) | commits `ccbbfe8`, `cbe2ac3`, `b56bd54` | approved |
| 2 | New battlefield geometry (two networks, No Man's Land, H.Q. exit) | **done**; Andrew: "continue with the plan" (22 Nov) — his own playtest still to come | commits `663727e`, `4667339` | **user playtest** (pending) |
| 3 | Terrain and functional cover (craters, wire, routes, enemy navigation) | **done, awaiting review** | commit `104a80e` | user review |
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

**Performance baseline on the Mac: PENDING** (Andrew, 22 Nov: deferred; not a blocker for M2; no
numbers are to be invented). When convenient: `godot --path . res://scenes/legacy_drowned_trenches.tscn
-- perf=30 god`, play a minute, paste the `PERF` lines here.

**Next action:** Andrew reviews Milestone 3 and plays the Front (`/Applications/Godot.app/Contents/MacOS/Godot
--path . res://scenes/play_front.tscn -- god`; M2's layout/scale/traversal judgement and M3's cover and
wire are both still his to make); Milestone 4 (the reference atmosphere, the hard visual gate) only on his word.

### Decisions taken by Andrew on 22 Nov (answers to Session Zero's questions)
1. Performance: 60 fps at his normal development resolution; measure the real baseline on the Mac
   first; no unverified claims, no premature optimisation (D-10).
2. The legacy trenches keep kill-all (ELIMINATION); the Drowned Front is SURVIVAL; bunkers stay
   ELIMINATION (D-03).
3. No Man's Land starts at ~90 m, a prototype dimension (D-12).
4. Field soldiers stay cosmetic dressing; the director adds separate real soldiers on the existing AI (D-13).
5. Added requirement: the 138 MB of scanned art must be recoverable from git or another independent
   backup, not just hashed — verified, see D-01.

---

## Milestone 0 — Preservation and planning (Session Zero, 22 Nov 2026)

### Acceptance (from the package, B1/F)
- [x] Repository inspected: Git clean at `0772251`, no stash, no untracked user work; `.godot/` ignored.
- [x] Full baseline: tag `legacy-drowned-trenches-baseline` → `0772251`.
- [x] `archive/legacy_drowned_trenches/` with snapshot (34 files, 828 KB), `files.tsv`, two hash
      manifests (34 snapshot files; 89 originals: 32 code files and 57 art files), `check.sh`, `restore.sh`, `RESTORE.md`.
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

## Milestone 1 — Objective separation (22 Nov 2026)

### Acceptance (package F, row 1)
- [x] `ELIMINATION` on bunker floors, unchanged: exit shut while anyone lives; the last kill opens it
      and runs the final-kill camera once, with its brutality report; upgrades at the exit.
- [x] `SURVIVAL` on trench floors: the exit (H.Q.) is open and lit green from the first moment with
      every enemy alive; the exit works with enemies alive; no final-kill camera, no report, no
      `EXIT OPEN` banner, ever on that floor, even with every enemy dead.
- [x] Kills, headshots, tickets, the Carnival Curse, the records (`total_kills`), lifesteal, slow-mo,
      upgrades, death, history, best floor: the same code paths on both modes (nothing reads
      `remaining` except the ELIMINATION branch and the HUD).
- [x] Enemy counts and the battle unchanged on trench floors (15 + the guaranteed officer on floor 3;
      24 on floor 6; `TrenchBattle` hands out duties as before).
- [x] Floor transitions 1 → 6: bunker/bunker/trench/bunker/bunker/trench with the right objective,
      exit state and light at the start of each, and the finale state reset each floor.
- [x] Save compatibility: no new key; the in-memory save's keys are identical before and after a
      SURVIVAL floor and the written file reads back with the same keys; floors/best floor/history
      recorded as before.
- [x] The legacy scene (`survival_trenches = false`) keeps ELIMINATION on its trench floor.

### Files
- `scripts/game/game.gd` (5 hunks, +69/−0 lines against the archived copy): `enum Objective`,
  `objective`, `@export survival_trenches`; `next_floor()` sets the objective and opens the exit on
  SURVIVAL, banner adds `REACH THE ENEMY H.Q.`; `_on_clown_died()` wraps the finale/exit block in
  `if objective == Objective.ELIMINATION`; new `_open_exit()` (shared by both); `_refresh_hud()`
  shows `Kills: n` + `REACH THE ENEMY H.Q. - the green door` on SURVIVAL, `Clowns left: n` +
  `EXIT OPEN` otherwise.
- `scripts/dev/legacy_drowned_trenches.gd`: `game.survival_trenches = false`; prints the objective;
  `perf=SECONDS` attaches the frame probe.
- `scripts/dev/frame_probe.gd` (new): frame-time recorder for the Mac baseline (D-10).
- `scripts/dev/test_objective.gd` + `scenes/test_objective.tscn` (new): sections `bunker`,
  `survival`, `survival_clear`, `legacy`, `save`, `transitions` (63 checks).
- `scripts/dev/test_trench_level.gd` and `scripts/dev/test_nav.gd`: both drive the player over the
  whole route; on a SURVIVAL floor that walks him onto the open H.Q. door, which brings up the upgrade
  screen and pauses the tree (`_set_state(UPGRADE)` pauses). Both fixtures now shut the exit for the
  drive (the walker restores it). These were the only regressions the change caused, both in tests.
- `docs/DROWNED_FRONT_DECISIONS.md` (D-01 verification, D-03, D-10, D-12, D-13), this tracker,
  `DROWNED_FRONT_ARCHITECTURE.md` §2, `README.md`.
- Not touched: weapons, enemies, gore, ragdolls, killcam code itself (`kill_cam.gd`), curse,
  events, base, saves' format, the legacy trench classes. `check.sh --live` now reports exactly two
  files: `scripts/game/game.gd` (a shared-reference file; the objective hunks above) and
  `scripts/dev/test_trench_level.gd` (the additive walker fixture). Both are listed here as D-02
  requires; the legacy level's own behaviour is unchanged (the legacy scene forces ELIMINATION).

### Tests (headless, container, `godot --headless --fixed-fps 60 --path . res://scenes/<scene>.tscn`)
| Scene | Result | Against the M0 baseline |
|---|---|---|
| **test_objective** (new) | **0 failed** (63 checks), 31 s; run twice | — |
| test_killcam | 1 failed: `low_side` shot variety in `fall` | same single failure as baseline; the `floor`, `double`, `interrupt`, `event`, `report` sections (the ones this change could affect) all pass |
| test_game | observations as before: 6 clowns, all shot → `remaining=0 exit_open=true`, upgrade offered, floor 2, death saves | same |
| test_curse | 0 failed (the `kind` script error as before) | baseline had 2 neck-angle failures; passes now (that check is physics-flaky) |
| test_base | 0 FAIL | same |
| test_events | all rooms played, event-room upgrades still offered | same |
| test_trench | 0 failed | same |
| test_trench_level `game battle suspense nav` | 0 failed after the walker fix (first run: 1 failed, the walker stopped at the open H.Q.) | same |
| test_locker, test_cover | 0 FAIL | same |
| test_nav -- trench | first run: 15,876 "stuck" frames (the test hops the player onto random route cells, the open H.Q. door paused the floor in the upgrade state); the test now shuts the exit for its 30 s runs → `stuck >3s 0`, in a wall 0, same as baseline | fixture fixed, same |
| legacy scene smoke | `floor 3, TrenchMaze, 15 enemies, seed 1916, objective ELIMINATION / ok (trench)` | — |

### M1 follow-up (22 Nov, approved by Andrew): the H.Q. door takes [E]
On a SURVIVAL floor the upgrade screen used to come up the moment the player was within 1.3 m of
the open H.Q. door (the ELIMINATION rule), so brushing past it mid-fight would end the floor, and
two test fixtures that drive the player over the route tripped it. Now a SURVIVAL floor's exit
carries an `ExitDoor` (`scripts/world/exit_door.gd`, a `StaticBody3D` on `LAYER_WORLD` with
`prompt()`/`use()`, the same mechanism as event-room doors and mounted guns): look at it within
2.4 m and the prompt `[E] ENTER THE H.Q.` shows; [E] offers the upgrades. `Game._process`'s
proximity trigger now runs only on ELIMINATION floors, which are unchanged (no door node is added
there). The HUD on SURVIVAL says `… the green door, [E] to go in`. The two fixture hacks were
reverted (`test_trench_level.gd` is byte-identical to the archive again; `test_nav.gd` as before):
`test_nav -- trench` → `stuck >3s 608` of 181,901 frames (baseline 125; the pause-induced 15,876 is
gone; this count varies run to run with the chase), `test_trench_level game` → route walked 46/46,
0 failed. `test_objective` grew to 69 checks (proximity does nothing on SURVIVAL, the prompt text,
[E] works with enemies alive and with every enemy dead, no door on ELIMINATION or legacy floors):
0 failed. `test_killcam floor report event` 0 failed; `test_game` at exit → upgrades as before.

### Known and noted
- The HUD on SURVIVAL shows the run's kill total, not a per-floor count.
- Mac performance baseline: **PENDING** (deferred by Andrew on 22 Nov); nothing claimed.

### Recoverability of the scanned art (Andrew's added requirement)
`git archive legacy-drowned-trenches-baseline art/trench art/level/fx_*.png art/level/wall_conc.png`
extracted 139 MB into a scratch directory; all 57 art files hashed identical to `ORIGINALS.sha256`;
`git fsck` clean; `origin/main` on GitHub was at `0772251` (the baseline commit), so the bytes are
also off-machine. The tag itself was not on GitHub yet: `git push origin main --tags`.

## Milestone 2 — New battlefield geometry (22 Nov 2026)

### What was built
`FrontMaze` (`scripts/world/front/front_maze.gd`) and `FrontArt` (`front_art.gd`): two trench
networks, each laid out by the legacy `TrenchMaze._layout()` in a scratch instance, copied into one
32 × 108-cell grid (ours at the rear edge as it always was; theirs turned 180° so its fire trench
faces ours and its rear ends at the world's front edge), 52 rows (78 m) of open No Man's Land
between the blocks — **fire trenches 97 m apart, wire belts about 85 m** — on one carved
heightfield (336k samples at 0.2 m), with up to three *assault ramps* a side cut through the
parapet, two wire belts with gaps at the saps and the ramps, 90–150 shell holes thickest in the
middle, dead trees and two wrecked limbers out there, and the H.Q. portal (legacy dressing, [E]
door) at the far end of **their** rear communication trench. Pathfinding is the legacy top layer
(every clear earth cell is a top cell), so `Maze.path` carries the player's route and the brains
across No Man's Land with no new navigation code (D-05 → option (a)). Full design: D-02 (resolved),
D-14. `game.next_floor()` uses `FrontMaze` on SURVIVAL trench floors and `TrenchMaze` when
`survival_trenches` is off (the legacy scene); the legacy `TrenchBattle`/`TrenchField`/`TrenchFog`
are **not** run on the Front (they assume the legacy's single front; the director replaces them in
M6–M9); the ambience does run.

### Acceptance (package F, row 2)
- [x] A generated level contains starting trenches, No Man's Land, enemy trenches and the H.Q. exit.
- [x] The player can walk the complete route: `test_front game` drives the player along the maze's
      own path from the start to the H.Q.: **140 of 140 points reached, 0 stuck**, down at −2.3 m
      in the trenches and up at +0.6 m on the ground, then [E] at the door → upgrades.
- [x] Seeded connectivity: 40 seeds, **0 failed**: every trench cell of each network reachable
      within it, no trench in No Man's Land, a route up out of ours and down into theirs, every
      assault ramp joined to both the start and the exit.
- [x] Enemies spawn on trench cells only (15 + officer on floor 3, 9 of them in the enemy lines),
      none in the open; the crowd navigation test on Front floors 3/6/9: in a wall 0, sunk 0,
      stuck > 3 s 122 of 181,901 frames (the legacy trench: 0–608 run to run).
- [x] Legacy untouched: `check.sh --live` reports only `scripts/game/game.gd`; the legacy scene
      still builds `TrenchMaze … objective ELIMINATION`; `test_trench` 0 failed;
      `test_trench_level game battle nav field` 0 failed (its fixture now sets
      `survival_trenches = false`, as it tests the legacy level; `test_nav` has `trench` = legacy
      and a new `front` mode).
- [ ] **User playtest** — layout, scale, traversal (this gate).

### Files
- New: `scripts/world/front/front_maze.gd` (560 lines; 110 of them the copied carve, 60 the copied
  world build, marked), `scripts/world/front/front_art.gd` (250 lines; the wire belt and No Man's
  Land dressing are adapted copies), `scenes/play_front.tscn` + `scripts/dev/play_front.gd`,
  `scenes/test_front.tscn` + `scripts/dev/test_front.gd`, `docs/reference/front_m2/m2_*.png`.
- Modified: `scripts/game/game.gd` (maze choice, no battle on the Front, a build print),
  `scripts/dev/test_objective.gd` (the SURVIVAL floor is the Front now), `scripts/dev/test_nav.gd`
  (`front` mode; `trench` pinned to the legacy), `scripts/dev/test_trench_level.gd` (two fixtures
  pinned to the legacy level — this is a legacy-test file in the archive; the change is the one
  line `game.survival_trenches = false` in each of its two game set-ups, so `check.sh --live` will
  now report it as well as `game.gd`), docs, README.
- Not touched: `trench_maze.gd`, `trench_art.gd`, `trench_battle.gd`, `trench_field.gd`,
  `trench_fog.gd`, `trench_ambience.gd`, `battle_duty.gd`, shaders, art, weapons, enemies, gore.

### Tests (headless, container)
| Scene | Result |
|---|---|
| **test_front** `layouts geo game` | **0 failed** (40 seeds; parapets/fire steps/ramps/wire on each side's own front; the full walk; [E]) — 174 s |
| test_front `views render` (Forward+) | 6 frames in 567 s: `docs/reference/front_m2/` |
| test_objective | 0 failed (69 checks; survival sections on the Front) |
| test_trench, test_trench_level `game battle nav field`, test_nav `trench` | 0 failed (legacy) |
| test_nav `front` | in a wall 0, sunk 0, stuck 122 frames |
| test_game, test_events, test_cover, test_motion, test_anim_ref | as baseline |
| test_killcam | 1 failed (`low_side`, as baseline) |
| test_curse | 2 failed (neck angle as baseline; `beside a wall … 0.08 m` is a physics-flaky check seen before) |
| test_zornhauptmann | flaky: 3, 4, 5, 7 and 11 failed across runs. Its `_floor()` builds floor 3, so the officer is now tested on the Front. The extra failures are one pre-existing pattern — the officer sees the player, has the pistol up, and never fires — which also occurred on the legacy level (0–1 shots in 1 of 4 runs on 22 Nov) but seems more frequent here (2 of 7 runs). Not a geometry fault; **to be looked at in Milestone 3** with the rest of enemy behaviour on the Front. |

Build time headless in the container: 3.8 s a floor average, 4.3 s worst (carve 2.5 s).

### Known limitations (for the playtest)
- **Scale and flatness.** No Man's Land is 78 m of gently rolling ground with shell holes; from our
  parapet the enemy line is a dark band under the haze (fog begins at 18 m and the far side is ~100 m
  off). Whether 90 m feels right is exactly what the playtest is for (D-12).
- **Craters are holes, not yet cover.** The legacy crater profile is used (0.35–1.7 m deep, rims
  up to ~40°). Crouch cover, enterable slopes and wire that shapes routes are Milestone 3.
- **Flank routes.** The fire trenches stop two cells short of the grid's sides, so a player (or
  soldier) can go up a ramp behind the fire trench and round its end along the edge of the world
  instead of over the top. 13 of 80 main routes in the seed test did. Kept as a second route for
  now; M3 decides (wire across the flanks, or make them a feature).
- **The enemy network reads as a mirror of ours** (same generator, same dressing, signs and all).
  Distinctness is M3/M10.
- **No battle, no director yet:** the soldiers stand their posts only in the sense that
  `ClownBrain` idles, wanders and hunts; nothing fires across No Man's Land, no fog banks, no field
  soldiers. The far side's horizon smoke and fires sit beyond the enemy lines.
- **Atmosphere is the legacy storm day** (Milestone 4).
- **Build time on the Mac unmeasured** (D-10 pending); 3.8 s headless here.
- The `test_zornhauptmann` flakiness above.

### How to play it
```
cd ~/ClownShooter
godot --path . res://scenes/play_front.tscn -- god            # straight onto the Front, god mode
godot --path . res://scenes/play_front.tscn -- seed=1916      # the layout in the M2 renders
godot --path . res://scenes/play_front.tscn -- perf=30        # with the frame-time probe (D-10)
```
Or a normal run: floor 3. You start at our rear; the fire trench is forward (the HUD says REACH
THE ENEMY H.Q.); climb one of the ramps cut through the parapet (gaps in the wire mark them),
cross, drop down a ramp into their fire trench, work back through their communication trenches to
the H.Q. portal at the far edge, [E] to go in.

## Milestone 3 — Terrain and functional cover (22 Nov 2026)

Authorised by Andrew's "just continue with the plan" after M2 (taken as M3 only; his M2 playtest is
still pending and nothing here forecloses it: No Man's Land's length is one number).

### What was built (D-15)
- **Shell holes that are cover:** No Man's Land's holes are 2.2–4.5 m across and 0.9–1.7 m deep,
  a cosine bowl with a low lip (walls ≤ ~38°, floors chest-deep, a crouched head under the rim),
  deeper holes winning where they overlap. 150 attempts a floor, ~55–60 holes of 2.2 m+ placed.
- **Wire that shapes the way:** the belt plan lives in `FrontMaze.wire_belts`; the cells under it
  leave the top layer (brains path through the gaps); the player is stopped by collision on
  `LAYER_RAMP` (sight and rounds pass). Gaps at every sap and assault ramp; 3–5 short belts in the
  middle. The M2 flank routes are closed by this.
- **Crouch** (Ctrl or C): capsule and eye drop, pace halves, stands only with headroom;
  `eye_height()`/`chest_height()` ready for the brains (M6).
- **Enemy navigation across open ground:** nothing new was needed beyond the wire cells; a
  rifleman alerted in their fire trench comes over the top, across and up to rifle range.
- **Spawn validation:** `cells_far_from` walks the real graph (ramps, top, wire gaps), so every
  spawn cell has a path to the start and the exit; the test checks none is on the open ground.

### Acceptance (package F, row 3)
- [x] Craters give crouch cover and are enterable: 57 holes on the test seed, 45 chest-deep, 46
      hide a crouched head, **all 57 walkable** (no wall over 45° over a stride; steepest 43°).
- [x] Wire shapes but does not break routes: 40 seeds, 0 failed, with the wire cells removed;
      the main route used an assault ramp 69 of 80 times, a sap's gap otherwise; the player is held
      at a belt (2.6 m on in 4 s against the wire 2.7–6.3 m away) and walks through a gap (11.9 m).
- [x] Enemies path across: a rifleman from their fire trench, 95 m off, crosses the open ground
      (8,574 of 9,000 frames up top, 0 in the wire) and closes to 16 m, where riflemen stop to fire.
- [x] No blocked seeds; spawns only on trench cells with a path.
- [x] The full walk still clean: 140 of 140 points, 0 stuck, 0 side-steps, 0.11 m worst off the ground.

### Files
- `scripts/world/front/front_maze.gd`: `wire_belts`, `_plan_wire`, `belt_band`, `wire_at`,
  `_top_layer` override, `wire_cells`; cover-sized `_craters`; the bowl/lip stamping in `_carve`.
- `scripts/world/front/front_art.gd`: `_wire` from the plan, `_wire_belt`, `_wire_block`,
  `_wire_body` (LAYER_RAMP).
- `scripts/player/fps_player.gd`: crouch (`_tick_crouch`, `_headroom`, `eye_height`,
  `chest_height`, `crouch`, the capsule refs). The one protected-system file touched: additive,
  movement otherwise unchanged (test_motion, test_stairs_walk, test_nav as before).
- `scripts/dev/test_front.gd`: sections `cover`, `wire`, `crossing`; `views` adds `shell_hole`,
  `shell_hole_standing`, `wire`.
- Docs: D-15, this tracker, architecture §8a, README.

### Tests (headless, container)
| Scene | Result |
|---|---|
| **test_front** (all sections) | **0 failed**; build 4.1 s avg / 4.6 s worst headless |
| test_objective | 0 failed |
| test_nav `front` | in a wall 0, sunk 0, **stuck 0**, inside another 22 |
| test_nav `trench`, test_trench, test_trench_level `game nav` | 0 failed (legacy) |
| test_killcam `floor report` | 0 failed |
| test_game, test_cover, test_motion, test_events, test_base, test_stairs_walk, test_legs | as baseline |
| test_curse | 1 failed (`rattlejack: the neck snaps over (49 deg)`, baseline) |
| legacy scene | `TrenchMaze … objective ELIMINATION / ok` |

### Known and noted
- Enemies do not collide with the wire (player-only layer); they route round it. A soldier pushed
  off his path (a ragdoll shove, a grenade) could stand in a belt. Acceptable for now; revisit with
  the impact/AI work if it shows.
- The brains still aim at a fixed 1.25 m and look for the head at 1.5 m; crouching hides the
  *player's view* behind a rim today, and will hide him from rifles and MGs when M6 reads
  `eye_height()`/`chest_height()`.
- Crater water (decorative planes in holes over 0.55 m) now sits in deeper holes: wading, no
  footstep sound change out there yet.
- Fire-step bays under a bridge or at a sap keep their legacy behaviour; nothing in the trenches changed.
- Mac performance still **PENDING**.

(Milestones 4–13: scope as in the package; detailed when authorised.)
