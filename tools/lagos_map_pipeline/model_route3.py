"""Race loop over a two-level road raster (road_raster.py): roads may pass under bridges.
model_route3.py <dir> '[[x,z], [x,z,"lo"], [x,z,"j"], ...]' [max_step]
 "lo": snap to the lower road where two cross;  "j": straight line from the previous waypoint.
Env BRIDGE=1: bridge breaks in the road mesh in a straight line instead of failing."""
import json, sys, os, numpy as np
from scipy import ndimage, sparse
from scipy.sparse import csgraph
from PIL import Image, ImageDraw
D = sys.argv[1]; WP = json.loads(sys.argv[2])
STEP = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
g = json.load(open(D + '/grid.json')); X0, Z0, C = g["X0"], g["Z0"], g["R"]
top = np.load(D + '/top.npy'); kind = np.load(D + '/kind.npy')
bot = np.load(D + '/bot.npy') if os.path.exists(D + '/bot.npy') else top.copy()
road = ndimage.binary_closing(kind == 3, iterations=2)
# fill closed seams with neighbouring heights
if (road & (top < -1e8)).any():
    _, (iz, ix) = ndimage.distance_transform_edt(top < -1e8, return_indices=True)
    fill = road & (top < -1e8); top[fill] = top[iz[fill], ix[fill]]; bot[fill] = bot[iz[fill], ix[fill]]
H, W = road.shape
two = road & (top - bot > 2.5)
edt = ndimage.distance_transform_edt(road) * C
n0 = -np.ones((H, W), np.int64); c0 = np.flatnonzero(road.ravel()); n0.ravel()[c0] = np.arange(c0.size)
n1 = -np.ones((H, W), np.int64); c1 = np.flatnonzero(two.ravel()); n1.ravel()[c1] = c0.size + np.arange(c1.size)
NN = c0.size + c1.size
cellz = np.r_[c0, c1] // W; cellx = np.r_[c0, c1] % W
cellh = np.r_[top.ravel()[c0], bot.ravel()[c1]]
rows, cols, w = [], [], []
zz0, xx0 = np.nonzero(road)
for dz, dx in [(0, 1), (1, 0), (1, 1), (1, -1)]:
    zz2, xx2 = zz0 + dz, xx0 + dx
    ok = (zz2 >= 0) & (zz2 < H) & (xx2 >= 0) & (xx2 < W)
    zz, xx, zz2, xx2 = zz0[ok], xx0[ok], zz2[ok], xx2[ok]
    ok = road[zz2, xx2]; zz, xx, zz2, xx2 = zz[ok], xx[ok], zz2[ok], xx2[ok]
    L = C * np.hypot(dz, dx)
    cst = L * (1.0 + 30.0 / (1.0 + np.minimum(edt[zz, xx], edt[zz2, xx2])) ** 1.5)
    for la, ha, na in ((0, top, n0), (1, bot, n1)):
        for lb, hb, nb in ((0, top, n0), (1, bot, n1)):
            a_ = na[zz, xx]; b_ = nb[zz2, xx2]
            if la == 1: a_ = np.where(a_ >= 0, a_, -1)
            ok = (a_ >= 0) & (b_ >= 0) & (np.abs(ha[zz, xx] - hb[zz2, xx2]) < STEP * C)
            # a single-level cell is reachable from either level of its neighbour
            rows += [a_[ok], b_[ok]]; cols += [b_[ok], a_[ok]]; w += [cst[ok], cst[ok]]
            if lb == 1:
                pass
    # single-level neighbour of a two-level cell: lower level may also step onto it
    for (za, xa, zb, xb) in ((zz, xx, zz2, xx2), (zz2, xx2, zz, xx)):
        a_ = n1[za, xa]; b_ = n0[zb, xb]
        ok = (a_ >= 0) & (~two[zb, xb]) & (np.abs(bot[za, xa] - top[zb, xb]) < STEP * C)
        cc = cst[ok] if za is zz else cst[ok]
        rows += [a_[ok], b_[ok]]; cols += [b_[ok], a_[ok]]; w += [cc, cc]
G = sparse.csr_matrix((np.concatenate(w), (np.concatenate(rows), np.concatenate(cols))), shape=(NN, NN))
def node(x, z, lo=False):
    j, i = int((x - X0) / C), int((z - Z0) / C)
    for r in range(0, 40):
        sl = (slice(max(0, i - r), i + r + 1), slice(max(0, j - r), j + r + 1))
        sub = road[sl]
        if sub.any():
            zz, xx = np.nonzero(sub)
            dd = np.hypot(sl[0].start + zz - i, sl[1].start + xx - j) - 0.3 * edt[sl][zz, xx] / C
            q = np.argmin(dd); zi, xi = sl[0].start + zz[q], sl[1].start + xx[q]
            return n1[zi, xi] if lo and n1[zi, xi] >= 0 else n0[zi, xi]
    raise SystemExit('no road near %s' % ((x, z),))
def pt(n):
    return np.array([X0 + (cellx[n] + 0.5) * C, cellh[n], Z0 + (cellz[n] + 0.5) * C])
JUMP = [len(wp) > 2 and wp[2] == "j" for wp in WP] + [False]
nodes = [node(wp[0], wp[1], len(wp) > 2 and wp[2] == "lo") for wp in WP]; nodes.append(nodes[0])
if os.environ.get("COMP"):
    nc, lab = csgraph.connected_components(G, directed=False); sz = np.bincount(lab)
    print("waypoint components:", [(i, int(lab[n]), int(sz[lab[n]])) for i, n in enumerate(nodes[:-1])])
pts = []
def walk(pred, a, b):
    seg = [b]
    while seg[-1] != a:
        seg.append(pred[seg[-1]])
    return seg[::-1]
for k, (a, b) in enumerate(zip(nodes[:-1], nodes[1:])):
    if JUMP[k + 1]:
        pa, pb = pt(a), pt(b); m = max(2, int(np.linalg.norm(pb - pa) / C))
        pts += [pa + (pb - pa) * (i / m) for i in range(m)]; continue
    dist, pred = csgraph.dijkstra(G, indices=a, return_predecessors=True)
    if np.isfinite(dist[b]):
        pts += [pt(n) for n in walk(pred, a, b)[:-1]]; continue
    if not os.environ.get("BRIDGE"):
        raise SystemExit('no path from waypoint %d to %d' % (k, k + 1))
    print('bridging gap between waypoints %d and %d' % (k, k + 1))
    P_ = np.c_[X0 + (cellx + 0.5) * C, Z0 + (cellz + 0.5) * C]
    r1 = np.flatnonzero(np.isfinite(dist)); pb = pt(b)
    m1 = r1[np.argmin(np.linalg.norm(P_[r1] - pb[[0, 2]], axis=1))]
    dist2, pred2 = csgraph.dijkstra(G, indices=b, return_predecessors=True)
    r2 = np.flatnonzero(np.isfinite(dist2)); pm1 = pt(m1)
    m2 = r2[np.argmin(np.linalg.norm(P_[r2] - pm1[[0, 2]], axis=1))]; pm2 = pt(m2)
    pts += [pt(n) for n in walk(pred, a, m1)]
    m = max(2, int(np.linalg.norm(pm2 - pm1) / C)); pts += [pm1 + (pm2 - pm1) * (i / m) for i in range(1, m)]
    pts += [pt(n) for n in walk(pred2, b, m2)[::-1][:-1]]
P = np.array(pts)
np.save(D + '/path.npy', P)
print('path pts', len(P), 'length %.0f m' % np.sum(np.linalg.norm(np.diff(P[:, [0, 2]], axis=0), axis=1)), 'y %.1f..%.1f' % (P[:, 1].min(), P[:, 1].max()))
im = Image.open(D + '/top.png').convert('RGB'); d = ImageDraw.Draw(im)
d.line([((p[0] - X0) / C, (p[2] - Z0) / C) for p in P], fill=(255, 255, 255), width=3)
for i, wp in enumerate(WP):
    cx, cz = (wp[0] - X0) / C, (wp[1] - Z0) / C
    d.ellipse([cx - 8, cz - 8, cx + 8, cz + 8], outline=(255, 0, 255), width=3); d.text((cx + 10, cz), str(i), fill=(255, 255, 255))
im.save(D + '/route.png')
