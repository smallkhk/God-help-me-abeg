class_name CarDatabase
extends RefCounted
## Central registry of the player-car roster (spec §6.2). Each id maps to a
## VehicleData resource under res://data/vehicles/. The garage and the player
## spawn both read from here, so adding a car = drop a .tres + add its id below.
## When a real .glb model arrives it is wired to the matching id without touching
## the physics data.

## Display order in the garage (cheapest/starter first).
const ORDER: Array[StringName] = [
	&"camry_01",
	&"hilux_01",
	&"cruiser_01",
	&"hatch_01",
	&"sedan_01",
	&"family_01",
	&"sport_01",
	&"suv_01",
	&"luxury_01",
	&"concept_01",
	&"super_01",
]


static func data_path(car_id: StringName) -> String:
	return "res://data/vehicles/%s.tres" % car_id


static func get_data(car_id: StringName) -> VehicleData:
	var path := data_path(car_id)
	if not ResourceLoader.exists(path):
		push_warning("CarDatabase: no data for car '%s'" % car_id)
		return null
	return load(path) as VehicleData


static func exists(car_id: StringName) -> bool:
	return ResourceLoader.exists(data_path(car_id))


static func all() -> Array[VehicleData]:
	var out: Array[VehicleData] = []
	for id in ORDER:
		var d := get_data(id)
		if d:
			out.append(d)
	return out


## 0..1 ratings derived from the actual physics data, so every displayed bar
## corresponds to a real gameplay effect (spec §6.3).
static func ratings(d: VehicleData) -> Dictionary:
	return {
		"top_speed": clampf((d.max_drive_force / maxf(d.drag_coefficient, 0.01)) / 22000.0, 0.0, 1.0),
		"accel": clampf((d.max_drive_force / d.mass) / 7.5, 0.0, 1.0),
		"grip": clampf((d.lateral_grip_front + d.lateral_grip_rear) / 3.2, 0.0, 1.0),
		"braking": clampf((d.brake_force / d.mass) / 9.0, 0.0, 1.0),
		"weight": clampf(d.mass / 2200.0, 0.0, 1.0),
	}


static func drivetrain_label(d: VehicleData) -> String:
	match d.drivetrain:
		VehicleData.Drivetrain.FWD: return "FWD"
		VehicleData.Drivetrain.RWD: return "RWD"
		VehicleData.Drivetrain.AWD: return "AWD"
	return "?"
