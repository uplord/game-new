extends Node

@onready var game =  get_tree().root.get_node("Game")

@export var current_map: String = ""
@export var current_scene: String = ""
@export var current_instance: int = 1

var default_map := "StarterTown"
var default_scene := "Scene1"

var DebugLogger = preload("res://Utilities/Logger.gd")

var logger: Node
var map: Node
var phantom_camera: Node
var fade_cover: Node

var player_scene = preload("res://Entities/Player/Player.tscn")
var remote_player_scene = preload("res://Entities/RemotePlayer/RemotePlayer.tscn")

var player: Node2D

var spawn_requested := false

var remote_players := {}


# --------------------------------------------------
# SETUP
# --------------------------------------------------
func setup(_scene_container: Node):
	logger = DebugLogger.new()
	add_child(logger)

	current_map = default_map
	current_scene = default_scene


# --------------------------------------------------
# MAP
# --------------------------------------------------
func load_map() -> void:
	if map:
		map.queue_free()
		map = null

	var map_path = "res://Maps/%s/Map.tscn" % [
		current_map
	]
	
	var packed_scene = load(map_path)

	if packed_scene == null:
		logger.error("Failed loading map: %s" % map_path)
		return

	map = packed_scene.instantiate()
	game.add_child(map)
	
	_setup_player()
	
	load_scene(current_scene)


# --------------------------------------------------
# SCENE
# --------------------------------------------------
func load_scene(scene_name: String) -> void:
	if not map:
		return

	for child in map.get_children():
		if child.name.begins_with("Scene"):
			child.queue_free()

	var path := "res://Maps/%s/Scenes/%s.tscn" % [current_map, scene_name]
	
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

	var player_parent = get_node_or_null("PlayerParent")
	if player_parent == null:
		player_parent = Node2D.new()
		player_parent.name = "PlayerParent"
		map.add_child(player_parent)

	if player.get_parent():
		player.get_parent().remove_child(player)

	player_parent.add_child(player)
	
	player.visible = false

	await get_tree().process_frame

	phantom_camera = game.get_node("CameraManager/PhantomCamera2D")
	phantom_camera.follow_target = player

	if not spawn_requested:
		spawn_requested = true

		ServerManager.send_to_server({
			"type": "c_spawn_player",
		})


# --------------------------------------------------
# CAMERA
# --------------------------------------------------
func load_camera() -> void:
	if not game:
		return

	for child in game.get_children():
		if child.name == "CameraManager":
			child.queue_free()

	var path := "res://Game/CameraManager/CameraManager.tscn"

	var packed = load(path)

	if packed == null:
		logger.error("Failed camera scene")
		return

	var scene = packed.instantiate()
	
	fade_cover = scene.get_node("Cover/FadeCover")
	fade_cover.visible = true

	game.add_child(scene)
	
	await get_tree().process_frame
	await get_tree().process_frame

	_fade_in()


# --------------------------------------------------
# REMOTE PLAYERS
# --------------------------------------------------
func clear_remote_players():
	for p in remote_players.values():
		if is_instance_valid(p):
			p.queue_free()

	remote_players.clear()


func spawn_remote_player(id: int, pos: Vector2, facing: int = 1, remote_velocity: Vector2 = Vector2.ZERO):
	if remote_players.has(id):
		if is_instance_valid(remote_players[id]):
			remote_players[id].queue_free()

	var remote_player = remote_player_scene.instantiate()
	remote_player.position = pos
	if remote_player.has_method("set_remote_state"):
		remote_player.set_remote_state(pos, remote_velocity)
	else:
		remote_player.set_target_position(pos)
	if remote_player.has_method("set_facing"):
		remote_player.set_facing(facing)

	var player_parent = map.get_node_or_null("PlayerParent")
	if player_parent == null:
		player_parent = Node2D.new()
		player_parent.name = "PlayerParent"
		map.add_child(player_parent)

	player_parent.add_child(remote_player)
	remote_players[id] = remote_player


func update_remote_player(id: int, pos: Vector2, facing: int = 1, remote_velocity: Vector2 = Vector2.ZERO):
	if not remote_players.has(id):
		spawn_remote_player(id, pos, facing, remote_velocity)
		return

	var p = remote_players[id]

	if not is_instance_valid(p):
		remote_players.erase(id)
		return

	if p.has_method("set_remote_state"):
		p.set_remote_state(pos, remote_velocity)
	elif p.has_method("set_target_position"):
		p.set_target_position(pos)
	else:
		p.position = pos

	if p.has_method("set_facing"):
		p.set_facing(facing)


func remove_remote_player(id: int):
	if not remote_players.has(id):
		return

	if is_instance_valid(remote_players[id]):
		remote_players[id].queue_free()

	remote_players.erase(id)


# --------------------------------------------------
# FADE FUNCTIONS
# --------------------------------------------------
func _fade_in():
	fade_cover.visible = true

	var tween = create_tween()
	tween.tween_property(fade_cover, "modulate:a", 0.0, 0.4)
	tween.finished.connect(func(): fade_cover.visible = false)


func _fade_out():
	fade_cover.visible = true

	var tween = create_tween()
	tween.tween_property(fade_cover, "modulate:a", 1.0, 0.25)
