extends Node

var server_manager: Node
var logger: Node
var instance_manager: InstanceManager

const MOVEMENT_BROADCAST_INTERVAL := 0.016
var last_movement_broadcast_time: Dictionary = {}


func setup(sm: Node, logger_ref: Node) -> void:
	server_manager = sm
	logger = logger_ref
	instance_manager = server_manager.instance_manager


func forget_client(client_id: int) -> void:
	last_movement_broadcast_time.erase(client_id)


func _get_sync_facing(player: Dictionary) -> int:
	var velocity: Vector2 = player.get("velocity", Vector2.ZERO)
	if abs(velocity.x) > 20.0:
		return int(sign(velocity.x))

	return int(player.get("facing", 1))


func _make_sync_player_data(player: Dictionary) -> Dictionary:
	var velocity: Vector2 = player.get("velocity", Vector2.ZERO)
	return {
		"id": player.get("id", 0),
		"position": player.get("position", Vector2.ZERO),
		"velocity": velocity,
		"direction": player.get("direction", Vector2.RIGHT),
		"facing": _get_sync_facing(player),
		"pose": player.get("pose", 0),
		"sequence": player.get("sequence", 0),
		"server_time": Time.get_ticks_msec() / 1000.0,
		"stopped": velocity.length() <= 20.0,
	}


# --------------------------------------------------
# VALIDATION
# --------------------------------------------------
func _is_valid_client(client_id: int) -> bool:
	return server_manager.remote_players.has(client_id)


func _is_position_valid(pos: Vector2) -> bool:
	return abs(pos.x) < 100000 and abs(pos.y) < 100000


func _validate_move(
	client_id: int,
	data: Dictionary
) -> bool:
	if not _is_valid_client(client_id):
		print(111)
		return false

	if not data.has("position"):
		print(222)
		return false

	if not _is_position_valid(data.position):
		print(444)
		return false

	return true


# --------------------------------------------------
# SERVER PACKETS
# --------------------------------------------------
func handle_server_packet(client_id: int, data: Dictionary) -> void:
	var packet_type = data.get("type", "")

	if packet_type != "c_handshake" and not server_manager.connected_clients.has(client_id):
		return

	match packet_type:
		"c_handshake":
			server_manager.connected_clients[client_id] = 0.0
			logger.info("Total players: %d" % server_manager.connected_clients.size())

			server_manager.send_to_client(client_id, {
				"type": "s_handshake_ack",
				"client_id": client_id
			})

		"c_heartbeat":
			if server_manager.connected_clients.has(client_id):
				server_manager.connected_clients[client_id] = 0.0

		"c_spawn_player":
			if server_manager.remote_players.has(client_id):
				return

			var map = SceneManager.current_map
			var scene = SceneManager.current_scene
			
			var instance = instance_manager.find_available_instance(
				map,
				scene,
			)
			
			if instance == -1:
				logger.info("Client spawn failed: %d" % client_id)
				return

			instance_manager.add_player_to_instance(
				client_id,
				map,
				scene,
				instance,
			)

			var spawn_position = instance_manager.get_spawn_position(
				client_id,
				map,
				scene,
				instance
			)

			var player_data = {
				"id": client_id,
				"position": spawn_position,
				"direction": Vector2.RIGHT,
				"facing": 1,
				"pose": 0,
				"sequence": 0,
				"map": map,
				"scene": scene,
				"instance": instance
			}

			server_manager.remote_players[client_id] = player_data

			server_manager.add_to_instance(client_id, player_data)

			server_manager.send_to_client(
				client_id,
				{
					"type": "s_spawn_player",
					"spawn_position": spawn_position,
					"instance": instance
				}
			)

			logger.info("Client spawn: %d - %s - %s - %s" % [client_id, map, scene, instance])

			sync_visibility_group(
				map,
				scene,
				instance
			)

		"c_move_player":
			if not _validate_move(client_id, data):
				server_manager.handle_disconnect(client_id, "bad move")
				return

			var player = server_manager.remote_players.get(
				client_id,
				null
			)

			if player == null:
				return

			player.position = data.position
			player.velocity = data.get("velocity", Vector2.ZERO)
			player.facing = int(data.get("facing", player.get("facing", 1)))
			player.pose = int(data.get("pose", player.get("pose", 0)))
			player.sequence = int(data.get("sequence", player.get("sequence", 0)))

			server_manager.remote_players[client_id] = player

			var now := Time.get_ticks_msec() / 1000.0
			var last_broadcast := float(last_movement_broadcast_time.get(client_id, 0.0))
			if now - last_broadcast < MOVEMENT_BROADCAST_INTERVAL:
				return
			last_movement_broadcast_time[client_id] = now

			var players_in_instance = instance_manager.get_instance_players(
				player.map,
				player.scene,
				player.instance
			)

			for target_client_id in players_in_instance:

				if target_client_id == client_id:
					continue

				server_manager.send_to_client(target_client_id, {
					"type": "s_remote_move",
					"id": client_id,
					"position": player.position,
					"velocity": player.get("velocity", Vector2.ZERO),
					"facing": player.get("facing", 1),
					"pose": player.get("pose", 0),
					"sequence": player.get("sequence", 0),
					"server_time": now,
					"stopped": false,
				})

		"c_stop_player":
			if not _validate_move(client_id, data):
				server_manager.handle_disconnect(client_id, "bad stop")
				return

			var player = server_manager.remote_players.get(client_id, null)
			if player == null:
				return

			player.position = data.position
			player.velocity = Vector2.ZERO
			player.facing = int(data.get("facing", player.get("facing", 1)))
			player.pose = int(data.get("pose", player.get("pose", 0)))
			player.sequence = int(data.get("sequence", player.get("sequence", 0)))
			server_manager.remote_players[client_id] = player

			var stop_time := Time.get_ticks_msec() / 1000.0
			last_movement_broadcast_time[client_id] = stop_time

			var players_in_instance = instance_manager.get_instance_players(
				player.map,
				player.scene,
				player.instance
			)

			for target_client_id in players_in_instance:
				if target_client_id == client_id:
					continue

				server_manager.send_to_client(target_client_id, {
					"type": "s_remote_move",
					"id": client_id,
					"position": player.position,
					"velocity": Vector2.ZERO,
					"facing": player.get("facing", 1),
					"pose": player.get("pose", 0),
					"sequence": player.get("sequence", 0),
					"server_time": stop_time,
					"stopped": true,
				})

		"c_teleport_player":
			logger.info("Client teleport: %d" % client_id)

		"c_request_sync":
			logger.info("Client request sync: %d" % client_id)
			
			var player = server_manager.remote_players.get(
				client_id,
				null
			)

			if player == null:
				return

			var players_in_instance = instance_manager.get_instance_players(
				player.map,
				player.scene,
				player.instance
			)

			var players := []

			for other_client_id in players_in_instance:
				if other_client_id == client_id:
					continue

				var other_player = server_manager.remote_players.get(other_client_id, null)
				if other_player == null:
					continue

				players.append(_make_sync_player_data(other_player))

			server_manager.send_to_client(
				client_id,
				{
					"type": "s_request_sync",
					"players": players,
					"map_population":
						instance_manager.get_map_instance_population(
							player.map,
							player.instance
						)
				}
			)


# --------------------------------------------------
# SYNC VISIBILITY GROUP
# --------------------------------------------------
func sync_visibility_group(
	map: String,
	scene: String,
	instance: int
):
	var players_in_instance = instance_manager.get_instance_players(
		map,
		scene,
		instance
	)

	var map_population = instance_manager.get_map_instance_population(
		map,
		instance
	)

	for target_client_id in players_in_instance:
		if not server_manager.connected_clients.has(target_client_id):
			continue

		var visible_players := []

		for other_client_id in players_in_instance:

			if other_client_id == target_client_id:
				continue

			if not server_manager.connected_clients.has(other_client_id):
				continue

			if server_manager.remote_players.has(other_client_id):
				visible_players.append(
					_make_sync_player_data(server_manager.remote_players[other_client_id])
				)

		server_manager.send_to_client(target_client_id, {
			"type": "s_request_sync",
			"players": visible_players,
			"map_population": map_population
		})


# --------------------------------------------------
# CLIENT PACKETS
# --------------------------------------------------
func handle_client_packet(data: Dictionary) -> void:
	match data.get("type", ""):
		"s_handshake_ack":
			server_manager.local_peer_id = data.client_id
			server_manager.mark_server_ready()

		"s_spawn_player":
			SceneManager.set_map_status(
				data.get("map", SceneManager.current_map),
				data.get("scene", SceneManager.current_scene),
				int(data.get("instance", SceneManager.current_instance)),
				int(data.get("map_population", 1))
			)
			SceneManager.player.position = data.spawn_position
			SceneManager.player.visible = true

			server_manager.send_to_server({
				"type": "c_request_sync"
			})

		"s_teleport_player":
			logger.info("Server teleport")

		"s_request_sync":
			logger.info("Server request sync")

			if data.has("map") or data.has("instance") or data.has("map_population"):
				SceneManager.set_map_status(
					data.get("map", SceneManager.current_map),
					data.get("scene", SceneManager.current_scene),
					int(data.get("instance", SceneManager.current_instance)),
					int(data.get("map_population", SceneManager.current_map_population))
				)

			SceneManager.clear_remote_players()

			for p in data.players:
				SceneManager.spawn_remote_player(
					p.id,
					p.position,
					int(p.get("facing", 1)),
					p.get("velocity", Vector2.ZERO),
					int(p.get("pose", 0)),
					int(p.get("sequence", 0)),
					bool(p.get("stopped", false)),
				)

		"s_remote_move":
			var id = data.id
			SceneManager.update_remote_player(
				id,
				data.position,
				int(data.get("facing", 1)),
				data.get("velocity", Vector2.ZERO),
				int(data.get("pose", 0)),
				int(data.get("sequence", 0)),
				bool(data.get("stopped", false)),
			)
