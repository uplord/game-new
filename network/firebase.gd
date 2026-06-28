extends Node

signal login_success(data: Dictionary)
signal login_failed(message: String)
signal auth_request_started
signal auth_request_finished
signal character_update_success(data: Dictionary)
signal character_update_failed(message: String)

const API_KEY := "AIzaSyDgVFX8sc5sxycJbOU9q0qNGkDjgdpWccU"
const PROJECT_ID := "uplord-adventure"
const AUTH_URL := "https://identitytoolkit.googleapis.com/v1"
const FIRESTORE_URL := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % PROJECT_ID
const FIRESTORE_RUN_QUERY_URL := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:runQuery" % PROJECT_ID
const ACCOUNTS_COLLECTION := "accounts"
const CHARACTERS_COLLECTION := "characters"

var http: HTTPRequest

var id_token := ""
var refresh_token := ""
var user_id := ""
var email := ""
var display_name := ""
var username := ""
var request_in_progress := false

var account_data: Dictionary = {}
var character_data: Dictionary = {}
var character_id := ""
var character_document_name := ""

var _request_kind := ""
var _pending_register_username := ""
var _pending_auth_kind := ""
var _pending_character_update_fields: Dictionary = {}


func _ready() -> void:
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_request_completed)


func is_authenticated() -> bool:
	return id_token != "" and user_id != ""


func has_character() -> bool:
	return character_id != "" and not character_data.is_empty()


func get_current_user_data() -> Dictionary:
	return {
		"idToken": id_token,
		"refreshToken": refresh_token,
		"localId": user_id,
		"email": email,
		"displayName": display_name,
		"username": get_display_name(),
		"account": account_data,
		"character_id": character_id,
		"character": character_data,
	}


func get_account_data() -> Dictionary:
	return account_data.duplicate(true)


func get_character_data() -> Dictionary:
	return character_data.duplicate(true)


func get_display_name() -> String:
	if username.strip_edges() != "":
		return username.strip_edges()

	if display_name.strip_edges() != "":
		return display_name.strip_edges()

	if email.find("@") > 0:
		return email.get_slice("@", 0)

	return "Undefined"


func get_character_name() -> String:
	var character_name := str(character_data.get("name", "")).strip_edges()
	if character_name != "":
		return character_name
	return get_display_name()


func get_character_value(path: String, fallback = null):
	return _get_nested_value(character_data, path, fallback)


func get_account_value(path: String, fallback = null):
	return _get_nested_value(account_data, path, fallback)


func logout() -> void:
	id_token = ""
	refresh_token = ""
	user_id = ""
	email = ""
	display_name = ""
	username = ""
	account_data.clear()
	character_data.clear()
	character_id = ""
	character_document_name = ""
	_pending_register_username = ""
	_pending_auth_kind = ""
	_request_kind = ""
	_pending_character_update_fields.clear()
	request_in_progress = false


func register_user(user_email: String, password: String, new_username: String = "") -> void:
	new_username = new_username.strip_edges()
	if new_username == "":
		login_failed.emit("Enter a username.")
		return

	if new_username.length() < 3:
		login_failed.emit("Username must be at least 3 characters.")
		return

	_pending_register_username = new_username
	_send_auth_request("accounts:signUp", user_email, password, "register")


func login(user_email: String, password: String) -> void:
	_pending_register_username = ""
	_send_auth_request("accounts:signInWithPassword", user_email, password, "login")


func update_character_fields(fields: Dictionary) -> void:
	if not is_authenticated() or character_id == "":
		character_update_failed.emit("No character is loaded.")
		return

	if request_in_progress:
		character_update_failed.emit("Please wait for the current Firebase request to finish.")
		return

	if fields.is_empty():
		character_update_success.emit(character_data)
		return

	_pending_character_update_fields = fields.duplicate(true)

	var firestore_fields := _build_firestore_fields_from_dot_paths(fields)
	var update_masks: Array[String] = []
	for key in fields.keys():
		update_masks.append("updateMask.fieldPaths=%s" % str(key).uri_encode())

	var body := JSON.stringify({"fields": firestore_fields})
	var url := "%s/%s/%s?%s" % [
		FIRESTORE_URL,
		CHARACTERS_COLLECTION,
		character_id,
		"&".join(update_masks),
	]

	request_in_progress = true
	_request_kind = "firestore_update_character"

	var err := http.request(url, _get_firestore_headers(), HTTPClient.METHOD_PATCH, body)
	if err != OK:
		request_in_progress = false
		_request_kind = ""
		_pending_character_update_fields.clear()
		character_update_failed.emit("Character update could not be started: %s" % error_string(err))


func update_character_field(path: String, value) -> void:
	update_character_fields({path: value})


func add_character_gold(amount: int) -> void:
	var current_gold := int(get_character_value("gold", 0))
	update_character_field("gold", max(0, current_gold + amount))


func set_character_skill_xp(skill_id: String, xp: int) -> void:
	update_character_field("skills.%s" % skill_id, max(0, xp))


func _send_auth_request(endpoint: String, user_email: String, password: String, request_kind: String) -> void:
	if request_in_progress:
		login_failed.emit("Please wait for the current login request to finish.")
		return

	user_email = user_email.strip_edges().to_lower()

	if user_email == "":
		login_failed.emit("Enter an email address.")
		return

	if password.length() < 6:
		login_failed.emit("Password must be at least 6 characters.")
		return

	var body := JSON.stringify({
		"email": user_email,
		"password": password,
		"returnSecureToken": true,
	})

	var url := "%s/%s?key=%s" % [AUTH_URL, endpoint, API_KEY]
	var headers := ["Content-Type: application/json"]

	request_in_progress = true
	_request_kind = request_kind
	_pending_auth_kind = request_kind
	auth_request_started.emit()

	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail_request("Could not start Firebase request: %s" % error_string(err))


func _send_display_name_update(new_display_name: String) -> void:
	new_display_name = new_display_name.strip_edges()

	if id_token == "" or new_display_name == "":
		_send_firestore_create_account()
		return

	var body := JSON.stringify({
		"idToken": id_token,
		"displayName": new_display_name,
		"returnSecureToken": true,
	})

	var url := "%s/accounts:update?key=%s" % [AUTH_URL, API_KEY]
	var headers := ["Content-Type: application/json"]

	_request_kind = "update_profile"

	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail_request("Account was created, but the username could not be saved: %s" % error_string(err))


func _send_firestore_create_account() -> void:
	if not is_authenticated():
		_fail_request("Cannot create account profile without a logged-in Firebase user.")
		return

	var now := _now_firestore_timestamp()
	var saved_username := _pending_register_username.strip_edges()
	if saved_username == "":
		saved_username = get_display_name()

	username = saved_username
	display_name = saved_username

	account_data = {
		"username": saved_username,
		"email": email.strip_edges().to_lower(),
		"banned": false,
		"role": "user",
		"gems": 100,
		"created_at": now,
		"last_login": now,
	}

	var body := JSON.stringify({"fields": _dictionary_to_firestore_fields(account_data)})
	var url := "%s/%s/%s" % [FIRESTORE_URL, ACCOUNTS_COLLECTION, user_id]

	_request_kind = "firestore_create_account"

	var err := http.request(url, _get_firestore_headers(), HTTPClient.METHOD_PATCH, body)
	if err != OK:
		_fail_request("Account was created, but the database profile could not be saved: %s" % error_string(err))


func _send_firestore_create_default_character() -> void:
	if not is_authenticated():
		_fail_request("Cannot create a character without a logged-in Firebase user.")
		return

	var now := _now_firestore_timestamp()
	var safe_name := get_display_name()
	character_id = "%s_character_0" % user_id
	character_document_name = "%s/%s/%s" % [FIRESTORE_URL, CHARACTERS_COLLECTION, character_id]

	character_data = {
		"account_id": user_id,
		"name": safe_name,
		"gold": 1000,
		"selected": true,
		"first_login": true,
		"created_at": now,
		"last_played": now,
		"appearance": {
			"armor": 0,
			"cape": 0,
			"hair": 0,
			"helm": 0,
		},
		"colours": {
			"base": "#ffffff",
			"eyes": "#ffffff",
			"hair": "#ffffff",
			"skin": "#ffffff",
			"trim": "#ffffff",
		},
		"skills": {
			"melee": 0,
			"magic": 0,
			"defence": 0,
			"healing": 0,
		},
		"stats": {
			"deaths": 0,
			"monsters_killed": 0,
			"play_time": 0,
		},
	}

	var body := JSON.stringify({"fields": _dictionary_to_firestore_fields(character_data)})
	var url := "%s/%s/%s" % [FIRESTORE_URL, CHARACTERS_COLLECTION, character_id]

	_request_kind = "firestore_create_character"

	var err := http.request(url, _get_firestore_headers(), HTTPClient.METHOD_PATCH, body)
	if err != OK:
		_fail_request("Account was created, but the starter character could not be saved: %s" % error_string(err))


func _send_firestore_update_last_login() -> void:
	if not is_authenticated():
		_finish_auth_success()
		return

	var body := JSON.stringify({
		"fields": {
			"last_login": {"timestampValue": _now_firestore_timestamp()},
		}
	})

	var url := "%s/%s/%s?updateMask.fieldPaths=last_login" % [FIRESTORE_URL, ACCOUNTS_COLLECTION, user_id]

	_request_kind = "firestore_update_last_login"

	var err := http.request(url, _get_firestore_headers(), HTTPClient.METHOD_PATCH, body)
	if err != OK:
		_fail_request("Logged in, but last login could not be updated: %s" % error_string(err))


func _send_firestore_load_account() -> void:
	if not is_authenticated():
		_finish_auth_success()
		return

	var url := "%s/%s/%s" % [FIRESTORE_URL, ACCOUNTS_COLLECTION, user_id]

	_request_kind = "firestore_load_account"

	var err := http.request(url, _get_firestore_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_fail_request("Logged in, but account profile could not be loaded: %s" % error_string(err))


func _send_firestore_query_first_character() -> void:
	if not is_authenticated():
		_finish_auth_success()
		return

	var body := JSON.stringify({
		"structuredQuery": {
			"from": [{"collectionId": CHARACTERS_COLLECTION}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "account_id"},
					"op": "EQUAL",
					"value": {"stringValue": user_id},
				}
			},
			"orderBy": [{
				"field": {"fieldPath": "created_at"},
				"direction": "ASCENDING",
			}],
			"limit": 1,
		}
	})

	_request_kind = "firestore_query_character"

	var err := http.request(FIRESTORE_RUN_QUERY_URL, _get_firestore_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail_request("Logged in, but character data could not be loaded: %s" % error_string(err))


func _request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response_text := body.get_string_from_utf8()
	var response = JSON.parse_string(response_text)

	if response == null:
		_fail_request("Firebase returned an invalid response.")
		return

	if response_code < 200 or response_code >= 300:
		var error_data = response if response is Dictionary else {}
		_handle_request_error(error_data)
		return

	match _request_kind:
		"register", "login":
			_handle_auth_response(response as Dictionary)
		"update_profile":
			_handle_profile_update_response(response as Dictionary)
		"firestore_create_account":
			_send_firestore_create_default_character()
		"firestore_create_character":
			_pending_register_username = ""
			_finish_auth_success()
		"firestore_update_last_login":
			_send_firestore_load_account()
		"firestore_load_account":
			_apply_firestore_account_data(response as Dictionary)
			_send_firestore_query_first_character()
		"firestore_query_character":
			_handle_character_query_response(response)
		"firestore_update_character":
			_apply_character_update_response(response as Dictionary)
		_:
			_finish_auth_success()


func _handle_auth_response(data: Dictionary) -> void:
	id_token = str(data.get("idToken", id_token))
	refresh_token = str(data.get("refreshToken", refresh_token))
	user_id = str(data.get("localId", user_id))
	email = str(data.get("email", email)).strip_edges().to_lower()
	display_name = str(data.get("displayName", display_name)).strip_edges()
	username = display_name
	account_data.clear()
	character_data.clear()
	character_id = ""
	character_document_name = ""

	if not is_authenticated():
		_fail_request("Login succeeded but Firebase did not return a user token.")
		return

	if _pending_auth_kind == "register" and _pending_register_username != "":
		_send_display_name_update(_pending_register_username)
		return

	_send_firestore_update_last_login()


func _handle_profile_update_response(data: Dictionary) -> void:
	id_token = str(data.get("idToken", id_token))
	refresh_token = str(data.get("refreshToken", refresh_token))
	display_name = str(data.get("displayName", display_name)).strip_edges()
	username = display_name
	_send_firestore_create_account()


func _handle_character_query_response(response) -> void:
	character_data.clear()
	character_id = ""
	character_document_name = ""

	if response is Array:
		for item in response:
			if not (item is Dictionary):
				continue

			var document = (item as Dictionary).get("document", {})
			if not (document is Dictionary):
				continue

			_apply_firestore_character_data(document as Dictionary)
			_finish_auth_success()
			return

	# Existing Firebase Auth users may not have a character yet. Create one so the
	# rest of the game can always rely on Firebase.character_data being available.
	_send_firestore_create_default_character()


func _apply_character_update_response(data: Dictionary) -> void:
	_apply_firestore_character_data(data)
	for key in _pending_character_update_fields.keys():
		_set_nested_value(character_data, str(key), _pending_character_update_fields[key])
	_pending_character_update_fields.clear()
	request_in_progress = false
	_request_kind = ""
	character_update_success.emit(get_character_data())


func _handle_request_error(data: Dictionary) -> void:
	# If the Firebase Auth login worked but the Firestore account document is missing,
	# create a small fallback account document so old test users can still continue.
	if _request_kind == "firestore_update_last_login":
		_send_firestore_create_missing_account()
		return

	var message := _get_firebase_error_message(data)

	if _request_kind == "firestore_update_character":
		request_in_progress = false
		_request_kind = ""
		_pending_character_update_fields.clear()
		character_update_failed.emit(message)
		return

	_fail_request(message)


func _send_firestore_create_missing_account() -> void:
	_pending_register_username = get_display_name()
	_send_firestore_create_account()


func _apply_firestore_account_data(data: Dictionary) -> void:
	var fields = data.get("fields", {})
	if not (fields is Dictionary):
		return

	account_data = _firestore_fields_to_dictionary(fields as Dictionary)

	var saved_username := str(account_data.get("username", "")).strip_edges()
	if saved_username != "":
		username = saved_username
		display_name = saved_username

	var saved_email := str(account_data.get("email", "")).strip_edges().to_lower()
	if saved_email != "":
		email = saved_email


func _apply_firestore_character_data(data: Dictionary) -> void:
	var document_name := str(data.get("name", ""))
	if document_name != "":
		character_document_name = document_name
		character_id = document_name.get_file()

	var fields = data.get("fields", {})
	if fields is Dictionary:
		character_data = _firestore_fields_to_dictionary(fields as Dictionary)


func _finish_auth_success() -> void:
	request_in_progress = false
	_request_kind = ""
	_pending_auth_kind = ""
	auth_request_finished.emit()
	login_success.emit(get_current_user_data())


func _fail_request(message: String) -> void:
	request_in_progress = false
	_request_kind = ""
	_pending_auth_kind = ""
	auth_request_finished.emit()
	login_failed.emit(message)


func _get_firestore_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % id_token,
	])


func _now_firestore_timestamp() -> String:
	var value := Time.get_datetime_string_from_system(true, false)
	if not value.ends_with("Z"):
		value += "Z"
	return value


func _dictionary_to_firestore_fields(source: Dictionary) -> Dictionary:
	var fields := {}
	for key in source.keys():
		fields[str(key)] = _to_firestore_value(source[key])
	return fields


func _to_firestore_value(value) -> Dictionary:
	match typeof(value):
		TYPE_BOOL:
			return {"booleanValue": value}
		TYPE_INT:
			return {"integerValue": str(value)}
		TYPE_FLOAT:
			return {"doubleValue": value}
		TYPE_DICTIONARY:
			return {"mapValue": {"fields": _dictionary_to_firestore_fields(value as Dictionary)}}
		TYPE_ARRAY:
			var values := []
			for item in value:
				values.append(_to_firestore_value(item))
			return {"arrayValue": {"values": values}}
		_:
			var string_value := str(value)
			if _looks_like_firestore_timestamp(string_value):
				return {"timestampValue": string_value}
			return {"stringValue": string_value}


func _firestore_fields_to_dictionary(fields: Dictionary) -> Dictionary:
	var result := {}
	for key in fields.keys():
		result[str(key)] = _from_firestore_value(fields[key])
	return result


func _from_firestore_value(value):
	if not (value is Dictionary):
		return null

	var data := value as Dictionary

	if data.has("stringValue"):
		return str(data.get("stringValue", ""))
	if data.has("integerValue"):
		return int(data.get("integerValue", 0))
	if data.has("doubleValue"):
		return float(data.get("doubleValue", 0.0))
	if data.has("booleanValue"):
		return bool(data.get("booleanValue", false))
	if data.has("timestampValue"):
		return str(data.get("timestampValue", ""))
	if data.has("mapValue"):
		var map_value = data.get("mapValue", {})
		if map_value is Dictionary:
			var map_fields = (map_value as Dictionary).get("fields", {})
			if map_fields is Dictionary:
				return _firestore_fields_to_dictionary(map_fields as Dictionary)
		return {}
	if data.has("arrayValue"):
		var result := []
		var array_value = data.get("arrayValue", {})
		if array_value is Dictionary:
			var values = (array_value as Dictionary).get("values", [])
			if values is Array:
				for item in values:
					result.append(_from_firestore_value(item))
		return result

	return null


func _build_firestore_fields_from_dot_paths(fields: Dictionary) -> Dictionary:
	var root := {}
	for path in fields.keys():
		_set_nested_firestore_value(root, str(path).split("."), fields[path])
	return root


func _set_nested_firestore_value(root: Dictionary, parts: PackedStringArray, value) -> void:
	if parts.is_empty():
		return

	var key := parts[0]
	if parts.size() == 1:
		root[key] = _to_firestore_value(value)
		return

	if not root.has(key):
		root[key] = {"mapValue": {"fields": {}}}

	var next = root[key]
	if not (next is Dictionary):
		root[key] = {"mapValue": {"fields": {}}}
		next = root[key]

	var map_value = (next as Dictionary).get("mapValue", {})
	if not (map_value is Dictionary):
		(next as Dictionary)["mapValue"] = {"fields": {}}
		map_value = (next as Dictionary)["mapValue"]

	var nested_fields = (map_value as Dictionary).get("fields", {})
	if not (nested_fields is Dictionary):
		(map_value as Dictionary)["fields"] = {}
		nested_fields = (map_value as Dictionary)["fields"]

	var remaining := PackedStringArray()
	for i in range(1, parts.size()):
		remaining.append(parts[i])

	_set_nested_firestore_value(nested_fields as Dictionary, remaining, value)


func _get_nested_value(source: Dictionary, path: String, fallback = null):
	var current = source
	for part in path.split("."):
		if not (current is Dictionary):
			return fallback
		if not (current as Dictionary).has(part):
			return fallback
		current = (current as Dictionary)[part]
	return current


func _set_nested_value(source: Dictionary, path: String, value) -> void:
	var parts := path.split(".")
	var current := source
	for i in range(parts.size()):
		var key := parts[i]
		if i == parts.size() - 1:
			current[key] = value
			return
		if not current.has(key) or not (current[key] is Dictionary):
			current[key] = {}
		current = current[key]


func _looks_like_firestore_timestamp(value: String) -> bool:
	return value.ends_with("Z") and value.contains("T")


func _get_firebase_error_message(data: Dictionary) -> String:
	var code := "LOGIN_FAILED"

	var error_data = data.get("error", {})
	if error_data is Dictionary:
		code = str((error_data as Dictionary).get("message", code))

	match code:
		"EMAIL_EXISTS":
			return "An account already exists for this email."
		"EMAIL_NOT_FOUND":
			return "No account was found for this email."
		"INVALID_PASSWORD":
			return "The password is incorrect."
		"INVALID_LOGIN_CREDENTIALS":
			return "The email or password is incorrect."
		"USER_DISABLED":
			return "This account has been disabled."
		"INVALID_EMAIL":
			return "Enter a valid email address."
		"WEAK_PASSWORD : Password should be at least 6 characters":
			return "Password must be at least 6 characters."
		"PERMISSION_DENIED", "Missing or insufficient permissions.":
			return "Firestore permissions blocked the account or character update. Check your Firestore rules."
		_:
			return code.capitalize().replace("_", " ")
