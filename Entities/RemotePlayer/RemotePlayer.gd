extends CharacterBody2D

@onready var body = $Base/Model

const SNAP_DISTANCE := 600.0
const MOVING_SMOOTH_TIME := 0.07
const STOPPING_SMOOTH_TIME := 0.035
const MAX_EXTRAPOLATION := 0.045
const STOP_VELOCITY_EPSILON := 1.0

var target_position := Vector2.ZERO
var target_velocity := Vector2.ZERO
var last_packet_time := 0.0
var has_target := false

var facing := 1
var body_start_scale := Vector2.ZERO


func _ready() -> void:
	target_position = position
	has_target = true
	body_start_scale = body.scale
	last_packet_time = _now()
	_apply_facing()


func _process(delta: float) -> void:
	if not has_target:
		return

	var desired_position := target_position
	var smooth_time := STOPPING_SMOOTH_TIME

	if target_velocity.length_squared() > STOP_VELOCITY_EPSILON * STOP_VELOCITY_EPSILON:
		var age = clamp(_now() - last_packet_time, 0.0, MAX_EXTRAPOLATION)
		desired_position = target_position + target_velocity * age
		smooth_time = MOVING_SMOOTH_TIME

	if position.distance_squared_to(desired_position) > SNAP_DISTANCE * SNAP_DISTANCE:
		position = desired_position
		return

	var weight := 1.0 - exp(-delta / smooth_time)
	position = position.lerp(desired_position, weight)


func set_remote_state(pos: Vector2, vel: Vector2 = Vector2.ZERO) -> void:
	target_position = pos
	target_velocity = vel
	last_packet_time = _now()

	if not has_target:
		position = pos
		has_target = true


func set_target_position(pos: Vector2) -> void:
	set_remote_state(pos, Vector2.ZERO)


func set_facing(value: int) -> void:
	if value == 0:
		return

	facing = sign(value)
	_apply_facing()


func _apply_facing() -> void:
	if body_start_scale != Vector2.ZERO:
		body.scale.x = abs(body_start_scale.x) * facing


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
 
