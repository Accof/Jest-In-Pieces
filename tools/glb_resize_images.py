"""Downscale every image embedded in a GLB to at most <size> on a side.

    python3 tools/glb_resize_images.py <file.glb> <size>

Colour and normal maps are re-encoded as baseline JPEG (quality 92; the normal
map without chroma subsampling), a metal/roughness map (name containing
"metal", "rough", "mr" or Tripo's unnamed PNG) as lossless WebP so its hard
metal edges do not ring (Godot imports EXT_texture_webp). Nothing else in the
file changes. Used for the enemy rifle (Tripo's 4K maps -> 2K: a rifle at
arm's length does not need more, and the three maps are shared by every
rifle on the floor).
"""
import io
import json
import struct
import sys

from PIL import Image

path, size = sys.argv[1], int(sys.argv[2])
b = open(path, "rb").read()
jl = struct.unpack("<I", b[12:16])[0]
j = json.loads(b[20:20 + jl])
bin_start = 20 + jl + 8
bl = struct.unpack("<I", b[20 + jl:24 + jl])[0]
binc = b[bin_start:bin_start + bl]
views = [binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]] for v in j["bufferViews"]]
webp_used = False
for im in j["images"]:
    i = im["bufferView"]
    name = im.get("name", "").lower()
    x = Image.open(io.BytesIO(views[i]))
    w, h = x.size
    if max(w, h) > size:
        k = size / max(w, h)
        x = x.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    o = io.BytesIO()
    is_mr = any(t in name for t in ("metal", "rough", "mr")) or (im.get("mimeType") == "image/png" and "normal" not in name and "color" not in name)
    if is_mr:
        x.convert("RGB").save(o, "WEBP", lossless=True, quality=100, method=6)
        im["mimeType"] = "image/webp"
        im["name"] = "MetalRough"
        webp_used = True
    else:
        x.convert("RGB").save(o, "JPEG", quality=92, optimize=False, progressive=False, subsampling=0 if "normal" in name else 2)
        im["mimeType"] = "image/jpeg"
    views[i] = o.getvalue()
    print("%s: %dx%d -> %dx%d, %s, %d bytes" % (im.get("name"), w, h, x.size[0], x.size[1], im["mimeType"], len(views[i])))
if webp_used:
    # textures that refer to a webp image do so through the extension
    for t in j.get("textures", []):
        src = t.get("source")
        if src is not None and j["images"][src]["mimeType"] == "image/webp":
            t.setdefault("extensions", {})["EXT_texture_webp"] = {"source": src}
            del t["source"]
    for key in ("extensionsUsed", "extensionsRequired"):
        j.setdefault(key, [])
        if "EXT_texture_webp" not in j[key]:
            j[key].append("EXT_texture_webp")
out = bytearray()
for v, data in zip(j["bufferViews"], views):
    while len(out) % 4:
        out.append(0)
    v["byteOffset"] = len(out)
    v["byteLength"] = len(data)
    out += data
while len(out) % 4:
    out.append(0)
j["buffers"][0]["byteLength"] = len(out)
js = json.dumps(j, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(out), 0x004E4942) + bytes(out)
open(path, "wb").write(glb)
print("wrote", path, len(glb), "bytes")
