#!/usr/bin/env python3
"""Trace a race loop over an imported map model's own road surfaces.
Input dir (made by model_map.py from the model's triangles): top.npy (height of the
top-most surface per cell), kind.npy (3 = road), grid.json {X0, Z0, R (m/cell), U}.
Shortest path through the waypoints (metres, model space at unit scale U),
kept to the middle of the road, never stepping more than MAX_STEP between
neighbouring cells (so ramps are followed, not jumped).
  python3 -I model_route.py <dir> '[[x,z], ...]' [min_y] [max_step]   (numpy, scipy, pillow)
Writes <dir>/path.npy ([x, y, z] per point) and <dir>/route.png for review."""
import json, sys, numpy as np
from scipy import ndimage, sparse
from scipy.sparse import csgraph
from PIL import Image, ImageDraw
D = sys.argv[1]
WP = json.loads(sys.argv[2])
MIN_Y = float(sys.argv[3]) if len(sys.argv) > 3 else -1e8
MAX_STEP = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
g = json.load(open(D + '/grid.json'))
X0, Z0, R0 = g["X0"], g["Z0"], g["R"]
top = np.load(D + '/top.npy'); kind = np.load(D + '/kind.npy')
K = max(1, int(round(1.0 / R0)))          # work on ~1 m cells
C = R0 * K
t = top[::K, ::K]; road = kind[::K, ::K] == 3
H, W = road.shape
edt = ndimage.distance_transform_edt(road) * C
idx = -np.ones((H, W), np.int64)
ids = np.flatnonzero(road.ravel()); idx.ravel()[ids] = np.arange(ids.size)
rows, cols, w = [], [], []
zz0, xx0 = np.nonzero(road)
for dz, dx in [(0, 1), (1, 0), (1, 1), (1, -1)]:
    zz2, xx2 = zz0 + dz, xx0 + dx
    ok = (zz2 >= 0) & (zz2 < H) & (xx2 >= 0) & (xx2 < W)
    zz, xx, zz2, xx2 = zz0[ok], xx0[ok], zz2[ok], xx2[ok]
    ok = road[zz2, xx2] & (np.abs(t[zz, xx] - t[zz2, xx2]) < MAX_STEP * C)
    zz, xx, zz2, xx2 = zz[ok], xx[ok], zz2[ok], xx2[ok]
    L = C * np.hypot(dz, dx)
    cst = L * (1.0 + 30.0 / (1.0 + np.minimum(edt[zz, xx], edt[zz2, xx2])) ** 1.5)
    a_, b_ = idx[zz, xx], idx[zz2, xx2]
    rows += [a_, b_]; cols += [b_, a_]; w += [cst, cst]
G = sparse.csr_matrix((np.concatenate(w), (np.concatenate(rows), np.concatenate(cols))), shape=(ids.size, ids.size))
def node(x, z):
    j, i = int((x - X0) / C), int((z - Z0) / C)
    for r in range(0, 40):
        sl = (slice(max(0, i - r), i + r + 1), slice(max(0, j - r), j + r + 1))
        sub = road[sl] & (t[sl] > MIN_Y)
        if sub.any():
            zz, xx = np.nonzero(sub)
            q = np.argmax(edt[sl][zz, xx])
            return idx[sl[0].start + zz[q], sl[1].start + xx[q]]
    raise SystemExit('no road near %s' % ((x, z),))
nodes = [node(x, z) for x, z in WP] + [node(*WP[0])]
path = []
for n_i, (a, b) in enumerate(zip(nodes[:-1], nodes[1:])):
    dist, pred = csgraph.dijkstra(G, indices=a, return_predecessors=True)
    if np.isinf(dist[b]):
        raise SystemExit('no path from waypoint %d to %d' % (n_i, n_i + 1))
    seg = [b]
    while seg[-1] != a:
        seg.append(pred[seg[-1]])
    path += seg[::-1][:-1]
zz, xx = np.unravel_index(ids[path], (H, W))
P = np.c_[X0 + (xx + 0.5) * C, t[zz, xx], Z0 + (zz + 0.5) * C]
np.save(D + '/path.npy', P)
print('path pts', len(P), 'length %.0f m' % np.sum(np.linalg.norm(np.diff(P[:, [0, 2]], axis=0), axis=1)),
      'min half-width %.1f m' % edt[zz, xx].min(), 'y %.1f..%.1f' % (P[:, 1].min(), P[:, 1].max()))
im = Image.open(D + '/top.png').convert('RGB'); d = ImageDraw.Draw(im)
d.line([((p[0] - X0) / R0, (p[2] - Z0) / R0) for p in P], fill=(255, 255, 255), width=4)
for i, (x, z) in enumerate(WP):
    cx, cz = (x - X0) / R0, (z - Z0) / R0
    d.ellipse([cx - 8, cz - 8, cx + 8, cz + 8], outline=(255, 0, 255), width=3); d.text((cx + 10, cz), str(i), fill=(255, 255, 255))
im.save(D + '/route.png')
