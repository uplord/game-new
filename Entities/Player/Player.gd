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
var FOLLOW_START_DISTANCE := 64.0
const FOLLOW_STOP_DISTANCE := 16.0
const HOLD_SEND_INTERVAL := 0.033
const HOLD_TARGET_CHANGE_DISTANCE := 6.0
const CLICK_STOP_DISTANCE := 8.0

const ENGAGEMENT_PADDING := 48.0
const MIN_ENEMY_APPROACH_DISTANCE := 128.0
const ENEMY_DISTANCE_TOLERANCE := 8.0

const MIN_CLICK_DISTANCE := 10.0
const MOVE_THRESHOLD := 2.0
const POSITION_SEND_INTERVAL := 0.016
const POSITION_SEND_DISTANCE := 1.0

var facing := 1
var last_facing := 1
var movement_locked := false
var actually_moving := false
var body_start_scale := Vector2.ZERO

var mouse_mode := MouseMode.NONE
var click_target := Vector2.ZERO
var mouse_down_time := 0.0
var hold_started := false
var mouse_press_active := false

var follow_moving := false
var last_hold_send_time := 0.0
var last_sent_hold_target := Vector2.INF
var last_position_send_time := 0.0
var last_sent_position := Vector2.INF
var was_moving_last_frame := false
var movement_sequence := 0

var prev_pose: PlayerPose = PlayerPose.IDLE
var approach_enemy: Node2D = null
var attacking_pose_active := false


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
		mouse_press_active = true
		hold_started = false
	else:
		if not mouse_press_active:
			return

		mouse_press_active = false
		var held_time := _now() - mouse_down_time

		if held_time < HOLD_THRESHOLD:
			_on_click()
		else:
			_on_hold_release()


func _process(_delta: float) -> void:
	if movement_locked:
		return

	if not mouse_press_active or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
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
		
		if get_slide_collision_count() > 0 and mouse_mode == MouseMode.CLICK_MOVE:
			mouse_mode = MouseMode.NONE
			click_target = Vector2.ZERO
			velocity = Vector2.ZERO

	var movement_delta := position - prev_pos

	_update_facing_from_movement(movement_delta)
	_update_facing_towards_approach_enemy()
	_update_movement_state(prev_pos)
	_send_position_if_needed()
	_update_camera_look_ahead()


func _get_movement_input() -> Vector2:
	if movement_locked:
		return Vector2.ZERO

	var keyboard_input := Input.get_vector(
		"left_move",
		"right_move",
		"up_move",
		"down_move"
	)

	if keyboard_input != Vector2.ZERO:
		_clear_enemy_target()
		approach_enemy = null
		mouse_mode = MouseMode.NONE
		follow_moving = false
		return keyboard_input

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

		if approach_enemy != null and is_instance_valid(approach_enemy):
			_face_global_position(approach_enemy.global_position)

		approach_enemy = null
		_send_stop()
		return Vector2.ZERO

	return to_target.normalized()


func _get_hold_follow_input() -> Vector2:
	var screen_dir := _get_screen_mouse_direction()
	var dist_sq := screen_dir.length_squared()

	if not follow_moving and dist_sq > FOLLOW_START_DISTANCE * FOLLOW_START_DISTANCE:
		follow_moving = true
	elif follow_moving and dist_sq < FOLLOW_STOP_DISTANCE * FOLLOW_STOP_DISTANCE:
		follow_moving = false

	if not follow_moving:
		return Vector2.ZERO

	var mouse_pos := _get_map_mouse_position()
	_send_hold_move_if_needed(mouse_pos)

	return screen_dir.normalized()


func _on_click() -> void:
	var clicked_enemy := _get_enemy_under_mouse()
	if clicked_enemy != null:
		if clicked_enemy.has_method("target"):
			clicked_enemy.target()
			move_close_to_enemy(clicked_enemy)
		else:
			_clear_enemy_target()
		return

	var new_target := _get_map_mouse_position()

	if position.distance_squared_to(new_target) < MIN_CLICK_DISTANCE * MIN_CLICK_DISTANCE:
		return

	_clear_enemy_target()
	approach_enemy = null
	click_target = new_target
	mouse_mode = MouseMode.CLICK_MOVE
	follow_moving = false

	_send_move(new_target)


func _on_hold_start() -> void:
	_clear_enemy_target()
	approach_enemy = null
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


func move_close_to_enemy(enemy: Node) -> void:
	_move_close_to_enemy(enemy)


func _move_close_to_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not (enemy is Node2D):
		return

	approach_enemy = enemy as Node2D

	var enemy_position := approach_enemy.global_position
	var desired_distance := get_enemy_approach_distance(self, approach_enemy)

	var offset_from_enemy := global_position - enemy_position
	var current_distance := offset_from_enemy.length()

	_face_global_position(enemy_position)

	if abs(current_distance - desired_distance) <= ENEMY_DISTANCE_TOLERANCE:
		mouse_mode = MouseMode.NONE
		click_target = Vector2.ZERO
		_send_stop()
		return

	var direction_away_from_enemy := Vector2.ZERO

	if current_distance > 0.01:
		direction_away_from_enemy = offset_from_enemy.normalized()
	else:
		direction_away_from_enemy = Vector2.LEFT if facing > 0 else Vector2.RIGHT

	var desired_global_position := enemy_position + direction_away_from_enemy * desired_distance

	var desired_local_position := desired_global_position
	if get_parent() is Node2D:
		desired_local_position = (get_parent() as Node2D).to_local(desired_global_position)

	click_target = desired_local_position
	mouse_mode = MouseMode.CLICK_MOVE
	follow_moving = false
	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0

	_send_move(click_target)


func get_enemy_approach_distance(player: Node, enemy: Node) -> float:
	var player_half := get_collision_width(player) * 0.5
	var enemy_half := get_collision_width(enemy) * 0.5

	return max(
		player_half + enemy_half + ENGAGEMENT_PADDING,
		MIN_ENEMY_APPROACH_DISTANCE
	)


func get_collision_width(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return MIN_ENEMY_APPROACH_DISTANCE

	var shape_node := node.find_child("CollisionShape2D", true, false) as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return MIN_ENEMY_APPROACH_DISTANCE

	var shape := shape_node.shape
	var scale_x = abs(shape_node.global_scale.x)

	if shape is RectangleShape2D:
		return shape.size.x * scale_x

	if shape is CapsuleShape2D:
		return shape.radius * 2.0 * scale_x

	if shape is CircleShape2D:
		return shape.radius * 2.0 * scale_x

	return MIN_ENEMY_APPROACH_DISTANCE


func _clear_enemy_target() -> void:
	var ui := game.get_node_or_null("UI") if game != null else null
	if ui != null and ui.has_method("hide_enemy_card"):
		ui.hide_enemy_card()


func cancel_mouse_movement() -> void:
	mouse_press_active = false
	hold_started = false
	mouse_mode = MouseMode.NONE
	follow_moving = false
	click_target = Vector2.ZERO
	approach_enemy = null
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
	actually_moving = movement.length_squared() > 4.0 or velocity.length_squared() > 4.0
	
	var desired_pose: PlayerPose

	if actually_moving:
		desired_pose = PlayerPose.RUNNING
	elif attacking_pose_active:
		desired_pose = PlayerPose.FIGHT
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


func _update_camera_look_ahead() -> void:
	if camera_controller == null or not is_instance_valid(camera_controller):
		camera_controller = null
		return

	if mouse_mode == MouseMode.HOLD_FOLLOW and mouse_press_active:
		var screen_dir := _get_screen_mouse_direction()

		if screen_dir.length_squared() <= FOLLOW_STOP_DISTANCE * FOLLOW_STOP_DISTANCE:
			camera_controller.set_look_ahead_direction(0.0)
		else:
			camera_controller.set_look_ahead_direction(clamp(screen_dir.normalized().x, -1.0, 1.0))

		return

	var move_speed := _get_move_speed()

	if move_speed == 0.0:
		return

	var horizontal_amount := velocity.x / move_speed
	camera_controller.set_look_ahead_direction(horizontal_amount)


func _update_facing_from_movement(movement_delta: Vector2) -> void:
	if approach_enemy != null and is_instance_valid(approach_enemy):
		_face_global_position(approach_enemy.global_position)
		return

	if mouse_mode == MouseMode.HOLD_FOLLOW and mouse_press_active:
		var screen_dir := _get_screen_mouse_direction()
		if abs(screen_dir.x) > FOLLOW_STOP_DISTANCE:
			last_facing = sign(screen_dir.x)
	else:
		if abs(movement_delta.x) > 2.0:
			last_facing = sign(movement_delta.x)

	facing = last_facing
	_apply_facing()


func _update_facing_towards_approach_enemy() -> void:
	if approach_enemy == null or not is_instance_valid(approach_enemy):
		return

	_face_global_position(approach_enemy.global_position)


func _face_global_position(target_global_position: Vector2) -> void:
	var delta_x := target_global_position.x - global_position.x
	if abs(delta_x) <= MOVE_THRESHOLD:
		return

	last_facing = sign(delta_x)
	facing = last_facing
	_apply_facing()


func _apply_facing() -> void:
	if body_start_scale != Vector2.ZERO:
		body.scale.x = body_start_scale.x * facing


func _get_move_speed() -> float:
	if camera_controller == null:
		return speed

	return speed * camera_controller.get_map_scale()


func _is_mouse_over_ui() -> bool:
	return _viewport.gui_get_hovered_control() != null


func _get_enemy_under_mouse() -> Node:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 0xFFFFFFFF

	var hits := space_state.intersect_point(query, 32)
	for hit in hits:
		var collider := hit.get("collider") as Node
		var enemy := _find_targetable_enemy(collider)
		if enemy != null:
			return enemy

	return null


func _find_targetable_enemy(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group("targetable_enemies"):
			return current
		current = current.get_parent()

	return null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _get_map_mouse_position() -> Vector2:
	if get_parent() is Node2D:
		return (get_parent() as Node2D).to_local(get_global_mouse_position())

	return get_global_mouse_position()


func _next_movement_sequence() -> int:
	movement_sequence += 1
	return movement_sequence


func _get_screen_mouse_direction() -> Vector2:
	var player_screen_pos := get_global_transform_with_canvas().origin
	var mouse_screen_pos := get_viewport().get_mouse_position()
	return mouse_screen_pos - player_screen_pos


func _send_position_if_needed() -> void:
	if not actually_moving:
		if was_moving_last_frame:
			was_moving_last_frame = false
			last_sent_position = Vector2.INF
			_send_stop()
		return

	was_moving_last_frame = true

	var now := _now()
	if now - last_position_send_time < POSITION_SEND_INTERVAL:
		return

	last_position_send_time = now
	last_sent_position = position

	ServerManager.send_to_server({
		"type": "c_move_player",
		"sequence": _next_movement_sequence(),
		"client_time": now,
		"position": position,
		"velocity": velocity,
		"facing": facing,
		"pose": int(prev_pose),
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})


func _send_move(_target: Vector2) -> void:
	ServerManager.send_to_server({
		"type": "c_move_player",
		"sequence": _next_movement_sequence(),
		"client_time": _now(),
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
		"sequence": _next_movement_sequence(),
		"client_time": _now(),
		"position": position,
		"velocity": Vector2.ZERO,
		"facing": facing,
		"pose": int(prev_pose),
		"map": SceneManager.current_map,
		"scene": SceneManager.current_scene,
	})
