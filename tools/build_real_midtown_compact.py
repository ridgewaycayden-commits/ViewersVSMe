import json, math, os, sys

SRC = r"C:\Users\mika9\arnis-roblox\out\midtown-small.json"
OUT = r"C:\Users\mika9\ViewersVSMe\src\ServerStorage\RealMidtownCompact.lua"

if not os.path.exists(SRC):
    raise SystemExit(f"Missing source manifest: {SRC}")

print("[MIDTOWN COMPACT] Reading real Arnis Manhattan manifest...")
with open(SRC, "r", encoding="utf-8") as f:
    manifest = json.load(f)

chunks = manifest.get("chunks") or []
buildings = []
roads = []


def n(v, default=0.0):
    try:
        return float(v)
    except Exception:
        return default


def rgb(c, default=(115, 118, 124)):
    if not isinstance(c, dict):
        return default
    return (
        max(0, min(255, int(n(c.get("r"), default[0])))),
        max(0, min(255, int(n(c.get("g"), default[1])))),
        max(0, min(255, int(n(c.get("b"), default[2])))),
    )


def oriented_box(points):
    pts = [(n(p.get("x")), n(p.get("z"))) for p in points if isinstance(p, dict)]
    if len(pts) < 3:
        return None
    cx = sum(x for x, _ in pts) / len(pts)
    cz = sum(z for _, z in pts) / len(pts)
    xx = sum((x-cx)*(x-cx) for x, _ in pts)
    zz = sum((z-cz)*(z-cz) for _, z in pts)
    xz = sum((x-cx)*(z-cz) for x, z in pts)
    angle = 0.5 * math.atan2(2*xz, xx-zz)
    ca, sa = math.cos(angle), math.sin(angle)
    us, vs = [], []
    for x, z in pts:
        dx, dz = x-cx, z-cz
        us.append(dx*ca + dz*sa)
        vs.append(-dx*sa + dz*ca)
    min_u, max_u = min(us), max(us)
    min_v, max_v = min(vs), max(vs)
    u0 = (min_u+max_u)/2
    v0 = (min_v+max_v)/2
    ox = u0*ca - v0*sa
    oz = u0*sa + v0*ca
    return cx+ox, cz+oz, max_u-min_u, max_v-min_v, math.degrees(angle)

minx = minz = float("inf")
maxx = maxz = float("-inf")

for chunk in chunks:
    origin = chunk.get("originStuds") or {}
    ox, oz = n(origin.get("x")), n(origin.get("z"))

    for b in chunk.get("buildings") or []:
        fp = b.get("footprint") or []
        box = oriented_box(fp)
        if not box:
            continue
        x, z, w, d, angle = box
        x += ox; z += oz
        if w < 2 or d < 2:
            continue
        height = max(8.0, n(b.get("height"), n(b.get("heightStuds"), 24.0)))
        base_y = n(b.get("baseY"), 0.0)
        color = rgb(b.get("wallColor"))
        buildings.append((x, z, w, d, height, base_y, angle, color))
        minx=min(minx,x-w/2); maxx=max(maxx,x+w/2)
        minz=min(minz,z-d/2); maxz=max(maxz,z+d/2)

    for r in chunk.get("roads") or []:
        pts = r.get("points") or []
        width = max(3.0, n(r.get("widthStuds"), 10.0))
        kind = str(r.get("kind") or "road")
        for a, b in zip(pts, pts[1:]):
            if not isinstance(a, dict) or not isinstance(b, dict):
                continue
            x1, z1 = n(a.get("x"))+ox, n(a.get("z"))+oz
            x2, z2 = n(b.get("x"))+ox, n(b.get("z"))+oz
            y = (n(a.get("y"))+n(b.get("y")))/2
            if math.hypot(x2-x1, z2-z1) < 1:
                continue
            roads.append((x1,z1,x2,z2,y,width,kind))
            minx=min(minx,x1,x2); maxx=max(maxx,x1,x2)
            minz=min(minz,z1,z2); maxz=max(maxz,z1,z2)

if not buildings and not roads:
    raise SystemExit("No buildings or roads found in manifest.")

cx = (minx + maxx) / 2 if math.isfinite(minx) else 0
cz = (minz + maxz) / 2 if math.isfinite(minz) else 0

os.makedirs(os.path.dirname(OUT), exist_ok=True)
print(f"[MIDTOWN COMPACT] {len(buildings)} buildings, {len(roads)} road segments")
print("[MIDTOWN COMPACT] Writing lightweight Roblox module...")

with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("return {\n")
    f.write(f"  source = 'Arnis/OpenStreetMap Midtown Manhattan',\n  buildingCount = {len(buildings)},\n  roadCount = {len(roads)},\n")
    f.write("  buildings = {\n")
    for x,z,w,d,h,by,ang,c in buildings:
        f.write("    {%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d},\n" % (x-cx,z-cz,w,d,h,by,ang,c[0],c[1],c[2]))
    f.write("  },\n  roads = {\n")
    for x1,z1,x2,z2,y,w,kind in roads:
        kind = kind.replace("'", "")[:24]
        f.write("    {%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,'%s'},\n" % (x1-cx,z1-cz,x2-cx,z2-cz,y,w,kind))
    f.write("  }\n}\n")

size = os.path.getsize(OUT)
print(f"[MIDTOWN COMPACT] DONE - {OUT}")
print(f"[MIDTOWN COMPACT] Output size: {size/1024/1024:.2f} MB")
print("[MIDTOWN COMPACT] Rojo can now sync this lightweight real-NYC dataset safely.")
