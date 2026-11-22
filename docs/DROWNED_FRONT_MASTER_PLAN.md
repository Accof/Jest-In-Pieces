# Operation Drowned Front — Master plan

The source of truth is the user's package, kept verbatim at `docs/DROWNED_FRONT_PACKAGE_v1.0.md`
(v1.0, 22 Nov 2026), and the reference image `docs/reference/no_mans_land_reference.png`. This
document is the plan **resolved against the real codebase**: what we are building, in what order,
with which files, and what has been decided (`DROWNED_FRONT_DECISIONS.md`). Progress and test
results live in `DROWNED_FRONT_IMPLEMENTATION_TRACKER.md`; the inspected architecture in
`DROWNED_FRONT_ARCHITECTURE.md`. Read all four at the start of a session.

## 1. Vision in one paragraph

The Drowned Trenches stop being a 48 × 42 m kill-all maze and become a crossing: the player
enters a friendly-looking trench network from the rear, works up to the fire trench, goes over the
top into 80–120 m of shell-churned No Man's Land under a sickly green-grey fog, and reaches the
enemy's trench network and its H.Q. bunker. The war goes on around them whether or not they are
seen; they do not have to kill anyone. **Objective: survive, cross, reach the enemy H.Q.**

## 2. Pillars (package A2, as they bind this codebase)

1. **Preserve before modifying** — done in Milestone 0 (`archive/legacy_drowned_trenches/`, tag
   `legacy-drowned-trenches-baseline`, `scenes/legacy_drowned_trenches.tscn`). The legacy classes
   are not edited by the rebuild (D-02); `check.sh --live` is run at every milestone.
2. **No forced trench clear** — `Game.objective` SURVIVAL on trench floors (D-03), ELIMINATION in
   bunkers unchanged.
3. **A real journey** — two distinct networks and the open ground between, on one carved
   heightfield (D-04), seeded and validated.
4. **A living battlefield** — a director choosing situations, realised by the existing brains and
   duties (D-06), with cosmetic and damaging fire kept apart.
5. **Fog as gameplay and art** — a new environment profile for the front (Architecture §7), one
   visibility model for eyes and AI (D-08), the reference image as the authority, a hard approval gate.
6. **Physical weapon feedback** — `SurfaceImpactManager` filling the empty world-hit branch (D-07),
   in bunkers too.
7. **Tense but fair** — MG arcs, telegraphed artillery, real cover, no omniscience.
8. **Protect the existing game** — D-09; every milestone re-runs the affected tests.
9. **Incremental** — one milestone per authorisation; docs updated; stop for review.

## 3. What exists today that we build on (short form; Architecture has the detail)

- A floor is a `Maze` subclass with a fixed API (§4 there); the trench floor is `TrenchMaze` on a
  1.5 m grid with a carved `HeightMapShape3D`, dressed by `TrenchArt`, animated by `TrenchBattle`
  (duties, pace, encounters), `TrenchField` (cosmetic No Man's Land fight), `TrenchFog` (banks,
  `visibility()`), `TrenchAmbience`, `FarFigures`.
- Enemies: `Clown` + `ClownBrain` (local hearing by path cells, local sight with fog, witness
  alerts, suppression, cover, mocap locomotion, duties). Variants intact.
- The exit opens on `remaining <= 0`; the final kill runs the killcam and the brutality report.
- Bullets do nothing to the world. Explosions have profiles (`drum`, `grenade`, `shell`) and a scorch decal.
- Atmosphere is already per-floor-type (`_apply_floor_look`); the current trench look is a cold
  storm sky with crisp air for 18 m and blue-grey distance; the user has rejected brighter/SDFGI.
- Sound is all synthesised (`SfxSynth`) in named, replaceable slots.
- Tests: 36 headless scenes; the trench has two (`test_trench`, `test_trench_level` with 25 sections).

## 4. Target architecture (responsibilities → files; names provisional until each milestone lands)

| Responsibility (package B3) | Where it goes | Reuses |
|---|---|---|
| Objective controller | `Game.objective` + a small `objective.gd` helper if it grows | `_on_clown_died`, `_build_exit`, HUD |
| Front generator | `scripts/world/front/front_maze.gd` (`FrontMaze extends TrenchMaze`, overrides `generate`, `_carve`) | `TrenchMaze` layout routines per network (called twice with offsets/mirroring), `_bake_sky`, bridges |
| Trench network generator | `scripts/world/front/trench_network.gd` (pure layout: cells + kinds for one network in a sub-rectangle) | extracted *copies* of `TrenchMaze`'s layout steps if they cannot be called with an offset |
| No Man's Land generator | `scripts/world/front/no_mans_land.gd` (craters, ridges, wire belts with gaps, wreck sites, landmarks → heightfield edits + prop list) | `TrenchArt` crater/wire/wreck builders via static access or copies |
| Dressing | `scripts/world/front/front_art.gd` | `TrenchArt`'s material setup (`mud_material`, `prop_material`, `make_plume`, `smoke_material`, `_mist`) |
| Atmosphere controller | `scripts/world/front/front_atmosphere.gd` (region profiles: start trenches / NML / enemy trenches; fog, smoke, wind; smooth blends) | `TrenchArt.make_environment` as the starting point, `TrenchFog` for banks |
| Battlefield audio | `scripts/world/front/front_ambience.gd` | `TrenchAmbience`, `SfxSynth` slots |
| Threat controller | `scripts/world/front/front_threats.gd`: MG emplacements (arcs, bursts, cooling, blind spots), artillery (telegraph, impact, suppression) | `MountedGun` mechanics, `Explosion` `shell` profile, `ClownBrain.near_miss` |
| Surface impact manager | `scripts/fx/surface_impacts.gd` (autoload-like node under the world) | `Explosion`'s puffs/decals, `Blood`'s projection |
| Director | `scripts/world/front/front_director.gd` (tension, alertness, pacing, catalogue, budgets, cooldowns) | `TrenchBattle` pace/encounter logic as the model |
| Event points / registry | `scripts/world/front/event_points.gd` (typed, validated, navigable points from the generator) | `TrenchBattle`'s post finding, `BattleDuty` posts |
| Squad coordinator | `scripts/world/front/squad.gd` (small shared tasks: cover/advance/hold/investigate/withdraw) | `BattleDuty`, `ClownBrain` |
| Debug overlay | `scripts/ui/front_debug.gd` (dev only, toggled) | the HUD label pattern |
| Tests | `scenes/test_front.tscn` (`scripts/dev/test_front.gd`): seeds, connectivity, routes, craters, wire, exits; later sections per milestone; `scenes/test_impacts.tscn` + a material range scene | `test_trench_level`'s patterns (route walker, renders, `_shot`) |

## 5. Milestones, scope and dependencies (package F, resolved)

| # | Deliverable | Depends on | Main files | Acceptance / gate |
|---|---|---|---|---|
| 0 | Preservation, docs, baseline | — | archive, docs, legacy scene | done; user review |
| 1 | `ELIMINATION` vs `SURVIVAL` | 0 | `game.gd` (hunks in Arch §2), objective test | bunkers unchanged; trench exit independent of kills; killcam once per bunker floor, never on survival; user review |
| 2 | Geometry: two networks, No Man's Land, H.Q. exit | 1 | `front_maze`, `trench_network`, `no_mans_land`, `front_art` (minimal dressing), `game.next_floor` picks `FrontMaze` for trench floors (legacy scene keeps `TrenchMaze`) | walkable end to end; `test_front` connectivity over ≥ 50 seeds; **user playtest** |
| 3 | Terrain and functional cover | 2 | `no_mans_land` (crater shapes, slopes, water), wire with gaps, open-ground navigation (D-05), spawn validation | craters give crouch cover and are enterable; no blocked seeds; enemies path across; user review |
| 4 | Reference atmosphere | 2 (3 preferred) | `front_atmosphere`, fog/visibility model (D-08), wet surfaces, silhouette scene, 4+ Godot screenshots vs the reference | **HARD VISUAL APPROVAL — STOP**; baseline `drowned_front_approved_atmosphere` recorded |
| 5 | Physical impacts | 1 | `surface_impacts.gd`, collider tagging in `TrenchArt`/`FrontArt`/`LevelArt`/`Maze`, hooks in `fps_player.shoot_ray`, enemy raycasts, mounted gun; `test_impacts` + material range | every material distinct; MG bursts walk; budgets hold; bunkers too; weapons/gore untouched; user review |
| 6 | Core combat hazards | 3, 5 | `front_threats` (MG emplacements, suppression feedback, artillery) | fair, legible, cover works, no phantom damage; user playtest |
| 7 | Director foundation | 3 | `front_director`, `event_points`, debug overlay | deterministic, bounded, local awareness; user review |
| 8 | Initial director events | 7 | catalogue 1–3 (silhouette, bridge reinforcements, parapet firefight) | independent duties and real paths; user playtest |
| 9 | Expanded activity | 8 | catalogue 4–6, 9–10, `squad.gd` | variety, perception, lifecycle; user review |
| 10 | Enemy trench suspense | 8 | catalogue 7–8, region pacing, audio foreground | quiet after the crossing; user playtest |
| 11 | Procedural variants | 6, 9 | smoke/artillery/MG-heavy and flare-lit configs | seed diversity, routes intact; user review |
| 12 | Performance and polish | all | simulation tiers (started early, see risks), budgets measured on the Mac | agreed budget met; user review |
| 13 | Final integration | all | regression, docs, restore proof | acceptance list (package G); final approval |

**Milestone 4 procedure** (package C3): stop after it; capture (a) frontline parapet, (b) No Man's
Land panorama, (c) mud/crater/wire ground detail, (d) fog-obscured silhouettes, at fixed camera
coordinates and seed, in Forward+; compare to the reference; list differences and limitations;
ask for approval; iterate; record the approved settings and screenshots under
`docs/reference/approved_atmosphere/` and a git tag `drowned_front_approved_atmosphere`.

## 6. File impact list (expected; updated as milestones land)

**New (M1–M4 done):** `scripts/world/exit_door.gd`, `scripts/world/front/front_maze.gd`,
`scripts/world/front/front_art.gd`, `scripts/world/front/front_atmosphere.gd` (M4),
`scenes/play_front.tscn`, `scenes/test_front.tscn`, `scenes/test_objective.tscn`,
`scripts/dev/frame_probe.gd`. **New (to come):** the rest of
`scripts/world/front/*` (above), `scripts/fx/surface_impacts.gd`, `scripts/ui/front_debug.gd`,
`scenes/test_impacts.tscn`, `scenes/look_impacts.tscn` (material range),
(`shaders/front_sky.gdshader` was not needed: the overcast sky re-parametered, M4),
possibly `shaders/mud_terrain` **copies** for the front (not edits).

**Modified (additive, each hunk recorded in the tracker):** `scripts/game/game.gd` (objective, floor
pick, environment pick, HUD text), `scripts/player/fps_player.gd` (world-hit hook only),
`scripts/clown/clown_brain.gd` (world-hit hook; visibility model call if `TrenchFog` is not
reused as is), `scripts/events/mounted_gun.gd` (impact hook), `scripts/world/level_art.gd` and
`scripts/world/maze.gd` (collider surface tags), `README.md` (new section; stale `test_stake` line).

**Not modified:** the legacy trench files (D-02), weapons' damage code, gore, ragdoll, anatomy,
killcam, curse, tickets, saves, base, event rooms, Mixamo/clip code, Klappersoldat, art assets.

## 7. Risks (package J, with what the code says)

| # | Risk | Mitigation |
|---|---|---|
| J1 | Archive completeness / shared-asset drift | hashes of code **and art**, tag, restore test done; `check.sh --live` each milestone |
| J2 | Heightfield can't do vertical faces/overhangs; size and `_carve` cost | the trench walls already work as steep heightfield slopes; prototype the enlarged field first thing in M2 and time it |
| J3 | Navigation across parapets/craters | real geometry (ramps, fire steps, crater slopes); open-ground grid or navmesh (D-05); no teleporting |
| J4 | Rendered fog ≠ AI sight | one visibility function fed by the environment's fog + banks (D-08), tested with the fog test pattern already in `test_trench_level fogbank` |
| J5 | MG fairness | generator validates arcs against routes: every accepted seed has a route outside every arc's effective zone or a blind spot |
| J6 | Director vs progression | SURVIVAL floors never count kills toward anything but tickets; director actors are never on a required list (there is none) |
| J7 | Cosmetic vs damaging fire | two code paths; the debug overlay shows which is which |
| J8 | Perf under automatic fire | impact pooling/caps; damage never throttled |
| J9 | Atmosphere isolation | per-floor environments already; the front gets its own; the base/bunker/legacy envs untouched, checked by renders |
| J10 | AI duplication | director uses `ClownBrain`/`BattleDuty`; no new brain |
| J11 | README drift | Architecture doc written from code; README updated at the end |
| J12 | Human review | playtests at 2, 6, 8, 10; visual gate at 4 |
| + | **Perf is already near budget** (battle ~1.1–1.6 ms, fog puffs heavy) | simulation tiers designed in M2/M7, not deferred to M12 |
| + | **Flaky unseeded tests** | every new test seeds; failures classified against the M0 baseline |
| + | **No Mac GPU in the container** | numbers and final visual calls come from the user's Mac |

## 8. Session protocol
1. Read the four docs; `git status`; `archive/legacy_drowned_trenches/check.sh --live`.
2. Confirm the authorised milestone; restate its acceptance, files, dependencies and test plan.
3. Implement incrementally; run the affected tests; render where visuals matter.
4. Update the tracker (status, files, commands, results, screenshots, blockers, next action) and
   any decision; commit as a checkpoint; **stop for review**.
