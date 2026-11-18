# Re-encode every image embedded in a GLB as a plain baseline JPEG (PIL), rebuilding
# the binary chunk. Godot's JPEG decoder rejects some JPEGs Blender writes.
import json, struct, io, sys
from PIL import Image
path = sys.argv[1]
b = open(path, "rb").read()
jl = struct.unpack("<I", b[12:16])[0]; j = json.loads(b[20:20 + jl])
bin_start = 20 + jl + 8; bl = struct.unpack("<I", b[20 + jl:24 + jl])[0]
binc = b[bin_start:bin_start + bl]
views = [binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]] for v in j["bufferViews"]]
for im in j["images"]:
    i = im["bufferView"]
    x = Image.open(io.BytesIO(views[i])).convert("RGB")
    o = io.BytesIO(); x.save(o, "JPEG", quality=92, optimize=False, progressive=False, subsampling=0 if "normal" in im.get("name", "").lower() else 2)
    views[i] = o.getvalue(); im["mimeType"] = "image/jpeg"
out = bytearray()
for v, data in zip(j["bufferViews"], views):
    while len(out) % 4: out.append(0)
    v["byteOffset"] = len(out); v["byteLength"] = len(data); out += data
while len(out) % 4: out.append(0)
j["buffers"][0]["byteLength"] = len(out)
js = json.dumps(j, separators=(",", ":")).encode()
while len(js) % 4: js += b" "
glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(out), 0x004E4942) + bytes(out)
open(path, "wb").write(glb)
print("re-encoded", len(j["images"]), "images;", len(glb), "bytes")
