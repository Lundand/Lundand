"""Renders build/layout.json (from tools/dump-layout.luau) as a top-down master plan PNG.

python3 tools/render_plan.py [layout.json] [out.png]
"""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

src = sys.argv[1] if len(sys.argv) > 1 else "build/layout.json"
out = sys.argv[2] if len(sys.argv) > 2 else "build/master-plan.png"
d = json.load(open(src))
S = 2.0  # pixels per stud
MIN_X, MAX_X, MIN_Z, MAX_Z = -520, 940, -580, 980
W, H = int((MAX_X - MIN_X) * S), int((MAX_Z - MIN_Z) * S)
img = Image.new("RGB", (W, H), (120, 150, 95))
g = ImageDraw.Draw(img)

def P(x, z):
    return ((x - MIN_X) * S, (z - MIN_Z) * S)

def corners(e):
    x, z = e["center"]; hw, hd = e["size"][0] / 2, e["size"][1] / 2
    yaw = math.radians(e.get("yaw", 0)); c, s = math.cos(yaw), math.sin(yaw)
    return [P(x + ox * c + oz * s, z - ox * s + oz * c) for ox, oz in ((-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd))]

def box(x0, x1, z0, z1, fill, outline=None):
    g.rectangle([P(x0, z0), P(x1, z1)], fill=fill, outline=outline)

# forest
f = d["forest"]["bounds"]
box(f["minX"], f["maxX"], f["minZ"], f["maxZ"], (70, 110, 60))
for zn in d["forest"]["zones"]:
    g.polygon(corners(zn), outline=(200, 60, 60))
pts = [P(*p) for p in d["forest"]["path"]]
g.line(pts, fill=(150, 120, 80), width=int(8 * S))
for br in d["forest"]["branches"]:
    g.line([P(*p) for p in br], fill=(150, 120, 80), width=int(5 * S))
for c in d["forest"]["clearings"]:
    x, z = c["center"]; r = c["radius"]; g.ellipse([P(x - r, z - r), P(x + r, z + r)], fill=(110, 145, 80))
# water
for w in d["water"]:
    g.polygon(corners(w), fill=(70, 110, 160))
b = d["bounds"]
box(b["minX"], b["maxX"], b["minZ"], b["maxZ"], (176, 168, 152))
for w in d["water"]:
    g.polygon(corners(w), fill=(70, 110, 160))
SURF = {"Plaza": (205, 195, 175), "Yard": (190, 182, 160), "Alley": (150, 140, 125), "Garden": (110, 150, 85), "Courtyard": (195, 185, 165)}
for e in d["ground"]:
    col = SURF.get(e.get("surface"))
    if col:
        if e.get("shape") == "Disc":
            x, z = e["center"]; r = e["size"][0] / 2; g.ellipse([P(x - r, z - r), P(x + r, z + r)], fill=col)
        else:
            g.polygon(corners(e), fill=col)
for e in d["roads"]:
    g.polygon(corners(e), fill=(158, 150, 138) if e.get("width") != "Main" else (140, 132, 120))
for p in d["piers"]:
    box(392, 392 + p["length"], p["z"] - 4, p["z"] + 4, (120, 90, 60))
for sh in d["ships"]:
    x, z = sh["center"]; g.rectangle([P(x - sh["beam"] / 2, z - sh["length"] / 2), P(x + sh["beam"] / 2, z + sh["length"] / 2)], fill=(90, 60, 40))
# public buildings with a real ground floor (CityBuilder.PUBLIC, guild halls aside); every other door leads to an
# instanced interior
WALK_IN = ("Inn", "Guild", "Forge", "Apothecary", "CraftGuild", "SlumTavern", "Tavern")
COL = {"Sale": (90, 140, 210), "Npc": (190, 150, 110), "Public": (220, 190, 70), "Royal": (150, 90, 170), "Guild": (90, 190, 170)}
for e in d["blocks"]:
    col = COL.get(e.get("access"), (120, 120, 120))
    if e.get("kind") in ("Wall", "Tower", "Gatehouse"):
        col = (100, 100, 105)
    if e.get("use") in WALK_IN:
        col = (205, 120, 80)
    if e.get("shopfront"):
        col = (196, 64, 92)
    g.polygon(corners(e), fill=col, outline=(40, 35, 30))
    # door tick
    door = e.get("door")
    if door:
        x, z = e["center"]; hw, hd = e["size"][0] / 2, e["size"][1] / 2
        lx, lz = {"South": (0, hd), "North": (0, -hd), "East": (hw, 0), "West": (-hw, 0)}[door]
        yaw = math.radians(e.get("yaw", 0)); c, s = math.cos(yaw), math.sin(yaw)
        px, pz = x + lx * c + lz * s, z - lx * s + lz * c
        g.ellipse([P(px - 1.5, pz - 1.5), P(px + 1.5, pz + 1.5)], fill=(250, 250, 250))
# city wall
t = d["walls"]["thickness"]
for gate in d["gates"]:
    pass
box(b["minX"] - t / 2, b["maxX"] + t / 2, b["minZ"] - t / 2, b["minZ"] + t / 2, (80, 80, 85))
box(b["minX"] - t / 2, b["maxX"] + t / 2, b["maxZ"] - t / 2, b["maxZ"] + t / 2, (80, 80, 85))
box(b["minX"] - t / 2, b["minX"] + t / 2, b["minZ"], b["maxZ"], (80, 80, 85))
box(b["maxX"] - t / 2, b["maxX"] + t / 2, b["minZ"], b["maxZ"], (80, 80, 85))
for gate in d["gates"]:
    x, z = gate["center"]; w = gate["width"] / 2
    if abs(z - b["maxZ"]) < 1 or abs(z - b["minZ"]) < 1:
        box(x - w, x + w, z - t, z + t, (176, 168, 152) if gate.get("kind") != "Sea" else (70, 110, 160))
    else:
        box(x - t, x + t, z - w, z + w, (176, 168, 152) if gate.get("kind") != "Sea" else (70, 110, 160))
for tw in d.get("wallTowers", []):
    g.polygon(corners(tw), fill=(70, 70, 75), outline=(40, 35, 30))
for n in d["npcs"]:
    x, z = n["at"]; g.ellipse([P(x - 2, z - 2), P(x + 2, z + 2)], fill=(230, 60, 60))
x, z = d["spawn"]["center"]; g.ellipse([P(x - 4, z - 4), P(x + 4, z + 4)], outline=(255, 255, 255), width=2)
for r in d["hideout"]["rooms"]:
    g.polygon(corners(r), outline=(255, 60, 200), width=2)
try:
    font = ImageFont.load_default(size=28)
except TypeError:
    font = ImageFont.load_default()
labels = [("CASTLE", 0, -420), ("NOBLE QUARTER", -300, -360), ("CRAFTSMAN QUARTER", 300, -400), ("HARBOUR", 340, 160), ("SLUMS", -300, 230), ("SQUARE", 0, 0), ("FOREST", 0, 700), ("CHURCH", -120, -128), ("RESIDENTIAL", -280, 60), ("RESIDENTIAL", 80, 230), ("MARKET", 190, -60)]
for text, x, z in labels:
    px, pz = P(x, z); g.text((px - 60, pz - 14), text, fill=(20, 20, 20), font=font)
img.save(out)
print("wrote", out, img.size)
