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
var player: Node2D

var spawn_requested := false


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

	var player_parent = get_node_or_null("Player")
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
	print("phantom_camera", phantom_camera)
	phantom_camera.follow_target = player

	if not spawn_requested:
		spawn_requested = true
		
		print("SPAWN")

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
