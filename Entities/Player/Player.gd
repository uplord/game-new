extends CharacterBody2D
class_name Player

@onready var game = get_tree().root.get_node("Game")
@onready var camera_controller: Node = null
@onready var _viewport := get_viewport()

@onready var body = $Base/Model
@export var speed := 400.0

var animation_state: AnimationNodeStateMachinePlayback
const PlayerPose = PlayerUtil.PlayerPose

enum MouseMode {
	NONE,
	CLICK_MOVE,
	HOLD_FOLLOW
}

const HOLD_THRESHOLD := 0.2
const FOLLOW_START_DISTANCE := 64.0
const FOLLOW_STOP_DISTANCE := 16.0
const HOLD_SEND_INTERVAL := 0.1
const HOLD_TARGET_CHANGE_DISTANCE := 24.0
const CLICK_STOP_DISTANCE := 8.0
const MIN_CLICK_DISTANCE := 10.0
const MOVE_THRESHOLD := 0.01
const POSITION_SEND_INTERVAL := 0.033
const POSITION_SEND_DISTANCE := 2.0

var facing := 1
var last_facing := 1
var movement_locked := false
var actually_moving := false
var body_start_scale := Vector2.ZERO

var mouse_mode := MouseMode.NONE
var click_target := Vector2.ZERO
var mouse_down_time := 0.0
var hold_started := false

var follow_moving := false
var last_hold_send_time := 0.0
var last_sent_hold_target := Vector2.INF
var last_position_send_time := 0.0
var last_sent_position := Vector2.INF
var was_moving_last_frame := false

var prev_pose: PlayerPose = PlayerPose.IDLE


func _ready() -> void:
	await get_tree().process_frame
	
	body.animation_tree_enabled = true
	body.keep_animation_tree_for_player = true
	body.starting_pose = PlayerPose.IDLE
	
	var model: Node = body.get_model_root()
	if model == null:
		push_error("Model not loaded")
		return

	var anim_tree: AnimationTree = model.get_node_or_null("AnimationTree") as AnimationTree
	if anim_tree == null:
		push_error("AnimationTree missing")
		return

	anim_tree.active = true
	anim_tree.process_mode = Node.PROCESS_MODE_INHERIT

	animation_state = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	if animation_state == null:
		push_error("Animation state machine missing")
		return

	animation_state.travel("Idle")

	camera_controller = game.get_node("CameraManager")
	body_start_scale = body.scale

func _unhandled_input(event: InputEvent) -> void:
	if movement_locked:
		return

	if not event is InputEventMouseButton:
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed and _is_mouse_over_ui():
		return

	if event.pressed:
		mouse_down_time = _now()
		hold_started = false
	else:
		var held_time := _now() - mouse_down_time

		if held_time < HOLD_THRESHOLD:
			_on_click()
		else:
			_on_hold_release()


func _process(_delta: float) -> void:
	if movement_locked:
		return

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	if _is_mouse_over_ui():
		return

	var held_time := _now() - mouse_down_time

	if held_time > HOLD_THRESHOLD and not hold_started:
		hold_started = true
		_on_hold_start()


func _physics_process(_delta: float) -> void:
	var prev_pos := position
	var input_vector := _get_movement_input()

	velocity = Vector2.ZERO

	if not movement_locked and input_vector != Vector2.ZERO:
		var move_speed := _get_move_speed()
		velocity = input_vector * move_speed
		move_and_slide()

	_update_movement_state(prev_pos)
	_update_facing(input_vector)
	_send_position_if_needed()
	_update_camera_look_ahead()


func _get_movement_input() -> Vector2:
	if movement_locked:
		return Vector2.ZERO

	match mouse_mode:
		MouseMode.CLICK_MOVE:
			return _get_click_move_input()

		MouseMode.HOLD_FOLLOW:
			return _get_hold_follow_input()

	return Vector2.ZERO


func _get_click_move_input() -> Vector2:
	var to_target := click_target - position
	var stop_distance_sq := CLICK_STOP_DISTANCE * CLICK_STOP_DISTANCE

	if to_target.length_squared() <= stop_distance_sq:
		mouse_mode = MouseMode.NONE
		click_target = Vector2.ZERO
		_send_stop()
		return Vector2.ZERO

	return to_target.normalized()


func _get_hold_follow_input() -> Vector2:
	var mouse_pos := _get_map_mouse_position()
	var dir := mouse_pos - position
	var dist_sq := dir.length_squared()

	if not follow_moving and dist_sq > FOLLOW_START_DISTANCE * FOLLOW_START_DISTANCE:
		follow_moving = true
	elif follow_moving and dist_sq < FOLLOW_STOP_DISTANCE * FOLLOW_STOP_DISTANCE:
		follow_moving = false

	if not follow_moving:
		return Vector2.ZERO

	_send_hold_move_if_needed(mouse_pos)

	return dir.normalized()


func _on_click() -> void:
	var new_target := _get_map_mouse_position()

	if position.distance_squared_to(new_target) < MIN_CLICK_DISTANCE * MIN_CLICK_DISTANCE:
		return

	click_target = new_target
	mouse_mode = MouseMode.CLICK_MOVE
	follow_moving = false

	_send_move(new_target)


func _on_hold_start() -> void:
	click_target = Vector2.ZERO
	mouse_mode = MouseMode.HOLD_FOLLOW
	follow_moving = false

	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0


func _on_hold_release() -> void:
	mouse_mode = MouseMode.NONE
	follow_moving = false

	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0

	_send_stop()


func _send_hold_move_if_needed(mouse_pos: Vector2) -> void:
	var now := _now()

	if now - last_hold_send_time < HOLD_SEND_INTERVAL:
		return

	var target_changed := last_sent_hold_target == Vector2.INF \
		or last_sent_hold_target.distance_squared_to(mouse_pos) > HOLD_TARGET_CHANGE_DISTANCE * HOLD_TARGET_CHANGE_DISTANCE

	if not target_changed:
		return

	last_hold_send_time = now
	last_sent_hold_target = mouse_pos

	_send_move(mouse_pos)


func _update_movement_state(prev_pos: Vector2) -> void:
	var movement := position - prev_pos
	actually_moving = movement.length_squared() > 4.0
	
	var desired_pose: PlayerPose

	if actually_moving:
		desired_pose = PlayerPose.RUNNING
	else:
		desired_pose = PlayerPose.IDLE

	if desired_pose != prev_pose:
		set_pose(desired_pose)


func set_pose(pose: PlayerPose) -> void:
	if animation_state == null:
		return

	if prev_pose == pose:
		return

	prev_pose = pose
	animation_state.travel(PlayerUtil.to_anim_name(pose))
	_send_pose_update()


func _update_camera_look_ahead() -> void:
	if camera_controller == null:
		return

	var move_speed := _get_move_speed()

	if move_speed == 0.0:
		return

	var horizontal_amount := velocity.x / move_speed
	camera_controller.set_look_ahead_direction(horizontal_amount)


func _update_facing(input_vector: Vector2) -> void:
	if abs(input_vector.x) > MOVE_THRESHOLD:
		last_facing = sign(input_vector.x)

	facing = last_facing

	if body_start_scale != Vector2.ZERO:
		body.scale.x = body_start_scale.x * facing


func _get_move_speed() -> float:
	if camera_controller == null:
		return speed

	return speed * camera_controller.get_map_scale()


func _is_mouse_over_ui() -> bool:
	return _viewport.gui_get_hovered_control() != null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _get_map_mouse_position() -> Vector2:
	if get_parent() is Node2D:
		return (get_parent() as Node2D).to_local(get_global_mouse_position())

	return get_global_mouse_position()

func _send_position_if_needed() -> void:
	if not actually_moving:
		if was_moving_last_frame:
			was_moving_last_frame = false
			_send_stop()
		return

	was_moving_last_frame = true

	var now := _now()

	if now - last_position_send_time < POSITION_SEND_INTERVAL:
		return

	var moved_enough := last_sent_position == Vector2.INF \
		or last_sent_position.distance_squared_to(position) > POSITION_SEND_DISTANCE * POSITION_SEND_DISTANCE

	if not moved_enough:
		return

	last_position_send_time = now
	last_sent_position = position

	ServerManager.send_to_server({
		"type": "c_move_player",
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"pose": int(prev_pose),
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})

func _send_move(_target: Vector2) -> void:
	# Send the player's current position, not the clicked destination.
	# The destination is only used locally for movement.
	ServerManager.send_to_server({
		"type": "c_move_player",
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"pose": int(prev_pose),
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})


func _send_pose_update() -> void:
	ServerManager.send_to_server({
		"type": "c_move_player",
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"pose": int(prev_pose),
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})


func _send_stop() -> void:
	ServerManager.send_to_server({
		"type": "c_stop_player",
		"position": position,
		"velocity": Vector2.ZERO,
		"facing": facing,
		"pose": int(prev_pose),
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})
