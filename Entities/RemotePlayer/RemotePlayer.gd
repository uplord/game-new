extends Node2D

@onready var body = $Base/Model

const SNAP_DISTANCE := 600.0
const SMOOTH_TIME := 0.045
const MAX_EXTRAPOLATION := 0.08
const STOP_VELOCITY_EPSILON := 50.00

var target_position := Vector2.ZERO
var target_velocity := Vector2.ZERO
var last_packet_time := 0.0
var has_target := false

var facing := 1
var body_start_scale := Vector2.ZERO
var animation_state: AnimationNodeStateMachinePlayback
var current_pose: int = PlayerUtil.PlayerPose.IDLE


func _ready() -> void:
	body.animation_tree_enabled = true
	body.starting_pose = PlayerUtil.PlayerPose.IDLE
	body_start_scale = body.scale
	_setup_animation_tree()
	_apply_facing()


func _process(delta: float) -> void:
	if not has_target:
		return

	var is_stopped := target_velocity.length() <= STOP_VELOCITY_EPSILON
	var desired_position := target_position

	if not is_stopped:
		var age = clamp(_now() - last_packet_time, 0.0, MAX_EXTRAPOLATION)
		desired_position += target_velocity * age

	if position.distance_squared_to(desired_position) > SNAP_DISTANCE * SNAP_DISTANCE:
		position = desired_position
		return

	if is_stopped:
		if position.distance_squared_to(target_position) < 25.0:
			position = target_position
			return

		var stop_weight := 1.0 - exp(-delta / 0.015)
		position = position.lerp(target_position, stop_weight)
	else:
		var move_weight := 1.0 - exp(-delta / SMOOTH_TIME)
		position = position.lerp(desired_position, move_weight)


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


func set_pose(pose: int) -> void:
	if current_pose == pose:
		return

	current_pose = pose

	if animation_state == null:
		return

	animation_state.travel(PlayerUtil.to_anim_name(pose))


func _setup_animation_tree() -> void:
	await get_tree().process_frame

	var model: Node = body.get_model_root()
	if model == null:
		return

	var anim_tree: AnimationTree = model.get_node_or_null("AnimationTree") as AnimationTree
	if anim_tree == null:
		return

	anim_tree.active = true
	anim_tree.process_mode = Node.PROCESS_MODE_INHERIT
	animation_state = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	if animation_state != null:
		animation_state.travel(PlayerUtil.to_anim_name(current_pose))


func _apply_facing() -> void:
	if body_start_scale != Vector2.ZERO:
		body.scale.x = abs(body_start_scale.x) * facing


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
