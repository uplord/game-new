extends CanvasLayer

signal start_pressed

@onready var email_input: LineEdit = $ColorRect/CenterContainer/VBoxContainer/EmailInput
@onready var password_input: LineEdit = $ColorRect/CenterContainer/VBoxContainer/PasswordInput
@onready var login_button: Button = $ColorRect/CenterContainer/VBoxContainer/AuthButtons/LoginButton
@onready var register_button: Button = $ColorRect/CenterContainer/VBoxContainer/AuthButtons/RegisterButton
@onready var status_label: Label = $ColorRect/CenterContainer/VBoxContainer/StatusLabel
@onready var connect_button: Button = $ColorRect/CenterContainer/VBoxContainer/Button

const CONNECT_TEXT := "Connect"
const RECONNECT_TEXT := "Reconnect in %ds"

var _connect_cooldown_active := false
var _connect_cooldown_token := 0
var _auth_busy := false


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	password_input.text_submitted.connect(_on_password_submitted)

	if Firebase.has_signal("login_success") and not Firebase.login_success.is_connected(_on_login_success):
		Firebase.login_success.connect(_on_login_success)
	if Firebase.has_signal("login_failed") and not Firebase.login_failed.is_connected(_on_login_failed):
		Firebase.login_failed.connect(_on_login_failed)
	if Firebase.has_signal("auth_request_started") and not Firebase.auth_request_started.is_connected(_on_auth_request_started):
		Firebase.auth_request_started.connect(_on_auth_request_started)
	if Firebase.has_signal("auth_request_finished") and not Firebase.auth_request_finished.is_connected(_on_auth_request_finished):
		Firebase.auth_request_finished.connect(_on_auth_request_finished)

	_update_auth_status()
	_reset_connect_button()


func _on_login_pressed() -> void:
	if _auth_busy:
		return

	status_label.text = "Logging in..."
	Firebase.login(email_input.text, password_input.text)


func _on_register_pressed() -> void:
	if _auth_busy:
		return

	status_label.text = "Creating account..."
	Firebase.register_user(email_input.text, password_input.text)


func _on_password_submitted(_new_text: String) -> void:
	_on_login_pressed()


func _on_auth_request_started() -> void:
	_auth_busy = true
	login_button.disabled = true
	register_button.disabled = true


func _on_auth_request_finished() -> void:
	_auth_busy = false
	login_button.disabled = false
	register_button.disabled = false


func _on_login_success(data: Dictionary) -> void:
	var logged_in_email := str(data.get("email", email_input.text))
	status_label.text = "Logged in as %s" % logged_in_email
	_update_auth_status()


func _on_login_failed(message: String) -> void:
	status_label.text = message
	_update_auth_status()


func _update_auth_status() -> void:
	var logged_in := Firebase.has_method("is_authenticated") and Firebase.is_authenticated()

	connect_button.disabled = not logged_in or _connect_cooldown_active

	if logged_in:
		var current_user := Firebase.get_current_user_data() if Firebase.has_method("get_current_user_data") else {}
		var logged_in_email := str(current_user.get("email", ""))
		if logged_in_email != "":
			status_label.text = "Logged in as %s" % logged_in_email
	else:
		if status_label.text == "":
			status_label.text = "Login or register to play."


func _on_connect_pressed() -> void:
	if _connect_cooldown_active or connect_button.disabled:
		return

	if Firebase.has_method("is_authenticated") and not Firebase.is_authenticated():
		status_label.text = "Login first."
		_update_auth_status()
		return

	start_pressed.emit()


func start_connect_cooldown(seconds: int = 5) -> void:
	_connect_cooldown_token += 1
	var token := _connect_cooldown_token

	_connect_cooldown_active = true
	connect_button.disabled = true

	for time_left in range(seconds, 0, -1):
		if token != _connect_cooldown_token:
			return

		connect_button.text = RECONNECT_TEXT % time_left
		await get_tree().create_timer(1.0).timeout

	if token != _connect_cooldown_token:
		return

	_reset_connect_button()


func _reset_connect_button() -> void:
	_connect_cooldown_active = false
	connect_button.text = CONNECT_TEXT
	_update_auth_status()
