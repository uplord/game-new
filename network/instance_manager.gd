extends Node

class_name InstanceManager

const MAX_INSTANCES_PER_MAP = 100
const INSTANCE_PLAYER_LIMIT = 1

var server_manager: Node
var logger: Node

var instance_population := {}
var used_spawn_ids := {}
var spawn_points_cache := {}

# --------------------------------------------------
# SETUP
# --------------------------------------------------
func setup(sm: Node, logger_ref: Node):
	server_manager = sm
	logger = logger_ref


# --------------------------------------------------
# INSTANCE KEYS
# --------------------------------------------------
func get_instance_key(map: String, scene: String, instance: int) -> String:
	return "%s::%s::%d" % [map, scene, instance]


# --------------------------------------------------
# INSTANCE LIMITS
# --------------------------------------------------
func get_map_player_limit(map: String) -> int:
	var path = "res://maps/%s/map.tscn" % [
		map
	]

	var packed = load(path)

	if packed == null:
		return INSTANCE_PLAYER_LIMIT

	var temp = packed.instantiate()

	var limit : int = INSTANCE_PLAYER_LIMIT

	if "player_max" in temp:
		limit = temp.player_max

	temp.queue_free()

	return limit


func get_map_instance_population(
	map: String,
	instance: int
) -> int:
	var total := 0

	for key in instance_population.keys():

		var parts = key.split("::")

		if parts.size() < 3:
			continue

		var key_map = parts[0]
		var key_instance = int(parts[2])

		if key_map == map and key_instance == instance:
			total += instance_population[key].size()

	return total


# --------------------------------------------------
# FIND INSTANCE
# --------------------------------------------------
func find_available_instance(
	map: String,
	scene: String
) -> int:
	var limit = get_map_player_limit(map)

	for instance in range(
		1,
		MAX_INSTANCES_PER_MAP + 1
	):

		var population = get_map_instance_population(
			map,
			instance
		)

		# INSTANCE HAS SPACE
		if population < limit:

			var key = get_instance_key(
				map,
				scene,
				instance
			)

			if not instance_population.has(key):
				instance_population[key] = []

			return instance

	logger.warn(
		"No available instances for map: %s"
		% map
	)

	return -1


# --------------------------------------------------
# INSTANCE PLAYERS
# --------------------------------------------------
func add_player_to_instance(
	client_id: int,
	map: String,
	scene: String,
	instance: int
):
	var key = get_instance_key(
		map,
		scene,
		instance
	)

	if not instance_population.has(key):
		instance_population[key] = []

	if not instance_population[key].has(client_id):
		instance_population[key].append(client_id)


func remove_player_from_instance(
	client_id: int,
	map: String,
	scene: String,
	instance: int
):
	var key = get_instance_key(
		map,
		scene,
		instance
	)

	if not instance_population.has(key):
		return

	instance_population[key].erase(client_id)

	if instance_population[key].is_empty():
		instance_population.erase(key)


func get_instance_players(
	map: String,
	scene: String,
	instance: int,
) -> Array:
	var key = get_instance_key(
		map,
		scene,
		instance,
	)

	return instance_population.get(key, [])


func get_instance_count(
	map: String,
	scene: String,
	instance: int
) -> int:
	return get_instance_players(
		map,
		scene,
		instance
	).size()

# --------------------------------------------------
# SPAWN CACHE
# --------------------------------------------------
func get_spawn_points(
	map: String,
	scene: String
) -> Array:
	var key = "%s::%s" % [
		map,
		scene
	]

	if spawn_points_cache.has(key):
		return spawn_points_cache[key]

	var scene_path = "res://maps/%s/scenes/%s.tscn" % [
		map,
		scene
	]

	var packed = load(scene_path)

	if packed == null:
		logger.warn(
			"Scene not found: %s"
			% scene_path
		)

		spawn_points_cache[key] = []
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

	spawn_points_cache[key] = points

	return points


# --------------------------------------------------
# SPAWN MANAGEMENT
# --------------------------------------------------
func free_spawn(client_id: int):
	for key in used_spawn_ids.keys():

		if used_spawn_ids[key].has(client_id):

			used_spawn_ids[key].erase(client_id)

			if used_spawn_ids[key].is_empty():
				used_spawn_ids.erase(key)


func get_spawn_position(
	client_id: int,
	map: String,
	scene: String,
	instance: int
) -> Vector2:
	var instance_key = get_instance_key(
		map,
		scene,
		instance
	)

	if not used_spawn_ids.has(instance_key):
		used_spawn_ids[instance_key] = {}

	var instance_spawns = used_spawn_ids[instance_key]

	var points = get_spawn_points(
		map,
		scene
	)

	if points.is_empty():
		logger.warn(
			"No spawn points for %s::%s"
			% [map, scene]
		)

		return Vector2.ZERO

	var available := []

	for i in range(points.size()):

		if not instance_spawns.values().has(i):
			available.append(i)

	var chosen := 0

	if available.is_empty():
		chosen = randi() % points.size()
	else:
		chosen = available.pick_random()

	instance_spawns[client_id] = chosen

	return points[chosen]


# --------------------------------------------------
# TELEPORT RESOLUTION
# --------------------------------------------------
func resolve_teleport_position(
	map: String,
	scene: String,
	teleport_name: String
) -> Vector2:
	var scene_path = "res://maps/%s/scenes/%s.tscn" % [
		map,
		scene
	]

	var packed = load(scene_path)

	if packed == null:
		return Vector2.ZERO

	var temp_scene = packed.instantiate()

	var position := Vector2.ZERO

	if teleport_name != "":
		var node = temp_scene.find_child(
			teleport_name,
			true,
			false
		)

		if node:
			position = node.global_position

	temp_scene.queue_free()

	return position


# --------------------------------------------------
# CLEANUP
# --------------------------------------------------
func clear_empty_instances():
	for key in instance_population.keys():

		if instance_population[key].is_empty():
			instance_population.erase(key)
