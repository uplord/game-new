extends Node

signal login_success(data: Dictionary)
signal login_failed(message: String)
signal auth_request_started
signal auth_request_finished

const API_KEY := ""
const AUTH_URL := "https://identitytoolkit.googleapis.com/v1"

var http: HTTPRequest

var id_token := ""
var refresh_token := ""
var user_id := ""
var email := ""
var request_in_progress := false


func _ready() -> void:
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_request_completed)


func is_authenticated() -> bool:
	return id_token != "" and user_id != ""


func get_current_user_data() -> Dictionary:
	return {
		"idToken": id_token,
		"refreshToken": refresh_token,
		"localId": user_id,
		"email": email,
	}


func logout() -> void:
	id_token = ""
	refresh_token = ""
	user_id = ""
	email = ""


func register_user(user_email: String, password: String) -> void:
	_send_auth_request("accounts:signUp", user_email, password)


func login(user_email: String, password: String) -> void:
	_send_auth_request("accounts:signInWithPassword", user_email, password)


func _send_auth_request(endpoint: String, user_email: String, password: String) -> void:
	if request_in_progress:
		login_failed.emit("Please wait for the current login request to finish.")
		return

	user_email = user_email.strip_edges()

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
	auth_request_started.emit()

	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		request_in_progress = false
		auth_request_finished.emit()
		login_failed.emit("Could not start Firebase request: %s" % error_string(err))


func _request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_in_progress = false
	auth_request_finished.emit()

	var response_text := body.get_string_from_utf8()
	var response = JSON.parse_string(response_text)

	if not (response is Dictionary):
		login_failed.emit("Firebase returned an invalid response.")
		return

	var data := response as Dictionary

	if response_code != 200:
		login_failed.emit(_get_firebase_error_message(data))
		return

	id_token = str(data.get("idToken", ""))
	refresh_token = str(data.get("refreshToken", ""))
	user_id = str(data.get("localId", ""))
	email = str(data.get("email", ""))

	if not is_authenticated():
		login_failed.emit("Login succeeded but Firebase did not return a user token.")
		return

	login_success.emit(get_current_user_data())


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
		_:
			return code.capitalize().replace("_", " ")
