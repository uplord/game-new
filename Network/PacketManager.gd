extends Node

var server_manager: Node
var logger: Node
var instance_manager: InstanceManager


func setup(sm: Node, logger_ref: Node) -> void:
	server_manager = sm
	logger = logger_ref
	instance_manager = server_manager.instance_manager


# --------------------------------------------------
# SERVER PACKETS
# --------------------------------------------------
func handle_server_packet(client_id: int, data: Dictionary) -> void:
	match data.get("type", ""):
		"c_handshake":
			logger.info("Client handshake: %d" % client_id)

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
			logger.info("Client spawn: %d" % client_id)
			
			var map = SceneManager.current_map
			var scene = SceneManager.current_scene
			
			var points = instance_manager.get_spawn_points(
				map,
				scene
			)
			
			var spawn_position = Vector2.ZERO
			
			if points.is_empty():
				logger.warn(
					"No spawn points for %s::%s"
					% [map, scene]
				)

				spawn_position =  Vector2.ZERO

			spawn_position = points.pick_random()
			
			print("spawn_position: ", spawn_position)

			server_manager.send_to_client(
				client_id,
				{
					"type": "s_spawn_player",
					"spawn_position": spawn_position
				}
			)

		"c_move_player":
			logger.info("Client move: %d" % client_id)
			logger.info("Move position: %s" % data.position)

		"c_teleport_player":
			logger.info("Client teleport: %d" % client_id)

		"c_request_sync":
			logger.info("Client request sync: %d" % client_id)


# --------------------------------------------------
# CLIENT PACKETS
# --------------------------------------------------
func handle_client_packet(data: Dictionary) -> void:
	match data.get("type", ""):
		"s_handshake_ack":
			logger.info("Handshake_ack: %d" % data.client_id)
			server_manager.local_peer_id = data.client_id
			server_manager.mark_server_ready()

		"s_spawn_player":
			logger.info("Server spawn position: %s" % data.spawn_position)
			SceneManager.player.position = data.spawn_position
			SceneManager.player.visible = true

		"s_teleport_player":
			logger.info("Server teleport")

		"s_request_sync":
			logger.info("Server request sync")
