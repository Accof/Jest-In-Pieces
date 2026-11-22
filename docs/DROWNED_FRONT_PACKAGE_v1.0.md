# JEST IN PIECES — OPERATION DROWNED FRONT
## Complete Claude Development Package · Master Brief, Addenda, Execution Plan and Acceptance Gates

**Version:** 1.0 · **Prepared:** 22 November 2026  
**Target:** Godot 4 Forward+ / GDScript  
**Status:** Planning specification — not an assertion that any new functionality has been implemented.

> **HOW TO USE THIS PACKAGE**  
> Give Claude this entire file and the user's No Man's Land visual reference image. Ask Claude to **read the full package**, inspect the actual repository and **execute only Session Zero**. Do not authorize the trench rebuild until the preservation baseline and plan are reviewed. Thereafter authorize one milestone at a time. Claude must not silently continue to the next milestone. The visual checkpoint at Milestone 4 is a **hard user-approval gate**.

---

# PART A — MASTER CREATIVE AND PRODUCT BRIEF

## A1. Vision

Transform the existing Drowned Trenches in *Jest in Pieces* from a compact kill-all trench maze into a substantial, procedurally varied WWI-inspired **survival traversal**: **starting trench system → frontline parapet → No Man's Land → enemy trench system → enemy H.Q. bunker exit**. The world must feel like an ongoing, hostile war, independent of the player. The player is an intruder passing through it, not a soldier required to clear the entire front.

**Core player objective:** **SURVIVE. CROSS NO MAN'S LAND. REACH THE ENEMY H.Q.**

The intended emotional arc is anticipation in the starting trenches; dread before going over the top; unpredictable, occasionally ferocious danger during the crossing; then unsettling quiet and uncertainty in the enemy trenches. Combat can be avoided, exploited, or initiated. A successful stealthy crossing is as valid as a violent one.

## A2. Non-negotiable design pillars

1. **Preserve before modifying.** Archive the existing Drowned Trenches in a genuinely recoverable and preferably playable form, with its generation, assets, materials, shaders, lighting, collision, AI and progression dependencies.
2. **No forced trench clear.** The new trench floor uses `SURVIVAL`; bunker floors retain `ELIMINATION`. The enemy H.Q. exit is available without a kill count.
3. **A real geographical journey.** Two navigable, distinct trench networks with exposed No Man's Land between them; multiple viable routes and meaningful cover.
4. **A living battlefield.** Patrols, parapet fighting, reinforcements, distant soldiers, machine-gun positions and artillery can exist independently of player detection.
5. **Fog as gameplay and art direction.** Pale, sickly green-grey haze, overcast diffuse light, dark wet mud, layered silhouettes, drifting smoke. The supplied image is the primary visual reference.
6. **Physical weapon feedback.** Bullets produce surface-specific holes, mud clods, dust, splinters, sparks and water impacts in both trenches and bunkers.
7. **Tense but fair.** Real machine-gun and artillery hazards, legible threats, usable craters and movement windows. No omniscient AI, invisible damage or unavoidable kill zones.
8. **Protect the existing game.** Do not regress weapons, enemies, variants, animation, cover, damage, gore, ragdolls, killcam, Carnival Curse, tickets, upgrades, saves, base or event rooms.
9. **Incremental implementation.** Tests, playable checkpoints, progress documentation, performance budgets and user sign-off at each milestone.

## A3. Current project context to verify in repository

The README describes a Godot 4 project tested on 4.7.2, with `scenes/game.tscn` as the main scene. Every third floor (`trench_every`) is the Drowned Trenches. The current trench layout is roughly 48 × 42 m with approximately 270 m of trench, generated via `scripts/world/trench_maze.gd` (`TrenchMaze`, 1.5 m grid). It contains fire, support and reserve lines, communications, saps, dugouts, a gun pit and an H.Q. portal. Current outdoor war activity is largely atmospheric and cannot hurt the player. Existing lighting includes `shaders/overcast_sky.gdshader`, sky-visibility shading, haze and a cold grade; the terrain uses scanned Poly Haven materials in `art/trench/polyhaven/` and `art/trench/pbr/`. Relevant files described by the README include `scripts/world/trench_ambience.gd`, `scripts/world/level_art.gd`, environment setup in `game.gd`, `scripts/clown/clown_brain.gd`, `scripts/fx/kill_cam.gd`, and `scripts/fx/explosion.gd`.

**Treat these as starting clues, not guaranteed current file locations.** Claude must inspect the repository before changing anything. The README also describes existing headless tests including `scenes/test_game.tscn`, `test_cover.tscn`, `test_events.tscn`, `test_death.tscn`, and `test_legs.tscn`; discover the full suite and run it with the installed Godot binary.

## A4. Protected game systems

Preserve the existing procedural testing pistol, revolver, shotgun, MP18-like SMG, Lee-Enfield-like bolt-action rifle, crossbow/stake projectile, grenades, mounted and portable machine guns, player handling and ammunition. Preserve human enemy movement improvements and Mixamo work where present. Preserve both Witzsoldat appearances and their configured spawn distribution, Rattlejack's distinctive firing/death behaviour, the intentionally robotic Klappersoldat, officer enemies, limb damage, gore segments, blood, oil puddles, ragdolls, body reactions, killcam, Carnival Curse, progression and persistent statistics. Preserve scanned PBR assets, their UV scale, normal/roughness/height maps and shader behaviour. Do not overwrite these assets or replace them with inferior generated substitutes.

---

# PART B — TECHNICAL ARCHITECTURE AND BACKUP

## B1. Phase 0: mandatory legacy preservation

**No destructive or architectural modification to the original trench system before this is verified.**

1. Inspect Git status, tracked/untracked files, ignored assets and any pre-existing user changes. Never discard or overwrite user work. If Git is unavailable, record that fact and use a verifiable filesystem snapshot.
2. Create a **complete baseline** with a clear identifier and timestamp, using a Git branch/tag/commit only where safe and appropriate. Preserve uncommitted work without assuming permission to commit unrelated changes.
3. Create `archive/legacy_drowned_trenches/` (or a clearly documented equivalent) containing a restorable snapshot of the old trench experience. Include the old generator, level integration, atmosphere, prop placement, shaders/material configurations, asset references, spawn and exit behaviour, and necessary dependencies. Shared assets can be referenced only if immutable or separately snapshotted and documented.
4. Prefer a runnable `scenes/legacy_drowned_trenches.tscn` or equivalent debug selector. If isolation is impractical, create a documented, tested restoration path rather than a misleading nonfunctional scene.
5. Run baseline tests and a real gameplay launch. Capture screenshots of original trench lighting, materials and geometry. Record exact commands, seeds, test results, Godot version and known failures.
6. Write `archive/legacy_drowned_trenches/RESTORE.md` explaining how to restore and reuse it without overwriting the new level.
7. Confirm the archive can be restored **from the archive**, not just from a potentially changing working tree.

**Phase 0 acceptance:** original level is reproducibly restorable; ideally separately playable; tests and visuals are documented. Stop if not achieved.

## B2. Planning and documentation

Create and maintain:

- `docs/DROWNED_FRONT_MASTER_PLAN.md` — this consolidated specification and resolved decisions.
- `docs/DROWNED_FRONT_IMPLEMENTATION_TRACKER.md` — milestones, status, dependencies, acceptance criteria, test results, screenshots, blockers, next action.
- `docs/DROWNED_FRONT_ARCHITECTURE.md` — inspected existing architecture, real file paths, interfaces, ownership, integration risks and data flow.
- `docs/DROWNED_FRONT_DECISIONS.md` — short design decision records, alternatives and trade-offs.

At each new Claude session, read these documents before changing code. Update them after each milestone. Do not rely on conversational context to preserve state.

## B3. Suggested responsibilities, not mandated filenames

- **Front generator:** assembles starting trenches, No Man's Land, enemy trenches and H.Q. exit.
- **Trench network generator:** reusable independent trench networks and their connections.
- **No Man's Land generator:** craters, cover, wire, terrain, obstacles, visual landmarks.
- **Objective controller:** survival versus elimination progression.
- **Battlefield director:** event selection, pacing, budgets and cooldowns.
- **Event points/registry:** safe, typed, navigable locations and reusable event definitions.
- **Squad coordinator:** limited shared tasks without replacing existing enemy brains.
- **Atmosphere controller:** region profiles, fog, smoke, lighting, wind.
- **Battlefield audio:** spatial ambience and distant/nearby combat layers.
- **Threat controller:** MG firing arcs, artillery events and suppression.
- **Surface impact manager:** shared material-aware hits and effect budgets.

Avoid redundant managers and parallel frameworks; integrate into the actual architecture. Define clear event ownership, lifecycle, seed handling, spawn validation and cleanup.

---

# PART C — COMPLETE GAMEPLAY AND ENVIRONMENT REQUIREMENTS

## C1. Objectives and progression

Implement explicit objective modes:

- `ELIMINATION`: existing bunker floor rules; required enemies must be eliminated before exit unlocks. Preserve event-room completion and existing final-kill camera semantics.
- `SURVIVAL`: new Drowned Front; exit is traversable and usable without eliminating enemies; director activity does not contribute to a required-kill counter. Player can escape while enemies remain alive.

Keep kills, headshots, tickets, perks, statistics, death, return-to-base and post-floor upgrades functional. Do not trigger the floor-final killcam on an arbitrary trench kill. Preserve any other intentional killcam contexts. No mandatory final battle or artificial gate at the H.Q.

## C2. Macro layout and procedural generation

**Initial scale targets only, tune after playtesting:** starting trenches approximately 50 × 40 m; No Man's Land approximately 80–120 m of crossing distance; enemy trenches approximately 50 × 40 m. Do not blindly enlarge the existing maze. Generate a coherent contiguous landscape with meaningful sightlines, navigation, elevation and landmarks. Use reproducible seeds.

**Starting trench network:** rear approach, support and reserve lines, communication trenches, front fire bays, traverses, duckboards, sandbags, firing steps, parapets, dugouts, observation positions, ammo storage, flooded areas, slumped walls, occasional bridges and believable dressing. Multiple approaches to the frontline.

**Frontline transition:** increasing gunfire, visible muzzle flashes and impacts, smoke over parapets, damaged earthworks and soldiers at posts. Permit crossing via climb-over, sap, breach or collapsed wall where practical. No fake entrances or inaccessible visual-only routes.

**No Man's Land:** shell-churned uneven mud, shallow/deep water-filled craters, broken trees, wire and screw pickets, abandoned equipment, wreckage, damaged gun pits, scattered bodies, ruined timber, sparse landmarks and smoke. Avoid uniform random-noise terrain. Shell craters must provide *actual* player and enemy cover, crouch room and navigable slopes. Wire should shape routes, with viable gaps and no random impossible barriers.

**Enemy trenches:** unfamiliar layout, distinct from the starting side; guarded fire bays, communications, dugouts, machine-gun positions, flooded sections, narrow bends, alternate approaches and H.Q. portal. Crossing into them should feel like relief followed by dread.

**Connectivity requirements:** player can travel from spawn to exit in every accepted seed; multiple viable routes are preferred. Validate collision, navigation, slopes, trenches, craters, bridges, entrances, player clearance, spawn reachability and exit. Reject or repair invalid seeds, recording why. Prevent enemies and event actors from spawning in unreachable spaces.

## C3. Visual target: supplied green-grey reference image

The supplied image is the **primary art-direction authority**. Claude must have access to the actual image; prose is not an adequate substitute.

**Desired look:** sickly desaturated olive/sage/green-grey haze; pale dirty yellow-grey overcast sky; bright diffused distant atmosphere without direct sun; near-black wet brown foreground mud; subtle puddle reflections; sharp nearby timber/wire and broken trees that become indistinct silhouettes with distance; drifting local smoke; oppressive but readable exposure. Colour is restrained so orange muzzle flashes, red flares and occasional clockwork eyes stand out.

Do **not** implement as a full-screen green overlay. Use physically coherent environment fog, sky and ambient lighting, restrained grading, material wetness and local smoke. Keep foreground legible; vary visibility naturally across regions. Initial distant recognition target ~30–60 m, adjustable after comparison. Preserve all scanned PBR materials and UV scales. Bunker and base lighting must remain unaffected. Use separate environment profiles and smooth transitions.

**Visual test scene:** fixed camera positions with wet mud, puddle/crater, wire, timber, dead tree, distant soldier silhouettes and drifting smoke. Capture actual Godot screenshots, not mock-ups or generated art. Provide at least four views: panorama towards enemy lines; ground-level mud/crater/wire detail; view over starting parapet; silhouettes at different smoke/fog densities. Where possible compare side by side with reference.

### HARD USER APPROVAL GATE — MILESTONE 4

**Stop all further implementation after Milestone 4.** Present actual running-game screenshots, comparison, measured settings, limitations and a request for explicit approval. Iterate on user feedback until approved. Only then record a named, recoverable approved atmosphere baseline (e.g. `drowned_front_approved_atmosphere`) and proceed. Later changes that materially affect the approved look require renewed approval. This is a hard gate, not an optional check.

## C4. Dynamic Battlefield Director

The director chooses *situations*, not exact soldier poses. Existing AI remains responsible for navigation, combat, cover and reactions.

**Separate metrics:**
- **Tension (0–100):** recent firefights, nearby shots/explosions, damage, pursuit, immediate threats and time since action.
- **Alertness (0–100 or local network):** confirmed sightings, heard shots, discovered bodies, reports, last known player position and time since contact. A loud battle need not reveal the player. Do not propagate global omniscience.

**Pacing modes:** uneasy quiet, rising tension, active combat and recovery. High tension should often *suppress additional spawns* so an existing fight can resolve. Recovery allows movement; the distant war continues regardless.

**Event inputs:** current region, line of sight, valid event points, player movement and exposure, health, active enemies, recent events, last known player position, distance, seed, cooldowns, budgets and performance. Update periodically rather than expensive every-frame scanning.

**Event catalogue, introduced incrementally:**
1. Lone soldier silhouette emerging from fog on a real patrol route.
2. Reinforcement group crossing a bridge or moving to frontline duties.
3. Parapet squad firing across No Man's Land.
4. Patrol investigating a locally heard disturbance or reported sighting.
5. Machine-gun emplacement engaging a plausible sector.
6. Nearby telegraphed artillery impact and soldiers ducking/relocating.
7. Occupied dugout with audible signs of life.
8. Rare Klappersoldat presence in a suitable location.
9. Drifting smoke crossing creating a temporary concealment opportunity.
10. Battlefield aftermath: damaged post, fleeing soldiers, disturbed equipment.

**Rules:** events need validated geometry and navigation, no visible spawning in the player's immediate view, finite active budgets, meaningful cooldowns, deterministic testability, safe cleanup and no exit obstruction. Soldier groups have destinations independent of the player. A shot alerts only those who plausibly perceive or receive reports of it. Soldiers should return to duties or investigate last-known positions after losing contact. Distant visual battles should not automatically become active enemies chasing the player.

**AI coordination:** small, imperfect groups may cover each other, advance, hold a parapet, react to incoming fire, investigate or withdraw. Keep Witzsoldat variants and their shared behaviour intact; retain Rattlejack and Klappersoldat identities. Human enemies should use their best available movement/animation; do not overwrite Mixamo-derived work or make Klappersoldat move like a normal human.

## C5. Machine guns, suppression and artillery

**Machine guns:** defined firing arcs, actual sightlines, muzzle flashes, distinct audio, bursts and pauses, finite reload/cooling logic, vulnerable operators or mechanisms, bullet impacts and meaningful blind spots. Do not make them perfectly accurate or omniscient. The player can observe, bypass, suppress, flank or attack them. Nearby fire should kick mud from trench walls and walk across open ground.

**Suppression:** nearby bullet cracks, dirt puffs, sound pressure and restrained camera feedback that encourages cover. Avoid excessive screen shake, aim disabling, control stealing or invisible stun. Damage must correspond to gameplay-relevant projectile/raycast collisions.

**Artillery:** distant flashes and delayed booms as ambience; occasional dangerous local impacts with warning whistle, visible location/impact, mud/debris/smoke and reactions. Telegraph danger fairly; avoid unavoidable instant-death barrages. A player pinned in a crater should eventually receive a plausible movement window from gun pauses, smoke, target switching or battlefield interruption, not overt scripted mercy.

## C6. Horror, silhouettes and encounter uncertainty

Fog progressively hides detail: distant dark shapes, middle-distance equipment and posture, near-distance gas masks and weapons. Mix real soldiers with occasional false shapes (broken trees, wire, hanging gear, wreckage). Soldiers may cross a route, disappear behind smoke, move between craters or pass unaware. Avoid every sighting becoming combat.

Use rare, audible Klappersoldat encounters (ticking, metallic steps, glowing eyes, deliberate movement). On entering enemy trenches, lower broad combat intensity and foreground water drips, timber creaks, footsteps around corners, muffled distant fire and occupied dugouts. Keep horror largely environmental; avoid constant jump scares.

## C7. Audio and atmosphere interaction

Layer distant artillery, rifle shots, MG chatter, wind, wire rattle, timber creaks, water, boots on mud/duckboards, shell whistles, nearby gunfire, soldiers and mechanical ticking. Use distance, attenuation, occlusion, interior/exterior filtering and appropriate reverb. Let sounds precede visual contact. Preserve existing audio architecture; provide replaceable asset slots if authentic recordings are unavailable. Do not mislabel synthesised placeholders as finished production sound.

## C8. Player freedom and crossing variation

Players can sneak, ambush, snipe, wait for smoke, move crater-to-crater, flank MGs, retreat, sprint at risk or bypass enemies. No kill-all condition, no forced alarm, no arbitrary boss. Reckless sprinting is discouraged by geography, cover, real firing arcs and patrol positioning—not invisible gates.

After the base crossing works, add controlled variants: smoke-heavy, artillery-heavy, MG-defended and optional darker flare-lit configurations. Each must retain connectivity, fair threat presentation, multiple routes, visibility and performance. Do not maximise randomness at the expense of authored-feeling layouts.

---

# PART D — ADDENDUM: PHYSICAL BATTLEFIELD IMPACT SYSTEM

## D1. Scope and architecture

Create a reusable **surface-aware impact system** for both new trenches and existing bunkers. Inspect all current hitscan, projectile, penetration, ricochet, collision and effect pipelines before implementing. A central `SurfaceImpactManager` (or equivalent) receives impact position, normal, incoming direction, surface classification, weapon/projectile type, impact energy and penetration/ricochet status. Prefer explicit physics/material metadata; do not rely exclusively on arbitrary node names. Reuse existing damage and explosion authority; do not introduce a conflicting second damage system.

## D2. Material response matrix

| Surface | Immediate response | Persistent response | Audio |
|---|---|---|---|
| Saturated mud / wet earth | Heavy dark clods, wet splatter, gravity-driven debris | Dark impact mark | Damp, muffled thud |
| Dry soil | Fine dust puff, grit, small dirt particles | Subtle mark | Dry dirt strike |
| Timber / duckboards | Directional splinters, chips | Bullet hole / damaged grain | Sharp wood crack |
| Concrete / stone | Pale dust, chipped fragments | Chipped impact decal | Hard brittle crack |
| Corrugated iron / metal | Brief sparks as appropriate, fragments | Pockmark; optional cheap dent on selected props | Metallic ping/clang |
| Sandbags | Dust, soil and fabric fibres | Puncture mark | Dull fabric/earth strike |
| Standing water | Droplets, sharp splash, expanding ripple | Transient ripple only | Water impact |

Avoid identical generic particle explosions on all surfaces. Preserve PBR maps and geometry. Persistent marks must align with surface normals, not float, project through unrelated geometry or accumulate without limits. Vary scale, rotation and mark choice. Directional debris must account for hit angle: ground impacts kick upward; wall impacts eject outward; glancing shots are different from perpendicular hits. Use gravity and limited collision where useful.

## D3. Machine-gun and explosion integration

A burst should visibly **walk across terrain**: successive mud puffs, crater-edge impacts, splashes and occasional metal sparks. Gameplay-relevant bullets must use actual collisions; distant cosmetic gunfire must be explicitly separated from damaging fire. Nearby explosions reuse existing explosion logic and add appropriate mud plumes, smoke, debris, water spray and shock feedback. **Permanent terrain deformation is optional and out of initial scope**; investigate separately if worthwhile.

## D4. Performance and AI integration

Use particle pooling when helpful, bounded decals, distance-based LOD, aggregated cosmetic effects during automatic fire and safe cleanup. Never throttle hit detection or damage to reduce VFX cost. In a later integration step, nearby impact events can notify existing AI for flinch, duck, cover and investigation—subject to actual perception and local awareness, not global knowledge.

## D5. Dedicated material test range

Create a repeatable test scene with wet mud wall/ground, dry soil, timber, concrete, metal, sandbags and water. Test single-shot and automatic weapons, directional debris, persistent marks, penetration/ricochet interactions, water ripples, cleanup and performance. Validate in existing bunkers as well as trenches. Capture actual screenshots or footage. No fake non-collision demonstration effects.

**Impact acceptance:** every material reacts distinctly; mud visibly flies from trench walls; bullet holes persist within budget; MG bursts produce spatially sequenced terrain impacts; existing weapons/damage/gore/ragdolls are unchanged.

---

# PART E — PERFORMANCE, QA AND REGRESSION

## E1. Performance architecture

Use simulation tiers: nearby soldiers with full AI/combat/physics/animation; midrange soldiers with safely reduced update frequency; distant soldiers with simplified activity; horizon figures and battle effects as non-interactive scenery. Distinguish distant cosmetic gunfire from damaging rounds. Optimise terrain, repeated props, shadows, particles, smoke, volumetrics, water and draw calls. Use bounded corpses/effects where compatible with existing persistence rules; do not silently delete effects explicitly required to last the floor. Measure performance on actual target hardware and record before/after numbers. Establish a target budget with the user rather than inventing one.

## E2. Automated checks

- Generate many deterministic seeds and assert player spawn → H.Q. reachability, viable route count, valid terrain collision, crater access, bridge clearance, trench entrance and no blocked exit.
- Validate event point reachability, director budgets/cooldowns, event lifecycle and cleanup, no forced kill counter, and no visible pop-in in tested view cones.
- Validate local perception: sound range, line of sight, last known positions, fog/smoke occlusion where technically supported, alertness decay and no omniscient reports.
- Validate MG arcs, line-of-fire collision, cover protection, damage, reload/pause and suppression; artillery telegraph and impact.
- Validate material classification, decal orientation, particles and effect budgets under automatic fire.
- Validate bunker `ELIMINATION`, trench `SURVIVAL`, exit use, tickets, upgrades, save compatibility, death/return-to-base, final-kill camera and event-room rules.
- Re-run existing project tests, especially gameplay, events, enemy cover/legs/death and any weapon/projectile tests.
- Verify the legacy trench archive still restores/launches after the new work.

## E3. Visual and manual QA

Headless tests cannot prove atmosphere, animation quality or encounter pacing. Launch a rendered build and inspect: fog reference match; mud/water materials; silhouette readability; smoke movement; craters; MG sightlines; bullet impacts; AI climbing/crouching/navigation; bunker lighting isolation. Play at least one complete route per milestone where appropriate. Test cautious, aggressive, stealthy and speed-focused approaches. Record failures and real observations, not claimed tests.

## E4. Development-only overlay

Show seed, region, objective mode, director state, tension, alertness, active events, active enemies by simulation tier, spawn budget, cooldowns, performance metrics and exit state. Add safe toggles for director on/off and selected test events. Do not expose debug state in production UI by default.

---

# PART F — MILESTONE ROADMAP AND APPROVAL CONTRACT

**General rule:** Claude may autonomously implement/test/fix **within the currently authorized milestone**. At milestone end, it must update tracker/docs, provide changed files, test commands and outcomes, screenshots where relevant, risks and a recoverable checkpoint, then **stop for user approval**. No automatic progression. Never commit, reset or delete unrelated user changes.

| Milestone | Deliverable | Key acceptance | Approval |
|---|---|---|---|
| **0 — Preservation and planning** | Repository audit, docs, verified legacy archive, baseline tests | Old trenches reproducibly restorable; no rebuild started | User review |
| **1 — Objective separation** | `ELIMINATION` vs `SURVIVAL` | Bunkers unchanged; trench exit independent of kills; killcam correct | User review |
| **2 — New battlefield geometry** | Two trench networks, continuous No Man's Land, H.Q. exit | Player can walk complete route; seeded connectivity tests | **User playtest** |
| **3 — Terrain and functional cover** | Craters, wire, obstacles, routes, enemy navigation | Cover and traversal work; no blocked seeds | User review |
| **4 — Reference atmosphere** | Green-grey lighting, fog, smoke, wet surfaces, silhouettes | Four real in-game screenshots compared to supplied image | **HARD VISUAL APPROVAL — STOP** |
| **5 — Physical impacts** | Material-specific holes, mud, dust, wood, metal, water, explosion VFX | Test range and bunker/trench demonstrations; bounded effects | User review |
| **6 — Core combat hazards** | MG nests, suppression, artillery basics | Threats fair, legible, cover works, no phantom damage | User playtest |
| **7 — Director foundation** | Tension/alertness, event points, budgets, debug overlay | Deterministic selection, no omniscience or accumulation | User review |
| **8 — Initial director events** | Lone silhouette, bridge reinforcements, parapet firefight | Soldiers have independent duties and real paths | User playtest |
| **9 — Expanded battlefield activity** | Investigation, smoke events, artillery reactions, squads | Variety, perception, event lifecycle and pacing | User review |
| **10 — Enemy trench suspense** | Dugouts, sounds, rare clockwork encounters, region pacing | Quiet after crossing; believable uncertainty | User playtest |
| **11 — Procedural variants** | Smoke/artillery/MG and optional flare crossings | Seed diversity without broken routes or unfairness | User review |
| **12 — Performance and polish** | AI LOD, rendering/physics/audio budgets, tuning | Measured stable performance; no major regressions | User review |
| **13 — Final integration** | Full regression, docs, restore proof, final playable experience | All acceptance criteria verified, known limits disclosed | Final approval |

### Milestone 4 mandatory visual approval procedure

1. Stop after the atmosphere milestone. Do not start bullet impacts or director work.
2. Capture **actual Godot-rendered screenshots** from (a) frontline parapet, (b) No Man's Land panorama, (c) mud/crater/wire ground detail, (d) fog-obscured soldiers/silhouettes. Include consistent camera coordinates and seed if feasible.
3. Compare with the supplied reference image. Explain differences in colour, fog, sky, contrast, scale, silhouettes and wetness; list remaining limitations.
4. Ask the user explicitly whether to approve or request changes. If changes requested, revise and recapture; do not progress.
5. On explicit approval, preserve the settings, screenshots and a named baseline. Material changes to the approved look require renewed approval.

---

# PART G — CROSS-CUTTING ACCEPTANCE CRITERIA

The project is not complete until all of the following are demonstrated:

1. Original Drowned Trenches are backed up and independently recoverable.
2. Existing bunker floors, events, saves and progression still work.
3. A generated level contains starting trenches, No Man's Land, enemy trenches and H.Q. exit.
4. At least one valid continuous route always exists; preferably several tactical routes.
5. No trench kill-all requirement; exit usable while enemies live.
6. Craters provide genuine, traversable cover; wire shapes but does not break routes.
7. MG fire and nearby artillery create real, telegraphed and avoidable danger.
8. Green-grey lighting/fog/smoke match the user-approved image direction.
9. Soldiers emerge through fog as readable silhouettes; visibility changes with smoke.
10. Battlefield activity continues independently of the player.
11. Director creates varied, bounded, geographically plausible events.
12. Enemy awareness is local and perception-based, not omniscient.
13. Witzsoldat variants, Rattlejack, Klappersoldat and other existing enemies retain intended identities.
14. Mud, timber, concrete, metal, sandbags and water react distinctly to bullets.
15. Bullet marks persist within budgets; MG bursts visibly strike the terrain.
16. Existing weapons, gore, ragdolls, Carnival Curse and killcam semantics remain intact.
17. Nearby, distant and horizon activity use appropriate performance tiers.
18. Automated seed, gameplay and regression tests pass or documented failures are explicitly approved.
19. Actual rendered screenshots and full-playthrough tests support visual and gameplay claims.
20. README, architecture, tracker, decisions and legacy restoration instructions are up to date.

---

# PART H — CLAUDE FIRST-SESSION PROMPT (COPY/PASTE)

> We are starting **Operation Drowned Front**, a substantial multi-stage overhaul of the Drowned Trenches in *Jest in Pieces*. Read the attached `Jest_in_Pieces_Drowned_Front_Master_Package.md` **in full** and inspect the actual Godot repository and README. The supplied green-grey No Man's Land image is the definitive atmosphere reference.
>
> **IMPORTANT: This first session is SESSION ZERO / MILESTONE 0 ONLY. DO NOT IMPLEMENT THE NEW TRENCHES YET.**
>
> 1. Inspect repository architecture, Git status, current trench generator, integration, environment, materials, AI, objective and test suite. Preserve uncommitted user work.
> 2. Create `docs/DROWNED_FRONT_MASTER_PLAN.md`, `docs/DROWNED_FRONT_IMPLEMENTATION_TRACKER.md`, `docs/DROWNED_FRONT_ARCHITECTURE.md` and `docs/DROWNED_FRONT_DECISIONS.md`. Use the package as the source of truth; resolve file names and dependencies against the actual codebase.
> 3. Create a verifiable, recoverable backup of the **entire existing trench experience**, not just one script, under `archive/legacy_drowned_trenches/` or a clearly justified equivalent. Prefer a runnable legacy scene. Document and test restoration.
> 4. Establish a safe baseline checkpoint; run existing headless tests and a rendered legacy trench check. Record exact commands, outcomes and known baseline failures.
> 5. Produce a realistic implementation plan, risks, file impact list and milestone dependencies. Identify any architectural conflicts before coding.
> 6. Report what was preserved, how to restore the old level, which tests passed/failed and the precise next milestone.
>
> **STOP and wait for my approval.** Do not start Milestone 1 or modify the new battlefield in this session. Future sessions must work one authorized milestone at a time, update documentation, verify functionality and stop for review. Milestone 4 requires my explicit **visual approval** based on actual in-game screenshots before any further implementation.

---

# PART I — REUSABLE PROMPT FOR EACH FOLLOWING SESSION

> Read `docs/DROWNED_FRONT_MASTER_PLAN.md`, `docs/DROWNED_FRONT_IMPLEMENTATION_TRACKER.md`, `docs/DROWNED_FRONT_ARCHITECTURE.md` and `docs/DROWNED_FRONT_DECISIONS.md`, plus the relevant sections of the Operation Drowned Front package. Inspect current Git status and preserve user changes.
>
> **You are authorized to work on Milestone [NUMBER AND NAME] ONLY.** First summarise its acceptance criteria, affected systems, dependencies and test plan. Implement incrementally, run automated checks and inspect rendered gameplay where required. Preserve the original archived trenches, existing PBR assets, bunker behaviour, enemy variants, weapons, gore, ragdolls, saves and progression.
>
> At completion, update the tracker and documentation; report changed files, exact tests/results, actual visual evidence if relevant, unresolved issues and a safe checkpoint. **STOP for my review before starting the next milestone.** Do not claim tests or visual checks you did not perform.

---

# PART J — RISK REGISTER / TECHNICAL DECISIONS TO VALIDATE

1. **Legacy backup completeness:** shared asset mutation can silently corrupt an archive. Prefer immutable copies or recorded hashes and a tested restoration path.
2. **Godot terrain and collision:** carved heightfields, deep trenches, vertical walls, bridges and shell craters may require separate meshes/colliders or hybrid approaches. Validate before committing to a generator design.
3. **Navigation across vertical transitions:** pathfinding alone may not handle parapet climbing, ledges or crater exits. Use verified transitions and appropriate movement abilities; do not fake them with teleportation.
4. **Fog and enemy perception:** rendered fog is not automatically respected by AI sight checks. Implement a consistent visibility model if fog is intended as actual concealment, and test it.
5. **Procedural MG fairness:** geometry and firing arcs must be validated together; a gun should never cover every viable crossing route.
6. **Director versus floor progression:** survival-mode actors cannot become required kills or trigger incorrect final-kill logic.
7. **Distant fire authenticity:** separate cosmetic horizon gunfire from gameplay-damaging projectiles; no untelegraphed hits.
8. **Performance under automatic fire:** impacts, decals, particles and physics must be bounded without throttling actual collision/damage.
9. **Atmosphere isolation:** environmental changes must not recolour bunkers, base, legacy trench or enemy materials unintentionally.
10. **Existing AI integration:** reuse current brains and animation; don't implement a duplicate enemy framework.
11. **Unverified README details:** source code may have changed. Treat this package's current-project references as a map to inspect, not a substitute for inspection.
12. **Human visual review:** code and headless tests cannot verify dread, pacing, fog composition or impact feel. Reserve real playtests and screenshots.

---

# FINAL CREATIVE REFERENCE

The player approaches the frontline through wet, damaged trenches. Rifles crack beyond the parapet. Soldiers hurry past with duties of their own. A machine gun rattles somewhere in the murk. The player climbs over the top into a vast, sickly green-grey haze. Near-black mud and water-filled craters stretch towards an unseen enemy line. Broken wire, timber and soldiers appear and disappear as smoke moves. Bullets strike trench walls and throw mud into the air. A shell whistles in; the player dives into a crater. Far away, dark figures move between shattered trees. They might have seen the player—or might be fighting someone else. The crossing is sometimes furious, sometimes eerily quiet. On the far side, the player slips into unfamiliar enemy trenches, where the artillery becomes muffled and mechanical ticking echoes from a dugout. The H.Q. bunker lies somewhere ahead. The player does not need to kill every soldier. **The objective is to survive and get through.**

**START WITH SESSION ZERO. PRESERVE THE ORIGINAL LEVEL. DO NOT BEGIN THE REBUILD UNTIL AUTHORIZED.**
