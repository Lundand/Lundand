"""Renders parts exported by tools/export-parts.luau from an isometric viewpoint (flat shading, painter's order).
Rough, for checking shapes and placement, not looks.

python3 tools/render_view.py parts.json out.png [yawDegrees] [pitchDegrees] [scale] [cutY]
cutY drops every part above that height (a cutaway to see interiors).
"""
import json, math, sys
from PIL import Image, ImageDraw

parts = json.load(open(sys.argv[1]))
out = sys.argv[2]
yaw = math.radians(float(sys.argv[3]) if len(sys.argv) > 3 else 35)
pitch = math.radians(float(sys.argv[4]) if len(sys.argv) > 4 else 35)
scale = float(sys.argv[5]) if len(sys.argv) > 5 else 4
cut = float(sys.argv[6]) if len(sys.argv) > 6 else 1e9
LIGHT = (0.4, 0.8, 0.45)

def mat(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return (x, y, z), ((r00, r01, r02), (r10, r11, r12), (r20, r21, r22))

def world(pos, rot, v):
    return tuple(pos[i] + rot[i][0] * v[0] + rot[i][1] * v[1] + rot[i][2] * v[2] for i in range(3))

def view(p):
    x, y, z = p
    cx, sx = math.cos(yaw), math.sin(yaw)
    x1, z1 = x * cx - z * sx, x * sx + z * cx
    cp, sp = math.cos(pitch), math.sin(pitch)
    y2, z2 = y * cp - z1 * sp, y * sp + z1 * cp
    return x1, y2, z2  # z2: depth (bigger = closer)

def shapes(part):
    sx, sy, sz = [v / 2 for v in part["s"]]
    if part["k"] == "w":
        # Roblox wedge: full-height face at +z, slope down to the bottom edge at -z
        v = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz), (-sx, sy, sz), (sx, sy, sz)]
        faces = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 1, 5, 4), (0, 3, 4), (1, 2, 5)]
    else:
        v = [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
        faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    return v, faces

polys = []
for part in parts:
    pos, rot = mat(part["c"])
    if pos[1] > cut:
        continue
    verts, faces = shapes(part)
    wv = [world(pos, rot, p) for p in verts]
    for face in faces:
        pts = [wv[i] for i in face]
        a, b, c = pts[0], pts[1], pts[2]
        u = [b[i] - a[i] for i in range(3)]
        w = [c[i] - a[i] for i in range(3)]
        n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        length = math.sqrt(sum(x * x for x in n)) or 1
        n = [x / length for x in n]
        centre = [sum(p[i] for p in pts) / len(pts) for i in range(3)]
        out_dir = [centre[i] - pos[i] for i in range(3)]
        if sum(n[i] * out_dir[i] for i in range(3)) < 0:
            n = [-x for x in n]
        shade = 0.45 + 0.55 * max(0, sum(n[i] * LIGHT[i] for i in range(3)))
        col = tuple(min(255, int(ch * shade)) for ch in part["rgb"])
        vp = [view(p) for p in pts]
        depth = sum(p[2] for p in vp) / len(vp)
        polys.append((depth, [(p[0], p[1]) for p in vp], col, part["t"]))

xs = [p[0] for _, pts, _, _ in polys for p in pts]
ys = [p[1] for _, pts, _, _ in polys for p in pts]
minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
W, H = int((maxx - minx) * scale) + 20, int((maxy - miny) * scale) + 20
img = Image.new("RGB", (W, H), (150, 180, 210))
d = ImageDraw.Draw(img, "RGBA")
polys.sort(key=lambda t: t[0])
for depth, pts, col, t in polys:
    xy = [((p[0] - minx) * scale + 10, (maxy - p[1]) * scale + 10) for p in pts]
    d.polygon(xy, fill=col + (int(255 * (1 - t * 0.8)),), outline=(0, 0, 0, 40))
img.save(out)
print(out, img.size, len(polys), "faces")
