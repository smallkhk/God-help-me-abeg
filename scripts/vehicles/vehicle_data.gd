class_name VehicleData
extends Resource
## Data-driven vehicle definition (spec §5.4, §6.3).
##
## All tunable physics parameters live here, NOT buried as constants in the
## controller. One VehicleData resource == one car's personality. Values below
## are a STARTING CALIBRATION for a fictional compact/midsize sedan and MUST be
## refined by running the acceptance tests (spec §5.7). They are not real-world
## manufacturer figures.
##
## Units are SI: metres, seconds, kilograms, newtons, radians. The HUD converts
## m/s to km/h (× 3.6).

enum Drivetrain { FWD, RWD, AWD }

@export_group("Identity")
@export var display_name: String = "Danfo-Spec Sedan"
@export var vehicle_id: StringName = &"sedan_01"

@export_group("Mass & Geometry")
## Total mass in kg. Heavier cars resist speed/direction changes more.
@export var mass: float = 1250.0
## Distance between front and rear axles (m). Used for wheel placement reference.
@export var wheelbase: float = 2.6
## Distance between left and right wheels (m).
@export var track_width: float = 1.55
## Centre-of-mass vertical offset from the body origin (m). Negative = lower =
## more stable, less roll. Tall SUVs sit higher.
@export var center_of_mass_y: float = -0.4
## Centre-of-mass forward offset from body origin (m). +Z is forward.
@export var center_of_mass_z: float = 0.0

@export_group("Engine & Drivetrain")
@export var drivetrain: Drivetrain = Drivetrain.FWD
## Peak drive force at the wheels (N) at full throttle in the power band. This is
## a simplified stand-in for an engine torque curve × gearing; the transmission
## scales it per gear. Tune so 0-100 km/h and top speed feel believable.
@export var max_drive_force: float = 9000.0
## Engine braking force applied when off-throttle and in gear (N).
@export var engine_brake_force: float = 1200.0
## Idle / min RPM shown on HUD and used by transmission logic.
@export var idle_rpm: float = 900.0
@export var max_rpm: float = 6800.0
## RPM at which drive force peaks; force tapers above this toward max_rpm.
@export var peak_power_rpm: float = 5200.0

@export_group("Transmission")
## Forward gear ratios. Higher ratio = more force, lower top speed per gear.
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.4, 2.1, 1.45, 1.0, 0.78])
@export var reverse_ratio: float = 3.2
@export var final_drive: float = 3.9
## Effective rolling radius of a driven wheel (m), used for RPM<->speed mapping.
@export var wheel_radius: float = 0.33
## Automatic shift thresholds as a fraction of max_rpm.
@export var upshift_rpm_fraction: float = 0.92
@export var downshift_rpm_fraction: float = 0.45
## Minimum seconds between automatic shifts (prevents gear hunting, spec §5.5).
@export var shift_cooldown: float = 0.6

@export_group("Braking")
## Max braking force per axle pair (N). Finite: stopping distance grows with speed.
@export var brake_force: float = 11000.0
## Handbrake force applied to the rear axle (N). Reduces rear grip to help slides.
@export var handbrake_force: float = 6000.0
## Fraction of rear lateral grip remaining while handbrake is held (0..1).
@export var handbrake_grip_fraction: float = 0.35

@export_group("Steering")
## Maximum steering angle at low speed (radians). ~0.6 rad ≈ 34°.
@export var max_steer_angle: float = 0.60
## Steering angle floor at high speed as a fraction of max (spec §5.2:
## speed-sensitive steering).
@export var high_speed_steer_fraction: float = 0.28
## Speed (m/s) at which steering reaches its high-speed minimum.
@export var steer_speed_falloff: float = 45.0
## How fast the steering angle moves toward its target (rad/s). Lower = heavier.
@export var steer_rate: float = 3.2
## How fast steering returns to centre when no input (rad/s).
@export var steer_return_rate: float = 5.0

@export_group("Suspension")
## Natural rest length of the spring / raycast probe length (m).
@export var suspension_rest_length: float = 0.45
## Spring stiffness (N/m). Higher = firmer, less body movement.
@export var suspension_stiffness: float = 32000.0
## Damper force (N per m/s of compression velocity). Controls bounce (spec §5.2).
@export var suspension_damping: float = 3800.0
## Max spring travel beyond rest before hard limit (m).
@export var suspension_max_travel: float = 0.18
## Anti-roll bar stiffness (N/m of left-right compression difference).
@export var anti_roll_stiffness: float = 8000.0

@export_group("Tyre Grip")
## Peak lateral grip coefficient (× normal load gives max side force).
@export var lateral_grip_front: float = 1.35
@export var lateral_grip_rear: float = 1.40
## Peak longitudinal grip coefficient (drive/brake traction).
@export var longitudinal_grip: float = 1.45
## Slip angle (rad) at which lateral grip peaks, then falls off (slide onset).
@export var peak_slip_angle: float = 0.14
## Wet-road grip multiplier applied to all grip values (spec §5.2 wet grip).
@export var wet_grip_multiplier: float = 0.72

@export_group("Aerodynamics")
## Drag area term: force = drag_coefficient * speed^2 (N). Caps top speed.
@export var drag_coefficient: float = 0.42
## Downforce term: force = downforce_coefficient * speed^2 (N), adds grip at speed.
@export var downforce_coefficient: float = 0.0
## Rolling resistance force (N) roughly proportional to speed.
@export var rolling_resistance: float = 18.0

@export_group("Assists (spec §5.6)")
## 0 = off, 1 = full. The controller blends these; they modify inputs, they do
## not replace the physics (spec §5.6).
@export var abs_strength: float = 0.8
@export var traction_control_strength: float = 0.7
@export var stability_assist_strength: float = 0.5

@export_group("Visual model (optional — replaces the placeholder box)")
## A .glb/.gltf (or .tscn) car model. When set, the controller shows this instead
## of the box body. Physics is unchanged — the model is cosmetic.
@export var model_scene: PackedScene
## Fit the model to the physics body: position offset, rotation (degrees) and a
## uniform scale. Tuned per model so the wheels sit on the ground and it faces +Z.
@export var model_offset: Vector3 = Vector3.ZERO
@export var model_rotation_deg: Vector3 = Vector3.ZERO
@export var model_scale: float = 1.0
## Hide the placeholder box body + wheels when a model is shown.
@export var hide_placeholder_when_model: bool = true

@export_group("Ratings (display only — each must map to a real effect)")
@export var price_naira: int = 1500000
@export var durability: float = 0.7


func get_gear_ratio(gear: int) -> float:
	# gear: -1 reverse, 0 neutral, 1..N forward.
	if gear == -1:
		return -reverse_ratio
	if gear <= 0:
		return 0.0
	var idx := gear - 1
	if idx < gear_ratios.size():
		return gear_ratios[idx]
	return gear_ratios[gear_ratios.size() - 1]


func top_gear() -> int:
	return gear_ratios.size()
