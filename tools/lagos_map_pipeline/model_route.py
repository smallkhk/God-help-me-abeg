#!/usr/bin/env python3
"""Trace a race loop over an imported map model's own road surfaces.
Input (in <work>/i95/): top.npy / kind.npy, a 1 m top-down raster of the model
(height of the top-most surface, and 3 = road) made from the model's triangles.
Shortest centred path through the waypoints (model units, street level only),
with no step > 1 m between neighbouring cells (so ramps are followed, not jumped).
  python3 -I model_route.py <work> '[[x,z], ...]'   (needs numpy, scipy, pillow)
Writes <work>/i95/path.npy (then model_chunk.py) and route.png for review."""
import json, sys, numpy as np
from scipy import ndimage, sparse
from scipy.sparse import csgraph
from PIL import Image, ImageDraw
S = sys.argv[1]
WP = json.loads(sys.argv[2])
top = np.load(S + '/i95/top.npy'); kind = np.load(S + '/i95/kind.npy')
X0, Z0, C = -1050, -5800, 2
t = top[::C, ::C]; k = kind[::C, ::C]
road = k == 3
H, W = road.shape
edt = ndimage.distance_transform_edt(road) * C
idx = -np.ones((H, W), np.int64)
ids = np.flatnonzero(road.ravel()); idx.ravel()[ids] = np.arange(ids.size)
rows, cols, w = [], [], []
for dz, dx in [(0, 1), (1, 0), (1, 1), (1, -1)]:
    a = road[max(0, -dz):H - max(0, dz), max(0, -dx):W - max(0, dx)]
    zz, xx = np.nonzero(road)
    zz2, xx2 = zz + dz, xx + dx
    ok = (zz2 >= 0) & (zz2 < H) & (xx2 >= 0) & (xx2 < W)
    zz, xx, zz2, xx2 = zz[ok], xx[ok], zz2[ok], xx2[ok]
    ok = road[zz2, xx2] & (np.abs(t[zz, xx] - t[zz2, xx2]) < 1.0)
    zz, xx, zz2, xx2 = zz[ok], xx[ok], zz2[ok], xx2[ok]
    L = C * np.hypot(dz, dx)
    cst = L * (1.0 + 30.0 / (1.0 + np.minimum(edt[zz, xx], edt[zz2, xx2])) ** 1.5)
    a_, b_ = idx[zz, xx], idx[zz2, xx2]
    rows += [a_, b_]; cols += [b_, a_]; w += [cst, cst]
G = sparse.csr_matrix((np.concatenate(w), (np.concatenate(rows), np.concatenate(cols))), shape=(ids.size, ids.size))
def node(x, z):
    j, i = int((x - X0) / C), int((z - Z0) / C)
    best = None
    for r in range(0, 20):
        sub = road[max(0, i - r):i + r + 1, max(0, j - r):j + r + 1] & (t[max(0, i - r):i + r + 1, max(0, j - r):j + r + 1] > -20)
        if sub.any():
            zz, xx = np.nonzero(sub)
            q = np.argmax(edt[max(0, i - r):i + r + 1, max(0, j - r):j + r + 1][zz, xx])
            return idx[max(0, i - r) + zz[q], max(0, j - r) + xx[q]]
    raise SystemExit('no road near %s' % ((x, z),))
path = []
nodes = [node(x, z) for x, z in WP] + [node(*WP[0])]
for a, b in zip(nodes[:-1], nodes[1:]):
    dist, pred = csgraph.dijkstra(G, indices=a, return_predecessors=True)
    if np.isinf(dist[b]):
        n_, lab = csgraph.connected_components(G, directed=False)
        print('pair', nodes.index(a), '->', nodes.index(b), 'components', n_, 'label a', lab[a], 'label b', lab[b])
        comp = np.zeros(H * W, bool); comp[ids[lab == lab[a]]] = True; comp = comp.reshape(H, W)
        img = np.zeros((H, W, 3), np.uint8); img[road] = (90, 90, 90); img[comp] = (255, 200, 0)
        Image.fromarray(img).save(S + '/i95/comp.png')
        raise SystemExit('no path')
    seg = [b]
    while seg[-1] != a:
        seg.append(pred[seg[-1]])
    path += seg[::-1][:-1]
zz, xx = np.unravel_index(ids[path], (H, W))
P = np.c_[X0 + (xx + 0.5) * C, Z0 + (zz + 0.5) * C]
Y = t[zz, xx]
np.save(S + '/i95/path.npy', np.c_[P[:, 0], Y, P[:, 1]])
print('path pts', len(P), 'length', round(float(np.sum(np.linalg.norm(np.diff(P, axis=0), axis=1))), 1), 'min clearance', round(float(edt[zz, xx].min()), 1), 'y', Y.min(), Y.max())
im = Image.open(S + '/i95/top.png').convert('RGB')
d = ImageDraw.Draw(im)
pts = [((p[0] - X0), (p[1] - Z0)) for p in P]
d.line(pts, fill=(255, 255, 255), width=7)
for i, (x, z) in enumerate(WP):
    d.ellipse([x - X0 - 14, z - Z0 - 14, x - X0 + 14, z - Z0 + 14], outline=(255, 0, 255), width=5); d.text((x - X0 + 16, z - Z0), str(i), fill=(255, 255, 255))
im.resize((im.size[0] // 2, im.size[1] // 2)).save(S + '/i95/route.png')
