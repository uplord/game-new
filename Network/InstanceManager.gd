extends Node

class_name InstanceManager

var server_manager: Node
var logger: Node

var instance_population := {}


# --------------------------------------------------
# SETUP
# --------------------------------------------------
func setup(sm: Node, logger_ref: Node):
	server_manager = sm
	logger = logger_ref


# --------------------------------------------------
# SPAWN CACHE
# --------------------------------------------------
func get_spawn_points(
	map: String,
	scene: String
) -> Array:
	var scene_path = "res://Maps/%s/Scenes/%s.tscn" % [
		map,
		scene
	]

	var packed = load(scene_path)

	if packed == null:
		logger.warn(
			"Scene not found: %s"
			% scene_path
		)

		return []

	var temp_scene = packed.instantiate()

	var points := []

	var spawn_parent = temp_scene.get_node_or_null(
		"SpawnPoints"
	)

	if spawn_parent:
		for child in spawn_parent.get_children():
			if child is Marker2D:
				points.append(child.global_position)

	temp_scene.queue_free()

	return points
