extends Node

signal map_status_changed

@onready var game =  get_tree().root.get_node("Game")
@onready var loading_screen: ColorRect = game.get_node("CanvasLayer/LoadingScreen")
@onready var loading_title: Label = game.get_node("CanvasLayer/LoadingScreen/CenterContainer/VBoxContainer/Title")
@onready var loading_message: Label = game.get_node("CanvasLayer/LoadingScreen/CenterContainer/VBoxContainer/Message")

@export var current_map: String = ""
@export var current_scene: String = ""
@export var current_instance: int = 1
@export var current_map_population: int = 0

var default_map := "starter_town"
var default_scene := "scene1"

var DebugLogger = preload("res://utilities/logger.gd")

var logger: Node
var map: Node
var phantom_camera: Node

var resize_timer: Timer

var player_scene = preload("res://entities/player/player.tscn")
var remote_player_scene = preload("res://entities/remote_player/remote_player.tscn")

var player: Node2D

var spawn_requested := false
var teleport_arrival_lock_key := ""

var remote_players := {}


# --------------------------------------------------
# SETUP
# --------------------------------------------------
func setup(_scene_container: Node):
	logger = DebugLogger.new()
	add_child(logger)
	
	resize_timer = Timer.new()
	resize_timer.one_shot = true
	resize_timer.wait_time = 0.6
	add_child(resize_timer)

	resize_timer.timeout.connect(func():
		_fade_in()
	)

	current_map = default_map
	current_scene = default_scene
	current_instance = 1
	current_map_population = 0
	map_status_changed.emit()


# --------------------------------------------------
# MAP
# --------------------------------------------------
func load_map() -> void:
	_show_loading_screen("Loading", "Preparing map...")
	await get_tree().process_frame
	
	if map:
		map.queue_free()
		map = null

	var map_path = "res://maps/%s/map.tscn" % [
		current_map
	]
	
	var packed_scene = load(map_path)

	if packed_scene == null:
		logger.error("Failed loading map: %s" % map_path)
		return

	_show_loading_screen("Loading", "Building map...")
	map = packed_scene.instantiate()
	game.add_child(map)
	map_status_changed.emit()

	# Load the current scene first because CameraManager reads:
	# Game/Map/Scene/Boundaries/CameraLimits during its @onready setup.
	load_scene(current_scene)

	await get_tree().process_frame

	_show_loading_screen("Loading", "Loading scene...")
	await get_tree().process_frame

	# Then create the camera, and only after that attach it to the player.
	_show_loading_screen("Loading", "Setting up camera...")
	await load_camera()
	await get_tree().process_frame

	_show_loading_screen("Loading", "Spawning player...")
	await _setup_player()

	await get_tree().create_timer(1.0).timeout
	
	_show_loading_screen("", "")
	await get_tree().process_frame

	await _hide_loading_screen()


func unload_map() -> void:
	clear_remote_players()

	if player and is_instance_valid(player):
		player.queue_free()
		player = null

	if map:
		map.queue_free()
		map = null

	spawn_requested = false
	current_instance = 1
	current_map_population = 0
	map_status_changed.emit()


# --------------------------------------------------
# SCENE
# --------------------------------------------------
func load_scene(scene_name: String) -> void:
	current_scene = scene_name
	map_status_changed.emit()

	if not map:
		return

	for child in map.get_children():
		if child.name.begins_with("Scene"):
			map.remove_child(child)
			child.free()

	var path := "res://maps/%s/scenes/%s.tscn" % [current_map, scene_name]
	
	var packed = load(path)
	
	if packed == null:
		logger.error("Failed loading scene: %s" % path)
		return
	
	var scene = packed.instantiate()
	scene.name = "Scene"
	
	map.add_child(scene)


# --------------------------------------------------
# PLAYER
# --------------------------------------------------
func _setup_player():
	if player == null:
		player = player_scene.instantiate()
		player.add_to_group("player")

	var player_parent = map.get_node_or_null("Players")
	if player_parent == null:
		player_parent = Node2D.new()
		player_parent.name = "Players"
		map.add_child(player_parent)

	if player.get_parent():
		player.get_parent().remove_child(player)

	player_parent.add_child(player)
	
	player.visible = false

	await get_tree().process_frame

	phantom_camera = game.get_node_or_null("CameraManager/PhantomCamera2D")
	if phantom_camera:
		phantom_camera.follow_target = player
	else:
		logger.error("Failed finding PhantomCamera2D after loading camera")

	if not spawn_requested:
		spawn_requested = true

		ServerManager.send_to_server({
			"type": "c_spawn_player",
		})


func set_map_status(
	map_name: String,
	scene_name: String,
	instance: int,
	population: int
) -> void:
	current_map = map_name
	current_scene = scene_name
	current_instance = instance
	current_map_population = population
	map_status_changed.emit()


func set_map_population(population: int) -> void:
	current_map_population = population
	map_status_changed.emit()



# --------------------------------------------------
# TELEPORTS
# --------------------------------------------------
func teleport_player_to(
	map_name: String,
	scene_name: String,
	position: Vector2,
	facing: int = 1,
	arrival_teleport_name: String = "",
	instance: int = 1,
	population: int = 0
) -> void:
	_show_loading_screen("Loading", "Changing area...")

	if player and is_instance_valid(player):
		player.movement_locked = true
		player.velocity = Vector2.ZERO

	await get_tree().process_frame

	_clear_local_battle_for_area_change()

	var map_changed := map_name != current_map
	current_map = map_name
	current_scene = scene_name
	current_instance = instance
	current_map_population = population
	map_status_changed.emit()

	if map_changed:
		if map:
			map.queue_free()
			map = null

		var map_path := "res://maps/%s/map.tscn" % current_map
		var packed_map = load(map_path)
		if packed_map == null:
			logger.error("Failed loading map: %s" % map_path)
			return

		map = packed_map.instantiate()
		game.add_child(map)

	load_scene(current_scene)
	await get_tree().process_frame

	clear_remote_players()

	await load_camera()
	await get_tree().process_frame

	await _setup_player()

	teleport_arrival_lock_key = _make_teleport_lock_key(current_map, current_scene, arrival_teleport_name)

	if player and is_instance_valid(player):
		player.visible = true
		if player.has_method("reset_after_area_change"):
			player.reset_after_area_change(position, facing, teleport_arrival_lock_key)
		else:
			player.position = position
			player.velocity = Vector2.ZERO
			if player.has_method("set_facing_direction"):
				player.set_facing_direction(facing)
			if player.has_method("cancel_mouse_movement"):
				player.cancel_mouse_movement(false)

	ServerManager.send_to_server({
		"type": "c_request_sync"
	})

	await get_tree().process_frame
	
	_show_loading_screen("", "")
	await get_tree().process_frame
	
	await _hide_loading_screen()



func _clear_local_battle_for_area_change() -> void:
	var ui := game.get_node_or_null("UI") if game != null else null
	if ui != null and ui.has_method("hide_enemy_card"):
		ui.hide_enemy_card(true)
	if ui != null and ui.has_method("apply_battle_state"):
		ui.apply_battle_state({
			"player": {
				"hp": ui.battle_state.get("player", {}).get("hp", 100.0) if ui.get("battle_state") != null else 100.0,
				"max_hp": ui.battle_state.get("player", {}).get("max_hp", 100.0) if ui.get("battle_state") != null else 100.0,
				"mp": ui.battle_state.get("player", {}).get("mp", 100.0) if ui.get("battle_state") != null else 100.0,
				"max_mp": ui.battle_state.get("player", {}).get("max_mp", 100.0) if ui.get("battle_state") != null else 100.0,
				"in_battle": false,
				"target_enemy_id": "",
			},
			"enemy": {},
		})

	if player != null and is_instance_valid(player):
		if player.has_method("cancel_mouse_movement"):
			player.cancel_mouse_movement(false)
		player.set("attacking_pose_active", false)

func get_teleport_lock_key() -> String:
	return teleport_arrival_lock_key


func clear_teleport_lock_if_matches(lock_key: String) -> void:
	if teleport_arrival_lock_key == lock_key:
		teleport_arrival_lock_key = ""


func make_teleport_lock_key(map_name: String, scene_name: String, teleport_name: String) -> String:
	return _make_teleport_lock_key(map_name, scene_name, teleport_name)


func _make_teleport_lock_key(map_name: String, scene_name: String, teleport_name: String) -> String:
	if teleport_name == "":
		return ""
	return "%s::%s::%s" % [map_name, scene_name, teleport_name]


# --------------------------------------------------
# CAMERA
# --------------------------------------------------
func unload_camera() -> void:
	if phantom_camera and is_instance_valid(phantom_camera):
		phantom_camera = null

	if not game:
		return

	for child in game.get_children():
		if child.name == "CameraManager":
			child.queue_free()


func load_camera() -> void:
	if not game:
		return

	for child in game.get_children():
		if child.name == "CameraManager":
			child.queue_free()

	await get_tree().process_frame

	var path := "res://game/camera_manager/camera_manager.tscn"

	var packed = load(path)

	if packed == null:
		logger.error("Failed camera scene")
		return

	var scene = packed.instantiate()

	game.add_child(scene)
	
	await get_tree().process_frame
	await get_tree().process_frame


# --------------------------------------------------
# REMOTE PLAYERS
# --------------------------------------------------
func clear_remote_players():
	for p in remote_players.values():
		_free_remote_player_now(p)

	remote_players.clear()


func _free_remote_player_now(remote_player: Node) -> void:
	if not is_instance_valid(remote_player):
		return

	# Do not leave the old remote visible until the end of the frame.
	# This matters during scene teleports because queue_free() alone can let
	# the remote render once at its old scene position before the sync arrives.
	remote_player.visible = false
	remote_player.set_process(false)
	remote_player.set_physics_process(false)

	var parent := remote_player.get_parent()
	if parent != null:
		parent.remove_child(remote_player)

	remote_player.queue_free()


func spawn_remote_player(id: int, pos: Vector2, facing: int = 1, remote_velocity: Vector2 = Vector2.ZERO, pose: int = 0, sequence: int = -1, stopped: bool = false, reserved_approach_target: Vector2 = Vector2.INF):
	if remote_players.has(id):
		_free_remote_player_now(remote_players[id])
		remote_players.erase(id)

	var remote_player = remote_player_scene.instantiate()
	remote_player.position = pos
	if remote_player.has_method("set_initial_facing"):
		remote_player.set_initial_facing(facing)
	if remote_player.has_method("set_remote_state"):
		remote_player.set_remote_state(pos, remote_velocity, sequence, stopped, pose, facing, reserved_approach_target)
	else:
		remote_player.set_target_position(pos)

	var player_parent = map.get_node_or_null("Players")
	if player_parent == null:
		player_parent = Node2D.new()
		player_parent.name = "Players"
		map.add_child(player_parent)

	player_parent.add_child(remote_player)
	remote_players[id] = remote_player


func update_remote_player(id: int, pos: Vector2, facing: int = 1, remote_velocity: Vector2 = Vector2.ZERO, pose: int = 0, sequence: int = -1, stopped: bool = false, reserved_approach_target: Vector2 = Vector2.INF):
	if not remote_players.has(id):
		spawn_remote_player(id, pos, facing, remote_velocity, pose, sequence, stopped, reserved_approach_target)
		return

	var p = remote_players[id]

	if not is_instance_valid(p):
		remote_players.erase(id)
		return

	if p.has_method("set_remote_state"):
		p.set_remote_state(pos, remote_velocity, sequence, stopped, pose, facing, reserved_approach_target)
	elif p.has_method("set_target_position"):
		p.set_target_position(pos)
	else:
		p.position = pos


func remove_remote_player(id: int):
	if not remote_players.has(id):
		return

	_free_remote_player_now(remote_players[id])
	remote_players.erase(id)


# --------------------------------------------------
# LOADING SCREEN
# --------------------------------------------------
func _show_loading_screen(title: String = "Loading", message: String = "") -> void:
	var main_menu = game.get_node("MainMenu")
	main_menu.visible = false
	loading_screen.visible = true
	loading_screen.modulate.a = 1.0
	loading_title.text = title
	loading_message.text = message


func _hide_loading_screen() -> void:
	if player and is_instance_valid(player):
		player.movement_locked = true
		player.velocity = Vector2.ZERO
		player.mouse_mode = player.MouseMode.NONE
		player.follow_moving = false

	loading_screen.visible = true
	loading_screen.modulate.a = 1.0

	var tween = create_tween()
	tween.tween_property(loading_screen, "modulate:a", 0.0, 1.0)

	await tween.finished

	loading_screen.visible = false

	if player and is_instance_valid(player):
		player.movement_locked = false


# FADE FUNCTIONS
# --------------------------------------------------
func _fade_in():
	if player and is_instance_valid(player):
		player.movement_locked = true
		player.velocity = Vector2.ZERO
		player.mouse_mode = player.MouseMode.NONE
		player.follow_moving = false

	loading_screen.visible = true
	loading_screen.modulate.a = 1.0

	var tween = create_tween()
	tween.tween_property(loading_screen, "modulate:a", 0.0, 1.0)

	await tween.finished

	loading_screen.visible = false

	if player and is_instance_valid(player):
		player.movement_locked = false
