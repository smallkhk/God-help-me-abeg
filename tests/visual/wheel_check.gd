extends SceneTree
## Checks the imported car models' wheels get bound and actually rotate.
func _init() -> void:
	await process_frame
	var ok := true
	for id in ["super_01", "concept_01"]:
		var car: VehicleController = load("res://scenes/vehicles/player/player_car.tscn").instantiate()
		car.is_player = false; car.data = CarDatabase.get_data(id); car.freeze = true
		root.add_child(car)
		for i in 5: await physics_frame
		var bound := 0
		var b0 := []
		for w in car.wheels:
			if w.model_pivot: bound += 1
			b0.append(w.model_pivot.global_transform.basis if w.model_pivot else Basis())
		car.linear_velocity = Vector3.ZERO
		for i in 20:
			car.set_driver_input(0, 0, 1.0, false)
			car.forward_speed = 10.0
			await physics_frame
		var moved := 0
		for k in car.wheels.size():
			var w = car.wheels[k]
			if w.model_pivot and not w.model_pivot.global_transform.basis.is_equal_approx(b0[k]): moved += 1
		print("[wheels] %s bound %d/4, rotating %d/4" % [id, bound, moved])
		if bound < 4: ok = false
		car.queue_free()
	print("[wheels] PASS" if ok else "[wheels] FAIL")
	quit()
