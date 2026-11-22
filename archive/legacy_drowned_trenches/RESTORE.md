# Legacy Drowned Trenches — archive and restoration

Snapshot of the Drowned Trenches as they were on **22 November 2026**, before
Operation Drowned Front (the survival-crossing rebuild) began.

- **Baseline commit:** `0772251` on `main` ("Add the uid file for the grime look dev script").
- **Git tag:** `legacy-drowned-trenches-baseline` points at that commit. `git checkout legacy-drowned-trenches-baseline` gives the whole project exactly as it was, art included.
- **Godot:** 4.7.2.stable (project `config/features` 4.7, Forward Plus).
- **Verified:** `check.sh --live` passed at archive time (every legacy file in the live tree, code and art, byte-identical to the archived original); the legacy scene built a trench floor headless (`legacy Drowned Trenches: floor 3, TrenchMaze, 15 enemies, seed 1916`); restoration into a scratch checkout from the archive alone was tested (see "Restoration test" below).

## What is here

```
archive/legacy_drowned_trenches/
  RESTORE.md            this file
  files.tsv             snapshot path -> original path -> role (legacy / legacy-test / legacy-tool / shared-reference)
  SNAPSHOT.sha256       hashes of the archive's own copies (is the archive intact?)
  ORIGINALS.sha256      hashes of the originals by their live-tree paths: the code above AND every
                        art file the trench loads (art/trench/**, art/level/fx_*.png, wall_conc.png)
  check.sh              verify the archive; with --live, verify the live tree still matches it
  restore.sh            copy the legacy code back into the live tree (or into another checkout)
  snapshot/             byte-exact copies (a .gdignore keeps Godot from scanning them, so the
    .gdignore           duplicated class_names do not clash with the live scripts)
    trench/             the trench-only code: TrenchMaze, TrenchArt, TrenchBattle, TrenchField,
                        TrenchFog, TrenchAmbience, FarFigures, BattleDuty, FieldSoldier, and the nine
                        shaders only the trench uses (overcast_sky, mud_terrain, water_mud, ground_mist,
                        pbr_object, wire_sway, balloon_sway, cloth_wind, ripple)
    tests/              test_trench, test_trench_level, render_level (scripts and scenes)
    tools/              gen_trench_textures.py (the generated mud textures in art/trench/)
    shared/             REFERENCE copies of shared files as they were at the baseline: game.gd (floor
                        selection, environment swap, exit, enemy shares), maze.gd (the Maze API the
                        trench extends), level_art.gd, clown_brain.gd (fog hook, hearing), fps_player.gd
                        (trench footsteps), explosion.gd ("shell" profile), sfx_synth.gd (the synthesised
                        trench sounds). These are NOT restored by default: they carry every other system too.
    docs/               the README's Drowned Trenches section and project.godot as they were
```

**Art is not copied.** `art/trench/` is 138 MB of scanned (Poly Haven, CC0) and generated
textures that the project treats as immutable. Instead every art file the trench loads is
hashed in `ORIGINALS.sha256`, and the git tag holds the bytes. `check.sh --live` tells you if
any of them has changed; `git checkout legacy-drowned-trenches-baseline -- art/trench` brings
them back.

## How the legacy level is wired (for whoever restores it)

- `game.gd` → `is_trench_floor(n)` (`n % trench_every == 0`) → `next_floor()` makes a
  `TrenchMaze` instead of a `Maze`; `_apply_floor_look(true)` swaps in
  `TrenchArt.make_environment()`, `make_camera_attributes()` and `setup_sun()`.
- `TrenchMaze.generate()` lays out the 1.5 m grid, carves the heightfield (`_carve`), bakes sky
  visibility (`_bake_sky`), builds the `HeightMapShape3D` collision and an `Art` child
  (`TrenchArt.build`), which dresses it and adds `TrenchAmbience` and `FarFigures`.
- `game.next_floor()` then makes a `TrenchBattle` (`assign(maze, clowns, seed, spawn)`), which
  hands out `BattleDuty` jobs to the floor's enemies and creates `TrenchField` (the No Man's Land
  fight, `FieldSoldier`s not on the kill list) and `TrenchFog` (fog banks; `ClownBrain._fog`).
- The exit is the game's ordinary exit door at `maze.exit_transform()` (the H.Q. portal at the far
  end of the fire trench) and opens when `remaining <= 0`, the same as a bunker floor.

## Playing the legacy level

```
godot --path . res://scenes/legacy_drowned_trenches.tscn -- [seed=N] [floor=N] [god]
```

`scenes/legacy_drowned_trenches.tscn` (`scripts/dev/legacy_drowned_trenches.gd`) starts a run
straight onto a trench floor with the project's own trench classes and a test save (your real
save is untouched). A headless smoke check:

```
LEGACY_QUIT_AFTER=3 godot --headless --fixed-fps 60 --path . res://scenes/legacy_drowned_trenches.tscn -- seed=1916
# prints: legacy Drowned Trenches: floor 3, TrenchMaze, N enemies, seed 1916 / ok (trench)
```

The plan for Operation Drowned Front (docs/DROWNED_FRONT_DECISIONS.md, D-02) is that the new
front gets **new classes** and the legacy classes stay in the tree untouched, so this scene keeps
playing the legacy level throughout. If a later change does touch a legacy file, `check.sh --live`
reports it, and the snapshot restores it.

## Restoring

1. From the project root: `archive/legacy_drowned_trenches/check.sh` (the archive is intact).
2. `archive/legacy_drowned_trenches/restore.sh --dry-run` lists what differs from the originals.
3. `archive/legacy_drowned_trenches/restore.sh` copies the **legacy** files (trench code, shaders,
   tests, tool) back over the live ones. Nothing is deleted. It does not touch the shared files.
4. `godot --headless --path . --import`, then play `scenes/legacy_drowned_trenches.tscn`.
5. `check.sh --live` should now pass for the code. If it reports art files, restore them from the tag:
   `git checkout legacy-drowned-trenches-baseline -- art/trench art/level/fx_billow.png art/level/fx_fire.png art/level/fx_smoke.png art/level/wall_conc.png`.

**Shared files.** If the new front has changed `game.gd`, `maze.gd`, `clown_brain.gd`, etc. in ways
the legacy classes no longer fit (e.g. the Maze API changed), you have three options, safest first:
- check out the tag into a separate directory and play it there (`git worktree add ../jest-legacy legacy-drowned-trenches-baseline`);
- diff the live file against `snapshot/shared/<file>` and reinstate only the trench hooks;
- `restore.sh --shared` overwrites those shared files wholesale with the baseline copies. This also
  rolls back everything else those files gained since 22 Nov 2026. Use it only in a scratch checkout.

**Into another checkout:** `restore.sh --to /path/to/checkout` restores there instead
(the target must contain a `project.godot`).

## Restoration test (how the archive was proven)

A scratch copy of the project had `scripts/world/trench_maze.gd` deleted and
`scripts/world/trench_art.gd` and `shaders/mud_terrain.gdshader` overwritten with junk. Only the
`archive/legacy_drowned_trenches/` directory was copied into it. Then:

```
archive/legacy_drowned_trenches/check.sh --live     # reported the three damaged files
archive/legacy_drowned_trenches/restore.sh           # restored 3 files
archive/legacy_drowned_trenches/check.sh --live     # ok
godot --headless --path . --import
LEGACY_QUIT_AFTER=3 godot --headless --fixed-fps 60 --path . res://scenes/legacy_drowned_trenches.tscn -- seed=1916   # ok (trench)
godot --headless --fixed-fps 60 --path . res://scenes/test_trench.tscn                                                 # TRENCH: 0 failed
```

The result of that run is recorded in docs/DROWNED_FRONT_IMPLEMENTATION_TRACKER.md (Milestone 0).
