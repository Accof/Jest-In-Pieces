# Operation Drowned Front — Decision records

Short records: what was decided, the alternatives, why. Status: **decided** (Session Zero),
**proposed** (needs the user's word), **open** (to be decided in the named milestone).
Add a record whenever a choice closes a door.

---

### D-01 · Legacy preservation = snapshot + hashes + tag — decided
- **Decision.** `archive/legacy_drowned_trenches/` holds byte-exact copies of the trench-only code
  (9 scripts, 9 shaders, tests, tool) under a `.gdignore`, reference copies of the shared files,
  `SNAPSHOT.sha256` (the archive's integrity), `ORIGINALS.sha256` (the live tree's legacy files
  **including every art file the trench loads**), `check.sh`, `restore.sh`, `RESTORE.md`. The git tag
  `legacy-drowned-trenches-baseline` (= commit `0772251`) holds the full tree. Art is hashed and
  tagged, not copied (138 MB, immutable scans).
- **Alternatives.** Copy `art/trench` into the archive (doubles 138 MB in the repo for files that
  never change); rely on git alone (not verifiable from the working tree, and the user may not
  think in commits).
- **Why.** Hashes make "is the legacy level still intact?" a one-line check (`check.sh --live`);
  the tag makes any byte recoverable; the snapshot restores the code without touching git history.
- **Recoverability verified (22 Nov, at Andrew's request).** `git archive legacy-drowned-trenches-baseline
  art/trench …` extracted 139 MB into a scratch directory and all 57 art files hashed identical to
  `ORIGINALS.sha256`; `git fsck` clean. The baseline commit `0772251` is also on GitHub
  (`origin/main` = `0772251` at the time of checking), so the bytes exist in two places. The **tag**
  had not been pushed yet: `git push origin main --tags`. Restore command: `git checkout
  legacy-drowned-trenches-baseline -- art/trench art/level/fx_billow.png art/level/fx_fire.png
  art/level/fx_smoke.png art/level/wall_conc.png`.

### D-02 · The new front is new code; the legacy classes stay untouched — decided (prototype may refine)
- **Decision.** The crossing is built as new classes (working names `FrontMaze extends TrenchMaze`
  or `extends Maze`, `FrontBuilder`, `NoMansLand`, `FrontDirector`, …). `TrenchMaze`, `TrenchArt`,
  `TrenchBattle`, `TrenchField`, `TrenchFog`, `TrenchAmbience`, `BattleDuty`, `FieldSoldier` and the
  nine trench shaders are **not edited** by the rebuild except for additive, backwards-compatible
  hooks (e.g. making a dresser accept a sub-rectangle), each one listed in the tracker and verified
  by `check.sh --live` reporting it. `scenes/legacy_drowned_trenches.tscn` must keep playing the
  legacy level at every milestone.
- **Alternatives.** Grow `TrenchMaze` into the front (the fastest path, but the legacy level dies in
  place and every change risks it); fork `TrenchArt` wholesale into the new classes (safe, 2,300 lines
  of duplication).
- **Why.** The package's first pillar. Reuse by composition (static helpers, sub-dressers) is tried
  first; duplication is accepted where composition would mean editing the legacy class.
- **Resolved in Milestone 2:** `FrontMaze extends TrenchMaze` and `FrontArt extends TrenchArt`.
  Each network is laid out by `TrenchMaze._layout()` in a scratch instance and copied into the
  front's grid; the enemy's is turned 180°. Everything that assumed "the front is toward -z" is
  overridden with a per-cell `facing`: in the maze `_rect`, `_floor_at`, `_ease_fire_steps`,
  `_widen_want`, `_craters`, `exit_transform`, `cells_far_from`, `_build_trench_world`, and
  `_carve` (a 110-line copy with a two-line change); in the art `_parapets`, `_fire_steps`,
  `_wire`, `_no_mans_land`, `_mist`. No legacy file was edited; `check.sh --live` reports only
  `game.gd`. Overrides that are copies are marked as such so a later fix to the legacy routine
  is known to need mirroring.

### D-03 · Objective modes on `Game` — decided, confirmed by Andrew 22 Nov (Milestone 1)
- **Decision.** `enum Objective { ELIMINATION, SURVIVAL }`, `var objective` set in `next_floor()`
  (SURVIVAL on trench floors). On SURVIVAL: `exit_open` is true from the start, the exit light is
  green/the H.Q. marked, the HUD shows the objective ("REACH THE ENEMY H.Q.") instead of
  `Clowns left`, `_on_clown_died` never starts the floor finale (no final-kill camera, no brutality
  report, no `EXIT OPEN` banner), kills/headshots/tickets/curse/records/perks still count. Bunker
  floors are unchanged. The legacy scene keeps ELIMINATION (`Game.survival_trenches = false`): it is
  the archive of the old experience. Implemented as `Game.Objective`, `Game.objective`,
  `Game.survival_trenches`, `Game._open_exit()`; the HUD shows `Kills: n` and `REACH THE ENEMY H.Q.`
  on SURVIVAL floors.
- **Alternatives.** A per-maze flag (`maze.objective`) — rejected: the objective is a floor rule the
  game owns, not a layout property. Keeping a soft kill target for a bonus — out of scope.
- **Why.** Smallest change that separates the two modes; every other system hangs off
  `_on_clown_died`, not off `remaining`.

### D-04 · Geometry: one carved heightfield, two networks, open ground between — proposed (Milestone 2)
- **Proposal.** Keep the proven ground model (one `HeightMapShape3D` at 0.2 m that is both mesh and
  collision; `col_h`/`vis_h`/`sdf`/`wet`; baked sky visibility) and enlarge it to hold: starting
  network (~50 × 40 m), No Man's Land (~80–120 m, tuneable), enemy network (~50 × 40 m). Each
  network is laid out by the existing trench layout logic with its own seed and orientation (the
  enemy side mirrored, facing the player's). No Man's Land is authored from shell craters (real
  depressions in `col_h`, with crouch cover and walkable slopes), wire belts with gaps, ridges and
  wreckage, not raw noise. The `Edge` wall becomes the outer boundary only.
- **Alternatives.** Separate meshes/colliders per feature (craters as meshes on a flat plane): more
  flexible, but bodies, blood pools, footsteps and the killcam are all proven on the heightfield.
  Terrain3D or a navmesh-first design: new dependencies, not justified yet.
- **Risks (J-2, J-3).** `_carve` cost at 3× the samples; A\* over open ground (D-05); vertical
  transitions (parapet climb) must be real geometry the player and enemies can use.

### D-05 · Navigation in No Man's Land — open (Milestone 3)
- Options: (a) extend the cell grid over the open ground (1.5 m cells, every cell open, costs from
  slope/water/wire; the existing `Maze` A\* and every brain keeps working); (b) `NavigationRegion3D`
  baked from the heightfield for the crossing only, with the trench grid for the networks. Leaning (a)
  for compatibility; decide after measuring A\* on ~4,000 extra cells.

### D-06 · Director drives situations through existing brains — decided in principle (Milestone 7)
- A `FrontDirector` node (per floor, like `TrenchBattle`) keeps tension and alertness, picks events
  from a catalogue with budgets/cooldowns, and realises them through `BattleDuty`/`ClownBrain`
  (soldiers with real duties and paths) or through cosmetic layers (far flashes, horizon figures).
  `TrenchBattle`'s pace/encounter code is the model, not the host: the legacy class stays as is.
  Damaging fire and cosmetic fire are different code paths, never the same actor flipping.

### D-07 · Surface impacts: one manager, metadata first — decided in principle (Milestone 5)
- `SurfaceImpactManager` (autoload or a child of the world) receives `(position, normal, dir,
  surface, weapon, energy, penetrated)` from `FpsPlayer.shoot_ray`'s world branch, the enemy raycasts
  and the mounted gun. Surface comes from collider meta (`surface = "mud"|"wood"|"concrete"|"metal"|
  "sandbag"|"water"|"soil"`) set by the dressers, from `TrenchMaze.surface_at` for the heightfield,
  else a material-name fallback. Decals and particles are pooled and capped; damage code is untouched.
  Bunkers get it too (`Maze`/`LevelArt` colliders tagged).

### D-08 · Fog as concealment must be one model — decided in principle (Milestone 4/6)
- Rendered fog and AI sight must agree: `TrenchFog.visibility()` (banks) gains a base term from the
  front's environment fog so the "30–60 m recognition" the user approves visually is also what
  soldiers see. The marksman and MG arcs read it. Tested, not assumed (J-4).

### D-09 · Protected systems are not touched — decided
- Weapons, player handling, gore, ragdolls, anatomy, killcam semantics, Carnival Curse, tickets,
  upgrades, saves, base, event rooms, Mixamo-derived soldier movement, the Klappersoldat's robotic
  movement, both Witzsoldat looks (50/50), Rattlejack, officer. Any milestone that must touch one of
  these files lists the exact hunk in the tracker and runs that system's test.

### D-10 · Performance budget — decided by Andrew 22 Nov
- **60 fps at Andrew's normal development resolution on his Mac.** The baseline is measured on the
  Mac first, not assumed: `godot --path . res://scenes/legacy_drowned_trenches.tscn -- perf=30`
  prints machine, renderer, window, average fps, 1% low, worst frame and dropped-frame counts every
  30 s of play (`scripts/dev/frame_probe.gd`). No performance claims without those numbers; no
  optimising ahead of them. Container (llvmpipe) numbers are never quoted as performance.

### D-11 · Documents, not conversation, carry state — decided
- `docs/DROWNED_FRONT_*.md` are read at the start of every session and updated at the end of every
  milestone; the project knowledge docs (`claude/*.md`) get a summary pointer only.

### D-12 · No Man's Land starts at ~90 m — decided by Andrew 22 Nov
- A prototype dimension for Milestone 2, tuned after Andrew can play the crossing.

### D-13 · Field soldiers stay cosmetic — decided by Andrew 22 Nov
- `TrenchField`'s men remain background dressing (never fight, not on the kill list). The director
  introduces **separate** real, combat-capable soldiers using the existing `Clown`/`ClownBrain`/
  `BattleDuty` AI. The two populations are never the same actor.

### D-14 · Front layout: ours at the rear edge, theirs at the front edge, one heightfield — decided (M2)
- The grid is 32 × (28 + nml_rows + 28) cells of 1.5 m: their network (rows 0–27, turned about so
  its fire trench faces us, its rear communication trench ending at the world's front edge, z ≈ 0),
  No Man's Land (`nml_rows` = 52 → 78 m of open ground between the blocks; fire trenches 97 m
  apart, wire belts ~85 m), our network (rows 80–107, the legacy layout as it was, the start at
  its rear end). One carved heightfield (336k samples at 0.2 m) is mesh and collision, as before.
- **The way over the top:** up to three *assault ramps* a side, cut through the parapet from a
  plain fire bay (the ordinary `_cut_ramps`, a little wider; the bay loses its fire step; the wire
  has a gap in front of it). They are also the way *down* into their fire trench.
- **The H.Q.** is at the far end of *their* rear communication trench: the player drops into their
  fire trench and works back through their lines to it. Legacy portal dressing, [E] door (M1).
- **Pathfinding** is the legacy top layer: every clear earth cell is a top cell, linked; No Man's
  Land is all top cells, so `Maze.path`/`path_cells` carry the player's route and the brains across
  it unchanged (D-05 resolved: option (a), the cell grid, at zero new code; its cost is one plain
  A* over ~2,900 nodes).
- **Flank routes** existed in M2 (round the end of a fire trench along the edge of the world).
  **M3: the wire closes them.** Each front belt runs the full width to the world's edge; the only
  ways through are its gaps (D-15).
- **The legacy battle is not run on the Front** (`TrenchBattle`, `TrenchField`, `TrenchFog`, its
  pace and encounters): they place the enemy, the field and the fog by the legacy's single front.
  The Front's soldiers keep their own `ClownBrain` behaviour until the director (M6–M9). The
  ambience (`TrenchAmbience`: wind, far guns, shells, drips) comes with the art and does run.
- **Enemy placement:** `FrontMaze.cells_far_from` returns trench cells only (never the open
  ground), two in three in the enemy network. Counts are the legacy's (15 + officer on floor 3).

### D-15 · Wire is a real barrier, shell holes are real cover, the player can crouch — decided (M3)
- **Wire.** `FrontMaze.wire_belts` is the plan (two full-width belts in front of the lines with a
  gap at every sap's observation post and every assault ramp; three to five short belts out in the
  middle). The plan drives both the look (`FrontArt._wire_belt`) and the game: the cells under a
  belt are taken out of the top layer (`_top_layer` override), so the brains path through the gaps
  like the player; each run of wire between two post positions and each coil gets a collision box
  on `LAYER_RAMP`, so it stops the **player only** — sight and rounds pass, as through real wire.
  A blown-out picket still blocks (its strands lie tangled); only a gap is open, and no run or coil
  is laid across one. Enemies are not stopped by the collision (their layer); they avoid the wire by
  pathing, which is the same thing in practice. The flank routes of M2 are closed by this.
- **Shell holes.** No Man's Land's holes are 2.2–4.5 m across the rim and 0.9–1.7 m deep (small
  ones mixed in), a **cosine bowl** with a low wide lip: the wall is never steeper than about 38°
  for any depth, so a man walks in and out, and the floor is chest-deep for a standing man and hides
  a crouched man's head (test: 57 holes, 45 chest-deep, 46 head-under, all walkable). Where holes
  run into one another the deeper bowl wins (min), lips max — summing them made 50° walls. The
  legacy parabola profile is unchanged for the legacy level.
- **Crouch.** `FpsPlayer`: hold Ctrl or C; capsule 1.8 → 1.2 m, eye 1.65 → 1.05 m, pace halved, no
  sprint; stands only with headroom (a shape check). `eye_height()` and `chest_height()` report the
  crouched figures for whoever aims at him — **not yet used by `ClownBrain`** (it still aims at
  +1.25 m and looks for the head at +1.5 m); that hook is Milestone 6's, with the MG arcs, so that
  crouching behind a rim really hides him from an MG and a rifleman alike.
- **Enemy cover in holes** (ducking into a crater under fire, crater-to-crater dashes) is the
  director's (M7–M9), on the field soldier's pattern; M3 only guarantees they can cross.
