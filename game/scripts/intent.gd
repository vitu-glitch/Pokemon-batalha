class_name Intent
extends RefCounted
## What a fighter wants to do this step. Filled in by the player's controller or by
## the AI, and the fighter processes it the same way in both cases: the AI plays by
## the same rules, timings and resources.

var move_input := Vector2.ZERO    # x right, y forward, relative to "yaw"
var yaw := 0.0                    # where the camera (or the AI) is looking
var pressed := {}                 # action -> true only on the step it was pressed
var held := {}                    # action -> true while it is held
var counter := {}                 # action -> presses so far (for netplay)


func press(action: String) -> void:
	pressed[action] = true
	held[action] = true
	counter[action] = (int(counter.get(action, 0)) + 1) % 256


func release(action: String) -> void:
	held.erase(action)


func clear() -> void:
	pressed.clear()


func keeps(action: String) -> bool:
	return held.get(action, false)
