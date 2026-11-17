# brown_mud_03 (Poly Haven, CC0)

Source: https://polyhaven.com/a/brown_mud_03 (2K PNG set), licensed CC0.

Used on the Drowned Trenches floor (`shaders/mud_terrain.gdshader`):

| File | From | Notes |
|---|---|---|
| `brown_mud_03_diff_2k.png` | `_diff_2k.png` | albedo, sRGB; the alpha channel (all 255) dropped |
| `brown_mud_03_nor_gl_2k.png` | `_nor_gl_2k.png` | normal map, OpenGL convention (green = up the image), as Godot expects |
| `brown_mud_03_ard_2k.png` | `_ao_2k.png`, `_rough_2k.png`, `_disp_2k.png` | packed, linear: R ambient occlusion, G roughness, B displacement (height) |

The packed map saves two texture samples per parallax step.
