class_name CollisionBaker
extends RefCounted
## Builds drivable trimesh collision from an imported visual mesh tree (spec §8.3
## "collision follows the visible road"). This is how a Blender/OSM .glb track
## becomes solid: Godot imports a .glb as a scene of MeshInstance3D nodes with no
## collision; this walks them and bakes one ConcavePolygonShape3D.
##
## Uses backface_collision = true so downward wheel raycasts hit the surface
## regardless of triangle winding (the fix we needed for the procedural bridge).

## Collect every triangle under `root` (in root-local space) and return a
## StaticBody3D holding a single concave collision shape. Does not add it to the
## tree — the caller places it.
static func bake(root: Node3D, body_name: String = "TrackCollision") -> StaticBody3D:
	var soup := PackedVector3Array()
	_gather(root, root.global_transform.affine_inverse(), soup)

	var body := StaticBody3D.new()
	body.name = body_name
	if soup.size() < 3:
		push_warning("CollisionBaker: no mesh triangles found under %s" % root.name)
		return body

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(soup)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


static func _gather(node: Node, to_local: Transform3D, soup: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		var faces := mesh.get_faces()  # all surfaces' triangles, mesh-local
		var xform := to_local * node.global_transform
		for v in faces:
			soup.push_back(xform * v)
	for child in node.get_children():
		if child is Node:
			_gather(child, to_local, soup)
