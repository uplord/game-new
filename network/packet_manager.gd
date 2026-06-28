extends Node

var server_manager: Node
var logger: Node
var instance_manager: InstanceManager

const MOVEMENT_BROADCAST_INTERVAL := 0.016
var last_movement_broadcast_time: Dictionary = {}

const PLAYER_MAX_HP := BattleCalculator.PLAYER_MAX_HP
const PLAYER_MAX_MP := BattleCalculator.PLAYER_MAX_MP
const ENEMY_MAX_HP := BattleCalculator.ENEMY_MAX_HP
const ENEMY_MAX_MP := BattleCalculator.ENEMY_MAX_MP
const PLAYER_GLOBAL_SKILL_COOLDOWN := 1.0
const GLOBAL_SKILL_COOLDOWN_ID := "_global_skill"
const BATTLE_STATE_BROADCAST_INTERVAL := 1.0
const ENEMY_RESPAWN_SECONDS := 10.0
const DEFAULT_ENEMY_REWARD_GOLD_MIN := 0
const DEFAULT_ENEMY_REWARD_GOLD_MAX := 0
const ENEMY_FIRST_ATTACK_DELAY := 1.0
const ENEMY_ACTION_INTERVAL := 2.0

const PLAYER_SKILL_IDS := [
	"slash",
	"fire",
	"defend",
	"heal",
	"ultra_attack",
]

const ENEMY_SKILL_ORDER := ["slash", "fire", "slash", "super_attack"]

var battle_players: Dictionary = {}
var battle_enemies: Dictionary = {}
var battle_broadcast_timer := 0.0

var changed_players := []


func setup(sm: Node, logger_ref: Node) -> void:
	server_manager = sm
	logger = logger_ref
	instance_manager = server_manager.instance_manager


func _process(delta: float) -> void:
	if server_manager == null or not server_manager.is_server:
		return
	_update_battle_timers(delta)


func forget_client(client_id: int) -> void:
	last_movement_broadcast_time.erase(client_id)
	battle_players.erase(client_id)

	for key in battle_enemies.keys().duplicate():
		var enemy: Dictionary = battle_enemies[key]
		var attackers: Array = enemy.get("attackers", [])
		if attackers.has(client_id):
			attackers.erase(client_id)
			enemy.attackers = attackers
			battle_enemies[key] = enemy
			_reset_enemy_if_no_attackers(str(key), enemy)


func _get_sync_facing(player: Dictionary) -> int:
	var velocity: Vector2 = player.get("velocity", Vector2.ZERO)
	if abs(velocity.x) > 20.0:
		return int(sign(velocity.x))

	return int(player.get("facing", 1))


func _make_sync_player_data(player: Dictionary) -> Dictionary:
	var velocity: Vector2 = player.get("velocity", Vector2.ZERO)
	return {
		"id": player.get("id", 0),
		"map": player.get("map", SceneManager.current_map),
		"scene": player.get("scene", SceneManager.current_scene),
		"instance": int(player.get("instance", SceneManager.current_instance)),
		"position": player.get("position", Vector2.ZERO),
		"velocity": velocity,
		"direction": player.get("direction", Vector2.RIGHT),
		"facing": _get_sync_facing(player),
		"pose": player.get("pose", 0),
		"reserved_enemy_approach_target": player.get("reserved_enemy_approach_target", Vector2.INF),
		"sequence": player.get("sequence", 0),
		"server_time": Time.get_ticks_msec() / 1000.0,
		"stopped": velocity.length() <= 20.0,
	}


# --------------------------------------------------
# SKILLS
# --------------------------------------------------
func _get_player_skills() -> Dictionary:
	var result := {}

	for skill_id in PLAYER_SKILL_IDS:
		var skill_resource: Resource = SkillManager.get_skill(str(skill_id))
		if skill_resource == null:
			continue

		result[str(skill_id)] = BattleCalculator.skill_resource_to_dictionary(skill_resource)

	return result


func _get_player_skill(skill_id: String) -> Dictionary:
	var skill_resource: Resource = SkillManager.get_skill(skill_id)
	if skill_resource == null:
		return {}

	return BattleCalculator.skill_resource_to_dictionary(skill_resource)


# --------------------------------------------------
# VALIDATION
# --------------------------------------------------
func _is_valid_client(client_id: int) -> bool:
	return server_manager.remote_players.has(client_id)


func _is_position_valid(pos: Vector2) -> bool:
	return abs(pos.x) < 100000 and abs(pos.y) < 100000


func _validate_move(client_id: int, data: Dictionary) -> bool:
	if not _is_valid_client(client_id):
		return false

	if not data.has("position"):
		return false

	if not _is_position_valid(data.position):
		return false

	return true


func _is_client_movement_for_current_area(client_id: int, data: Dictionary) -> bool:
	var player: Dictionary = server_manager.remote_players.get(client_id, {})
	if player.is_empty():
		return false

	# Movement sent before a teleport can arrive after the reliable teleport packet.
	# If we accept it, it overwrites the player's new server position and other
	# clients briefly spawn them at the old room position before the next update.
	if data.has("map") and str(data.get("map", "")) != str(player.get("map", "")):
		return false
	if data.has("scene") and str(data.get("scene", "")) != str(player.get("scene", "")):
		return false
	if data.has("instance") and int(data.get("instance", -1)) != int(player.get("instance", -1)):
		return false

	return true


func _is_newer_client_sequence(player: Dictionary, data: Dictionary) -> bool:
	if not data.has("sequence"):
		return true

	var incoming_sequence := int(data.get("sequence", 0))
	var current_sequence := int(player.get("sequence", -1))
	return incoming_sequence > current_sequence


# --------------------------------------------------
# SERVER PACKETS
# --------------------------------------------------
func handle_server_packet(client_id: int, data: Dictionary) -> void:
	var packet_type = data.get("type", "")

	if packet_type != "c_handshake" and not server_manager.connected_clients.has(client_id):
		return

	match packet_type:
		"c_handshake":
			var firebase_user_id := str(data.get("firebase_user_id", "")).strip_edges()

			if not server_manager.has_method("try_register_account_session"):
				server_manager.send_to_client(client_id, {
					"type": "s_login_rejected",
					"message": "Server account session support is missing."
				})
				return

			if not server_manager.try_register_account_session(client_id, firebase_user_id):
				return

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
			_handle_spawn_player(client_id)

		"c_move_player":
			_handle_move_player(client_id, data)

		"c_stop_player":
			_handle_stop_player(client_id, data)

		"c_select_enemy":
			_handle_select_enemy(client_id, data)

		"c_use_skill":
			_handle_use_skill(client_id, data)

		"c_reset_player_battle":
			_handle_reset_player_battle(client_id)

		"c_teleport_player":
			_handle_teleport_player(client_id, data)

		"c_request_sync":
			_handle_request_sync(client_id)


func _handle_spawn_player(client_id: int) -> void:
	if server_manager.remote_players.has(client_id):
		return

	var map = SceneManager.current_map
	var scene = SceneManager.current_scene

	var instance = instance_manager.find_available_instance(map, scene)
	if instance == -1:
		logger.info("Client spawn failed: %d" % client_id)
		return

	instance_manager.add_player_to_instance(client_id, map, scene, instance)

	var spawn_position = instance_manager.get_spawn_position(client_id, map, scene, instance)

	var player_data = {
		"id": client_id,
		"position": spawn_position,
		"direction": Vector2.RIGHT,
		"facing": 1,
		"pose": 0,
		"reserved_enemy_approach_target": Vector2.INF,
		"sequence": 0,
		"map": map,
		"scene": scene,
		"instance": instance
	}

	server_manager.remote_players[client_id] = player_data
	_get_or_create_player_battle_state(client_id)

	server_manager.add_to_instance(client_id, player_data)

	server_manager.send_to_client(client_id, {
		"type": "s_spawn_player",
		"spawn_position": spawn_position,
		"instance": instance,
		"battle": _make_battle_state(client_id, "")
	})

	logger.info("Client spawn: %d - %s - %s - %s" % [client_id, map, scene, instance])
	sync_visibility_group(map, scene, instance)


func _handle_move_player(client_id: int, data: Dictionary) -> void:
	if not _validate_move(client_id, data):
		server_manager.handle_disconnect(client_id, "bad move")
		return

	var player = server_manager.remote_players.get(client_id, null)
	if player == null:
		return

	if not _is_client_movement_for_current_area(client_id, data):
		return

	if not _is_newer_client_sequence(player, data):
		return

	player.position = data.position
	player.velocity = data.get("velocity", Vector2.ZERO)
	player.facing = int(data.get("facing", player.get("facing", 1)))
	player.pose = int(data.get("pose", player.get("pose", 0)))	
	player.reserved_enemy_approach_target = data.get("reserved_enemy_approach_target", Vector2.INF)
	player.sequence = int(data.get("sequence", player.get("sequence", 0)))

	server_manager.remote_players[client_id] = player

	var now := Time.get_ticks_msec() / 1000.0
	var last_broadcast := float(last_movement_broadcast_time.get(client_id, 0.0))
	if now - last_broadcast < MOVEMENT_BROADCAST_INTERVAL:
		return

	last_movement_broadcast_time[client_id] = now
	_broadcast_remote_move(client_id, player, false, now)


func _handle_stop_player(client_id: int, data: Dictionary) -> void:
	if not _validate_move(client_id, data):
		server_manager.handle_disconnect(client_id, "bad stop")
		return

	var player = server_manager.remote_players.get(client_id, null)
	if player == null:
		return

	if not _is_client_movement_for_current_area(client_id, data):
		return

	if not _is_newer_client_sequence(player, data):
		return

	player.position = data.position
	player.velocity = Vector2.ZERO
	player.facing = int(data.get("facing", player.get("facing", 1)))
	player.pose = int(data.get("pose", player.get("pose", 0)))	
	player.reserved_enemy_approach_target = data.get("reserved_enemy_approach_target", Vector2.INF)
	player.sequence = int(data.get("sequence", player.get("sequence", 0)))

	server_manager.remote_players[client_id] = player

	var stop_time := Time.get_ticks_msec() / 1000.0
	last_movement_broadcast_time[client_id] = stop_time
	_broadcast_remote_move(client_id, player, true, stop_time)


func _broadcast_remote_remove(client_id: int, map_name: String, scene_name: String, instance: int) -> void:
	var players_in_instance = instance_manager.get_instance_players(map_name, scene_name, instance)

	for target_client_id in players_in_instance:
		if target_client_id == client_id:
			continue

		server_manager.send_to_client(target_client_id, {
			"type": "s_remote_remove",
			"id": client_id,
			"map": map_name,
			"scene": scene_name,
			"instance": instance,
		})


func _broadcast_remote_move(client_id: int, player: Dictionary, stopped: bool, server_time: float) -> void:
	var players_in_instance = instance_manager.get_instance_players(player.map, player.scene, player.instance)

	for target_client_id in players_in_instance:
		if target_client_id == client_id:
			continue

		server_manager.send_to_client(target_client_id, {
			"type": "s_remote_move",
			"id": client_id,
			"map": player.get("map", SceneManager.current_map),
			"scene": player.get("scene", SceneManager.current_scene),
			"instance": int(player.get("instance", SceneManager.current_instance)),
			"position": player.position,
			"velocity": player.get("velocity", Vector2.ZERO),
			"facing": player.get("facing", 1),
			"pose": player.get("pose", 0),
			"reserved_enemy_approach_target": player.get("reserved_enemy_approach_target", Vector2.INF),
			"sequence": player.get("sequence", 0),
			"server_time": server_time,
			"stopped": stopped,
		})


func _handle_teleport_player(client_id: int, data: Dictionary) -> void:
	var player: Dictionary = server_manager.remote_players.get(client_id, {})
	if player.is_empty():
		return

	var old_map := str(player.get("map", SceneManager.current_map))
	var old_scene := str(player.get("scene", SceneManager.current_scene))
	var old_instance := int(player.get("instance", SceneManager.current_instance))

	_broadcast_remote_remove(client_id, old_map, old_scene, old_instance)

	var target_map := str(data.get("target_map", ""))
	var target_scene := str(data.get("target_scene", ""))
	var target_teleport := str(data.get("target_teleport", ""))
	var target_facing := int(data.get("target_facing", 1))
	if target_facing == 0:
		target_facing = 1
	target_facing = -1 if target_facing < 0 else 1

	if target_map == "" or target_scene == "" or target_teleport == "":
		return

	# A teleport is a hard area change, even when it stays inside the same map.
	# Clear this player's current enemy target and remove them from any enemy
	# attacker lists so the old battle cannot continue in the new scene.
	_exit_player_battle_for_area_change(client_id)

	var target_position := instance_manager.resolve_teleport_position(target_map, target_scene, target_teleport)

	var target_instance := old_instance
	if target_map != old_map:
		instance_manager.remove_player_from_instance(client_id, old_map, old_scene, old_instance)
		server_manager.remove_from_instance(client_id, old_map, old_scene, old_instance)
		target_instance = instance_manager.find_available_instance(target_map, target_scene)
		if target_instance == -1:
			instance_manager.add_player_to_instance(client_id, old_map, old_scene, old_instance)
			server_manager.add_to_instance(client_id, player)
			return
	else:
		instance_manager.remove_player_from_instance(client_id, old_map, old_scene, old_instance)
		server_manager.remove_from_instance(client_id, old_map, old_scene, old_instance)

	instance_manager.add_player_to_instance(client_id, target_map, target_scene, target_instance)

	player.position = target_position
	player.velocity = Vector2.ZERO
	player.facing = target_facing
	player.pose = 0
	player.sequence = int(player.get("sequence", 0)) + 1
	player.map = target_map
	player.scene = target_scene
	player.instance = target_instance

	server_manager.remote_players[client_id] = player
	server_manager.add_to_instance(client_id, player)

	var battle_player := _get_or_create_player_battle_state(client_id)
	battle_player.map = target_map
	battle_player.scene = target_scene
	battle_player.instance = target_instance
	battle_players[client_id] = battle_player

	server_manager.send_to_client(client_id, {
		"type": "s_teleport_player",
		"map": target_map,
		"scene": target_scene,
		"instance": target_instance,
		"map_population": instance_manager.get_map_instance_population(target_map, target_instance),
		"position": target_position,
		"facing": target_facing,
		"target_teleport": target_teleport,
		"battle": _make_battle_state(client_id, ""),
	})

	sync_visibility_group(old_map, old_scene, old_instance)
	sync_visibility_group(target_map, target_scene, target_instance)
	logger.info("Client teleport: %d - %s/%s -> %s/%s" % [client_id, old_map, old_scene, target_map, target_scene])


func _handle_request_sync(client_id: int) -> void:
	logger.info("Client request sync: %d" % client_id)

	var player = server_manager.remote_players.get(client_id, null)
	if player == null:
		return

	var players_in_instance = instance_manager.get_instance_players(player.map, player.scene, player.instance)
	var players := []

	for other_client_id in players_in_instance:
		if other_client_id == client_id:
			continue

		var other_player = server_manager.remote_players.get(other_client_id, null)
		if other_player == null:
			continue

		players.append(_make_sync_player_data(other_player))

	server_manager.send_to_client(client_id, {
		"type": "s_request_sync",
		"players": players,
		"map": player.map,
		"scene": player.scene,
		"instance": player.instance,
		"map_population": instance_manager.get_map_instance_population(player.map, player.instance)
	})


# --------------------------------------------------
# BATTLE SYSTEM
# --------------------------------------------------
func _now() -> float:
	return BattleCalculator.now()


func _update_battle_timers(delta: float) -> void:
	var players_in_battle := _get_players_in_battle()

	for client_id in battle_players.keys():
		var player: Dictionary = battle_players[client_id]
		var original_hp := float(player.get("hp", PLAYER_MAX_HP))
		var original_mp := float(player.get("mp", PLAYER_MAX_MP))
		var original_effect_count: int = player.get("effects", []).size()
		var original_effect_seconds := _effects_second_signature(player.get("effects", []))
		var is_in_battle := players_in_battle.has(client_id)

		if is_in_battle:
			player = BattleCalculator.process_effects(player)
		else:
			# DOT/debuff effects are battle-only. If a player teleports or leaves
			# battle, clear them before processing effects so a queued DOT tick
			# cannot damage them after they arrive in the new scene.
			player.effects = _remove_player_debuff_effects(player.get("effects", []))
			player = BattleCalculator.process_effects(player)
			player = BattleCalculator.regen_player_out_of_battle(player, delta)

		battle_players[client_id] = player

		if (
			not is_equal_approx(original_hp, float(player.get("hp", PLAYER_MAX_HP)))
			or not is_equal_approx(original_mp, float(player.get("mp", PLAYER_MAX_MP)))
			or original_effect_count != player.get("effects", []).size()
			or original_effect_seconds != _effects_second_signature(player.get("effects", []))
		):
			if not changed_players.has(client_id):
				changed_players.append(client_id)

	for key in battle_enemies.keys().duplicate():
		var enemy: Dictionary = battle_enemies[key]

		if bool(enemy.get("defeated", false)):
			var respawn_at := float(enemy.get("respawn_at", 0.0))
			if respawn_at > 0.0 and _now() >= respawn_at:
				enemy.hp = float(enemy.get("max_hp", ENEMY_MAX_HP))
				enemy.mp = float(enemy.get("max_mp", ENEMY_MAX_MP))
				enemy.cooldowns = {}
				enemy.effects = []
				enemy.defeated = false
				enemy.respawn_at = 0.0
				enemy.attackers = []
				battle_enemies[key] = enemy
				_broadcast_enemy_visibility(enemy, true)
				_broadcast_battle_state_to_enemy_instance(enemy)
			continue

		var original_enemy_hp := float(enemy.get("hp", ENEMY_MAX_HP))
		var original_enemy_mp := float(enemy.get("mp", ENEMY_MAX_MP))
		var original_enemy_effect_count: int = enemy.get("effects", []).size()
		var original_enemy_effect_seconds := _effects_second_signature(enemy.get("effects", []))

		enemy = BattleCalculator.process_effects(enemy)

		var enemy_effects_changed: bool = (
			not is_equal_approx(original_enemy_hp, float(enemy.get("hp", ENEMY_MAX_HP)))
			or not is_equal_approx(original_enemy_mp, float(enemy.get("mp", ENEMY_MAX_MP)))
			or original_enemy_effect_count != enemy.get("effects", []).size()
			or original_enemy_effect_seconds != _effects_second_signature(enemy.get("effects", []))
		)

		if float(enemy.get("hp", ENEMY_MAX_HP)) <= 0.0:
			_mark_enemy_defeated(str(key), enemy)
			continue

		if enemy.get("attackers", []).is_empty():
			_reset_enemy_if_no_attackers(str(key), enemy)
			if enemy_effects_changed:
				_broadcast_battle_state_to_enemy_instance(enemy)
			continue

		battle_enemies[key] = enemy

		if enemy_effects_changed:
			_broadcast_battle_state_to_enemy_instance(enemy)

		if _apply_enemy_action_by_key(str(key)):
			var updated_enemy: Dictionary = battle_enemies.get(key, enemy)
			_broadcast_battle_state_to_enemy_instance(updated_enemy)

	battle_broadcast_timer += delta
	if battle_broadcast_timer >= BATTLE_STATE_BROADCAST_INTERVAL:
		battle_broadcast_timer = 0.0

		for client_id in changed_players:
			if server_manager.connected_clients.has(client_id):
				_send_battle_state(client_id)

		changed_players.clear()


func _effects_second_signature(effects: Array) -> String:
	var parts := []
	var current_time := _now()
	for effect in effects:
		if not effect is Dictionary:
			continue
		var expires_at := float(effect.get("expires_at", 0.0))
		var remaining = max(0.0, expires_at - current_time) if expires_at > 0.0 else 0.0
		parts.append("%s:%d:%d" % [str(effect.get("id", "")), int(effect.get("stacks", 1)), ceili(remaining)])
	return "|".join(parts)


func _get_players_in_battle() -> Dictionary:
	var players := {}

	for enemy in battle_enemies.values():
		if bool(enemy.get("defeated", false)):
			continue

		for client_id in enemy.get("attackers", []):
			if server_manager.connected_clients.has(client_id):
				players[client_id] = true

	return players


func _get_player_instance_data(client_id: int) -> Dictionary:
	return server_manager.remote_players.get(client_id, {})


func _get_or_create_player_battle_state(client_id: int) -> Dictionary:
	var world_player := _get_player_instance_data(client_id)
	var map := str(world_player.get("map", ""))
	var scene := str(world_player.get("scene", ""))
	var instance := int(world_player.get("instance", -1))

	var player: Dictionary = battle_players.get(
		client_id,
		BattleCalculator.create_player_battle_state(map, scene, instance)
	)

	player.map = map
	player.scene = scene
	player.instance = instance

	battle_players[client_id] = player
	return player


func _enemy_key_for_player(client_id: int, enemy_id: String) -> String:
	var player := _get_player_instance_data(client_id)

	return "%s::%s::%s::%s" % [
		str(player.get("map", SceneManager.current_map)),
		str(player.get("scene", SceneManager.current_scene)),
		str(player.get("instance", SceneManager.current_instance)),
		enemy_id,
	]


func _enemy_max_hp_from_data(data: Dictionary) -> float:
	var max_hp := float(data.get("enemy_max_hp", data.get("max_hp", ENEMY_MAX_HP)))
	return max(1.0, max_hp)


func _enemy_max_mp_from_data(data: Dictionary) -> float:
	var max_mp := float(data.get("enemy_max_mp", data.get("max_mp", ENEMY_MAX_MP)))
	return max(0.0, max_mp)


func _enemy_mp_from_data(data: Dictionary, fallback_max_mp: float) -> float:
	return clamp(float(data.get("enemy_mp", data.get("mp", fallback_max_mp))), 0.0, fallback_max_mp)


func _enemy_respawn_seconds_from_data(data: Dictionary) -> float:
	return max(0.0, float(data.get("enemy_respawn_seconds", data.get("respawn_seconds", ENEMY_RESPAWN_SECONDS))))


func _enemy_reward_gold_min_from_data(data: Dictionary) -> int:
	return max(0, int(data.get("enemy_reward_gold_min", data.get("gold_min", DEFAULT_ENEMY_REWARD_GOLD_MIN))))


func _enemy_reward_gold_max_from_data(data: Dictionary) -> int:
	return max(_enemy_reward_gold_min_from_data(data), int(data.get("enemy_reward_gold_max", data.get("gold_max", DEFAULT_ENEMY_REWARD_GOLD_MAX))))


func _enemy_reward_xp_from_data(data: Dictionary) -> Dictionary:
	var xp = data.get("enemy_reward_xp", data.get("xp", {}))
	if xp is Dictionary:
		return (xp as Dictionary).duplicate(true)
	return {}


func _apply_enemy_rewards_from_data(enemy: Dictionary, data: Dictionary) -> Dictionary:
	if data.is_empty():
		return enemy

	enemy.respawn_seconds = _enemy_respawn_seconds_from_data(data)
	enemy.reward_gold_min = _enemy_reward_gold_min_from_data(data)
	enemy.reward_gold_max = _enemy_reward_gold_max_from_data(data)
	enemy.reward_xp = _enemy_reward_xp_from_data(data)
	enemy.definition_id = str(data.get("enemy_definition_id", data.get("definition_id", enemy.get("definition_id", ""))))
	return enemy


func _roll_enemy_gold_reward(enemy: Dictionary) -> int:
	var gold_min = max(0, int(enemy.get("reward_gold_min", DEFAULT_ENEMY_REWARD_GOLD_MIN)))
	var gold_max = max(gold_min, int(enemy.get("reward_gold_max", gold_min)))
	if gold_max <= gold_min:
		return gold_min
	return randi_range(gold_min, gold_max)


func _apply_enemy_scene_stats(enemy: Dictionary, data: Dictionary, only_when_new: bool = false) -> Dictionary:
	if data.is_empty():
		return enemy

	enemy = _apply_enemy_rewards_from_data(enemy, data)

	var scene_max_hp := _enemy_max_hp_from_data(data)
	var scene_max_mp := _enemy_max_mp_from_data(data)
	var current_max_hp := float(enemy.get("max_hp", ENEMY_MAX_HP))
	var current_max_mp := float(enemy.get("max_mp", ENEMY_MAX_MP))

	if only_when_new or not is_equal_approx(scene_max_hp, current_max_hp):
		enemy.max_hp = scene_max_hp

		if bool(enemy.get("defeated", false)):
			enemy.hp = 0.0
		else:
			var supplied_hp := float(data.get("enemy_hp", data.get("hp", scene_max_hp)))
			enemy.hp = clamp(float(enemy.get("hp", supplied_hp)), 0.0, scene_max_hp)

	if only_when_new or not is_equal_approx(scene_max_mp, current_max_mp):
		enemy.max_mp = scene_max_mp

		if bool(enemy.get("defeated", false)):
			enemy.mp = 0.0
		else:
			var supplied_mp := _enemy_mp_from_data(data, scene_max_mp)
			enemy.mp = clamp(float(enemy.get("mp", supplied_mp)), 0.0, scene_max_mp)

	return enemy


func _get_or_create_enemy_state(client_id: int, enemy_id: String, enemy_name: String = "Enemy", scene_stats: Dictionary = {}) -> Dictionary:
	var key := _enemy_key_for_player(client_id, enemy_id)
	var player := _get_player_instance_data(client_id)

	if not battle_enemies.has(key):
		var scene_max_hp := _enemy_max_hp_from_data(scene_stats)
		var scene_max_mp := _enemy_max_mp_from_data(scene_stats)
		battle_enemies[key] = BattleCalculator.create_enemy_battle_state(
			enemy_id,
			enemy_name,
			str(player.get("map", SceneManager.current_map)),
			str(player.get("scene", SceneManager.current_scene)),
			int(player.get("instance", SceneManager.current_instance)),
			scene_max_hp,
			scene_max_mp,
			ENEMY_SKILL_ORDER
		)
		battle_enemies[key] = _apply_enemy_rewards_from_data(battle_enemies[key], scene_stats)
	else:
		var enemy: Dictionary = battle_enemies[key]
		if enemy_name != "" and str(enemy.get("name", "")) == "Enemy":
			enemy.name = enemy_name
		enemy = _apply_enemy_scene_stats(enemy, scene_stats)
		battle_enemies[key] = enemy

	return battle_enemies[key]


func _save_enemy_state(client_id: int, enemy_id: String, enemy: Dictionary) -> void:
	battle_enemies[_enemy_key_for_player(client_id, enemy_id)] = enemy


func _add_attacker(enemy: Dictionary, client_id: int) -> Dictionary:
	var attackers: Array = enemy.get("attackers", [])
	var was_idle := attackers.is_empty()

	if not attackers.has(client_id):
		attackers.append(client_id)

	enemy.attackers = attackers

	if was_idle:
		enemy.next_action_at = _now() + ENEMY_FIRST_ATTACK_DELAY

	return enemy


func _reset_enemy_if_no_attackers(enemy_key: String, enemy: Dictionary) -> bool:
	if bool(enemy.get("defeated", false)):
		return false

	if enemy.get("attackers", []).size() > 0:
		return false

	var max_hp := float(enemy.get("max_hp", ENEMY_MAX_HP))
	var max_mp := float(enemy.get("max_mp", ENEMY_MAX_MP))

	var needs_reset := not is_equal_approx(float(enemy.get("hp", max_hp)), max_hp)
	needs_reset = needs_reset or not is_equal_approx(float(enemy.get("mp", max_mp)), max_mp)
	needs_reset = needs_reset or not enemy.get("cooldowns", {}).is_empty()
	needs_reset = needs_reset or not enemy.get("effects", []).is_empty()
	needs_reset = needs_reset or float(enemy.get("next_action_at", 0.0)) != 0.0
	needs_reset = needs_reset or int(enemy.get("skill_index", 0)) != 0

	if not needs_reset:
		battle_enemies[enemy_key] = enemy
		return false

	enemy.hp = max_hp
	enemy.mp = max_mp
	enemy.cooldowns = {}
	enemy.effects = []
	enemy.next_action_at = 0.0
	enemy.skill_index = 0

	battle_enemies[enemy_key] = enemy
	_broadcast_enemy_visibility(enemy, true)
	_broadcast_battle_state_to_enemy_instance(enemy)
	return true


func _make_battle_state(client_id: int, enemy_id: String = "") -> Dictionary:
	var player := _get_or_create_player_battle_state(client_id)

	var target_id := enemy_id if enemy_id != "" else str(player.get("target_enemy_id", ""))
	var enemy := {}

	if target_id != "":
		enemy = _get_or_create_enemy_state(client_id, target_id)

	var respawn_remaining := 0.0
	if not enemy.is_empty() and bool(enemy.get("defeated", false)):
		respawn_remaining = max(0.0, float(enemy.get("respawn_at", 0.0)) - _now())

	return {
		"player": {
			"map": player.get("map", ""),
			"scene": player.get("scene", ""),
			"instance": player.get("instance", -1),
			"hp": player.get("hp", PLAYER_MAX_HP),
			"max_hp": player.get("max_hp", PLAYER_MAX_HP),
			"mp": player.get("mp", PLAYER_MAX_MP),
			"max_mp": player.get("max_mp", PLAYER_MAX_MP),
			"cooldowns": BattleCalculator.compact_cooldowns(player.get("cooldowns", {})),
			"effects": BattleCalculator.compact_effects(player.get("effects", [])),
			"target_enemy_id": target_id,
			"in_battle": _is_player_in_battle(client_id),
		},
		"enemy": {
			"id": enemy.get("id", ""),
			"name": enemy.get("name", "Enemy"),
			"hp": enemy.get("hp", 0.0),
			"max_hp": enemy.get("max_hp", ENEMY_MAX_HP),
			"mp": enemy.get("mp", ENEMY_MAX_MP),
			"max_mp": enemy.get("max_mp", ENEMY_MAX_MP),
			"cooldowns": BattleCalculator.compact_cooldowns(enemy.get("cooldowns", {})),
			"effects": BattleCalculator.compact_effects(enemy.get("effects", [])),
			"skill_order": enemy.get("skill_order", ENEMY_SKILL_ORDER),
			"defeated": bool(enemy.get("defeated", false)),
			"respawn_remaining": respawn_remaining,
		},
		"skills": _get_player_skills(),
		"status": _get_battle_status(player, enemy),
	}


func _is_player_in_battle(client_id: int) -> bool:
	for enemy in battle_enemies.values():
		if bool(enemy.get("defeated", false)):
			continue

		if enemy.get("attackers", []).has(client_id):
			return true

	return false


func _get_battle_status(player: Dictionary, enemy: Dictionary) -> String:
	if float(player.get("hp", PLAYER_MAX_HP)) <= 0.0:
		return "enemy_won"

	if not enemy.is_empty() and bool(enemy.get("defeated", false)):
		return "enemy_defeated"

	return "active"


func _send_battle_state(client_id: int) -> void:
	server_manager.send_to_client(client_id, {
		"type": "s_battle_state",
		"battle": _make_battle_state(client_id),
	})


func _get_enemy_instance_players(enemy: Dictionary) -> Array:
	var map := str(enemy.get("map", SceneManager.current_map))
	var scene := str(enemy.get("scene", SceneManager.current_scene))
	var instance := int(enemy.get("instance", SceneManager.current_instance))

	return instance_manager.get_instance_players(map, scene, instance)


func _broadcast_battle_state_to_enemy_instance(enemy: Dictionary) -> void:
	var enemy_id := str(enemy.get("id", ""))

	for target_client_id in _get_enemy_instance_players(enemy):
		if not server_manager.connected_clients.has(target_client_id):
			continue

		var player: Dictionary = _get_or_create_player_battle_state(target_client_id)

		if str(player.get("target_enemy_id", "")) == enemy_id or enemy.get("attackers", []).has(target_client_id):
			_send_battle_state(target_client_id)


func _broadcast_enemy_visibility(enemy: Dictionary, visible: bool) -> void:
	var enemy_id := str(enemy.get("id", ""))
	if enemy_id == "":
		return

	for target_client_id in _get_enemy_instance_players(enemy):
		if not server_manager.connected_clients.has(target_client_id):
			continue

		server_manager.send_to_client(target_client_id, {
			"type": "s_enemy_visibility",
			"enemy_id": enemy_id,
			"visible": visible,
			"hp": enemy.get("hp", ENEMY_MAX_HP),
			"max_hp": enemy.get("max_hp", ENEMY_MAX_HP),
			"mp": enemy.get("mp", ENEMY_MAX_MP),
			"max_mp": enemy.get("max_mp", ENEMY_MAX_MP),
		})


func _handle_select_enemy(client_id: int, data: Dictionary) -> void:
	var player := _get_or_create_player_battle_state(client_id)

	var enemy_id := str(data.get("enemy_id", ""))
	if enemy_id == "":
		return

	var enemy_name := str(data.get("enemy_name", "Enemy"))
	var enemy := _get_or_create_enemy_state(client_id, enemy_id, enemy_name, data)

	player.target_enemy_id = enemy_id
	battle_players[client_id] = player

	_send_battle_state(client_id)

	server_manager.send_to_client(client_id, {
		"type": "s_enemy_visibility",
		"enemy_id": enemy_id,
		"visible": not bool(enemy.get("defeated", false)),
		"hp": enemy.get("hp", ENEMY_MAX_HP),
		"max_hp": enemy.get("max_hp", ENEMY_MAX_HP),
		"mp": enemy.get("mp", ENEMY_MAX_MP),
		"max_mp": enemy.get("max_mp", ENEMY_MAX_MP),
	})


func _handle_use_skill(client_id: int, data: Dictionary) -> void:
	var skill_id := str(data.get("skill_id", ""))
	var skill: Dictionary = _get_player_skill(skill_id)

	if skill.is_empty():
		_send_battle_error(client_id, "Unknown skill")
		return

	var player := _get_or_create_player_battle_state(client_id)
	player = BattleCalculator.process_effects(player)

	if float(player.get("hp", PLAYER_MAX_HP)) <= 0.0:
		battle_players[client_id] = player
		_send_battle_state(client_id)
		return

	if BattleCalculator.has_effect(player, BattleCalculator.EFFECT_STUN):
		battle_players[client_id] = player
		_send_battle_error(client_id, "You are stunned")
		_send_battle_state(client_id)
		return

	var skill_type := str(skill.get("type", ""))
	var needs_enemy := skill_type == "melee" or skill_type == "magic" or skill_type == "debuff"
	var targets_self := skill_type == "buff"

	var enemy_id := str(data.get("enemy_id", player.get("target_enemy_id", "")))
	var enemy := {}

	if needs_enemy:
		if enemy_id == "":
			_send_battle_error(client_id, "No enemy target selected")
			_send_battle_state(client_id)
			return

		enemy = _get_or_create_enemy_state(client_id, enemy_id, str(data.get("enemy_name", "Enemy")), data)
		enemy = BattleCalculator.process_effects(enemy)

		if bool(enemy.get("defeated", false)):
			_send_battle_error(client_id, "Enemy is defeated")
			_send_battle_state(client_id)
			return

	var cooldowns: Dictionary = player.get("cooldowns", {})

	if BattleCalculator.is_on_cooldown(cooldowns, GLOBAL_SKILL_COOLDOWN_ID):
		_send_battle_error(client_id, "Skills are on global cooldown")
		_send_battle_state(client_id) 
		return

	if BattleCalculator.is_on_cooldown(cooldowns, skill_id):
		_send_battle_error(client_id, "Skill is on cooldown")
		_send_battle_state(client_id)
		return

	var mp_cost := float(skill.get("mp_cost", 0.0))
	if float(player.get("mp", 0.0)) < mp_cost:
		_send_battle_error(client_id, "Not enough MP")
		_send_battle_state(client_id)
		return

	player.mp = max(0.0, float(player.get("mp", 0.0)) - mp_cost)

	cooldowns[skill_id] = _now() + BattleCalculator.get_skill_cooldown(player, skill)

	cooldowns[GLOBAL_SKILL_COOLDOWN_ID] = _now() + PLAYER_GLOBAL_SKILL_COOLDOWN

	player.cooldowns = cooldowns

	if enemy_id != "":
		player.target_enemy_id = enemy_id

	if needs_enemy:
		enemy = _add_attacker(enemy, client_id)

	match skill_type:
		"melee", "magic":
			var damage := BattleCalculator.calculate_player_damage(player, enemy, skill)
			enemy.hp = max(0.0, float(enemy.get("hp", ENEMY_MAX_HP)) - damage)
			enemy = BattleCalculator.apply_effects(enemy, skill.get("effects", []), str(client_id))

		"debuff":
			enemy = BattleCalculator.apply_effects(enemy, skill.get("effects", []), str(client_id))

		"buff":
			player = BattleCalculator.apply_effects(player, skill.get("effects", []), str(client_id))

		_:
			if targets_self:
				player = BattleCalculator.apply_effects(player, skill.get("effects", []), str(client_id))

	battle_players[client_id] = player

	if not needs_enemy:
		_send_battle_state(client_id)
		return

	if float(enemy.get("hp", 0.0)) <= 0.0:
		_mark_enemy_defeated(_enemy_key_for_player(client_id, enemy_id), enemy)
		return

	_save_enemy_state(client_id, enemy_id, enemy)
	_broadcast_enemy_visibility(enemy, true)
	_apply_enemy_action(client_id, enemy_id)
	_broadcast_battle_state_to_enemy_instance(enemy)


func _mark_enemy_defeated(enemy_key: String, enemy: Dictionary) -> void:
	var attackers: Array = enemy.get("attackers", []).duplicate()
	var enemy_id := str(enemy.get("id", ""))

	enemy.defeated = true
	enemy.hp = 0.0
	enemy.respawn_at = _now() + float(enemy.get("respawn_seconds", ENEMY_RESPAWN_SECONDS))
	enemy.next_action_at = 0.0
	enemy.attackers = []
	enemy.cooldowns = {}
	enemy.effects = []

	battle_enemies[enemy_key] = enemy

	for attacker_id in attackers:
		if not battle_players.has(attacker_id):
			continue

		var player: Dictionary = battle_players[attacker_id]
		player.effects = _remove_player_debuff_effects(player.get("effects", []))

		if str(player.get("target_enemy_id", "")) == enemy_id:
			player.target_enemy_id = ""

		battle_players[attacker_id] = player
		_send_enemy_reward(attacker_id, enemy)
		_send_battle_state(attacker_id)

	_broadcast_enemy_visibility(enemy, false)
	_broadcast_battle_state_to_enemy_instance(enemy)


func _send_enemy_reward(client_id: int, enemy: Dictionary) -> void:
	var gold_reward := _roll_enemy_gold_reward(enemy)
	var xp_reward: Dictionary = {}
	var raw_xp = enemy.get("reward_xp", {})
	if raw_xp is Dictionary:
		xp_reward = (raw_xp as Dictionary).duplicate(true)

	server_manager.send_to_client(client_id, {
		"type": "s_enemy_reward",
		"enemy_id": str(enemy.get("id", "")),
		"enemy_definition_id": str(enemy.get("definition_id", "")),
		"gold": gold_reward,
		"xp": xp_reward.duplicate(true),
	})


func _apply_enemy_action_by_key(enemy_key: String) -> bool:
	if not battle_enemies.has(enemy_key):
		return false

	var enemy: Dictionary = battle_enemies[enemy_key]
	return _apply_enemy_action_state(enemy_key, enemy)


func _apply_enemy_action(attacking_client_id: int, enemy_id: String) -> bool:
	var enemy_key := _enemy_key_for_player(attacking_client_id, enemy_id)
	var enemy := _get_or_create_enemy_state(attacking_client_id, enemy_id)

	return _apply_enemy_action_state(enemy_key, enemy)



func _is_valid_enemy_attacker(enemy: Dictionary, client_id: int) -> bool:
	if not server_manager.connected_clients.has(client_id):
		return false

	if not battle_players.has(client_id):
		return false

	var player_state: Dictionary = battle_players.get(client_id, {})

	if float(player_state.get("hp", PLAYER_MAX_HP)) <= 0.0:
		return false

	# Teleporting/changing scene is a hard battle exit. This protects against
	# any enemy action that was due on the same frame as the teleport by making
	# sure the player is still targeting this enemy and still in the same area.
	if str(player_state.get("target_enemy_id", "")) != str(enemy.get("id", "")):
		return false

	if str(player_state.get("map", SceneManager.current_map)) != str(enemy.get("map", SceneManager.current_map)):
		return false

	if str(player_state.get("scene", SceneManager.current_scene)) != str(enemy.get("scene", SceneManager.current_scene)):
		return false

	if int(player_state.get("instance", SceneManager.current_instance)) != int(enemy.get("instance", SceneManager.current_instance)):
		return false

	return true

func _apply_enemy_action_state(enemy_key: String, enemy: Dictionary) -> bool:
	if bool(enemy.get("defeated", false)) or float(enemy.get("hp", ENEMY_MAX_HP)) <= 0.0:
		_mark_enemy_defeated(enemy_key, enemy)
		return false

	if _now() < float(enemy.get("next_action_at", 0.0)):
		battle_enemies[enemy_key] = enemy
		return false

	if BattleCalculator.has_effect(enemy, BattleCalculator.EFFECT_STUN):
		enemy.next_action_at = _now() + ENEMY_ACTION_INTERVAL
		battle_enemies[enemy_key] = enemy
		return true

	var attackers: Array = enemy.get("attackers", [])
	var valid_attackers := []

	for client_id in attackers:
		if _is_valid_enemy_attacker(enemy, client_id):
			valid_attackers.append(client_id)

	enemy.attackers = valid_attackers

	if valid_attackers.is_empty():
		_reset_enemy_if_no_attackers(enemy_key, enemy)
		return false

	var enemy_cooldowns: Dictionary = enemy.get("cooldowns", {})
	var skill_order: Array = enemy.get("skill_order", ENEMY_SKILL_ORDER)
	var skill_index := int(enemy.get("skill_index", 0))

	if skill_order.is_empty():
		enemy.next_action_at = _now() + ENEMY_ACTION_INTERVAL
		battle_enemies[enemy_key] = enemy
		return true

	var chosen_skill_id := str(skill_order[skill_index % skill_order.size()])
	var chosen_skill: Dictionary = _get_player_skill(chosen_skill_id)

	enemy.skill_index = skill_index + 1

	if chosen_skill.is_empty():
		enemy.next_action_at = _now() + ENEMY_ACTION_INTERVAL
		battle_enemies[enemy_key] = enemy
		return true

	var target_client_id: int = _choose_enemy_target(enemy, valid_attackers)
	var player := _get_or_create_player_battle_state(target_client_id)
	var skill: Dictionary = chosen_skill

	if bool(enemy.get("defeated", false)) or float(enemy.get("hp", ENEMY_MAX_HP)) <= 0.0:
		_mark_enemy_defeated(enemy_key, enemy)
		return false

	# Re-check immediately before applying damage. The target may have
	# teleported/changed scene since the valid attacker list was built.
	if not _is_valid_enemy_attacker(enemy, target_client_id):
		enemy.next_action_at = 0.0 if enemy.get("attackers", []).is_empty() else _now() + ENEMY_ACTION_INTERVAL
		battle_enemies[enemy_key] = enemy
		return false

	var damage := BattleCalculator.calculate_enemy_damage(enemy, player, skill)
	player.hp = max(0.0, float(player.get("hp", PLAYER_MAX_HP)) - damage)

	if float(player.get("hp", PLAYER_MAX_HP)) > 0.0:
		player = BattleCalculator.apply_effects(player, skill.get("effects", []), str(enemy.get("id", "")))

	enemy_cooldowns[chosen_skill_id] = _now() + BattleCalculator.get_skill_cooldown(enemy, skill)
	enemy.cooldowns = enemy_cooldowns
	enemy.next_action_at = _now() + ENEMY_ACTION_INTERVAL

	battle_players[target_client_id] = player
	battle_enemies[enemy_key] = enemy

	return true


func _choose_enemy_target(enemy: Dictionary, valid_attackers: Array) -> int:
	for effect in enemy.get("effects", []):
		if not effect is Dictionary:
			continue

		if str(effect.get("type", "")) != BattleCalculator.EFFECT_TAUNT:
			continue

		var source_id := int(str(effect.get("source_id", "0")))
		if valid_attackers.has(source_id):
			return source_id

	return int(valid_attackers[randi() % valid_attackers.size()])


func _handle_reset_player_battle(client_id: int) -> void:
	var player: Dictionary = _get_or_create_player_battle_state(client_id)
	player.hp = float(player.get("max_hp", PLAYER_MAX_HP))
	player.mp = float(player.get("max_mp", PLAYER_MAX_MP))
	player.cooldowns = {}
	player.effects = []
	player.target_enemy_id = ""

	battle_players[client_id] = player

	for key in battle_enemies.keys().duplicate():
		var enemy: Dictionary = battle_enemies[key]
		var attackers: Array = enemy.get("attackers", [])

		if attackers.has(client_id):
			attackers.erase(client_id)
			enemy.attackers = attackers


func _exit_player_battle_for_area_change(client_id: int) -> void:
	var player: Dictionary = _get_or_create_player_battle_state(client_id)

	# Changing scene/map is a hard battle exit. Clear both the current
	# target and any active battle effects so debuffs do not carry into
	# the next scene. HP/MP/cooldowns are kept, matching normal battle
	# exit behaviour.
	player.target_enemy_id = ""
	player.effects = []
	battle_players[client_id] = player

	for key in battle_enemies.keys().duplicate():
		var enemy: Dictionary = battle_enemies[key]
		var attackers: Array = enemy.get("attackers", [])

		if not attackers.has(client_id):
			continue

		attackers.erase(client_id)
		enemy.attackers = attackers

		if attackers.is_empty():
			enemy.next_action_at = 0.0

		battle_enemies[key] = enemy
		_reset_enemy_if_no_attackers(str(key), enemy)

	_send_battle_state(client_id)


func _remove_player_debuff_effects(effects: Array) -> Array:
	var kept_effects := []

	for effect in effects:
		if not effect is Dictionary:
			continue

		var effect_type := str(effect.get("type", ""))

		if effect_type == BattleCalculator.EFFECT_DEBUFF:
			continue
		if effect_type == BattleCalculator.EFFECT_DOT:
			continue
		if effect_type == BattleCalculator.EFFECT_STUN:
			continue
		if effect_type == BattleCalculator.EFFECT_TAUNT:
			continue

		kept_effects.append(effect)

	return kept_effects


func _send_battle_error(client_id: int, message: String) -> void:
	server_manager.send_to_client(client_id, {
		"type": "s_battle_error",
		"message": message,
	})


# --------------------------------------------------
# CLIENT PACKETS
# --------------------------------------------------
func _is_battle_state_for_current_area(battle: Dictionary) -> bool:
	if battle.is_empty():
		return true

	var player_state: Dictionary = battle.get("player", {})
	if player_state.is_empty():
		return true

	var state_map := str(player_state.get("map", SceneManager.current_map))
	var state_scene := str(player_state.get("scene", SceneManager.current_scene))
	var state_instance := int(player_state.get("instance", SceneManager.current_instance))

	return (
		state_map == str(SceneManager.current_map)
		and state_scene == str(SceneManager.current_scene)
		and state_instance == int(SceneManager.current_instance)
	)


func _apply_client_battle_state(battle: Dictionary) -> void:
	# A battle packet from the old scene can arrive after the teleport packet.
	# Ignore it so delayed enemy damage/effects cannot be applied to the UI
	# after the player has already landed in the new scene.
	if not _is_battle_state_for_current_area(battle):
		return

	var game := SceneManager.player.get_tree().root.get_node_or_null("Game") if SceneManager.player != null else null
	if game == null:
		return

	var ui := game.get_node_or_null("UI")
	if ui != null and ui.has_method("apply_battle_state"):
		ui.apply_battle_state(battle)


func _apply_client_enemy_visibility(data: Dictionary) -> void:
	var enemy_id := str(data.get("enemy_id", ""))
	if enemy_id == "":
		return

	var enemy := get_tree().root.get_node_or_null(enemy_id)
	if enemy == null:
		return

	enemy.visible = bool(data.get("visible", true))
	enemy.set_process(enemy.visible)
	enemy.set_physics_process(enemy.visible)
	enemy.set("hp", float(data.get("hp", enemy.get("hp"))))
	enemy.set("max_hp", float(data.get("max_hp", enemy.get("max_hp"))))

	var game := get_tree().root.get_node_or_null("Game")
	var ui := game.get_node_or_null("UI") if game != null else null

	if ui != null and ui.has_method("on_enemy_visibility_changed"):
		ui.on_enemy_visibility_changed(enemy, enemy.visible)


func _is_remote_move_for_current_area(data: Dictionary) -> bool:
	# Remote movement is sent unreliably/ordered, so an old movement packet
	# can arrive just after a teleport sync has removed that player from this
	# scene. Never let that stale packet respawn the remote player at their
	# previous scene position.
	if not data.has("map") and not data.has("scene") and not data.has("instance"):
		return true

	var packet_map := str(data.get("map", SceneManager.current_map))
	var packet_scene := str(data.get("scene", SceneManager.current_scene))
	var packet_instance := int(data.get("instance", SceneManager.current_instance))

	return (
		packet_map == str(SceneManager.current_map)
		and packet_scene == str(SceneManager.current_scene)
		and packet_instance == int(SceneManager.current_instance)
	)


func _apply_client_enemy_reward(data: Dictionary) -> void:
	var gold_reward := int(data.get("gold", 0))
	var xp_reward = data.get("xp", {})
	if not (xp_reward is Dictionary):
		xp_reward = {}

	var xp_dictionary := (xp_reward as Dictionary).duplicate(true)
	if xp_dictionary.is_empty():
		xp_dictionary = _get_cached_enemy_definition_xp(str(data.get("enemy_definition_id", "")))

	if Firebase.has_method("add_character_rewards"):
		Firebase.add_character_rewards(gold_reward, xp_dictionary)

	if logger != null:
		logger.info("Enemy reward: +%d gold, xp=%s" % [gold_reward, str(xp_dictionary)])


func _get_cached_enemy_definition_xp(definition_id: String) -> Dictionary:
	definition_id = definition_id.strip_edges()
	if definition_id == "":
		return {}
	if not Firebase.has_method("get_enemy_definition"):
		return {}

	var definition = Firebase.get_enemy_definition(definition_id)
	if not (definition is Dictionary):
		return {}

	var xp = (definition as Dictionary).get("xp", {})
	if xp is Dictionary:
		return (xp as Dictionary).duplicate(true)

	return {}


func handle_client_packet(data: Dictionary) -> void:
	match data.get("type", ""):
		"s_login_rejected":
			var message := str(data.get("message", "Login rejected."))
			logger.warn(message)
			if server_manager.has_signal("login_rejected"):
				server_manager.login_rejected.emit(message)
			server_manager.handle_server_disconnect()

		"s_login_replaced":
			var message := str(data.get("message", "Your account was logged in on another device."))
			logger.warn(message)
			if server_manager.has_signal("login_rejected"):
				server_manager.login_rejected.emit(message)
			server_manager.handle_server_disconnect()

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
			_apply_client_battle_state(data.get("battle", {}))

			server_manager.send_to_server({
				"type": "c_request_sync"
			})

		"s_battle_state":
			_apply_client_battle_state(data.get("battle", {}))

		"s_enemy_visibility":
			_apply_client_enemy_visibility(data)

		"s_battle_error":
			logger.warn("Battle error: %s" % data.get("message", "Unknown battle error"))

		"s_enemy_reward":
			_apply_client_enemy_reward(data)

		"s_teleport_player":
			logger.info("Server teleport")
			await SceneManager.teleport_player_to(
				data.get("map", SceneManager.current_map),
				data.get("scene", SceneManager.current_scene),
				data.get("position", Vector2.ZERO),
				int(data.get("facing", 1)),
				str(data.get("target_teleport", "")),
				int(data.get("instance", SceneManager.current_instance)),
				int(data.get("map_population", SceneManager.current_map_population))
			)
			_apply_client_battle_state(data.get("battle", {}))

		"s_request_sync":
			_apply_client_sync(data)

		"s_remote_remove":
			SceneManager.remove_remote_player(int(data.get("id", 0)))

		"s_remote_move":
			if _is_remote_move_for_current_area(data):
				SceneManager.update_remote_player(
					data.id,
					data.position,
					int(data.get("facing", 1)),
					data.get("velocity", Vector2.ZERO),
					int(data.get("pose", 0)),
					int(data.get("sequence", 0)),
					bool(data.get("stopped", false)),
					data.get("reserved_enemy_approach_target", Vector2.INF),
				)
			else:
				SceneManager.remove_remote_player(int(data.get("id", 0)))


func _apply_client_sync(data: Dictionary) -> void:
	logger.info("Server request sync")

	# Sync packets are reliable, so a previous-room sync can arrive after this
	# client has already changed scene. Never let an old sync change the local
	# SceneManager status or recreate remotes at old-room positions.
	if data.has("map") or data.has("scene") or data.has("instance"):
		var sync_map := str(data.get("map", SceneManager.current_map))
		var sync_scene := str(data.get("scene", SceneManager.current_scene))
		var sync_instance := int(data.get("instance", SceneManager.current_instance))

		var sync_matches_current := (
			sync_map == str(SceneManager.current_map)
			and sync_scene == str(SceneManager.current_scene)
			and sync_instance == int(SceneManager.current_instance)
		)

		if not sync_matches_current:
			return

		SceneManager.set_map_status(
			SceneManager.current_map,
			SceneManager.current_scene,
			SceneManager.current_instance,
			int(data.get("map_population", SceneManager.current_map_population))
		)
	elif data.has("map_population"):
		SceneManager.set_map_status(
			SceneManager.current_map,
			SceneManager.current_scene,
			SceneManager.current_instance,
			int(data.get("map_population", SceneManager.current_map_population))
		)

	SceneManager.clear_remote_players()

	for p in data.players:
		# Only spawn players that explicitly belong to this exact area. This prevents
		# a late sync from another scene from recreating a remote at an old position.
		if not _is_remote_move_for_current_area(p):
			continue

		SceneManager.spawn_remote_player(
			p.id,
			p.position,
			int(p.get("facing", 1)),
			p.get("velocity", Vector2.ZERO),
			int(p.get("pose", 0)),
			int(p.get("sequence", 0)),
			bool(p.get("stopped", false)),
			p.get("reserved_enemy_approach_target", Vector2.INF),
		)


# --------------------------------------------------
# SYNC VISIBILITY GROUP
# --------------------------------------------------
func sync_visibility_group(map: String, scene: String, instance: int):
	var players_in_instance = instance_manager.get_instance_players(map, scene, instance)
	var map_population = instance_manager.get_map_instance_population(map, instance)

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
				visible_players.append(_make_sync_player_data(server_manager.remote_players[other_client_id]))

		server_manager.send_to_client(target_client_id, {
			"type": "s_request_sync",
			"players": visible_players,
			"map": map,
			"scene": scene,
			"instance": instance,
			"map_population": map_population
		})
