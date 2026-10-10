"""Model Lagos landmarks in Blender from reference photos and export .glb.
Z-up in Blender (exported Y-up). Units = metres. Origin = ground centre."""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix
OUT, TEX = sys.argv[sys.argv.index("--")+1:][:2]

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name, col, rough=0.6, metal=0.0, img=None, emit=None, alpha=1.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if img:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(TEX, img))
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1); b.inputs["Emission Strength"].default_value = 3.0
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha; m.blend_method = "BLEND"
    return m

def obj_from_bm(name, bm, material):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    return o

def box(name, size, loc, material, rot_z=0.0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=Vector((0,0,0)), matrix=Matrix.Rotation(rot_z, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return obj_from_bm(name, bm, material)

def frustum(name, r0, r1, h, z0, segs, material, cap_top=True, uv_repeat=1.0):
    """Cylinder/cone ring with cylindrical UVs (u around, v up)."""
    bm = bmesh.new(); uv = bm.loops.layers.uv.new()
    bot = [bm.verts.new((r0*math.cos(2*math.pi*i/segs), r0*math.sin(2*math.pi*i/segs), z0)) for i in range(segs)]
    top = [bm.verts.new((r1*math.cos(2*math.pi*i/segs), r1*math.sin(2*math.pi*i/segs), z0+h)) for i in range(segs)]
    for i in range(segs):
        j = (i+1) % segs
        f = bm.faces.new((bot[i], bot[j], top[j], top[i]))
        u0 = i/segs*uv_repeat; u1 = (i+1)/segs*uv_repeat
        for l, (u, v) in zip(f.loops, [(u0,0),(u1,0),(u1,1),(u0,1)]): l[uv].uv = (u, v)
    if cap_top: bm.faces.new(top)
    return obj_from_bm(name, bm, material)

def uv_box_project(o, scale):
    """Simple world-scale box projection for facade textures."""
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=scale); bpy.ops.object.mode_set(mode="OBJECT"); o.select_set(False)

def export(name):
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
        export_draco_mesh_compression_enable=False, export_image_format="JPEG")
    print("[lm]", name, sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH"), "faces")

# ---------- National Theatre (Iganmu) ----------
reset()
white = mat("white", (0.88,0.87,0.83), 0.7)
facade = mat("facade", (1,1,1), 0.6, img="theatre_facade.jpg")
dark = mat("dark", (0.12,0.14,0.17), 0.3, 0.3)
frustum("plinth", 62, 62, 4, 0, 64, white)                    # podium/terrace
frustum("lower", 44, 45, 10, 4, 64, facade, uv_repeat=8)      # lower window ring
frustum("upper", 45, 54, 12, 14, 64, facade, uv_repeat=8)     # flared upper ring (the "cap")
frustum("roof", 54, 20, 7, 26, 32, white)                     # sloped crown
frustum("roof2", 20, 6, 4, 33, 24, white)
for k in range(32):                                            # the famous outward-leaning ribs
    a = 2*math.pi*k/32
    bm = bmesh.new()
    p0 = Vector((45.5*math.cos(a), 45.5*math.sin(a), 4)); p1 = Vector((55*math.cos(a), 55*math.sin(a), 27))
    t = Vector((-math.sin(a), math.cos(a), 0)) * 0.8
    vs = [bm.verts.new(v) for v in (p0-t, p0+t, p1+t, p1-t)]
    vs2 = [bm.verts.new(v + Vector((math.cos(a), math.sin(a), 0))*1.2) for v in (p0-t, p0+t, p1+t, p1-t)]
    for f in [vs, vs2[::-1], (vs[0],vs[1],vs2[1],vs2[0]), (vs[1],vs[2],vs2[2],vs2[1]), (vs[2],vs[3],vs2[3],vs2[2]), (vs[3],vs[0],vs2[0],vs2[3])]:
        bm.faces.new(f)
    obj_from_bm("rib%d" % k, bm, white)
export("national_theatre")

# ---------- Civic Towers (VI) ----------
reset()
glass = mat("glass", (1,1,1), 0.12, 0.4, img="civic_glass.jpg")
white = mat("white", (0.9,0.9,0.9), 0.4, 0.2)
box("podium", (60, 44, 8), (0, 0, 4), white)
t = box("tower", (36, 26, 70), (0, 0, 43), glass)
bpy.context.view_layer.objects.active = t; t.select_set(True)
bev = t.modifiers.new("bev", "BEVEL"); bev.width = 3.0; bev.segments = 1; bev.limit_method = "ANGLE"
bpy.ops.object.modifier_apply(modifier="bev"); t.select_set(False)
uv_box_project(t, 36.0)
box("setback", (30, 20, 6), (0, 0, 81), glass); uv_box_project(bpy.data.objects["setback"], 30.0)
box("crown", (16, 12, 6), (0, 0, 87), white)
frustum("spire", 2.6, 0.25, 44, 90, 12, white)
for zz in (98, 106, 114):
    frustum("ring%d" % zz, 3.2, 3.2, 0.6, zz, 16, white)
export("civic_towers")

# ---------- Eko Hotel (main tower, sawtooth facade + portico) ----------
reset()
facade = mat("eko", (1,1,1), 0.5, img="eko_facade.jpg")
white = mat("white", (0.94,0.94,0.9), 0.6)
glassd = mat("glassd", (0.08,0.12,0.16), 0.1, 0.5)
for k in range(9):                                   # staggered (sawtooth) bays
    o = box("bay%d" % k, (9, 16 + (k % 2) * 3, 78), (-36 + k * 9, (k % 2) * 1.5, 39), facade)
    uv_box_project(o, 20.0)
for sx in (-1, 1):
    o = box("wing%d" % sx, (46, 28, 26), (sx * 64, 8, 13), facade); uv_box_project(o, 20.0)
box("roof", (84, 20, 2), (0, 0.5, 79), white)
box("canopy", (26, 16, 1.2), (0, -18, 7), white)
for x in (-11, 11):
    frustum("col%d" % x, 0.7, 0.7, 6.4, 0, 12, white)
    bpy.data.objects["col%d" % x].location = (x, -24, 0)
box("lobby", (30, 6, 6), (0, -10, 3), glassd)
export("eko_hotel")

# ---------- Lekki-Ikoyi Link Bridge pylon + cables ----------
reset()
white = mat("white", (0.95,0.95,0.95), 0.35, 0.1)
steel = mat("steel", (0.8,0.8,0.82), 0.3, 0.8)
frustum("pylon", 2.6, 1.2, 90, 0, 16, white)
box("deck", (14, 340, 1.6), (0, 0, 12), white)
for side in (-1, 1):
    box("rail%d" % side, (0.4, 340, 1.1), (side * 6.8, 0, 13.3), steel)
for k in range(12):
    for s in (-1, 1):
        a = Vector((0, 0, 86 - k * 3.2)); b = Vector((s * 0.0, s * (18 + k * 13), 12.8))
        d = b - a; L = d.length
        o = frustum("cab%d_%d" % (k, s), 0.12, 0.12, L, 0, 6, steel, cap_top=False)
        o.rotation_mode = "QUATERNION"; o.rotation_quaternion = Vector((0,0,1)).rotation_difference(d.normalized())
        o.location = a
export("link_bridge")

# ---------- Lekki Toll Plaza canopy ----------
reset()
white = mat("white", (0.93,0.93,0.92), 0.4, 0.1)
fascia = mat("fascia", (1,1,1), 0.5, img="toll_fascia.jpg")
grey = mat("grey", (0.45,0.47,0.5), 0.5, 0.4)
lamp = mat("lamp", (1,0.95,0.8), 0.3, emit=(1,0.95,0.8))
W = 40.0
roof = box("roof", (W, 16, 1.2), (0, 0, 9.2), white)
f = box("fascia", (W + 0.4, 16.4, 2.6), (0, 0, 7.4), fascia); uv_box_project(f, 40.0)
for zz in (-5, 0, 5):
    box("light%d" % zz, (W - 2, 0.6, 0.12), (0, zz, 6.05), lamp)
for x in (-W/2 + 1, 0, W/2 - 1):   # outer edges + median only, lanes stay clear
    for y in (-6, 6):
        box("col_%d_%d" % (x, y), (1.0, 1.0, 6.2), (x, y, 3.1), grey)
for x in (-W/2 + 1, W/2 - 1):
    box("booth%d" % x, (2.4, 4.5, 2.8), (x, 0, 1.4), white)
# billboard gantry frame above the canopy
for x in (-10, 10):
    box("gpost%d" % x, (0.5, 0.5, 8), (x, 0, 14), grey)
box("gbar", (22, 0.5, 0.5), (0, 0, 18), grey)
export("toll_plaza")
