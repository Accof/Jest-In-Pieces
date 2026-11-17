# Trench PBR sets (Poly Haven, CC0)

Each folder holds one set, repacked from the 2K PNG downloads:
- `<name>_diff_2k.png`: albedo (sRGB), any alpha dropped.
- `<name>_nor_gl_2k.png`: normal map, OpenGL convention (green = toward the top of the image). This was checked against each set's height map: red follows -dh/du and green follows +dh/drow.
- `<name>_ard_2k.png`: linear, R ambient occlusion, G roughness, B displacement (16-bit sources reduced to 8-bit).

| Set | Source | Used for | Not used |
|---|---|---|---|
| brown_mud_wall | brown_mud (the "for wall" download) | trench walls and exposed earth up top (`shaders/mud_terrain.gdshader`) | |
| rocks_ground_08 | rocks_ground_08 | eroded rims, slumped and damaged stretches, patches of ground (`mud_terrain.gdshader`) | |
| rough_wood | rough_wood | linings, posts, duckboards, fire steps, beams, crates, signs (`shaders/pbr_object.gdshader`) | |
| hessian_230 | hessian_230 | sandbags (`pbr_object.gdshader`) | `mask` (weave openings: cuts holes in a filled bag), `metal` EXR (cloth is not metal) |
| rusty_metal_04 | rusty_metal_04 | corrugated iron, the dugout roof sheet, pickets (`pbr_object.gdshader`) | (no metalness map in the set: metallic comes from the bare, unrusted patches of the albedo) |

The trench floor scan (brown_mud_03) is in `../polyhaven/`.
