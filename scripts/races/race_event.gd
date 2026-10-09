class_name RaceEvent
extends Resource
## Data-driven race event definition (spec §11). An event references a track and
## the rules; the race manager reads it so new events = new .tres files, no code.

enum Kind { SPRINT, CIRCUIT, DRAG }

@export var event_id: StringName = &"bridge_test_sprint"
@export var display_name: String = "Bridge Test Sprint"
@export var kind: Kind = Kind.SPRINT
## Laps for a circuit (ignored for sprint/drag).
@export var laps: int = 1
## Countdown seconds before the timer starts.
@export var countdown: float = 3.0
## Reward in naira for finishing (career hook, spec §13).
@export var reward_naira: int = 50000
## Allowed car-class hint (free text for now).
@export var allowed_classes: String = "any"
## Time-of-day / weather preset names (applied later by the environment).
@export var time_of_day: String = "sunset"
@export var weather: String = "clear"


func best_time_key() -> String:
	return String(event_id)
