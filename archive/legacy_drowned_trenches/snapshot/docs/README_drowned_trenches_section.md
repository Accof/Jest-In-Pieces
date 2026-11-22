## The Drowned Trenches

Every third floor (`trench_every` on the game, 3) is a Western Front trench system in daylight the morning after heavy rain. It is a new layout every time, about 270 m of trench in a 48 x 42 m area, cut into open ground that runs out to the horizon.

**Layout** (`scripts/world/trench_maze.gd`, `TrenchMaze`, on a 1.5 m grid, the width of a trench):
- **Fire trench** facing No Man's Land: bays and traverses, a fire step under the front wall of every bay (step up onto it to see out over the parapet), sandbags on the parapet with a loophole here and there, and a parados behind.
- **Support line**, sinuous, about 12 m back, and a partial **reserve line** behind that.
- **Communication trenches**: zigzags between the lines, three to the front and two to the reserve, making loops. One runs back to the rear edge, which is where you come in.
- **Saps**: zigzags out from the fire trench to an **observation post** with a periscope.
- **Side features**:
  - dead-end firing positions;
  - dugouts (a timber entrance, a roof of beams, iron and sandbags, a lantern burning inside);
  - a flooded side trench;
  - a ruined field gun in its pit.
- **Landmarks**: a shattered tree at one junction, a flooded junction at another, and a stretch where the wall has slumped in (still passable).
- **Exit**: the H.Q. bunker, a concrete portal at the far end of the fire trench.

**Ground:**
- One carved heightfield (0.2 m) is both the mesh and the collision (`HeightMapShape3D`).
- The trench floors are uneven, with ruts, sumps and mud heaped at the foot of the walls.
- Walls lean back by their lining. Bare earth walls slump and bulge.
- Linings: timber boards on posts, corrugated iron on pickets, sandbags, woven hurdles, or boards that have come away. Most stop short of the top. Each has a thin collision box so bodies hit the lining.
- **Duckboards** run down the middle of the trenches. Some slats are missing or tilted, and the boards are sunk in the flooded stretches. You walk on them: the walked surface is raised under them.
- Bodies, blood pools, gibs, the Carnival Curse and the killcam all work on it.

**The trench floor** is a scanned mud: Poly Haven's brown_mud_03 (CC0, `art/trench/polyhaven/`).
- Maps: albedo, an OpenGL normal map, and ambient occlusion, roughness and height packed into one texture.
- 2.4 m per tile, so the boot prints come out boot-sized.
- Parallax occlusion from the height map gives the ruts and boot holes real depth up close (fading out by 14 m).
- Darkened, warmer and more saturated than the scan, so it reads as soaked Flanders mud.
- The low parts are darker, with a film of water on them (a wet sheen, not a mirror); the crests and crumbs stay rough.
- Water stands in the deepest hollows in patches.

**Scanned materials** (Poly Haven, CC0, `art/trench/pbr/`; each set is albedo, an OpenGL normal map, and AO/roughness/height packed into one texture):
- **Walls and exposed earth:** brown_mud.
  - On the walls it's projected along X or Z by which way the wall faces, 2.5 m per tile, two samples blended by noise so long walls don't repeat. Darker and wetter at the foot.
  - It's also the thrown-up earth up top near the trenches. Further off is the old procedural firmer ground.
- **Rocks:** rocks_ground_08, 2 m per tile. It shows on the eroded rim where a wall breaks over, in the slumped stretch, where linings have come away, in patches of ground, and at the foot of bare walls. It's blended by its height map so stones stand out of the mud.
- **Wood:** rough_wood (`shaders/pbr_object.gdshader`), 1 m per tile. Used for linings, posts, duckboards, fire steps, dugout beams, crates and signs. The grain runs along each piece's longest side, and every board and slat uses its own part of the texture.
- **Sandbags:** hessian_230, 0.45 m per tile. Muddied and wet. The weave's opening mask and the set's metalness map aren't used.
- **Corrugated iron:** rusty_metal_04, 1.6 m per tile, on the sheets, the dugout roof sheet and the wire pickets. The rust runs down; the bare grey patches read as metal.
- **Mapping:** the prop shader works in object space in metres, so nothing stretches along a long board.
- **Normal maps:** the orientation is checked by the "normals" test on every surface type.
- **Parallax:** only on the trench floor.
- **Wattle:** the woven hurdles have no scan; their procedural texture is darkened to sit with the scans.

**Mud and water:**
- `shaders/mud_terrain.gdshader` blends four generated muds (`tools/gen_trench_textures.py`, in `art/trench/`):
  - churned mud on the ground near the trenches;
  - sludge on the trench floors;
  - the cut soil strata on the walls;
  - firmer ground further off.
- Everything is darker and glossier the wetter it is, with puddles lying in the flat low places.
- Standing water (`shaders/water_mud.gdshader`) is opaque brown and mostly calm, with a slow shiver of wind across it.

**Light and atmosphere** (cold, wet, dark and oppressive, but readable):
- A storm sky (`shaders/overcast_sky.gdshader`): dark blue-grey cloud masses with lighter openings, silver edges and a warm-grey glow low toward the hidden sun, drifting slowly. No rain, no lightning, no sun disc.
- The light falls off down the trench: the sky is brightest, the parapets moderately lit, the upper walls dark, the lower walls and floor in deep shadow. This comes from a baked sky-visibility term (how much sky each point of ground can see, `TrenchMaze._bake_sky`) used as ambient occlusion on the ground and on every prop, not from turning the exposure down. Enemies are not darkened by it, so they stand out against the walls.
- The mud and water are very dark; the water reflects the sky softly (no hard sun glints).
- Depth haze: nothing in the first 18 m (the trench stays crisp), the far battlefield blue-grey. No dense fog in the trenches.
- A cold grade (a 3D LUT): blue-grey shadows, neutral mid-tones, a touch of warmth only in the brightest light, the darks a little desaturated. Not a blue filter, and no vignette or grain.
- Far off: tall smoke columns leaning with the wind (black over the fires, dark grey otherwise), a few orange fires flickering on the horizon with sparks (they light nothing), a ruined village and a broken church tower on the skyline, shattered trees at every distance, wrecked sandbag posts in No Man's Land, and now and then a file of soldiers walking along the skyline (`FarFigures`, scenery only).
- The bunkers and the base get their own dark lighting back.

**Dressing:**
- **No Man's Land:** two staggered rows of screw pickets with wire strung and criss-crossed between them, concertina coils along the front, and gaps where the saps go out. The wire sways a little. Beyond that: shell holes holding rainwater, dead trees, and a wrecked limber with a wheel off.
- **In the trenches:**
  - Dugouts have a bunk, crates, a telephone and a rifle rack. The gun pit has shell boxes; the OP has a telephone and a cable reel.
  - Along the walls lie shovels, picks, helmets, tins, kit bags, blankets, rifles and sheets of iron. A stretcher is left at the way in.
  - Big pieces only stand where there is room, and they have collision.
  - Hand-painted signs at the junctions name the trenches (PICCADILLY, BOND ST...) and say which way the fire trench is. Each dugout is numbered.
- **The carnival, barely:**
  - a cracked porcelain clown head half sunk in the mud;
  - a faded circus bill in one dugout, with a music box and a broken watch;
  - a tin clown on its side in a firing position;
  - a red balloon caught on the wire;
  - a grinning sign daubed on one timber lining.
- **Wind:** torn canvas over some dugout doors, telephone cable looped along the walls, and scraps of paper lifting at a few junctions.

**Sound** (`scripts/world/trench_ambience.gd`; all synthesised placeholders in `SfxSynth`, each replaceable by a .wav):
- wind, and the low rumble of the guns;
- shells landing far off: a flash on the horizon, the boom arriving later by the speed of sound, sometimes smoke rising where it fell;
- distant machine-gun bursts and rifle shots;
- timber creaking in the linings, and water dripping at dugout doors and over the flooding;
- loose wire and pickets rattling in the wind, water lapping when you are near it, and very occasionally a whistle far down the line;
- the music box playing a few bars of a waltz when you are near it, and very rarely the same tune, faint, from nowhere.

The war stays far off: nothing out there can hurt you.

**Footsteps** (the player, on trench floors): mud, duckboards, water or firmer ground, by what is underfoot. Wading throws a splash and leaves a ripple spreading on the water; mud flicks up now and then.

**Eye adaptation:** the exposure lifts slowly in a dugout or a dark corner and comes back down in the open.

**Enemies:**
- 1.5x the usual number: mostly WitzSoldaten, Rattlejacks and Klappersoldaten, a few clowns, and always an officer.
- The AI is unchanged. Hearing, the spawn spread and doorway approaches scale with the 1.5 m grid.

Settings on the game: `trench_every`, `trench_enemy_scale`, `trench_soldier_share`.

