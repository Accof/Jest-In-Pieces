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
- **Open sub-question (Milestone 2):** whether `FrontMaze` extends `TrenchMaze` (keeps every
  `maze is TrenchMaze` check in `TrenchBattle`, `BattleDuty`, `ClownBrain` working for free) or
  `Maze` (cleaner, but those checks need an interface). Leaning: extend `TrenchMaze`, override
  `generate()` and `_carve()`.

### D-03 · Objective modes on `Game` — decided (Milestone 1)
- **Decision.** `enum Objective { ELIMINATION, SURVIVAL }`, `var objective` set in `next_floor()`
  (SURVIVAL on trench floors). On SURVIVAL: `exit_open` is true from the start, the exit light is
  green/the H.Q. marked, the HUD shows the objective ("REACH THE ENEMY H.Q.") instead of
  `Clowns left`, `_on_clown_died` never starts the floor finale (no final-kill camera, no brutality
  report, no `EXIT OPEN` banner), kills/headshots/tickets/curse/records/perks still count. Bunker
  floors are unchanged. The legacy scene plays SURVIVAL too? **No:** `legacy_drowned_trenches.tscn`
  will pass a flag so the legacy level keeps ELIMINATION (it is the archive of the old experience).
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

### D-10 · Performance budget — proposed, needs the user
- Target hardware is the user's Mac (model and resolution to confirm). Proposal: **60 fps at the
  user's native resolution in the heaviest crossing seed, ≤ 4 ms CPU for AI+director on the floor**,
  measured with the game's own frame-time print and the Mac's Activity Monitor. The container's
  llvmpipe numbers are not a budget.

### D-11 · Documents, not conversation, carry state — decided
- `docs/DROWNED_FRONT_*.md` are read at the start of every session and updated at the end of every
  milestone; the project knowledge docs (`claude/*.md`) get a summary pointer only.
