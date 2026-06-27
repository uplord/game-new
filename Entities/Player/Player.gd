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
const MIN_ENEMY_APPROACH_DISTANCE := 64.0
const ENEMY_DISTANCE_TOLERANCE := 8.0
const ENEMY_TOO_CLOSE_TOLERANCE := 12.0

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
var enemy_approach_candidate_points: Array[Vector2] = []
var enemy_approach_candidate_index := 0
var enemy_approach_direction_away := Vector2.ZERO
var attacking_pose_active := false
var active_teleport_trigger_key := ""



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

	_refresh_camera_controller()
	body_start_scale = body.scale


func _refresh_camera_controller() -> void:
	camera_controller = game.get_node_or_null("CameraManager")


func _apply_arrival_camera_facing() -> void:
	_refresh_camera_controller()

	if camera_controller == null or not is_instance_valid(camera_controller):
		return

	# A teleport target's left/right direction should immediately frame the
	# player on the opposite side of the screen, the same way normal
	# movement look-ahead does. Snapping avoids the camera easing from the
	# previous scene's offset after the map/scene swap.
	var camera_dir := float(last_facing)

	if camera_controller.has_method("snap_look_ahead_direction"):
		camera_controller.snap_look_ahead_direction(camera_dir)
	elif camera_controller.has_method("set_look_ahead_direction"):
		camera_controller.set_look_ahead_direction(camera_dir)

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
			if approach_enemy != null and is_instance_valid(approach_enemy):
				if _try_enemy_alternate_position():
					velocity = Vector2.ZERO
				else:
					_stop_enemy_approach_if_close()
					mouse_mode = MouseMode.NONE
					click_target = Vector2.ZERO
					velocity = Vector2.ZERO
			else:
				mouse_mode = MouseMode.NONE
				click_target = Vector2.ZERO
				velocity = Vector2.ZERO

	var movement_delta := position - prev_pos

	_update_facing_from_movement(movement_delta)
	_update_facing_towards_approach_enemy()
	_update_movement_state(prev_pos)
	_send_position_if_needed()
	_update_camera_look_ahead()
	_check_teleports()


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
		_reset_enemy_approach_candidates()
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
			_focus_camera_on_enemy(approach_enemy)

		approach_enemy = null
		_reset_enemy_approach_candidates()
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
		else:
			_clear_enemy_target()
		return

	if _is_mouse_over_player():
		_swap_facing_direction()
		return

	var new_target := _get_map_mouse_position()

	if position.distance_squared_to(new_target) < MIN_CLICK_DISTANCE * MIN_CLICK_DISTANCE:
		return

	_clear_enemy_target()
	approach_enemy = null
	_reset_enemy_approach_candidates()
	click_target = new_target
	mouse_mode = MouseMode.CLICK_MOVE
	follow_moving = false

	if camera_controller != null and camera_controller.has_method("reset_to_default_camera"):
		camera_controller.reset_to_default_camera()

	_send_move(new_target)


func _on_hold_start() -> void:
	_clear_enemy_target()
	approach_enemy = null
	_reset_enemy_approach_candidates()
	click_target = Vector2.ZERO
	mouse_mode = MouseMode.HOLD_FOLLOW
	follow_moving = false

	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0

	if camera_controller != null and camera_controller.has_method("reset_to_default_camera"):
		camera_controller.reset_to_default_camera()


func _on_hold_release() -> void:
	mouse_mode = MouseMode.NONE
	follow_moving = false

	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0

	_send_stop()



# --------------------------------------------------
# TELEPORTS
# --------------------------------------------------
func _check_teleports() -> void:
	if movement_locked:
		return
	if SceneManager == null:
		return

	var teleports_parent := get_tree().root.get_node_or_null("Game/Map/Scene/Teleports")
	if teleports_parent == null:
		active_teleport_trigger_key = ""
		return

	var standing_on_teleport := false

	for teleport in teleports_parent.get_children():
		if not (teleport is Marker2D):
			continue

		var trigger_radius := 48.0
		var radius_value = teleport.get("trigger_radius")
		if radius_value != null:
			trigger_radius = float(radius_value)
		var distance_sq := global_position.distance_squared_to(teleport.global_position)
		var trigger_sq := trigger_radius * trigger_radius
		var lock_key := SceneManager.make_teleport_lock_key(
			SceneManager.current_map,
			SceneManager.current_scene,
			str(teleport.name)
		)

		if distance_sq > trigger_sq:
			if active_teleport_trigger_key == lock_key:
				active_teleport_trigger_key = ""
			if SceneManager.get_teleport_lock_key() == lock_key:
				SceneManager.clear_teleport_lock_if_matches(lock_key)
			continue

		standing_on_teleport = true

		# This prevents an instant return teleport after arriving on the target
		# marker. The player must leave this marker and step back onto it first.
		if SceneManager.get_teleport_lock_key() == lock_key:
			return

		# This prevents repeatedly firing the same marker every physics frame while
		# the player remains inside its trigger radius.
		if active_teleport_trigger_key == lock_key:
			return

		_try_use_teleport(teleport, lock_key)
		return

	if not standing_on_teleport:
		active_teleport_trigger_key = ""


func _try_use_teleport(teleport: Node, lock_key: String) -> void:
	var target_map := str(teleport.get("target_map"))
	var target_scene := str(teleport.get("target_scene"))
	var target_teleport := str(teleport.get("target_teleport"))

	if target_map == "" or target_scene == "" or target_teleport == "":
		return

	active_teleport_trigger_key = lock_key
	cancel_mouse_movement(false)

	var target_facing := 1
	if teleport.has_method("get_target_facing"):
		target_facing = int(teleport.get_target_facing())
	else:
		var target_direction = teleport.get("target_direction")
		if target_direction is Vector2:
			target_facing = -1 if target_direction.x < 0.0 else 1
		else:
			target_facing = -1 if int(target_direction) < 0 else 1

	ServerManager.send_to_server({
		"type": "c_teleport_player",
		"from_map": SceneManager.current_map,
		"from_scene": SceneManager.current_scene,
		"from_teleport": str(teleport.name),
		"target_map": target_map,
		"target_scene": target_scene,
		"target_teleport": target_teleport,
		"target_facing": target_facing,
	})


func set_facing_direction(direction: int) -> void:
	last_facing = -1 if direction < 0 else 1
	facing = last_facing
	_apply_facing()
	_send_stop()


func move_close_to_enemy(enemy: Node, force_reposition: bool = false) -> void:
	_move_close_to_enemy(enemy, force_reposition)




func is_enemy_approach_in_progress(enemy: Node) -> bool:
	return enemy != null \
		and is_instance_valid(enemy) \
		and approach_enemy == enemy \
		and mouse_mode == MouseMode.CLICK_MOVE


func is_close_to_enemy(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if not (enemy is Node2D):
		return false

	var enemy_node := enemy as Node2D
	var desired_distance := get_enemy_approach_distance(self, enemy_node)
	var current_distance := global_position.distance_to(enemy_node.global_position)

	# The desired distance is the furthest useful engagement distance, not an
	# exact point the player must hit. If map collision stops the player a little
	# closer than ideal, combat should still be allowed to start.
	return current_distance <= desired_distance + ENEMY_DISTANCE_TOLERANCE


func _move_close_to_enemy(enemy: Node, force_reposition: bool = false) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not (enemy is Node2D):
		return

	# Do not reset or focus the camera during enemy targeting.
	# Targeting should only move the player into engagement range.
	approach_enemy = enemy as Node2D

	var enemy_position := approach_enemy.global_position
	var desired_distance := get_enemy_approach_distance(self, approach_enemy)

	_face_global_position(enemy_position)

	var preferred_target := _get_best_enemy_approach_target(approach_enemy, desired_distance)

	# Normal targeting can stop if the player is already in a usable engagement
	# range. Battle attack buttons pass force_reposition=true so that, after the
	# player has backed away or ended up on the wrong/loose side, pressing attack
	# always tries to run them back to the closest free approach point before fighting.
	if not force_reposition and is_close_to_enemy(approach_enemy) and not _is_too_close_to_enemy(approach_enemy):
		mouse_mode = MouseMode.NONE
		click_target = Vector2.ZERO
		_reset_enemy_approach_candidates()
		_focus_camera_on_enemy(approach_enemy)
		_send_stop()
		return

	if force_reposition and global_position.distance_squared_to(preferred_target) <= CLICK_STOP_DISTANCE * CLICK_STOP_DISTANCE:
		mouse_mode = MouseMode.NONE
		click_target = Vector2.ZERO
		_reset_enemy_approach_candidates()
		_face_global_position(enemy_position)
		_send_stop()
		return

	enemy_approach_direction_away = (preferred_target - enemy_position).normalized()
	_set_enemy_approach_target(preferred_target)


func _is_too_close_to_enemy(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if not (enemy is Node2D):
		return false

	var enemy_node := enemy as Node2D
	var desired_distance := get_enemy_approach_distance(self, enemy_node)
	var current_distance := global_position.distance_to(enemy_node.global_position)

	return current_distance < desired_distance - ENEMY_TOO_CLOSE_TOLERANCE


func _try_enemy_alternate_position() -> bool:
	if approach_enemy == null or not is_instance_valid(approach_enemy):
		return false

	if enemy_approach_candidate_points.is_empty():
		var desired_distance := get_enemy_approach_distance(self, approach_enemy)
		_build_enemy_approach_candidates(approach_enemy, desired_distance)

	enemy_approach_candidate_index += 1

	while enemy_approach_candidate_index < enemy_approach_candidate_points.size():
		var next_target := enemy_approach_candidate_points[enemy_approach_candidate_index]
		if not _is_enemy_approach_point_occupied(next_target, approach_enemy):
			enemy_approach_direction_away = (next_target - approach_enemy.global_position).normalized()
			_set_enemy_approach_target(next_target)
			return true

		enemy_approach_candidate_index += 1

	return false


func _reset_enemy_approach_candidates() -> void:
	enemy_approach_candidate_points.clear()
	enemy_approach_candidate_index = 0
	enemy_approach_direction_away = Vector2.ZERO


func _get_best_enemy_approach_target(enemy: Node2D, desired_distance: float) -> Vector2:
	_build_enemy_approach_candidates(enemy, desired_distance)

	print("enemy_approach_candidate_points", enemy_approach_candidate_points)
	for i in range(enemy_approach_candidate_points.size()):
		var target := enemy_approach_candidate_points[i]
		if not _is_enemy_approach_point_occupied(target, enemy):
			enemy_approach_candidate_index = i
			return target

	enemy_approach_candidate_index = 0
	if enemy_approach_candidate_points.is_empty():
		return _get_enemy_side_target(enemy.global_position, _get_horizontal_enemy_approach_direction(enemy.global_position), desired_distance)

	return enemy_approach_candidate_points[0]


func _build_enemy_approach_candidates(enemy: Node2D, desired_distance: float) -> void:
	enemy_approach_candidate_points.clear()
	enemy_approach_candidate_index = 0

	var directions := _get_enemy_approach_directions(enemy)
	var enemy_position := enemy.global_position

	for direction in directions:
		if direction.length_squared() <= 0.001:
			continue

		# Directions define the generated/manual slots; distance is still controlled by
		# get_enemy_approach_distance(), which includes MIN_ENEMY_APPROACH_DISTANCE.
		enemy_approach_candidate_points.append(enemy_position + direction.normalized() * desired_distance)

	enemy_approach_candidate_points.sort_custom(Callable(self, "_sort_enemy_approach_points_by_player_distance"))


func _sort_enemy_approach_points_by_player_distance(a: Vector2, b: Vector2) -> bool:
	return global_position.distance_squared_to(a) < global_position.distance_squared_to(b)


func _get_enemy_approach_directions(enemy: Node2D) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var exported_directions = enemy.get("approach_point_directions")

	# Manual directions win if you set them on the Enemy.
	# Leave approach_point_directions empty to use approach_point_count instead.
	if exported_directions is PackedVector2Array:
		for direction in exported_directions:
			if direction is Vector2 and direction.length_squared() > 0.001:
				result.append(direction)

	if not result.is_empty():
		return result

	var point_count := 8
	var point_count_value = enemy.get("approach_point_count")
	if point_count_value is int:
		point_count = point_count_value
	elif point_count_value is float:
		point_count = int(point_count_value)
	point_count = clampi(point_count, 2, 32)

	var arc_degrees := 360.0
	var arc_degrees_value = enemy.get("approach_point_arc_degrees")
	if arc_degrees_value is float or arc_degrees_value is int:
		arc_degrees = float(arc_degrees_value)
	arc_degrees = clampf(arc_degrees, 45.0, 360.0)

	var offset_degrees := 0.0
	var offset_degrees_value = enemy.get("approach_point_arc_offset_degrees")
	if offset_degrees_value is float or offset_degrees_value is int:
		offset_degrees = float(offset_degrees_value)

	var step_degrees := 0.0
	if point_count > 1:
		step_degrees = 360.0 / float(point_count)

	if arc_degrees < 359.99 and point_count > 1:
		step_degrees = arc_degrees / float(point_count - 1)
		offset_degrees -= arc_degrees * 0.5

	for i in range(point_count):
		var angle := deg_to_rad(offset_degrees + step_degrees * float(i))
		result.append(Vector2(cos(angle), sin(angle)))

	return result


func _is_enemy_approach_point_occupied(target_global_position: Vector2, enemy: Node2D) -> bool:
	var occupancy_radius = max(get_collision_width(self), MIN_ENEMY_APPROACH_DISTANCE * 0.5)
	var occupancy_radius_sq = occupancy_radius * occupancy_radius

	for other_player in _get_other_visible_players_for_enemy_slots():
		if other_player == null or not is_instance_valid(other_player):
			continue
		if other_player == self:
			continue
		if not (other_player is Node2D):
			continue

		var other_node := other_player as Node2D

		# Only count players who are already close enough to be occupying one of this
		# enemy's slots. Players elsewhere in the scene should not reserve a point.
		if other_node.global_position.distance_to(enemy.global_position) > get_enemy_approach_distance(other_node, enemy) + occupancy_radius:
			continue

		if other_node.global_position.distance_squared_to(target_global_position) <= occupancy_radius_sq:
			return true

	return false


func _get_other_visible_players_for_enemy_slots() -> Array[Node]:
	var result: Array[Node] = []
	var scene_root := get_tree().root.get_node_or_null("Game/Map/Scene")
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return result

	_collect_player_slot_nodes(scene_root, result)
	return result


func _collect_player_slot_nodes(node: Node, result: Array[Node]) -> void:
	if node != self and node is Node2D:
		var node_name := str(node.name).to_lower()
		var script = node.get_script()
		var script_path := str(script.resource_path).to_lower() if script != null else ""

		if node_name.contains("remoteplayer") or script_path.ends_with("remote_player.gd") or node is Player:
			if not (node is CanvasItem) or (node as CanvasItem).visible:
				result.append(node)

	for child in node.get_children():
		_collect_player_slot_nodes(child, result)


func _get_horizontal_enemy_approach_direction(enemy_position: Vector2) -> Vector2:
	var x_direction : float = sign(global_position.x - enemy_position.x)

	if x_direction == 0:
		x_direction = -1 if facing > 0 else 1

	return Vector2(x_direction, 0.0)


func _get_enemy_side_target(enemy_position: Vector2, direction_away_from_enemy: Vector2, desired_distance: float) -> Vector2:
	var x_direction : float = sign(direction_away_from_enemy.x)

	if x_direction == 0:
		x_direction = -1 if facing > 0 else 1

	return Vector2(
		enemy_position.x + x_direction * desired_distance,
		enemy_position.y
	)


func _set_enemy_approach_target(target_global_position: Vector2) -> void:
	var target_local_position := target_global_position
	if get_parent() is Node2D:
		target_local_position = (get_parent() as Node2D).to_local(target_global_position)

	click_target = target_local_position
	mouse_mode = MouseMode.CLICK_MOVE
	follow_moving = false
	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0

	# Face the direction of the selected movement target before the first movement
	# packet is sent. The player will turn back toward the enemy after arriving.
	_face_click_target_direction()
	_send_move(click_target)


func _stop_enemy_approach_if_close() -> void:
	if approach_enemy == null or not is_instance_valid(approach_enemy):
		return

	if not is_close_to_enemy(approach_enemy):
		return

	_face_global_position(approach_enemy.global_position)
	_focus_camera_on_enemy(approach_enemy)
	approach_enemy = null
	_reset_enemy_approach_candidates()
	_send_stop()


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


func cancel_mouse_movement(reset_camera: bool = true) -> void:
	mouse_press_active = false
	hold_started = false
	mouse_mode = MouseMode.NONE
	follow_moving = false
	click_target = Vector2.ZERO
	approach_enemy = null
	_reset_enemy_approach_candidates()
	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0

	if reset_camera and camera_controller != null and camera_controller.has_method("reset_to_default_camera"):
		camera_controller.reset_to_default_camera()

	_send_stop()


func reset_after_area_change(new_position: Vector2, new_facing: int = 1, arrival_lock_key: String = "") -> void:
	# Scene/map changes reuse the same Player node. Without a full movement reset,
	# old click targets, hold-follow state, velocity and send throttles can carry
	# across for one or more physics frames and make the player appear to jolt or
	# run briefly after landing.
	movement_locked = true
	global_position = new_position
	position = new_position
	velocity = Vector2.ZERO
	actually_moving = false
	was_moving_last_frame = false
	mouse_press_active = false
	hold_started = false
	follow_moving = false
	mouse_mode = MouseMode.NONE
	click_target = Vector2.ZERO
	approach_enemy = null
	_reset_enemy_approach_candidates()
	attacking_pose_active = false
	last_sent_hold_target = Vector2.INF
	last_hold_send_time = 0.0
	last_position_send_time = 0.0
	last_sent_position = Vector2.INF
	active_teleport_trigger_key = arrival_lock_key

	set_facing_direction(new_facing)
	set_pose(PlayerPose.IDLE)
	prev_pose = PlayerPose.IDLE

	_apply_arrival_camera_facing()

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
	elif _should_hold_fight_pose():
		desired_pose = PlayerPose.FIGHT
	else:
		desired_pose = PlayerPose.IDLE

	if desired_pose != prev_pose:
		set_pose(desired_pose)


func _has_active_enemy_target() -> bool:
	return _get_active_enemy_target() != null


func _should_hold_fight_pose() -> bool:
	if attacking_pose_active:
		return true

	var enemy := _get_active_enemy_target()
	if enemy == null:
		return false

	# Keeping an enemy selected should not force the battle stance. If the
	# player manually backs away during battle, they should return to idle and
	# keep the direction they moved in. The fight pose comes back only after an
	# attack sends them back into the valid engagement position.
	return is_close_to_enemy(enemy) and not _is_too_close_to_enemy(enemy)


func _get_active_enemy_target() -> Node2D:
	var ui := game.get_node_or_null("UI") if game != null else null
	if ui == null:
		return null

	var enemy = ui.current_enemy_target
	if enemy != null and is_instance_valid(enemy) and enemy.visible and enemy is Node2D:
		return enemy as Node2D

	return null


func _is_player_in_battle() -> bool:
	var ui := game.get_node_or_null("UI") if game != null else null
	return ui != null and ui.has_method("is_player_in_battle") and ui.is_player_in_battle()


func set_pose(pose: PlayerPose) -> void:
	if animation_state == null:
		return

	if prev_pose == pose:
		return

	prev_pose = pose
	animation_state.travel(PlayerUtil.to_anim_name(pose))

	if not actually_moving:
		_send_stop()


func _update_camera_look_ahead() -> void:
	if camera_controller == null or not is_instance_valid(camera_controller):
		camera_controller = null
		return

	# While auto-moving into enemy engagement range, keep the camera where it is.
	# The enemy focus is only applied once the player reaches the chosen side of
	# the enemy, so the view does not jump ahead before the player arrives.
	if approach_enemy != null and is_instance_valid(approach_enemy):
		return

	# If the player is running while an enemy is targeted,
	# do not keep the enemy-focus camera offset active.
	if actually_moving and _has_active_enemy_target():
		var ui := game.get_node_or_null("UI")
		var enemy = ui.current_enemy_target if ui != null else null

		if enemy != null and is_instance_valid(enemy):
			var to_enemy_x = sign(enemy.global_position.x - global_position.x)
			var moving_x = sign(velocity.x)

			if moving_x != 0 and moving_x != to_enemy_x:
				if camera_controller.has_method("reset_to_default_camera"):
					camera_controller.reset_to_default_camera()
				elif camera_controller.has_method("clear_enemy_focus"):
					camera_controller.clear_enemy_focus()

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

	# Keep the camera biased toward the direction the player is facing even
	# after movement stops. Previously velocity.x became 0 when stationary,
	# which made the camera drift back to centered.
	if abs(horizontal_amount) <= 0.01:
		horizontal_amount = float(last_facing)

	camera_controller.set_look_ahead_direction(clamp(horizontal_amount, -1.0, 1.0))


func _is_enemy_approach_moving() -> bool:
	return approach_enemy != null \
		and is_instance_valid(approach_enemy) \
		and mouse_mode == MouseMode.CLICK_MOVE


func _face_click_target_direction() -> bool:
	if mouse_mode != MouseMode.CLICK_MOVE:
		return false

	var to_target := click_target - position
	if abs(to_target.x) <= MOVE_THRESHOLD:
		return false

	last_facing = sign(to_target.x)
	facing = last_facing
	_apply_facing()
	return true


func _update_facing_from_movement(movement_delta: Vector2) -> void:
	# Any time the player is physically moving, face the real travel direction.
	# This fixes battle movement where backing away from a targeted enemy could
	# keep the player visually locked toward the enemy and make them run backward.
	if abs(movement_delta.x) > 2.0:
		last_facing = sign(movement_delta.x)
		facing = last_facing
		_apply_facing()
		return

	# While auto-approaching a targeted enemy, fall back to the chosen click target
	# until movement_delta becomes large enough to show the real direction.
	if _is_enemy_approach_moving():
		_face_click_target_direction()
		facing = last_facing
		_apply_facing()
		return

	# Once stopped in battle, face the selected enemy again.
	if _face_enemy_target_if_active():
		return

	if mouse_mode == MouseMode.HOLD_FOLLOW and mouse_press_active:
		var screen_dir := _get_screen_mouse_direction()
		if abs(screen_dir.x) > FOLLOW_STOP_DISTANCE:
			last_facing = sign(screen_dir.x)

	facing = last_facing
	_apply_facing()


func _update_facing_towards_approach_enemy() -> void:
	# Do not override movement-facing while the player is still running to the
	# selected engagement point. Once movement stops, the stop path faces the enemy.
	if _is_enemy_approach_moving():
		return

	_face_enemy_target_if_active()


func _face_enemy_target_if_active() -> bool:
	var enemy: Node2D = null

	if approach_enemy != null and is_instance_valid(approach_enemy):
		enemy = approach_enemy
	else:
		enemy = _get_active_enemy_target()

	if enemy == null:
		return false

	# Do not snap the player back to facing the enemy after they manually move
	# away in battle. Keep their last movement-facing direction until they press
	# another attack/target action, which calls move_close_to_enemy() again.
	if approach_enemy == null and (not is_close_to_enemy(enemy) or _is_too_close_to_enemy(enemy)):
		return false

	_face_global_position(enemy.global_position)
	return true


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


func _swap_facing_direction() -> void:
	last_facing *= -1
	if last_facing == 0:
		last_facing = -1
	facing = last_facing
	_apply_facing()
	_send_stop()


func _is_mouse_over_player() -> bool:
	var mouse_pos := get_global_mouse_position()
	var shape_node := find_child("CollisionShape2D", true, false) as CollisionShape2D

	if shape_node == null or shape_node.shape == null:
		return global_position.distance_squared_to(mouse_pos) <= 64.0 * 64.0

	var local_mouse := shape_node.to_local(mouse_pos)
	var shape := shape_node.shape

	if shape is RectangleShape2D:
		var half_size = shape.size * 0.5
		return abs(local_mouse.x) <= half_size.x and abs(local_mouse.y) <= half_size.y

	if shape is CircleShape2D:
		return local_mouse.length_squared() <= shape.radius * shape.radius

	if shape is CapsuleShape2D:
		var half_height = max(shape.height * 0.5, shape.radius)
		return abs(local_mouse.x) <= shape.radius and abs(local_mouse.y) <= half_height

	return global_position.distance_squared_to(mouse_pos) <= 64.0 * 64.0


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


func _focus_camera_on_enemy(_enemy: Node2D) -> void:
	# Intentionally disabled for enemy targeting. The player can move next to the
	# enemy, but targeting must not shift/focus the camera toward that enemy.
	return


func _send_position_if_needed() -> void:
	if not actually_moving:
		_face_enemy_target_if_active()
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
		"instance": SceneManager.current_instance,
	})


func _send_move(_target: Vector2) -> void:
	if _is_enemy_approach_moving():
		_face_click_target_direction()
	else:
		_face_enemy_target_if_active()

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
		"instance": SceneManager.current_instance,
	})


func _send_stop() -> void:
	_face_enemy_target_if_active()

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
		"instance": SceneManager.current_instance,
	})
