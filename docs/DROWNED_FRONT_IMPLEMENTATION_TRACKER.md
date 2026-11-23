# Operation Drowned Front — Implementation tracker

Read first in every session, update at the end of every milestone. One milestone is authorised
at a time; **the next one starts only when the user says so**. Milestone 4 is a hard visual gate.

## Status board

| # | Milestone | Status | Checkpoint | Approval |
|---|---|---|---|---|
| 0 | Preservation and planning | **approved 22 Nov** | commits `a5376f1`, `4a5f5a1`; tag `legacy-drowned-trenches-baseline` (= `0772251`) | approved |
| 1 | Objective separation (`ELIMINATION` / `SURVIVAL`) | **approved 22 Nov** (+ [E] door follow-up `b56bd54`) | commits `ccbbfe8`, `cbe2ac3`, `b56bd54` | approved |
| 2 | New battlefield geometry (two networks, No Man's Land, H.Q. exit) | **done**; Andrew: "continue with the plan" (22 Nov) — his own playtest still to come | commits `663727e`, `4667339` | **user playtest** (pending) |
| 3 | Terrain and functional cover (craters, wire, routes, enemy navigation) | **done**; Andrew: "continue" (22 Nov) — his own playtest still to come | commit `104a80e`, `5d9baaa` | user review (pending) |
| 4 | Reference atmosphere (green-grey fog, sky, wet mud, silhouettes) | **APPROVED 22 Nov 22:09** — after five gate iterations on Andrew's live feedback (glint, sky, fog banks, litter, colour match, ground readability), his word: "you were right. i needed to reload the scene. Continue with the master plan" | commits `f13e92c` … `12ca5c7`; tag `drowned_front_approved_atmosphere`; `docs/reference/approved_atmosphere/` | approved |
| 5 | Physical impacts (surface-aware holes, mud, dust, wood, metal, water) | **done**; Andrew: "continue" (22 Nov 23:26) — his own shoot-around still to come | commits `bcde05b`, `ee8c88d`, `30c7c2d` | user review (pending) |
| 6 | Core combat hazards (MG nests, suppression, artillery) | **done, awaiting playtest** (built 23 Nov 00:15; the Mac was offline at the time — bundle `m6.tgz` delivered in chat, committed when it is back) | commit pending | user playtest |
| 7 | Director foundation (tension/alertness, event points, budgets, overlay) | not started | | user review |
| 8 | Initial director events (silhouette, bridge reinforcements, parapet firefight) | not started | | user playtest |
| 9 | Expanded battlefield activity | not started | | user review |
| 10 | Enemy trench suspense | not started | | user playtest |
| 11 | Procedural variants | not started | | user review |
| 12 | Performance and polish | not started | | user review |
| 13 | Final integration | not started | | final approval |

**Performance baseline on the Mac: MEASURED 23 Nov** (Apple M2, ~1900 × 1000, Metal/Forward+): bunker 27 → 60 fps, Front 12–22 → 58 fps standing still, after the light, fog, batching and shadow fixes and FSR 1 at 0.75 recorded in the performance note below; combat not yet measured (M12).

**Next action:** Andrew **playtests Milestone 6** — cross the Front under the two Maxims
(`play_front -- god` first, then without god: are the arcs legible, is the dead ground and the
flank there, do the bursts and belt changes give windows, does crouching in a hole save you, do the
shells telegraph fairly), and shoots a gunner off his gun and takes it. Milestone 7 (the director
foundation) only on his word. Still his: the M2/M3 and M5 judgements, and whether FSR 0.75 reads fine.

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
- Mac performance baseline: deferred by Andrew on 22 Nov; **measured 23 Nov** (see the performance note).

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
- Mac performance: measured 23 Nov (performance note).

## Milestone 4 — Reference atmosphere (22 Nov 2026) — APPROVED

Authorised by Andrew's "continue" after M3 (taken as M4 only). The package's rule for this milestone:
stop after it, present real screenshots against the reference, measured settings, differences,
limitations, and ask for explicit approval; nothing further until it is given.

### What was built (D-16)
- **`FrontAtmosphere`** (`scripts/world/front/front_atmosphere.gd`): the Front's own `Environment`,
  camera attributes and sun; `Game._apply_floor_look()` uses them only when the floor is outdoor
  and the maze is a `FrontMaze`. Not an overlay: sky + depth fog + ambient + a mild grade + materials.
- **Ground**: the scanned mud materials, soaked and darkened (`FrontArt.ground_material()`); the
  baseline wetness out on the field raised and water in the low places; crater water near-black.
- **Smoke**: five low patches drift over No Man's Land on the wind, out of shell holes; the far
  battle's columns thinned and paled; the ground mist in the haze's colour.
- **One visibility model**: `FrontAtmosphere.visibility(a, b)` (group `fog`, which `ClownBrain`
  already asks) — exp(−k·d) with 0.3 (the brains' "unseen") at **55 m**, plus the smoke patches.
- The gate shots are a `test_front` section (`atmos render`): fixed cameras, seed 1916.

### Measured settings (iteration 5 — "match the reference as closely as possible", 22 Nov; 1 was too uniformly green and bright, 2 greyed the fog and sky, 3 pushed the mud brown, 4 fixed the sky coverage and the glint and added the banks and the litter, 5 took the green out and the sky down to the image's weight)
| Part | Setting |
|---|---|
| Sky (`overcast_sky`) | mass (0.33, 0.34, 0.32), body (0.45, 0.46, 0.44), opening (0.66, 0.66, 0.62), warm (0.94, 0.90, 0.80) — the glow where the sun hides, horizon (0.62, 0.62, 0.575), ground (0.26, 0.25, 0.22), energy 0.9, coverage 0.5 (passes 1–3 had 0.82 — see gate feedback), light dir **(−0.3, 0.36, −0.88)**: low, behind the trees on their side |
| Fog (depth) | colour (0.58, 0.585, 0.545), sun scatter 0.3, begin 6 m, end 140 m, density 0.9, curve 1.0, aerial perspective 0.6, sky affect 0.6; volumetric fog on at density 0 (the mist volume adds to it), albedo (0.70, 0.705, 0.65) |
| Light | ambient from sky 0.5; sun energy 0.55, colour (0.86, 0.88, 0.80), angular 6°, **specular 0** (was 0.05: its glint in the trench-floor puddles blinded — Andrew, 22 Nov live on the Mac), shadows opacity 0.65 blur 3, 70 m |
| Exposure / tone | filmic, exposure 0.9, white 6; auto exposure scale 0.22, sensitivity 90–130 |
| Grade | saturation 0.7, contrast 1.06, LUT: shadows ×(1.06, 0.98, 0.88) (brown), mids ×(1.0, 0.995, 0.965), lights ×(1.02, 1.0, 0.93); glow 0.28, HDR threshold 1.1 |
| SSR / SSAO / SSIL | on / 1.5 (radius 1.4) / 0.5 |
| Ground | dry_ground 0.12, puddles 0.95, earth_darkness 0.28, floor_darkness 0.4, rock_darkness 0.5, brightness 0.76, wall_tint (0.60, 0.50, 0.42), **firm_tint (0.80, 0.66, 0.54)** (new uniform in `mud_terrain.gdshader`, default (1, 1, 1): the legacy level renders as before), floor_tint (0.78, 0.68, 0.58), water (0.26, 0.26, 0.22), puddle (0.07, 0.07, 0.06); field wetness 0.5 + up to 0.35 in the low ground; crater water colour (0.085, 0.08, 0.07) / deep (0.045, 0.043, 0.04) |
| Mist volume | tint (0.66, 0.67, 0.61), density 0.12, e-fold 1.4 m, ×2.6 over No Man's Land; bank tint (0.80, 0.80, 0.75) |
| Drifting smoke | 8 patches, 8 m quads, 16 billows each, 22 s life, wind (0.55, 0, 0.18); each counts as an 8 m sphere of optical density 0.06 |
| Fog banks (`FrontFog`) | radius 15–24 m, 3.5–6 m high, peak density 0.45–0.75, ≤3 at once, every 28–60 s, 1.0–1.6 m/s at our lines; puffs (0.72, 0.75, 0.66) |
| Far smoke columns | half the billows, scale ×0.75, colour ×1.25 / alpha ×0.7 of the legacy day's |
| Visibility | k = −ln 0.3 / 55 m: **0.65 at 20 m, 0.30 at 55 m, 0.14 at 90 m** (test bounds: < 0.31 at 55, < 0.16 at 90) |

### The gate shots (Forward+, software Vulkan in the container, 1280 × 720, seed 1916, floor 3)
All in `docs/reference/front_m4/` (`gate_sheet.png` has the reference beside the five;
`reference_vs_panorama.png`, `reference_vs_ground.png` full size). Cameras as `test_front -- atmos render` prints them:

| Shot | Camera (x, y, z), fov | What it shows |
|---|---|---|
| (a) `gate_a_parapet.png` | (20.22, 0.52, 128.76) on a fire step, 75° | sandbags and the step at hand, our wire and the field beyond, the enemy line a band under the haze ~100 m off |
| (b) `gate_b_panorama.png` | (20.0, 1.74, 94.0) standing on the lip of a hole, 75° | No Man's Land toward their line: holes, water, the far posts and stumps dissolving, their smoke and fires |
| (c) `gate_c_ground.png` | (23.36, 0.77, 119.65) crouched beside a 2.8 m hole, 75° | the mud close to, water in the hole, wire and a post, a stump |
| (d) `gate_d_silhouettes.png` | (24.0, 1.06, 110.0) low, 60° | three WitzSoldats standing at 14, 26 and 42 m |
| (e) `gate_e_silhouettes_dense.png` | same | the same men with the fog ended at 75 m instead of 140 (density 1.0, begin 3 m) — the "thicker bank" case |

### Against the reference (`docs/reference/no_mans_land_reference.png`)
Mean colours, measured on the images (sRGB 0–255; the reference's top quarter and bottom
third against the same bands of (b) and (c)):

| | sky | foreground ground |
|---|---|---|
| reference | (120, 123, 112) — a **mid** grey with a sage tint, not pale | (47, 40, 36) — near-black **brown** (R > G > B) |
| (b) panorama, pass 3 → **pass 5** | (207, 205, 188) → **(146, 146, 134)** | (64, 64, 51) → **(64, 63, 52)** (a fog bank was crossing: lit) |
| (c) ground, pass 3 → **pass 5** | (205, 205, 191) → **(161, 161, 151)** | (52, 51, 41) → **(20, 18, 13)** |
| (d) silhouettes, pass 5 | (146, 146, 136) | (38, 37, 29) |

- **Colour (pass 5).** Brown-grey now, red leading as in the image; the olive of passes 1–3 is
  gone (mist, fog, volumetric albedo and grade all taken to near-neutral, the firm ground tinted
  brown). The near mud in (c) runs darker than the reference's (20 vs 47) and flatter: the
  reference's foreground is lumpy wet relief catching the sky; ours is the scan's relief at the
  Front's low light. A touch more ground brightness or a steeper light are the levers if you want
  it lifted; I kept it on the dark side of the image rather than the light.
- **Fog.** Begins at 6 m, linear to 140 m: timber and wire sharp to hand, posts and stumps shapes
  by 50 m, the far side a band; the banks (pass 4) roll through it and take everything. Pass 5
  turned the haze's sun-scatter on and put the light low behind their trees, so the fog is now
  brighter toward that core as the image's is behind its near trees.
- **Sky (pass 5).** Taken down to the image's weight: layered grey masses, a warm glow only low
  over their side where the sun hides, 146 vs the image's 120 mean (the rest of the gap is the
  near-horizon core, which the image's framing also has). The package's "pale" is gone in favour
  of the picture, per "match the reference as closely as possible".
- **Contrast / exposure.** The reference is a dark image with a bright sky; ours is a mid image
  with a brighter sky. Oppressive-but-readable holds in ours; the mud is not yet "near-black".
- **Scale.** The field is 97 m fire trench to fire trench (D-12, yours to tune); the eye is
  1.65 m up, 1.0 m crouched; a man is 60–110 px tall at 14 m on a 1280-wide frame.
- **Silhouettes.** Men at 14 and 26 m read as men against the sky from a low eye; at 42 m he
  is a mark; by 55 m (the brains' limit) a shape. From a standing eye on flat ground figures sit
  on the dark ground band, not the sky, and read worse — the reference's low camera is doing
  work there too. (e) vs (d): the thicker bank takes the 42 m man away and softens the far
  line; the difference is modest at this density.
- **Wetness.** Water lies in the holes and the low ground, near-black with the sky in it; the
  mud is glossier than the legacy day's. The reference's foreground is wetter still — a mirror
  puddle with reflections of posts — and strewn with debris (timber, wire tangles, a helmet,
  stumps) that we do not have out there yet.

### Limitations (honest list)
- **Rendered on the container's software Vulkan (llvmpipe), not the Mac.** SSR, SSAO, SSIL,
  the volumetric mist and the shadow blur all look different on a real GPU, and the Mac's
  colour management (Display P3) will shift it again. **Please judge it live on the Mac**, not
  only from these PNGs; the fixed cameras are reproducible there (`play_front -- god seed=1916`).
- **Debris is now there (gate iteration, above), but it is box-and-cylinder dressing** from the
  legacy prop kit, not scanned or modelled wreckage: good at 10 m and in the haze, crude at 1 m.
  The reference's mirror puddle with reflections is SSR's job on the Mac.
- **One profile, no regions yet.** Our trench, No Man's Land, their trench and the H.Q. share
  the environment; the mist is thicker over No Man's Land, that is all. Region profiles,
  transitions, wind-driven banks and flare light are director work (M7+). The visibility model
  is one constant (55 m) today, by design.
- **Fog is a depth curve + a mist volume**, so smoke patches thin sight for the brains but the
  camera does not see them as fog proper; they are particles.
- **Auto-exposure** is held to a narrow band; a dugout will not go as dark as the legacy day's.
- **Enemies' own materials** are untouched; they take the light and the grade like everything else.
- Performance: measured 23 Nov (performance note); the Front's environment adds the mist
  volume (as the legacy day) and 5 small emitters; nothing else new is per-frame.
- `test_zornhauptmann` flakiness on the Front (since M2) still to be looked at.

### Gate feedback so far
- **22 Nov, live on the Mac:** "the water puddles in the trenches are way too bright. Blindingly so."
  Cause: the Front's light is higher (33° up vs the legacy day's 19°), so its specular glint in the
  near-mirror floor puddles lands where you look when you glance down into a trench, and blooms.
  Fix: sun `light_specular` 0.05 → **0** (overcast, light behind cloud: no glint), glow HDR
  threshold 0.95 → 1.1. The sheen from the sky's reflection stays. Legacy sun untouched.

- **22 Nov, Andrew:** "The sky is very bland and shows no clouds or variation (the original version
  of the scene had great clouds)." Cause: my misreading of the sky shader's `coverage` — higher =
  *fewer* openings, and past ~0.7 the dome is one pale plate; passes 1–3 ran 0.82 (legacy day: 0.5).
  That is also why the sky measured 1.7× brighter than the reference. Fix: coverage **0.56**, masses
  darkened to (0.40, 0.42, 0.39) / (0.55, 0.57, 0.53); the layered cloud is back (re-shot (b) in
  `docs/reference/front_m4/`). `test_front -- atmos render only=<letters>` now re-shoots a subset.
- **22 Nov, Andrew:** "No Man's Land is very bare — unless that's coming in the next milestones?"
  Honest answer: it is not scheduled later, it is owed from M2/M3 (package §C "No Man's Land": broken
  trees, pickets, abandoned equipment, wreckage, gun pits, bodies, ruined timber, landmarks). Today
  the field has holes + water, the wire belts, 9 dead trees, 2 wrecked limbers, smoke. Proposed as
  the next gate iteration: near-field dressing at the reference's density, then re-shoot. Awaiting
  his word.

- **22 Nov, Andrew:** "I don't see a lot of rolling fog / mist or smoke." Right: the Front had the
  uniform haze, a thin mist volume and five small smoke patches, and none of the legacy day's
  **fog banks** (`TrenchFog`, which `TrenchBattle` makes and the Front does not run). Fix:
  `FrontFog extends TrenchFog` (`scripts/world/front/front_fog.gd`) — the same banks (billowing
  puffs that pour into the trenches + density in the mist volume + sight cut both ways), spawned
  off their side and the flanks for the Front's geometry, drifting at our lines, every 28–60 s
  instead of 70–150, two already on the field at load; not in the `fog` group — `FrontAtmosphere`
  multiplies its `visibility()` in, so there is still one model (test: a line through a bank
  gets 0.08 of the way). Base mist 0.08 → 0.12, e-folding height 0.9 → 1.4 m, ×2.6 over the field;
  drifting smoke 5 → 8 patches, 16 billows each, 8 m. Shots with a bank crossing:
  `gate_b_panorama_fogbank.png`, `gate_d_silhouettes_fogbank.png`. Legacy `TrenchFog` untouched.

- **22 Nov, Andrew: "yes" to the field dressing.** `FrontArt._dressing()` + `_bodies()` (package §C
  "No Man's Land", owed from M2/M3): 9 clusters of stumps and shattered trees + 24 strays; 70 lone
  screw pickets (40% still carrying a strand) and 50 tangles of loose wire (`_tangle`, lines on the
  wire shader, cosmetic — no collision, D-14 stands); 60 pieces of ruined timber/duckboard; 2 gun
  pits (bag ring, wrecked carriage, barrel, wheels, helmets); kit — 50 helmets, 10 rifles, 3
  stretchers, tins, reels, blankets; 50 sandbags blown off the lips; one cottage ruin knocked down
  to chest height (`_cottage_ruin`; the legacy `_ruined_block` was tried first and made a 9 m
  tower-block skyline — out); **18 WitzSoldat corpses** (`Clown.make_corpse()`, the game's own
  bodies: in and about the holes, along the wire, half already prone; dead from the start, not in
  `game.clowns`, every gore system as it is; test: ≥10 bodies, all corpses, enemy count unchanged).
  60% of everything lands in the 30 m band in front of our wire. Nothing new collides, so M3's
  routes stand (`crossing` + `game` sections pass). All five shots re-taken.

### Acceptance (package F, row 4)
- [x] Green-grey lighting, fog, smoke, wet surfaces, silhouettes built as separate profile.
- [x] Four real in-game screenshots (five) at fixed cameras, compared with the supplied image.
- [x] Atmosphere isolation: Front env ≠ bunker env; the bunker's returns on the next floor; the legacy scene keeps TrenchArt's (checked in `test_front atmos`).
- [x] **Andrew's visual approval — given 22 Nov 22:09** ("you were right. i needed to reload the
  scene. Continue with the master plan"), after five gate iterations on his live feedback (the puddle
  glint, the bland sky, no rolling fog, the bare field, "match the reference as closely as possible",
  the black ground). Baseline recorded: `docs/reference/approved_atmosphere/` (the settings table as
  approved, the five shots re-rendered at the approved settings, `SETTINGS.md`), tag
  `drowned_front_approved_atmosphere` = commit `12ca5c7`. Later milestones must not change the look
  without a new approval (D-16).

### Files
- **`shaders/mud_terrain.gdshader` (shared with the legacy level): one new uniform `firm_tint`,
  default (1, 1, 1) — identity, so the legacy day renders as before (`test_trench` 0 failed; one
  flaky run of it failed then passed, as it has before). `archive/.../check.sh --live` will list
  the shader as changed from the baseline: this is why.**
- new `scripts/world/front/front_atmosphere.gd`, `front_fog.gd`; `scripts/world/front/front_art.gd` (`atmosphere`,
  `ground_material`, `_drift_smoke`, `_mist` colour, far-smoke thinning in `build`, crater water);
  `scripts/world/front/front_maze.gd` (field wetness baseline); `scripts/game/game.gd`
  (`_front_env`, the Front branch of `_apply_floor_look`); `scripts/dev/test_front.gd` (`atmos`);
  docs (D-16, architecture §7/§8a, master plan, README, this), `docs/reference/front_m4/`.

### Tests (headless, container)
| Scene | Result |
|---|---|
| **test_front** `atmos` | 0 failed (isolation ×3, visibility bounds) |
| test_front `layouts geo cover wire crossing game` | 0 failed |
| test_objective | 0 failed |
| test_nav `front` / `trench`, test_trench, test_trench_level `game nav` | as M3 |
| test_killcam `floor report`, test_game, test_events, test_base, test_curse | as baseline |
| legacy scene | `TrenchMaze … ELIMINATION / ok`, TrenchArt environment |

## Milestone 5 — Physical impacts (22 Nov 2026) — DONE, AWAITING REVIEW

Authorised by Andrew's "Continue with the master plan" after the M4 approval (taken as M5 only).

### What was built (D-07, package §D)
- **`Impacts`** (autoload, `scripts/fx/surface_impacts.gd`): one manager every world hit is reported
  to. It never touches damage — it is told after the weapon code has done its work — and answers with
  the right thing for the surface:

  | Surface | Debris | Mark | Sound |
  |---|---|---|---|
  | mud (saturated) | dark clods + wet spray, thrown up off the ground, along the line on a glancing hit; a dark puff | dark wet splat, smeared along a glancing round | `imp_mud` (damp thud + squelch) |
  | earth (dry, the legacy tops) | grit, a dust puff | subtle pale mark | `imp_earth` |
  | wood (linings, duckboards, bridges, crates) | directional splinters, a little dust | small hole with torn grain | `imp_wood` (crack) |
  | concrete (bunker walls, portals, columns) | pale chips, dust | pale chip with a dark pit | `imp_stone` |
  | metal (iron linings, guns, drums) | sparks (fading orange), now and then a chip | small pockmark | `imp_metal` (ring) |
  | sandbag / wattle | grit + fibres, dust | puncture | `imp_bag` |
  | water (flooded trench, crater pools) | droplets up, a spray puff | an expanding ripple ring, transient | `imp_water` (splash) |

- **Classification, metadata first:** a `surface` meta on the CollisionShape3D (the dressers set it:
  `TrenchArt._collide(..., surface)` on every lining by its type, bridges, ramps, crates, the gun, the
  portal; `LevelArt._collider(..., surface)` on columns/portals = concrete, drums = metal, the prop body
  = wood), then the body; the trench heightfield asks `TrenchMaze.surface_at()` (water / wood / mud /
  earth; on the Front "earth" is mud — it is all saturated) plus the Front's crater pools; a bunker's
  wall body is concrete; else earth. No node-name guessing.
- **Hooks:** `FpsPlayer.shoot_ray` world branch (so every player weapon and the mounted Maxim, whose
  old generic dust steps aside); `ClownBrain._fire` and the marksman's `_mark_fire` — a **miss** now
  casts on into the world and lands (`_miss_lands`; the hit roll is the damage authority exactly as
  before); the Rattlejack's Lewis gun; `Explosion._go` → `Impacts.blast()` (what the ground under the
  blast is made of: a mud plume and a broad dark mark, a sheet of water and three ripples, dust off
  concrete). Crossbow bolts stick as before (not routed).
- **Budgets (D4):** decals in a ring of 240 (distance-faded 35–47 m), 40 one-shot debris emitters and
  28 puff emitters in pools, 16 ripples; **6 debris bursts a frame**, beyond that a hit gets its mark
  and sound only (`aggregated` counter); 4 sounds a frame; past 45 m from the player mark only, past
  90 m nothing. Hit detection and damage are never throttled. `Impacts.clear()` with `Blood.clear()`
  when a floor is torn down.
- **Material range (D5):** `test_impacts -- range render` builds panels of every surface (real
  colliders with their meta), fires the rifle ray at each from one spot and renders
  `/tmp/impacts_range.png` + close-ups → `docs/reference/front_m5/`.

### Tests
| Scene | Result |
|---|---|
| **test_impacts** `classify` | the open field is mud; a flooded hole's bottom is water; 160 trench cells × 4 walls: wood 45, sandbag 89, wattle 36, metal 11, mud 222; a bunker's walls concrete ×48 |
| **test_impacts** `bullets` | one round → 1 hit, 1 mark, its debris dispatched; **400 rounds in one frame: 240 marks (ring), 258 aggregated past the 6-a-frame cap, 8.6 ms**; the next floor starts clean |
| **test_impacts** `walk` | 12 Maxim rounds walked along the ground → 12 marks in order |
| **test_impacts** `enemy` | a soldier's miss lands and marks the ground |
| **test_impacts** `blast` | a shell into a flooded hole → water; into the field → mud |
| **test_impacts** `range render` | every panel answers as itself; 42 rounds; shots written |
| test_front `geo cover wire crossing game atmos` | 0 failed |
| test_objective | 0 failed |
| test_trench | 0 failed |
| test_game, test_events | no FAIL (observations as before) |
| test_grenade | 0 failed ×2 after one failed run ("the closest come apart") — ragdoll randomness, seen before |

### Honest list
- The marks are drawn in code (48 px, three of each) — fine at play distance, soft close up. Real
  textured decals would be an art drop-in (`_tex[surface]`).
- Metal "dent" on props is not done (package: optional).
- Persistent marks are bounded by the ring (240); a long fight recycles the oldest. Blood has the same
  rule.
- Cosmetic far gunfire (the horizon battle) is separate already and does not go through this; only
  real rays do.
- Impact-driven AI reactions (flinch/duck on a near impact) are deferred to M6 as the package says
  ("in a later integration step").
- Mac perf unmeasured (PENDING) — the budgets are by design, not by measurement.

### Files
- new `scripts/fx/surface_impacts.gd`, `shaders/impact_ripple.gdshader` (the first M5 commit had
  overwritten the legacy footstep `ripple.gdshader`; restored byte for byte in `ee8c88d`), `scripts/dev/test_impacts.gd`,
  `scenes/test_impacts.tscn`, `docs/reference/front_m5/`; `project.godot` (autoload `Impacts`).
- touched (additive, legacy output unchanged): `scripts/world/trench_art.gd` (`_collide` surface
  param + 12 call sites), `scripts/world/level_art.gd` (`_collider` surface param, 4 sites, body meta),
  `scripts/player/fps_player.gd` (world branch), `scripts/clown/clown_brain.gd` (`_miss_lands`),
  `scripts/clown/battle_duty.gd` (marksman miss), `scripts/clown/rattlejack.gd` (world hit),
  `scripts/events/mounted_gun.gd` (old dust steps aside), `scripts/fx/explosion.gd` (blast hook),
  `scripts/fx/sfx_synth.gd` (7 `imp_*` placeholders), `scripts/game/game.gd` (`Impacts.clear()`).
  `archive/.../check.sh --live` will list trench_art.gd, mud_terrain.gdshader and the others as
  changed: this record is why.

## Milestone 6 — Core combat hazards (22–23 Nov 2026) — DONE, AWAITING PLAYTEST

Authorised by Andrew's "continue" after M5 (taken as M6 only).

### What was built (package C5; master plan "threat controller")
- **`FrontThreats`** (`scripts/world/front/front_threats.gd`), made by `Game` on a Front floor after
  the soldiers: places the nests from the geometry and runs the artillery.
- **`FrontMg`** (`front_mg.gd`) — an enemy Maxim on their parapet. **Placement:** their fire bays on
  their fire row facing our lines, the gun on the lip 1.05 m in front of the wall (just past the bag
  line), a view check from the muzzle at 25 and 50 m (≥ 4 of 6 lines clear), nests ≥ 18 m apart so
  the field keeps a flank; 2 per floor (seed 1916: x = 27.7 and 9.7, both on the fire row, both with
  a live gunner 2 m behind). **The gun is `MountedGun`** (the MG-nest event's piece, mesh, tripod,
  flash, tracer, heat), driven by the nest instead of a player. **Arc:** traverse ±55°, elevation
  −14°…+18° (`MountedGun`'s constants) — outside it the gun cannot point, and close under it is dead
  ground. **Sight:** range 115 m, the `fog` group's `visibility` ≥ 0.3 (so banks and smoke hide you
  from it exactly as from the soldiers), and a clear ray from the muzzle to your chest **or** your
  eye at your current crouch height. **Fire:** bursts of 7–14 rounds at 0.085 s, pauses 0.8–2.2 s
  between, a 100-round belt then a 5–7.5 s belt change, heat 0.028/round cooling 0.22/s with a
  boil-over at 1.0 until 0.35; a burst starts up to 1.4 m off and walks onto the mark; the aim cone
  is 3.2° on acquisition settling to 0.9° over 2.6 s of continuous tracking (lost sight resets it).
  **Every round is a ray** (world | player): the player hit → `take_damage` 14 at ≤ 40 m to 8 at
  115 m; the world hit → `Impacts.bullet` (mud kicks, wire pings); a round within 2.2 m of your chest
  → `FpsPlayer.suppress`; within 1.3 m of a soldier → his brain's `near_miss`. **States:** IDLE (a
  short burst across the field at nothing every 35–90 s), TRACK, SEARCH (bursts at where it last saw
  you ± 4 m every 5–11 s, gives up after 25 s), RELOAD, OVERHEAT, SILENT. **Vulnerable:** the gunner
  is an ordinary WitzSoldat (shoot him → the nest is silent and the piece becomes usable: [E] on it,
  `MountedGun.active`); the mechanism takes 420 damage from the player's rounds (`shot()` forwarded
  from the gun body) and jams with a snap. Not omniscient: no target → no fire except the searching
  and idle bursts, which are real rays too.
- **`FrontArtillery`** (`front_artillery.gd`): first salvo 25–45 s in, then salvos of 3–5 shells
  1.6–3.2 s apart, lulls of 32–70 s between. Each shell: `shell_whistle` (synth, falling, from 18 m
  up over the fall) **2.4 s before** it lands, then the game's own `Explosion` `shell` profile
  (damage, fling, gore, scorch as they were) + `Impacts.blast` (mud plume / water sheet). Fair by
  construction: the salvo's centre is 10–24 m from you (60%) or anywhere on the field (40%); **no
  shell is aimed within 7.5 m of where you stand when it is fired; at most one of a salvo within
  16 m; nothing outside z ∈ [their fire row − 1 m, our fire row + 1 m]** (the field and the two front
  parapets; never the H.Q. or our rear). Soldiers within 14 m get `near_miss` (heads down). The
  **movement windows** the package asks for are the lulls, the belt changes, the boil-overs and the
  pauses between bursts — measured, not scripted.
- **Suppression feedback** (`FpsPlayer.suppress(amount, at)`): a `crack` at the pass point, a fine
  camera tremor (±1.2 cm, 0.3°) proportional to suppression², easing at 0.35/s. No aim penalty, no
  control theft, no stun, no vignette. Damage only from rays.
- **Brains read the crouch** (`ClownBrain`): sight, fog and aim use `player.eye_height()` /
  `chest_height()` instead of fixed 1.5 / 1.25 — crouched behind a 1.35 m wall you are not seen,
  standing you are (tested). This closes the M3 note.
- Sounds (placeholders, synth): `mg_shot`, `shell_whistle`; `crack`, `metal_rattle`, `mag_out`,
  `metal_snap` reused.

### Tests (`test_threats`, headless)
| Section | Result |
|---|---|
| nests | 2 guns on their fire row, facing +z, on the lip, clear view 30 m out, live gunners 2.2 / 1.8 m behind; 18 m apart; the traverse covers the field ahead, not the flank |
| fire | a man standing 32 m out is seen at once; 10 rounds in 2 bursts within 2.7 s; misses land in the world (Impacts); hits on him are ray hits (1); suppression 0.13 after 6 near passes, eases to 0 in 3 s; crouched on the floor of a 1.7 m hole 19 m out: not seen, no hits in 6 s |
| pauses | 75 s under fire: 288 rounds in 29 bursts, 28 pauses, 2 belt changes, longest pause **8.3 s** |
| crew | gunner shot dead → nest dead, gun silent 5 s, piece takeable; 12 rifle rounds into the second gun → jammed |
| shells | first salvo held 29 s; a salvo of 5: every whistle ≥ 2.4 s, none within 7.5 m of the player, 1 within 16 m, all in the fair zone; the soldier 3 m from the centre got 5 near misses; next salvo 33 s later |
| crouch | behind a 1.35 m wall: standing (eye 1.65) seen, crouched (eye 1.05) not |
| test_front `game` | 0 failed (the Front builds and plays with the threats in) |
| look render | `docs/reference/front_m6/` |

### Honest list
- The gunner stands behind the gun with his rifle, looking down the barrel; there is no hands-on-the-
  grips pose. No relief crew: a dead gunner's gun stays silent until you take it.
- The idle "burst at nothing" is a real ray and can, rarely, find a player who is in that line —
  that is the gun doing what guns do, not phantom damage; the chance is small and the cone wide.
- Suppression's camera feedback is deliberately slight; if it reads as nothing on the Mac, the
  amplitude is one number (`FpsPlayer`, 0.012 / 0.006).
- Artillery does not yet pause for a pinned player explicitly — the windows come from the salvo
  rhythm and the MGs' own pauses; whether that *feels* fair is the playtest's question.
- Impact-driven AI reactions beyond near-miss suppression (investigate, flank) are director work (M7+).
- All clocks are game time (not the wall clock), so headless fast runs and the Mac agree.

### Files
- new `scripts/world/front/front_threats.gd`, `front_mg.gd`, `front_artillery.gd`,
  `scripts/dev/test_threats.gd`, `scenes/test_threats.tscn`, `docs/reference/front_m6/`.
- touched: `scripts/game/game.gd` (`threats`, made after the soldiers), `scripts/player/fps_player.gd`
  (`suppress`, `suppression`, the tremor), `scripts/clown/clown_brain.gd` (crouch heights in sight,
  fog and aim), `scripts/events/mounted_gun.gd` (`shot()` forwarded to a nest), `scripts/fx/sfx_synth.gd`
  (`mg_shot`, `shell_whistle`, `_whistle_in`), `scripts/world/front/front_fog.gd` (`clear_banks()`).

## Performance note (23 Nov 2026) — Andrew: "the frame rate gets worse as I progress to the next floor… not great on the trench area either"

**Is anything left over from previous floors? No.** `scenes/leak_probe.tscn` walks 8 floors (bunker,
Front, bunker, bunker, Front, bunker, bunker) with the player firing, enemies dying and grenades going
off on each, and counts what every node that outlives a floor is holding: the autoloads (`Impacts` 324,
`Blood` ~335, `MechFx` 68), the player (395), the game's own children — all identical before and after
every floor; orphan nodes 0 throughout; static memory rises and falls with the floor (690–970 MB), not
monotonically. The world is freed whole (`_clear_floor`).

**What grows is the floors.** `scenes/census.tscn`: a floor-4 bunker has 29 omni lights, **18 of them
casting shadows** — every caged bulb was a shadow-casting light (six cube faces of the scene re-rendered
per light per frame), and deeper floors have more rooms, so more bulbs, so more shadow passes: that is
the floor-by-floor fall. Measured in the container (Forward+, llvmpipe, 640×360, same spot): a floor-2
bunker drew **3,300–3,700 objects / 3.2–3.5 M primitives a frame**.

**Fix (`LevelArt._shadow_budget`, commit below):** only the 4 bulbs nearest the player (within 20 m)
cast shadows, re-ranked every 0.3 s; the rest light without shadows. Same spot after: **930–1,275
objects / 0.9–1.25 M primitives** (−65%). A bulb's shadow in the next room was never seen, so the
look does not change. The event rooms' own lights are untouched.

**The Front** (floor 3, seed 1916, from the census): 456 MeshInstance3Ds carrying **1.56 M triangles**
(the heightfield, the water planes, the trees), 79 MultiMeshes with 15.7 k instances (the litter, the
bags, the wire posts), 30 skeletons / 480 physical bones (17 soldiers + 18 corpses, asleep), 27
particle systems (599 quads), 7 lights (4 shadowed: the sun's 4 cascades over 70 m), plus SSR, SSAO,
SSIL, volumetric fog and the mist volume at full resolution. The software renderer cannot even
produce a frame-time reading for it in 4 minutes, so **no number from here means anything for the
Mac**: the heavy items on a real GPU are most likely the sun's shadow cascades over 1.5 M triangles,
the screen-space effects + volumetrics at native resolution, and the skinning of 30–43 bodies. Those
are Milestone 12's (performance) proper subjects, and the approved atmosphere (D-16) is not to be
touched for them without a new approval; render scale (FSR 2 at 0.77–0.85) is the lever that
changes nothing in the look.

**The Mac baseline, first reading (23 Nov 13:18, Andrew; D-10 no longer pending for the Front):**
Apple M2, window 1958 × 991 @ 60 Hz, Forward+, vsync on. `play_front -- god perf=10`, ten 10-s
windows standing/looking about at the start: **12.3–21.6 fps avg, 1% lows 7.4–20 fps**, every frame
over 33 ms; objects drawn 480–2,520, draw calls 341–2,303, **primitives 15.7–73.9 M a frame**,
video memory 1.02–1.10 GB, physics 3.8–6.7 ms. The census then put the floor's triangles at
**4.48 M, 4.34 M of them casting shadows — 2.75 M of which were the 8,597 sandbags at 320
triangles each**, every one drawn up to six times a frame (depth, colour, four shadow splits).
Fix: `FrontArt._bag_mesh()` override at 10 × 5 segments (120 tris; the legacy mesh untouched) and
the Front sun's shadow at 40 m in two splits instead of 70 m in four (past 40 m the haze had the
shadow anyway): floor triangles 4.48 M → 2.76 M, shadow passes halved. Before/after shots (a) and
(c) in `docs/reference/front_m6/perf_bags_shadows_before_after.png`: the differences are the live
fog bank and the cloud, not the bags. Second reading awaited. Next on the list (M12): the soldiers
and corpses at 22–33 k triangles each (30–43 bodies), LOD or a simplified shadow mesh; render scale.

**The bunker readings (23 Nov 13:45–14:00, Andrew, M2, ~1904 × 1020, Metal 4 / Forward+, vsync):**
control **26–29 fps** with 1–2 M primitives and 1,000–2,350 draw calls (so not geometry-bound);
`noshadows` at a half-size window 59 — but the control at that window was 58 too: **pixel-bound**;
at the big window `nopost` (SSR, SSAO, SSIL, glow off) 32; **`nofog` 45–48** — the volumetric fog was
~15 ms, fed by all ~29 bulbs' `light_volumetric_fog_energy` every frame; `scale=0.67` with FSR 2 only
32–35 (FSR 2 itself costs ~4 ms here and the fog's light pass does not shrink with render scale).
**Fixes:** `LevelArt._shadow_budget` now also leaves only the 6 nearest bulbs lighting the fog
(`5b16c05`) → control **36–43**; then **FSR 1 at 0.75** (`fsr1=0.75`) → **56–60 fps, 1% lows to 60**,
made the project default (`rendering/scaling_3d/mode=1, scale=0.75`) — the one change in this hunt
that touches the look (a slight softening), Andrew to judge by eye. Noted for later: physics spikes of
18–25 ms in some windows on a bunker floor (Jolt; corpses/ragdolls or an event), to be looked at in M12.

**The Front (23 Nov 14:04–14:14, Andrew, M2, ~1900 × 800–1000):** with the bag mesh, the 2-split sun
and FSR 1 in: **20–25 fps, still 57 M primitives a frame** on a 2.8 M-triangle floor. Cause: a
MultiMesh is culled as one box, and the "bags" batch spanned the whole floor, so all 8,600 bags were
drawn whole in the colour pass, the depth pass, each sun split and **each of the six faces of every
dugout lamp's shadow** (4 lamps, 4.6 m range). Fixes: `FrontArt._add/_box` key every batch by a 20 m
tile (79 → 497 batches, the same 15,704 instances; the legacy batching untouched) and the lamps'
shadows off (`96757a7`) → **5.2 M primitives, 41–49 fps, median 20.4 ms**. `nofog`: 19.4 ms — the
mist and banks are ~1 ms, left alone. Then the litter batches cast no shadow and the sun in one split
to 36 m (`772d6df`) → **3.7 M primitives, 1,300 draw calls, 58 fps, median 17.2 ms, 1% low 58.**

**D-10 status:** baseline measured; target met at Andrew's resolution standing still (bunker 60,
Front 58). Combat (ragdolls, impacts, tracers, the MGs) is not in these numbers. **M12 list:** soldier
and corpse meshes at 22–33 k triangles each × 30–43 bodies (LOD / a simplified shadow mesh); the ~150
crater water planes as separate MeshInstances (merge per tile); the bunker physics spikes (18–25 ms);
a Graphics options page (render scale / upscaler / fog and shadow quality, saved per user) so the FSR
default is a player's choice, not a project-wide fact; video memory at 0.93–1.1 GB (texture import).

**Andrew's amendment (14:16):** having played the Front with the `nofog` knob, he prefers it — "looks
better, I can see more detail, and the rolling smoke banks already add that misty look" — so the
Front's volumetric layer is off (`FrontAtmosphere.VOLUMETRIC`; D-16 amended, SETTINGS.md noted).
The bunkers keep theirs.

**Look-neutrality:** every change above except FSR 1 at 0.75 is invisible by construction (shadows
that were in the haze, bulbs' fog glow two rooms away, culling); the before/after shots for the bags
and the sun are in `docs/reference/front_m6/`. The approved atmosphere (D-16) stands; Andrew to say
if the 0.75 softening bothers him. The frame probe now prints the load too. In the
editor, Project Settings → Editor → Run → Main Run Args: `-- god perf=10` with `scenes/play_front.tscn`
(the Front), `-- god perf=10 bunker floor=2` and `-- god perf=10 bunker floor=8` (bunkers), and read
the `PERF …` lines in the Output panel: fps / 1% low, then `PERF load: objects drawn … draw calls …`.
Three lines each is enough to decide what M12 does first.

(Milestones 7–13: scope as in the package; detailed when authorised.)
