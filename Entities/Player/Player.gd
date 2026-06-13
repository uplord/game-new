extends CharacterBody2D
class_name Player

@onready var game = get_tree().root.get_node("Game")
@onready var camera_controller: Node = null
@onready var _viewport := get_viewport()

@onready var body = $Base/Model
@export var speed := 400.0

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


func _ready() -> void:
	await get_tree().process_frame

	camera_controller = game.get_node("CameraManager")
	body_start_scale = body.scale

	print("camera_controller: ", camera_controller)


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
	var prev_pos := global_position
	var input_vector := _get_movement_input()

	velocity = Vector2.ZERO

	if not movement_locked and input_vector != Vector2.ZERO:
		var move_speed := _get_move_speed()
		velocity = input_vector * move_speed
		move_and_slide()

	_update_movement_state(prev_pos)
	_update_camera_look_ahead()
	_update_facing(input_vector)


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
	var to_target := click_target - global_position
	var stop_distance_sq := CLICK_STOP_DISTANCE * CLICK_STOP_DISTANCE

	if to_target.length_squared() <= stop_distance_sq:
		mouse_mode = MouseMode.NONE
		click_target = Vector2.ZERO
		return Vector2.ZERO

	return to_target.normalized()


func _get_hold_follow_input() -> Vector2:
	var mouse_pos := get_global_mouse_position()
	var dir := mouse_pos - global_position
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
	var new_target := get_global_mouse_position()

	if global_position.distance_squared_to(new_target) < MIN_CLICK_DISTANCE * MIN_CLICK_DISTANCE:
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
	var movement := global_position - prev_pos
	actually_moving = movement.length_squared() > 4.0


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


func _send_move(target: Vector2) -> void:
	ServerManager.send_to_server({
		"type": "c_move_player",
		"position": target,
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})


func _send_stop() -> void:
	ServerManager.send_to_server({
		"type": "c_stop_player",
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})
