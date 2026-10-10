import bpy, sys, bmesh, mathutils, math
body_f, wheel_f, out = sys.argv[sys.argv.index("--")+1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=body_f)
body = [o for o in bpy.data.objects if o.type == "MESH"][0]
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
body.name = "Body"
R = 0.068; ZC = -0.167 + R; XC = 0.212
centers = {"wheel_fl": (XC, -0.296), "wheel_fr": (-XC, -0.296), "wheel_rl": (XC, 0.250), "wheel_rr": (-XC, 0.250)}
# cut the baked-in wheels out of the body
bm = bmesh.new(); bm.from_mesh(body.data)
kill = []
for f in bm.faces:
    c = f.calc_center_median()
    for (x, y) in centers.values():
        if math.hypot(c.y - y, c.z - ZC) < R * 1.05 and c.x * x > 0 and abs(c.x) > 0.15:
            kill.append(f); break
bmesh.ops.delete(bm, geom=kill, context="FACES")
bm.to_mesh(body.data); bm.free()
print("[camry] removed wheel faces:", len(kill), flush=True)
# decimate body
m = body.modifiers.new("dec", "DECIMATE"); m.ratio = 0.1
bpy.ops.object.modifier_apply(modifier="dec")
def pbr(name, col, metal, rough, coat=0.0):
    mt = bpy.data.materials.new(name); mt.use_nodes = True
    b = mt.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1); b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    try: b.inputs["Coat Weight"].default_value = coat
    except Exception: pass
    return mt
paint = pbr("CamryPaint", (0.62, 0.64, 0.66), 0.85, 0.22, 1.0)   # silver metallic
body.data.materials.clear(); body.data.materials.append(paint)
# wheel template
bpy.ops.import_scene.fbx(filepath=wheel_f)
w = [o for o in bpy.context.selected_objects if o.type == "MESH"][0]
bpy.ops.object.select_all(action="DESELECT"); w.select_set(True); bpy.context.view_layer.objects.active = w
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mn = mathutils.Vector((1e9,)*3); mx = -mn
for v in w.data.vertices: mn = mathutils.Vector(map(min, mn, v.co)); mx = mathutils.Vector(map(max, mx, v.co))
ctr = (mn + mx) / 2; diam = max(mx.y - mn.y, mx.z - mn.z)
s = 2 * R / diam
for v in w.data.vertices: v.co = (v.co - ctr) * s
wd = w.modifiers.new("dec", "DECIMATE"); wd.ratio = 0.25
bpy.ops.object.modifier_apply(modifier="dec")
tyre = pbr("Tyre", (0.03, 0.03, 0.03), 0.0, 0.85); rim = pbr("Rim", (0.8, 0.8, 0.82), 1.0, 0.18)
w.data.materials.clear(); w.data.materials.append(tyre); w.data.materials.append(rim)
for p in w.data.polygons:
    c = p.center
    p.material_index = 0 if math.hypot(c.y, c.z) > R * 0.78 else 1
for name, (x, y) in centers.items():
    o = w.copy(); o.data = w.data; o.name = name
    bpy.context.collection.objects.link(o)
    o.location = (x, y, ZC)
    if x < 0: o.rotation_euler = (0, 0, math.pi)   # face the rim outwards on the other side
bpy.data.objects.remove(w)
# real size: 4.9 m long, sit on z=0
root = bpy.data.objects.new("Camry", None); bpy.context.collection.objects.link(root)
for o in list(bpy.data.objects):
    if o.type == "MESH": o.parent = root
k = 4.9 / 0.988
root.scale = (k, k, k); root.location = (0, 0, 0.167 * k)
tot = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
print("[camry] polys", tot, flush=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_draco_mesh_compression_enable=False)
print("[camry] exported", out, flush=True)
