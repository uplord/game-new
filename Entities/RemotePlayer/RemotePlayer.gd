extends Node2D

@onready var body = $Base/Model

const INTERPOLATION_DELAY := 0.12
const MAX_EXTRAPOLATION_TIME := 0.08
const SNAP_DISTANCE := 600.0
const STOP_SNAP_DISTANCE := 1.0
const STOP_VELOCITY_EPSILON := 20.0
const VISUAL_MOVE_EPSILON := 6.0
const MAX_SNAPSHOTS := 32

var snapshots: Array[Dictionary] = []
var has_target := false
var last_sequence := -1
var server_pose: int = PlayerUtil.PlayerPose.IDLE

var visual_direction := Vector2.ZERO
var visual_stopped := true

var facing := 1
var initial_facing := 1
var body_start_scale := Vector2.ZERO
var animation_state: AnimationNodeStateMachinePlayback
var current_pose: int = PlayerUtil.PlayerPose.IDLE


func _ready() -> void:
	body.animation_tree_enabled = true
	body.starting_pose = PlayerUtil.PlayerPose.IDLE
	body_start_scale = body.scale
	facing = initial_facing
	_setup_animation_tree()
	_apply_facing()


func _process(delta: float) -> void:
	if not has_target or snapshots.is_empty():
		_update_visual_pose(Vector2.ZERO)
		return

	var previous_position := position
	var desired_position := _get_interpolated_position()

	if position.distance_squared_to(desired_position) > SNAP_DISTANCE * SNAP_DISTANCE:
		position = desired_position
		_update_visual_pose(Vector2.ZERO)
		return

	if visual_stopped and position.distance_squared_to(desired_position) <= STOP_SNAP_DISTANCE * STOP_SNAP_DISTANCE:
		position = desired_position
		_apply_visible_stop_facing()
		_update_visual_pose(Vector2.ZERO)
		return

	var correction_rate := 45.0 if visual_stopped else 18.0
	var weight := 1.0 - exp(-correction_rate * delta)
	position = position.lerp(desired_position, weight)

	var display_velocity = (position - previous_position) / max(delta, 0.001)

	if visual_direction != Vector2.ZERO:
		_update_visual_pose(visual_direction * display_velocity.length())
	else:
		_update_visual_pose(display_velocity)


func set_remote_state(
		pos: Vector2,
		vel: Vector2 = Vector2.ZERO,
		sequence: int = -1,
		stopped: bool = false,
		pose: int = PlayerUtil.PlayerPose.IDLE,
		network_facing: int = 0
	) -> void:
	if sequence >= 0:
		if sequence <= last_sequence:
			return
		last_sequence = sequence

	# Use this client's receive time for interpolation.
	# Do not compare unsynchronised server_time with this client's local clock,
	# because that makes keyboard movement appear immediately instead of after
	# the interpolation delay.
	var snapshot_time := _now()

	var clean_velocity := vel
	var snapshot_stopped := stopped or clean_velocity.length() <= STOP_VELOCITY_EPSILON
	server_pose = pose

	if snapshot_stopped:
		clean_velocity = Vector2.ZERO

	snapshots.append({
		"position": pos,
		"velocity": clean_velocity,
		"time": snapshot_time,
		"sequence": sequence,
		"stopped": snapshot_stopped,
		"pose": pose,
		"facing": network_facing,
	})

	while snapshots.size() > MAX_SNAPSHOTS:
		snapshots.pop_front()

	if not has_target:
		position = pos
		has_target = true


func _get_interpolated_position() -> Vector2:
	visual_direction = Vector2.ZERO
	visual_stopped = true

	var render_time := _now() - INTERPOLATION_DELAY

	while snapshots.size() >= 2 and float(snapshots[1].get("time", 0.0)) <= render_time:
		snapshots.pop_front()

	if snapshots.size() >= 2:
		var a: Dictionary = snapshots[0]
		var b: Dictionary = snapshots[1]

		var a_time := float(a.get("time", 0.0))
		var b_time := float(b.get("time", a_time))

		var pos_a: Vector2 = a.get("position", position)
		var pos_b: Vector2 = b.get("position", pos_a)

		var movement := pos_b - pos_a

		visual_stopped = bool(a.get("stopped", false)) and bool(b.get("stopped", false))

		if movement.length() > VISUAL_MOVE_EPSILON:
			visual_direction = movement.normalized()
			visual_stopped = false

		var span = max(b_time - a_time, 0.001)
		var t = clamp((render_time - a_time) / span, 0.0, 1.0)

		return pos_a.lerp(pos_b, t)

	var latest: Dictionary = snapshots[snapshots.size() - 1]
	var latest_time := float(latest.get("time", 0.0))
	var latest_position: Vector2 = latest.get("position", position)

	visual_stopped = bool(latest.get("stopped", false))

	if render_time < latest_time:
		return position

	if visual_stopped:
		return latest_position

	var latest_velocity: Vector2 = latest.get("velocity", Vector2.ZERO)

	if latest_velocity.length() > VISUAL_MOVE_EPSILON:
		visual_direction = latest_velocity.normalized()
		visual_stopped = false

	var age = clamp(render_time - latest_time, 0.0, MAX_EXTRAPOLATION_TIME)
	return latest_position + latest_velocity * age


func set_target_position(pos: Vector2) -> void:
	set_remote_state(pos, Vector2.ZERO, -1, true, PlayerUtil.PlayerPose.IDLE, facing)


func _update_visual_pose(display_velocity: Vector2) -> void:
	var visually_moving := display_velocity.length() > VISUAL_MOVE_EPSILON

	if visually_moving:
		set_pose(PlayerUtil.PlayerPose.RUNNING)

		if abs(display_velocity.x) > VISUAL_MOVE_EPSILON:
			set_facing(sign(display_velocity.x))
	else:
		set_pose(PlayerUtil.PlayerPose.IDLE)



func set_initial_facing(value: int) -> void:
	if value == 0:
		return

	initial_facing = sign(value)
	facing = initial_facing

	if body_start_scale != Vector2.ZERO:
		_apply_facing()


func _apply_visible_stop_facing() -> void:
	if snapshots.is_empty():
		return

	var latest: Dictionary = snapshots[snapshots.size() - 1]
	if not bool(latest.get("stopped", false)):
		return

	var stop_facing := int(latest.get("facing", 0))
	if stop_facing != 0:
		set_facing(stop_facing)

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
		body.scale.x = body_start_scale.x * facing


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
