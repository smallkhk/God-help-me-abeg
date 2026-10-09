class_name MapLoader
extends RefCounted

## Metres from the centreline to the middle of the first lane (clear of the median).
const LANE_OFFSET := 2.4
## Loads a map chunk JSON produced by tools/lagos_map_pipeline (spec §8.5).
## Pure data access — no scene building (that is map_builder.gd's job).

static func load_chunk(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("MapLoader: chunk not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("MapLoader: chunk JSON is not an object: %s" % path)
		return {}
	return data


## Convenience: spawn transform from a loaded chunk, matching the vehicle's
## forward = +Z convention (heading rotates about +Y).
static func spawn_transform(chunk: Dictionary) -> Transform3D:
	var s: Dictionary = chunk.get("spawn", {})
	var pos := Vector3(s.get("x", 0.0), s.get("y", 1.0), s.get("z", 0.0))
	var heading: float = s.get("heading_rad", 0.0)
	# spawn in the first lane, not on the centre median
	pos += Vector3(cos(heading), 0.0, -sin(heading)) * LANE_OFFSET
	var basis := Basis(Vector3.UP, heading)
	return Transform3D(basis, pos)
