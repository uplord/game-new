extends Node

signal server_ready
signal server_lost

const SERVER_IP := "80.193.20.125"
const PORT := 7777
const MAX_PLAYERS := 16
const HEARTBEAT_TIMEOUT := 3.0
const HEARTBEAT_INTERVAL := 1.0

var DebugLogger = preload("res://Utilities/Logger.gd")
var PacketManager = preload("./PacketManager.gd")
var InstanceManagerScript = preload("InstanceManager.gd")

var logger: Node
var instance_manager: Node
var packet_manager: Node

var peer: ENetMultiplayerPeer
var is_server: bool = false
var local_peer_id: int = -1

var hb_timer: Timer
var connected: bool = false
var handshake_sent: bool = false
var heartbeat_timer: float = 0.0

var connected_clients: Dictionary = {}
var remote_players: Dictionary = {}
var remote_players_by_instance: Dictionary = {}

# --------------------------------------------------
# INIT
# --------------------------------------------------
func _ready() -> void:
	set_process(false)
	logger = DebugLogger.new()
	add_child(logger)
	
	# Initialize instance manager
	instance_manager = InstanceManagerScript.new()
	instance_manager.setup(self, logger)
	add_child(instance_manager)

	# Initialize packet manager
	packet_manager = PacketManager.new()
	packet_manager.setup(self, logger)
	packet_manager.name = "PacketManager"
	add_child(packet_manager)

	if DisplayServer.get_name() == "headless":
		logger.info("Starting server...")
		start_server()

	hb_timer = Timer.new()
	hb_timer.wait_time = 0.1
	hb_timer.one_shot = false
	hb_timer.autostart = true
	hb_timer.timeout.connect(check_heartbeats)
	add_child(hb_timer)


func _process(delta: float) -> void:
	if peer == null:
		return

	var status := peer.get_connection_status()

	if connected and status != MultiplayerPeer.CONNECTION_CONNECTED:
		handle_server_disconnect()
		return

	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	peer.poll()

	
	# handshake
	if not handshake_sent and status == MultiplayerPeer.CONNECTION_CONNECTED:
		send_to_server({ "type": "c_handshake" })
		handshake_sent = true

	if connected:
		heartbeat_timer += delta
		if heartbeat_timer >= HEARTBEAT_INTERVAL:
			heartbeat_timer = 0
			send_to_server({ "type": "c_heartbeat" })

	# packets
	while peer.get_available_packet_count() > 0:
		if is_server:
			var client_id = peer.get_packet_peer()
			var data = peer.get_var()
			packet_manager.handle_server_packet(client_id, data)
		else:
			var data = peer.get_var()
			packet_manager.handle_client_packet(data)


# --------------------------------------------------
# SERVER
# --------------------------------------------------
func start_server(port: int = -1) -> void:
	if port == -1:
		port = PORT

	peer = ENetMultiplayerPeer.new()

	var err := peer.create_server(port)
	if err:
		logger.error("Server failed: %s" % error_string(err))
		return

	logger.info("Server started on port %d" % port)
	is_server = true
	set_process(true)


# --------------------------------------------------
# CLIENT
# --------------------------------------------------
func start_client(ip_address: String = "", port: int = -1) -> void:
	if ip_address == "":
		ip_address = SERVER_IP
	if port == -1:
		port = PORT
	
	peer = ENetMultiplayerPeer.new()

	var err := peer.create_client(ip_address, port)
	if err:
		logger.error("Client failed: %s" % error_string(err))
		return

	logger.info("Client to %s:%d..." % [ip_address, port])
	set_process(true)


# --------------------------------------------------
# HEARTBEATS
# --------------------------------------------------
func check_heartbeats():
	for client_id in connected_clients.keys().duplicate():
		connected_clients[client_id] += hb_timer.wait_time

		if connected_clients[client_id] > HEARTBEAT_TIMEOUT:
			handle_disconnect(client_id, "timeout")


func handle_server_disconnect():
	if not connected and not handshake_sent:
		return

	connected = false
	handshake_sent = false
	heartbeat_timer = 0.0

	logger.warn("Lost connection to server")
	server_lost.emit()

	if peer:
		peer.close()
		peer = null

	set_process(false)


func handle_disconnect(client_id: int, reason: String) -> void:
	logger.info("Disconnect: %d - %s" % [client_id, reason])

	var p = remote_players.get(client_id, null)

	full_cleanup_client(client_id)

	if p:
		packet_manager.sync_visibility_group(
			p.get("map", ""),
			p.get("scene", ""),
			p.get("instance", 1)
		)


func full_cleanup_client(client_id: int):
	if remote_players.has(client_id):
		var p = remote_players[client_id]

		remove_from_instance(
			client_id,
			p.get("map", ""),
			p.get("scene", ""),
			p.get("instance", 1)
		)

		instance_manager.remove_player_from_instance(
			client_id,
			p.get("map", ""),
			p.get("scene", ""),
			p.get("instance", 1)
		)

		instance_manager.free_spawn(client_id)
	
	remote_players.erase(client_id)	
	if packet_manager != null and packet_manager.has_method("forget_client"):
		packet_manager.forget_client(client_id)
	connected_clients.erase(client_id)
	logger.info("Total players: %d" % connected_clients.size())


# --------------------------------------------------
# SEND HELPERS
# --------------------------------------------------

func _send(data: Dictionary, target: int) -> void:
	if peer == null:
		return

	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	if is_server and not connected_clients.has(target):
		return

	var packet_type = data.get("type", "")

	var is_movement_packet = packet_type == "c_move_player" or (packet_type == "s_remote_move" and not bool(data.get("stopped", false)))

	if is_movement_packet:
		peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	else:
		peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)

	peer.set_target_peer(target)
	peer.put_var(data)
	peer.set_target_peer(0)


func send_to_server(data: Dictionary) -> void:
	if peer == null or is_server:
		return
	_send(data, 1)

func send_to_client(client_id: int, data: Dictionary) -> void:
	_send(data, client_id)


func broadcast_to_instance(map: String, instance: int, data: Dictionary):
	var key = "%s::%d" % [map, instance]

	if not remote_players_by_instance.has(key):
		return

	for client_id in remote_players_by_instance[key].keys():
		_send(data, client_id)


# -------------------------
# INSTANCE HELPERS
# -------------------------
func _instance_key(map: String, scene: String, instance: int) -> String:
	return "%s::%s::%d" % [map, scene, instance]


func add_to_instance(client_id: int, data: Dictionary) -> void:
	var key = _instance_key(data.map, data.scene, data.instance)

	if not remote_players_by_instance.has(key):
		remote_players_by_instance[key] = {}

	remote_players_by_instance[key][client_id] = data


func remove_from_instance(
		client_id: int,
		map: String,
		scene: String,
		instance: int
	) -> void:
	var key = _instance_key(map, scene, instance)

	if remote_players_by_instance.has(key):
		remote_players_by_instance[key].erase(client_id)

		if remote_players_by_instance[key].is_empty():
			remote_players_by_instance.erase(key)


# --------------------------------------------------
# UTILS
# --------------------------------------------------
func mark_server_ready() -> void:
	connected = true
	server_ready.emit()
