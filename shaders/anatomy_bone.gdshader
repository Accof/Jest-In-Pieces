shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Bone and cartilage, drawn from both sides (a skull broken open shows its
// inside): see anatomy.gdshaderinc.
#include "res://shaders/anatomy.gdshaderinc"
