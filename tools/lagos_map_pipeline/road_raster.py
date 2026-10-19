"""Road-only raster with two levels (for bridges / overpasses).
road_raster.py tris.json outdir unit_scale res  -> top.npy (highest road), bot.npy (lowest road),
kind.npy (3 = road), grid.json, top.png"""
import json, sys, numpy as np
from PIL import Image, ImageDraw
d = json.load(open(sys.argv[1])); OUT = sys.argv[2]; U = float(sys.argv[3]); R = float(sys.argv[4])
tri = np.concatenate([np.array(v, np.float32).reshape(-1, 3, 3) for v in d.values() if v and len(v) % 9 == 0]) * U
# drop walls: road triangles face up
n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); ln = np.linalg.norm(n, axis=1) + 1e-9
tri = tri[np.abs(n[:, 1]) / ln > 0.5]
allp = tri.reshape(-1, 3)
X0, Z0 = np.floor(allp[:, 0].min()) - 5, np.floor(allp[:, 2].min()) - 5
W, H = int((allp[:, 0].max() + 5 - X0) / R) + 1, int((allp[:, 2].max() + 5 - Z0) / R) + 1
top = np.full((H, W), -1e9, np.float32); bot = np.full((H, W), 1e9, np.float32)
for tr in tri:
    xs = (tr[:, 0] - X0) / R; zs = (tr[:, 2] - Z0) / R
    x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
    z0, z1 = int(max(0, np.floor(zs.min()))), int(min(H - 1, np.ceil(zs.max())))
    gx, gz = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(z0, z1 + 1) + 0.5)
    (ax, az), (bx, bz), (cx, cz) = zip(xs, zs)
    den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    if abs(den) < 1e-9: continue
    l1 = ((bz - cz) * (gx - cx) + (cx - bx) * (gz - cz)) / den
    l2 = ((cz - az) * (gx - cx) + (ax - cx) * (gz - cz)) / den
    l3 = 1 - l1 - l2
    ins = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    hh = l1 * tr[0, 1] + l2 * tr[1, 1] + l3 * tr[2, 1]
    st = top[z0:z1 + 1, x0:x1 + 1]; sb = bot[z0:z1 + 1, x0:x1 + 1]
    u = ins & (hh > st); st[u] = hh[u]
    u = ins & (hh < sb); sb[u] = hh[u]
kind = np.where(top > -1e8, 3, 0).astype(np.uint8)
bot[kind != 3] = -1e9
np.save(OUT + '/top.npy', top); np.save(OUT + '/bot.npy', bot); np.save(OUT + '/kind.npy', kind)
json.dump({"X0": float(X0), "Z0": float(Z0), "R": R, "U": U}, open(OUT + '/grid.json', 'w'))
img = np.zeros((H, W, 3), np.uint8) + 25
img[kind == 3] = (230, 120, 40); img[(kind == 3) & (top - bot > 2.5)] = (60, 160, 255)
im = Image.fromarray(img); dr = ImageDraw.Draw(im)
for x in range(int(X0) // 50 * 50, int(X0 + W * R), 50):
    dr.line([((x - X0) / R, 0), ((x - X0) / R, H)], fill=(60, 60, 60)); dr.text(((x - X0) / R + 2, 2), str(x), fill=(255, 255, 0))
for z in range(int(Z0) // 50 * 50, int(Z0 + H * R), 50):
    dr.line([(0, (z - Z0) / R), (W, (z - Z0) / R)], fill=(60, 60, 60)); dr.text((2, (z - Z0) / R + 2), str(z), fill=(255, 255, 0))
im.save(OUT + '/top.png'); print('grid', X0, Z0, W, H, 'two-level cells', int(((kind == 3) & (top - bot > 2.5)).sum()))
