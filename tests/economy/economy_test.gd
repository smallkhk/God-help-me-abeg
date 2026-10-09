extends SceneTree
## Economy + nitro check (headless): buy car, upgrades, money, nitro boost.
## Run: godot --headless --path . -s res://tests/economy/economy_test.gd
func _init() -> void:
	await process_frame
	var g = root.get_node("Game")
	var fails := []
	g.money = 1000000; g.owned = ["hatch_01", "sedan_01"]; g.upgrades = {}
	if g.buy_car(&"super_01", 25000000): fails.append("bought supercar without money")
	if not g.buy_car(&"hatch_01", 1) == false: fails.append("rebuy owned car")
	var c0: int = g.upgrade_cost(&"sedan_01", "engine")
	if not g.buy_upgrade(&"sedan_01", "engine"): fails.append("engine upgrade failed")
	if g.upgrade_level(&"sedan_01", "engine") != 1: fails.append("level not 1")
	if g.money != 1000000 - c0: fails.append("money not deducted")
	if g.buy_upgrade(&"super_01", "engine"): fails.append("upgraded unowned car")
	print("[economy] cost lvl1=", c0, " money=", g.money, " naira=", g.naira(1234567))
	# nitro: same car, 3 s full throttle with and without nitro
	var speeds := []
	for use_nitro in [false, true]:
		var scene: Node3D = load("res://scenes/world/test_track.tscn").instantiate()
		root.add_child(scene)
		await physics_frame
		var car: VehicleController = scene.find_children("*", "VehicleController", true, false)[0]
		var pd = car.get_node_or_null("PlayerDriver")
		if pd: pd.set_physics_process(false)
		for i in 60: await physics_frame
		for i in 180:
			car.set_driver_input(1.0, 0.0, 0.0, false)
			car.nitro_input = use_nitro
			await physics_frame
		speeds.append(car.linear_velocity.length())
		if use_nitro and car.nitro_amount > 0.95: fails.append("nitro tank did not drain")
		scene.queue_free()
		await process_frame
	print("[economy] speed after 3s: normal %.1f m/s, nitro %.1f m/s" % speeds)
	if speeds[1] <= speeds[0] + 1.0: fails.append("nitro gave no boost")
	g.money = 2000000; g.owned = ["hatch_01", "sedan_01"]; g.upgrades = {}; g.save()
	for f in fails: printerr("[economy] FAIL: ", f)
	print("[economy] PASS" if fails.is_empty() else "[economy] FAILED")
	quit(0 if fails.is_empty() else 1)
