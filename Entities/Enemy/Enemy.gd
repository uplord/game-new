@tool
extends Node2D

signal targeted(enemy: Node)

@export var enemy_definition_id := "slime_001"

@export_category("Model")
@export var model_data: ModelData:
	set(value):
		model_data = value
		_sync_model_options()

@export var animation_tree_enabled := false:
	set(value):
		animation_tree_enabled = value
		_sync_model_options()

@export var keep_animation_tree_for_player := false:
	set(value):
		keep_animation_tree_for_player = value
		_sync_model_options()

@export var starting_pose: PlayerUtil.PlayerPose = PlayerUtil.PlayerPose.IDLE:
	set(value):
		starting_pose = value
		_sync_model_options()


@export_category("Targeting")
@export var enemy_name := "Enemy"
@export var max_hp := 100.0
@export var hp := 100.0
@export var max_mp := 100.0
@export var mp := 100.0
@export var respawn_seconds := 10.0
@export var reward_gold_min := 0
@export var reward_gold_max := 0
@export var reward_xp: Dictionary = {}


@export_category("Approach Points")
@export_range(2, 32, 1) var approach_point_count: int = 8:
	set(value):
		approach_point_count = clampi(int(value), 2, 32)
		queue_redraw()

@export_range(45.0, 360.0, 1.0) var approach_point_arc_degrees: float = 360.0:
	set(value):
		approach_point_arc_degrees = clampf(float(value), 45.0, 360.0)
		queue_redraw()

@export_range(-360.0, 360.0, 1.0) var approach_point_arc_offset_degrees: float = 0.0:
	set(value):
		approach_point_arc_offset_degrees = float(value)
		queue_redraw()

@export var approach_point_directions: PackedVector2Array = PackedVector2Array():
	set(value):
		approach_point_directions = value
		queue_redraw()


@export_category("Approach Point Debug")
@export var show_approach_points := true:
	set(value):
		show_approach_points = value
		queue_redraw()

# These preview values only affect the yellow editor circles.
# They mirror Player.gd, so the circles represent the player's center/origin
# position when standing in an approach slot.
@export var approach_point_debug_player_width := 140.0:
	set(value):
		approach_point_debug_player_width = maxf(value, 1.0)
		queue_redraw()

@export var approach_point_debug_engagement_padding := 32.0:
	set(value):
		approach_point_debug_engagement_padding = maxf(value, 0.0)
		queue_redraw()

@export var approach_point_debug_min_distance := 32.0:
	set(value):
		approach_point_debug_min_distance = maxf(value, 1.0)
		queue_redraw()

@export var approach_point_debug_radius := 6.0:
	set(value):
		approach_point_debug_radius = maxf(value, 1.0)
		queue_redraw()


@onready var body: Node = $Base/Model

var is_selected := false
var enemy_definition_loaded := false


func _ready() -> void:
	_sync_model_options()

	if Engine.is_editor_hint():
		set_process(true)
		return

	add_to_group("targetable_enemies")
	_connect_target_area()
	_load_enemy_definition()


func _load_enemy_definition() -> void:
	if enemy_definition_id.strip_edges() == "":
		return

	if Firebase.has_signal("enemy_definition_loaded") and not Firebase.enemy_definition_loaded.is_connected(_on_enemy_definition_loaded):
		Firebase.enemy_definition_loaded.connect(_on_enemy_definition_loaded)

	if Firebase.has_method("load_enemy_definition"):
		Firebase.load_enemy_definition(enemy_definition_id)


func _on_enemy_definition_loaded(definition_id: String, data: Dictionary) -> void:
	if definition_id != enemy_definition_id:
		return
	_apply_enemy_definition(data)


func _apply_enemy_definition(data: Dictionary) -> void:
	if data.is_empty():
		return

	enemy_definition_loaded = true
	enemy_name = str(data.get("name", enemy_name))
	max_hp = max(1.0, float(data.get("max_hp", max_hp)))
	hp = max_hp
	max_mp = max(0.0, float(data.get("max_mp", max_mp)))
	mp = max_mp
	respawn_seconds = max(0.0, float(data.get("respawn_seconds", respawn_seconds)))

	_apply_enemy_definition_rewards(data)


func _apply_enemy_definition_rewards(data: Dictionary) -> void:
	var rewards = data.get("rewards", {})
	if rewards is Dictionary:
		reward_gold_min = int((rewards as Dictionary).get("gold_min", reward_gold_min))
		reward_gold_max = int((rewards as Dictionary).get("gold_max", reward_gold_max))

	var xp = rewards.get("xp", {})
	if xp is Dictionary:
		reward_xp = _normalize_reward_xp(xp as Dictionary)


func _normalize_reward_xp(xp: Dictionary) -> Dictionary:
	var normalized := {}
	for skill_id in ["melee", "defence", "magic", "healing"]:
		normalized[skill_id] = max(0, int(xp.get(skill_id, 0)))
	return normalized


func _refresh_rewards_from_cached_definition() -> void:
	if enemy_definition_id.strip_edges() == "":
		return
	if not Firebase.has_method("get_enemy_definition"):
		return

	var cached_definition = Firebase.get_enemy_definition(enemy_definition_id)
	if cached_definition is Dictionary and not (cached_definition as Dictionary).is_empty():
		_apply_enemy_definition_rewards(cached_definition as Dictionary)


func get_enemy_battle_data() -> Dictionary:
	# get_enemy_battle_data() can be called by the UI at the same time the
	# Firestore request is finishing. Pull from the Firebase cache here too so
	# the server receives enemy_definition.xp, not an empty reward_xp map.
	_refresh_rewards_from_cached_definition()

	return {
		"enemy_definition_id": enemy_definition_id,
		"enemy_name": enemy_name,
		"enemy_hp": hp,
		"enemy_max_hp": max_hp,
		"enemy_mp": mp,
		"enemy_max_mp": max_mp,
		"enemy_respawn_seconds": respawn_seconds,
		"enemy_reward_gold_min": reward_gold_min,
		"enemy_reward_gold_max": reward_gold_max,
		"enemy_reward_xp": reward_xp.duplicate(true),
	}


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	if not show_approach_points:
		return

	var directions := get_approach_point_directions()
	var desired_distance := get_debug_approach_distance()

	for i in range(directions.size()):
		var direction := directions[i]
		if direction.length_squared() <= 0.0001:
			continue

		var point_global := global_position + direction.normalized() * desired_distance
		var local_point := to_local(point_global)

		draw_circle(local_point, approach_point_debug_radius + 2.0, Color.BLACK)
		draw_circle(local_point, approach_point_debug_radius, Color.YELLOW)

		draw_line(Vector2.ZERO, local_point, Color.YELLOW, 1.0)

		draw_string(
			ThemeDB.fallback_font,
			local_point + Vector2(8.0, -8.0),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color.WHITE
		)


func get_debug_approach_distance() -> float:
	var spacing_scale := _get_debug_spacing_scale()
	var player_half := approach_point_debug_player_width * spacing_scale * 0.5
	var enemy_half := get_debug_collision_width() * 0.5

	return max(
		player_half + enemy_half + approach_point_debug_engagement_padding * spacing_scale,
		approach_point_debug_min_distance * spacing_scale
	)


func get_debug_collision_width() -> float:
	var shape_node := find_child("CollisionShape2D", true, false) as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return approach_point_debug_min_distance * _get_debug_spacing_scale()

	var shape := shape_node.shape
	var scale_x : float = abs(shape_node.global_scale.x)

	if shape is RectangleShape2D:
		return shape.size.x * scale_x

	if shape is CapsuleShape2D:
		return shape.radius * 2.0 * scale_x

	if shape is CircleShape2D:
		return shape.radius * 2.0 * scale_x

	return approach_point_debug_min_distance * _get_debug_spacing_scale()


func _get_debug_spacing_scale() -> float:
	return max(0.001, (abs(global_scale.x) + abs(global_scale.y)) * 0.5)


func get_approach_point_directions() -> PackedVector2Array:
	if approach_point_directions.size() > 0:
		return approach_point_directions

	var directions := PackedVector2Array()

	var count := clampi(approach_point_count, 2, 32)
	var arc := deg_to_rad(approach_point_arc_degrees)
	var offset := deg_to_rad(approach_point_arc_offset_degrees)

	if is_equal_approx(approach_point_arc_degrees, 360.0):
		for i in range(count):
			var angle := offset + TAU * float(i) / float(count)
			directions.append(Vector2.RIGHT.rotated(angle))
	else:
		for i in range(count):
			var t := 0.0
			if count > 1:
				t = float(i) / float(count - 1)

			var angle := offset - arc * 0.5 + arc * t
			directions.append(Vector2.RIGHT.rotated(angle))

	return directions


func set_selected(value: bool) -> void:
	is_selected = value

	var model_node := get_node_or_null("Base/Model")
	if model_node == null:
		return

	var shadow := model_node.find_child("Shadow", true, false)
	if shadow == null:
		return

	if shadow.material:
		shadow.material = shadow.material.duplicate()

	shadow.modulate = Color.WHITE

	if value:
		shadow.material.set_shader_parameter("selected", true)
	else:
		shadow.material.set_shader_parameter("selected", false)


func _sync_model_options() -> void:
	var model_node := get_node_or_null("Base/Model")
	if model_node == null:
		return

	model_node.set("model_data", model_data)
	model_node.set("animation_tree_enabled", animation_tree_enabled)
	model_node.set("keep_animation_tree_for_player", keep_animation_tree_for_player)
	model_node.set("starting_pose", starting_pose)


func _connect_target_area() -> void:
	var model_node := get_node_or_null("Base/Model")
	if model_node == null or not model_node.has_method("get_target_area"):
		return

	var target_area: Area2D = model_node.get_target_area()
	if target_area != null and not target_area.input_event.is_connected(_on_target_area_input_event):
		target_area.input_event.connect(_on_target_area_input_event)


func _on_target_area_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return

	if not event is InputEventMouseButton:
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	target()
	get_viewport().set_input_as_handled()


func target() -> void:
	if Engine.is_editor_hint():
		return

	targeted.emit(self)
	_cancel_player_mouse_movement()
	_show_enemy_card()
	_move_player_close_to_self()


func _move_player_close_to_self() -> void:
	var player := SceneManager.player
	if player != null and is_instance_valid(player) and player.has_method("move_close_to_enemy"):
		player.move_close_to_enemy(self)


func _show_enemy_card() -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game == null:
		return

	var ui := game.get_node_or_null("UI")
	if ui != null and ui.has_method("show_enemy_card"):
		ui.show_enemy_card(self)


func _cancel_player_mouse_movement() -> void:
	var player := SceneManager.player
	if player != null and is_instance_valid(player) and player.has_method("cancel_mouse_movement"):
		player.cancel_mouse_movement(false)
