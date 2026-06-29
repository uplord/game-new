extends Node

signal enemy_reward_applied(client_id: int, data: Dictionary)
signal enemy_reward_failed(client_id: int, message: String)
signal player_death_applied(client_id: int, data: Dictionary)
signal player_death_failed(client_id: int, message: String)

# This endpoint should only be reachable from your dedicated/headless Godot server.
# Do not expose this URL publicly and do not include the secret in client exports.
const DEFAULT_ADMIN_BASE_URL := "http://127.0.0.1:8787"

var _http: HTTPRequest
var _busy := false
var _queue: Array = []
var _active_request: Dictionary = {}



func _get_admin_base_url() -> String:
	var value := OS.get_environment("UPLORD_ADMIN_REWARD_URL").strip_edges()
	if value == "":
		value = DEFAULT_ADMIN_BASE_URL
	return value.trim_suffix("/")


func _get_admin_secret() -> String:
	return OS.get_environment("UPLORD_ADMIN_REWARD_SECRET").strip_edges()

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func apply_enemy_reward(client_id: int, account_id: String, enemy_definition_id: String, enemy_id: String = "") -> void:
	account_id = account_id.strip_edges()
	enemy_definition_id = enemy_definition_id.strip_edges()
	if account_id == "":
		enemy_reward_failed.emit(client_id, "Missing account id.")
		return
	if enemy_definition_id == "":
		enemy_reward_failed.emit(client_id, "Missing enemy definition id.")
		return

	var secret := _get_admin_secret()
	if secret == "":
		enemy_reward_failed.emit(client_id, "Missing UPLORD_ADMIN_REWARD_SECRET on the Godot server.")
		return

	_enqueue({
		"kind": "enemy_reward",
		"client_id": client_id,
		"url": "%s/apply-enemy-reward" % _get_admin_base_url(),
		"body": {
			"secret": secret,
			"account_id": account_id,
			"enemy_definition_id": enemy_definition_id,
			"enemy_id": enemy_id,
		},
	})


func apply_player_death(client_id: int, account_id: String) -> void:
	account_id = account_id.strip_edges()
	if account_id == "":
		player_death_failed.emit(client_id, "Missing account id.")
		return

	var secret := _get_admin_secret()
	if secret == "":
		player_death_failed.emit(client_id, "Missing UPLORD_ADMIN_REWARD_SECRET on the Godot server.")
		return

	_enqueue({
		"kind": "player_death",
		"client_id": client_id,
		"url": "%s/apply-player-death" % _get_admin_base_url(),
		"body": {
			"secret": secret,
			"account_id": account_id,
		},
	})


func _enqueue(request_data: Dictionary) -> void:
	_queue.append(request_data)
	_process_queue()


func _process_queue() -> void:
	if _busy or _queue.is_empty():
		return

	_active_request = _queue.pop_front()
	_busy = true

	var body_text := JSON.stringify(_active_request.get("body", {}))
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])

	var err := _http.request(
		str(_active_request.get("url", "")),
		headers,
		HTTPClient.METHOD_POST,
		body_text
	)

	if err != OK:
		var failed_request := _active_request.duplicate(true)
		_active_request.clear()
		_busy = false
		_emit_failed(failed_request, "Admin reward request could not start: %s" % error_string(err))
		_process_queue()


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var finished_request := _active_request.duplicate(true)
	_active_request.clear()
	_busy = false

	var response_text := body.get_string_from_utf8()
	var response = JSON.parse_string(response_text)
	if not (response is Dictionary):
		_emit_failed(finished_request, "Admin reward server returned invalid JSON.")
		_process_queue()
		return

	var response_data := response as Dictionary
	if response_code < 200 or response_code >= 300 or not bool(response_data.get("ok", false)):
		_emit_failed(finished_request, str(response_data.get("error", "Admin reward request failed.")))
		_process_queue()
		return

	var client_id := int(finished_request.get("client_id", 0))
	match str(finished_request.get("kind", "")):
		"enemy_reward":
			enemy_reward_applied.emit(client_id, response_data)
		"player_death":
			player_death_applied.emit(client_id, response_data)

	_process_queue()


func _emit_failed(request_data: Dictionary, message: String) -> void:
	push_warning("Admin reward failed: %s" % message)
	var client_id := int(request_data.get("client_id", 0))
	match str(request_data.get("kind", "")):
		"enemy_reward":
			enemy_reward_failed.emit(client_id, message)
		"player_death":
			player_death_failed.emit(client_id, message)
