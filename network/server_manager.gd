extends Node

signal server_ready
signal server_lost
signal login_rejected(message: String)

const SERVER_IP := "80.193.20.125"
const PORT := 7777
const MAX_PLAYERS := 16
const HEARTBEAT_TIMEOUT := 3.0
const HEARTBEAT_INTERVAL := 1.0

var DebugLogger = preload("res://utilities/logger.gd")
var PacketManager = preload("./packet_manager.gd")
var InstanceManagerScript = preload("./instance_manager.gd")
var ServerRewardWriterScript = preload("./server_reward_writer.gd")

var logger: Node
var instance_manager: Node
var packet_manager: Node
var server_reward_writer: Node

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

# Firebase account session tracking.
# active_account_sessions maps Firebase localId -> ENet peer id.
# client_account_ids maps ENet peer id -> Firebase localId.
var active_account_sessions: Dictionary = {}
var client_account_ids: Dictionary = {}

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

	# Server-only Firebase Admin reward writer. This calls the local Node.js
	# Admin SDK helper on the dedicated/headless server machine.
	server_reward_writer = ServerRewardWriterScript.new()
	server_reward_writer.name = "ServerRewardWriter"
	add_child(server_reward_writer)
	server_reward_writer.enemy_reward_applied.connect(packet_manager._on_server_enemy_reward_applied)
	server_reward_writer.enemy_reward_failed.connect(packet_manager._on_server_enemy_reward_failed)
	server_reward_writer.player_death_applied.connect(packet_manager._on_server_player_death_applied)
	server_reward_writer.player_death_failed.connect(packet_manager._on_server_player_death_failed)

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
	if not is_server and not handshake_sent and status == MultiplayerPeer.CONNECTION_CONNECTED:
		send_to_server(_make_handshake_packet())
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
	_clear_account_session(client_id)

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

	var packet_type = data.get("type", "")
	var allow_pre_handshake = packet_type == "s_login_rejected" or packet_type == "s_login_replaced"

	if is_server and not connected_clients.has(target) and not allow_pre_handshake:
		return


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



# --------------------------------------------------
# ACCOUNT SESSION HELPERS
# --------------------------------------------------
func _make_handshake_packet() -> Dictionary:
	var firebase_user_id := ""
	var firebase_id_token := ""
	var firebase_email := ""
	var firebase_display_name := ""

	if Engine.has_singleton("Firebase"):
		# Project autoloads are not native singletons, so this branch is normally unused.
		pass

	if has_node("/root/Firebase"):
		var firebase := get_node("/root/Firebase")
		if firebase.has_method("get_current_user_data"):
			var user_data: Dictionary = firebase.get_current_user_data()
			firebase_user_id = str(user_data.get("localId", ""))
			firebase_id_token = str(user_data.get("idToken", ""))
			firebase_email = str(user_data.get("email", ""))
			firebase_display_name = str(user_data.get("username", user_data.get("displayName", "")))

	return {
		"type": "c_handshake",
		"firebase_user_id": firebase_user_id,
		"firebase_id_token": firebase_id_token,
		"firebase_email": firebase_email,
		"firebase_display_name": firebase_display_name,
	}


func try_register_account_session(client_id: int, firebase_user_id: String) -> bool:
	firebase_user_id = firebase_user_id.strip_edges()

	if firebase_user_id == "":
		_reject_client_login(client_id, "Login first.")
		return false

	if active_account_sessions.has(firebase_user_id):
		var existing_client_id := int(active_account_sessions[firebase_user_id])

		if existing_client_id != client_id and (connected_clients.has(existing_client_id) or remote_players.has(existing_client_id)):
			_kick_existing_account_session(existing_client_id, firebase_user_id)
		else:
			# Old stale session; remove it and allow this login.
			active_account_sessions.erase(firebase_user_id)

	active_account_sessions[firebase_user_id] = client_id
	client_account_ids[client_id] = firebase_user_id
	return true


func _kick_existing_account_session(existing_client_id: int, firebase_user_id: String) -> void:
	logger.warn("Account %s logged in again. Kicking old peer %d." % [firebase_user_id, existing_client_id])

	# Tell the old client why it is being removed before closing the connection.
	# The new login will continue and become the active session.
	send_to_client(existing_client_id, {
		"type": "s_login_replaced",
		"message": "Your account was logged in on another device.",
	})

	handle_disconnect(existing_client_id, "account logged in elsewhere")

	if peer != null:
		peer.disconnect_peer(existing_client_id)


func _reject_client_login(client_id: int, message: String) -> void:
	logger.warn("Login rejected for %d: %s" % [client_id, message])
	send_to_client(client_id, {
		"type": "s_login_rejected",
		"message": message,
	})

	if peer != null:
		peer.disconnect_peer(client_id)


func _clear_account_session(client_id: int) -> void:
	if not client_account_ids.has(client_id):
		return

	var firebase_user_id := str(client_account_ids[client_id])
	client_account_ids.erase(client_id)

	if active_account_sessions.get(firebase_user_id, -1) == client_id:
		active_account_sessions.erase(firebase_user_id)


func get_account_id_for_client(client_id: int) -> String:
	return str(client_account_ids.get(client_id, "")).strip_edges()


func apply_enemy_reward_for_client(client_id: int, enemy_definition_id: String, enemy_id: String = "") -> void:
	if server_reward_writer == null:
		logger.error("Server reward writer is missing.")
		return

	var account_id := get_account_id_for_client(client_id)
	if account_id == "":
		logger.warn("Cannot apply enemy reward for %d: no account session." % client_id)
		return

	server_reward_writer.apply_enemy_reward(client_id, account_id, enemy_definition_id, enemy_id)


func apply_player_death_for_client(client_id: int) -> void:
	if server_reward_writer == null:
		logger.error("Server reward writer is missing.")
		return

	var account_id := get_account_id_for_client(client_id)
	if account_id == "":
		logger.warn("Cannot apply player death for %d: no account session." % client_id)
		return

	server_reward_writer.apply_player_death(client_id, account_id)

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
