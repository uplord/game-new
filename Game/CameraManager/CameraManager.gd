extends Node

@onready var map = get_tree().root.get_node("Game/Map")
@onready var phantom_camera = $PhantomCamera2D
@onready var camera_limits = map.get_node("Scene/Boundaries/CameraLimits")

@onready var bar_left: ColorRect = $Cover/BarLeft
@onready var bar_right: ColorRect = $Cover/BarRight
@onready var bar_top: ColorRect = $Cover/BarTop
@onready var bar_bottom: ColorRect = $Cover/BarBottom

@export var look_ahead_speed := 4.0
@export var enemy_focus_speed := 7.0
@export var enemy_focus_center_distance := 120.0
@export_range(0.0, 1.0, 0.01) var enemy_focus_center_screen_ratio := 0.20

const MAX_LANDSCAPE_ASPECT := 16.0 / 9.0
const BASE_SIZE := Vector2(735, 735)

var map_scale := 1.0
var game_offset := 0.0

var current_look_ahead := 0.0
var target_look_ahead := 0.0
var look_ahead_distance := 0.0

var enemy_focus_active := false
var enemy_focus_direction := 0.0

var current_game_offset := 0.0


func _ready():
	get_window().size_changed.connect(_on_window_resized)
	call_deferred("_init_camera")


func _process(delta):
	var desired_look_ahead := target_look_ahead

	if enemy_focus_active:
		desired_look_ahead = enemy_focus_direction

	var active_speed := enemy_focus_speed if enemy_focus_active else look_ahead_speed

	current_look_ahead = lerp(
		current_look_ahead,
		desired_look_ahead,
		1.0 - exp(-active_speed * delta)
	)
	
	current_game_offset = lerp(
		float(current_game_offset),
		float(game_offset),
		1.0 - exp(-look_ahead_speed * delta)
	)

	var new_offset := Vector2(
		current_look_ahead * look_ahead_distance,
		-current_game_offset
	)

	if phantom_camera.follow_offset.distance_squared_to(new_offset) > 0.01:
		phantom_camera.follow_offset = new_offset


func _init_camera():
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().size_changed.emit()


func _on_window_resized():
	apply_orientation_zoom()
	apply_black_bars()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_camera_limits()


func get_map_scale() -> float:
	return map_scale


func set_look_ahead_direction(dir: float) -> void:
	target_look_ahead = clamp(dir, -1.0, 1.0)


func reset_to_default_camera() -> void:
	enemy_focus_active = false
	enemy_focus_direction = 0.0
	target_look_ahead = 0.0


func apply_orientation_zoom():
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size := get_viewport().get_visible_rect().size
	
	look_ahead_distance = clamp((screen_size.x * 0.5) - 96.0, 80.0, 280.0)

	if screen_size.y > screen_size.x:
		var top_safe := float(safe_area.position.y / DisplayServer.screen_get_scale())
		var bottom_safe := screen_size.y - float((safe_area.position.y + safe_area.size.y) / DisplayServer.screen_get_scale())
		var screen_extra := (screen_size.y - screen_size.x) / 2.0
		var remaining_height := screen_size.y - screen_extra - top_safe - bottom_safe
		map_scale = remaining_height / BASE_SIZE.x
		game_offset = ((screen_extra + top_safe) - bottom_safe) / 2.0
	else:
		map_scale = screen_size.y / BASE_SIZE.y
		game_offset = 0.0
	print("map_scale: ", map_scale)
	map.scale = Vector2.ONE * map_scale

func apply_camera_limits() -> void:
	var shape = camera_limits.shape
	if shape == null:
		return

	var rect := shape as RectangleShape2D
	if rect == null:
		return

	var extents: Vector2 = rect.extents
	var t: Transform2D = camera_limits.global_transform
	
	var top_left: Vector2 = t * Vector2(-extents.x, -extents.y)
	var top_right: Vector2 = t * Vector2(extents.x, -extents.y)
	var bottom_left: Vector2 = t * Vector2(-extents.x, extents.y)
	var bottom_right: Vector2 = t * Vector2(extents.x, extents.y)
	
	var min_x = min(top_left.x, bottom_left.x)
	var max_x = max(top_right.x, bottom_right.x)
	var min_y = min(bottom_left.y, top_right.y)
	var max_y = max(top_left.y, bottom_right.y)
	var offset_y := game_offset

	phantom_camera.limit_left = min_x
	phantom_camera.limit_right = max_x
	phantom_camera.limit_top = min_y - offset_y
	phantom_camera.limit_bottom = max_y - offset_y


func is_mobile() -> bool:
	return OS.has_feature("android") or (
		OS.has_feature("ios") and not OS.has_feature("ipad")
	)


func apply_black_bars() -> void:
	if is_mobile():
		bar_left.visible = false
		bar_right.visible = false
		bar_top.visible = false
		bar_bottom.visible = false
		return

	var screen_size := get_viewport().get_visible_rect().size
	var aspect := screen_size.x / screen_size.y

	# No bars in portrait
	if aspect <= MAX_LANDSCAPE_ASPECT:
		bar_left.visible = false
		bar_right.visible = false
		bar_top.visible = false
		bar_bottom.visible = false
		return

	var target_width := screen_size.y * MAX_LANDSCAPE_ASPECT
	var bar_width := (screen_size.x - target_width) * 0.5

	bar_left.position = Vector2.ZERO
	bar_left.size = Vector2(bar_width, screen_size.y)

	bar_right.position = Vector2(screen_size.x - bar_width, 0.0)
	bar_right.size = Vector2(bar_width, screen_size.y)

	bar_left.visible = true
	bar_right.visible = true

	bar_top.visible = false
	bar_bottom.visible = false


func focus_enemy(direction: float) -> void:
	enemy_focus_active = true
	enemy_focus_direction = clamp(direction, -1.0, 1.0)


func focus_enemy_for_positions(player_x: float, enemy_x: float) -> void:
	var x_distance := enemy_x - player_x
	var center_distance := _get_enemy_focus_center_distance()

	# If the target is close enough on the X axis, keep the player centered.
	# If it is far away, offset the camera so the player sits on the opposite edge.
	if abs(x_distance) <= center_distance:
		focus_enemy(0.0)
	else:
		var max_focus_distance := center_distance * 3.0
		var focus_amount = clamp(x_distance / max_focus_distance, -1.0, 1.0)
		focus_enemy(focus_amount)


func _get_enemy_focus_center_distance() -> float:
	var screen_size := get_viewport().get_visible_rect().size
	var playable_width := screen_size.x

	if not is_mobile():
		var aspect := screen_size.x / screen_size.y
		if aspect > MAX_LANDSCAPE_ASPECT:
			playable_width = screen_size.y * MAX_LANDSCAPE_ASPECT

	var playable_world_width = playable_width / max(map_scale, 0.001)

	return max(
		enemy_focus_center_distance,
		playable_world_width * enemy_focus_center_screen_ratio
	)

func clear_enemy_focus() -> void:
	enemy_focus_active = false
