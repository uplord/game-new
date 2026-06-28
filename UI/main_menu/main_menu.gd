extends CanvasLayer

signal start_pressed

@onready var login_form: VBoxContainer = $ScrollContainer/CenterContainer/LoginForm
@onready var email_input: LineEdit = $ScrollContainer/CenterContainer/LoginForm/EmailInput
@onready var password_input: LineEdit = $ScrollContainer/CenterContainer/LoginForm/PasswordInput
@onready var login_button: Button = $ScrollContainer/CenterContainer/LoginForm/LoginButton
@onready var status_label: Label = $ScrollContainer/CenterContainer/LoginForm/StatusLabel
@onready var register_button: Button = $ScrollContainer/CenterContainer/LoginForm/RegisterButton

@onready var register_form: VBoxContainer = $ScrollContainer/CenterContainer/RegisterForm
@onready var register_username_input: LineEdit = $ScrollContainer/CenterContainer/RegisterForm/UsernameInput
@onready var register_email_input: LineEdit = $ScrollContainer/CenterContainer/RegisterForm/EmailInput
@onready var register_password_input: LineEdit = $ScrollContainer/CenterContainer/RegisterForm/PasswordInput
@onready var register_confirm_password_input: LineEdit = $ScrollContainer/CenterContainer/RegisterForm/ConfirmPasswordInput
@onready var create_account_button: Button = $ScrollContainer/CenterContainer/RegisterForm/CreateAccountButton
@onready var back_to_login_button: Button = $ScrollContainer/CenterContainer/RegisterForm/BackButton

const LOGIN_TEXT := "Login"
const CONNECTING_TEXT := "Connecting..."
const RECONNECT_TEXT := "Reconnect in %ds"
const MIN_PASSWORD_LENGTH := 6
const MIN_USERNAME_LENGTH := 3

var _connect_cooldown_active := false
var _connect_cooldown_token := 0
var _auth_busy := false
var _connect_after_auth := false
var _register_mode := false


func _ready() -> void:
	_setup_mobile_line_edit(email_input)
	_setup_mobile_line_edit(password_input)
	_show_login_form()

	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_show_register_pressed)
	email_input.text_submitted.connect(_on_email_submitted)
	password_input.text_submitted.connect(_on_password_submitted)
	email_input.text_changed.connect(_on_login_text_changed)
	password_input.text_changed.connect(_on_login_text_changed)
	
	register_username_input.text_changed.connect(_on_register_text_changed)
	register_email_input.text_changed.connect(_on_register_text_changed)
	register_password_input.text_changed.connect(_on_register_text_changed)
	register_confirm_password_input.text_changed.connect(_on_register_text_changed)
	if not create_account_button.pressed.is_connected(_on_create_account_pressed):
		create_account_button.pressed.connect(_on_create_account_pressed)
	if not back_to_login_button.pressed.is_connected(_on_back_to_login_pressed):
		back_to_login_button.pressed.connect(_on_back_to_login_pressed)

	if Firebase.has_signal("login_success") and not Firebase.login_success.is_connected(_on_login_success):
		Firebase.login_success.connect(_on_login_success)
	if Firebase.has_signal("login_failed") and not Firebase.login_failed.is_connected(_on_login_failed):
		Firebase.login_failed.connect(_on_login_failed)
	if Firebase.has_signal("auth_request_started") and not Firebase.auth_request_started.is_connected(_on_auth_request_started):
		Firebase.auth_request_started.connect(_on_auth_request_started)
	if Firebase.has_signal("auth_request_finished") and not Firebase.auth_request_finished.is_connected(_on_auth_request_finished):
		Firebase.auth_request_finished.connect(_on_auth_request_finished)

	if ServerManager.has_signal("login_rejected") and not ServerManager.login_rejected.is_connected(_on_server_login_message):
		ServerManager.login_rejected.connect(_on_server_login_message)

	_reset_login_button()
	_update_auth_status()

func _create_form_line_edit(node_name: String) -> LineEdit:
	var input := LineEdit.new()
	input.name = node_name
	_setup_mobile_line_edit(input)
	_copy_line_edit_theme(email_input, input)
	return input


func _setup_mobile_line_edit(input: LineEdit) -> void:
	if input == null:
		return

	input.set("autocapitalize", 0)


func _copy_line_edit_theme(source: LineEdit, target: LineEdit) -> void:
	if source == null or target == null:
		return

	for style_name in ["normal", "read_only", "focus"]:
		var style := source.get_theme_stylebox(style_name)
		if style != null:
			target.add_theme_stylebox_override(style_name, style)

	var font_size := source.get_theme_font_size("font_size")
	if font_size > 0:
		target.add_theme_font_size_override("font_size", font_size)

	target.add_theme_color_override("font_color", source.get_theme_color("font_color"))


func _show_login_form() -> void:
	_register_mode = false
	login_form.visible = true
	register_form.visible = false
	_update_auth_status()


func _show_register_form() -> void:
	_register_mode = true
	login_form.visible = false
	register_form.visible = true
	_update_register_status()


func _on_login_pressed() -> void:
	if _auth_busy or _connect_cooldown_active or login_button.disabled:
		return

	if Firebase.has_method("is_authenticated") and Firebase.is_authenticated():
		_start_game_connection()
		return

	var email := _get_email_text()
	var password := password_input.text

	if not _is_login_form_valid():
		status_label.text = _get_login_form_error()
		_update_auth_status()
		return

	_connect_after_auth = true
	status_label.text = "Logging in..."
	Firebase.login(email, password)


func _on_show_register_pressed() -> void:
	if _auth_busy or _connect_cooldown_active:
		return
	_show_register_form()


func _on_create_account_pressed() -> void:
	if _auth_busy or _connect_cooldown_active:
		return

	if not _is_register_form_valid():
		status_label.text = _get_register_form_error()
		_update_register_status()
		return

	_connect_after_auth = false
	status_label.text = "Creating account..."
	Firebase.register_user(
		_get_register_email_text(),
		register_password_input.text,
		_get_register_username_text()
	)


func _on_back_to_login_pressed() -> void:
	_show_login_form()
	status_label.text = "Login or register to play."


func _on_email_submitted(_new_text: String) -> void:
	password_input.grab_focus()


func _on_password_submitted(_new_text: String) -> void:
	_on_login_pressed()


func _on_login_text_changed(_new_text: String) -> void:
	_update_auth_status()


func _on_register_text_changed(_new_text: String) -> void:
	_update_register_status()


func _on_auth_request_started() -> void:
	_auth_busy = true
	login_button.disabled = true
	register_button.disabled = true
	if create_account_button != null:
		create_account_button.disabled = true
	if back_to_login_button != null:
		back_to_login_button.disabled = true


func _on_auth_request_finished() -> void:
	_auth_busy = false
	_update_auth_status()
	_update_register_status()


func _on_login_success(data: Dictionary) -> void:
	var username := str(data.get("username", data.get("displayName", ""))).strip_edges()
	if username == "":
		username = str(data.get("email", email_input.text))
	status_label.text = "Logged in as %s" % username
	_show_login_form()
	_update_auth_status()

	if _connect_after_auth:
		_connect_after_auth = false
		_start_game_connection()


func _on_login_failed(message: String) -> void:
	_connect_after_auth = false
	status_label.text = message
	_update_auth_status()
	_update_register_status()


func _on_server_login_message(message: String) -> void:
	status_label.text = message
	_connect_after_auth = false
	_reset_login_button()


func _start_game_connection() -> void:
	if _connect_cooldown_active:
		return

	login_button.disabled = true
	register_button.disabled = true
	login_button.text = CONNECTING_TEXT
	status_label.text = "Connecting..."
	start_pressed.emit()


func start_connect_cooldown(seconds: int = 5) -> void:
	_connect_cooldown_token += 1
	var token := _connect_cooldown_token
	status_label.text = "Please wait..."

	_connect_cooldown_active = true
	login_button.disabled = true
	register_button.disabled = true
	if create_account_button != null:
		create_account_button.disabled = true
	if back_to_login_button != null:
		back_to_login_button.disabled = true

	for time_left in range(seconds, 0, -1):
		if token != _connect_cooldown_token:
			return

		login_button.text = RECONNECT_TEXT % time_left
		await get_tree().create_timer(1.0).timeout

	if token != _connect_cooldown_token:
		return

	_reset_login_button()


func _reset_login_button() -> void:
	_connect_cooldown_active = false
	login_button.text = LOGIN_TEXT
	status_label.text = "Login or register to play."
	_update_auth_status()
	_update_register_status()


func reset_after_logout() -> void:
	_connect_cooldown_token += 1
	_connect_cooldown_active = false
	_auth_busy = false
	_connect_after_auth = false
	_register_mode = false

	login_button.text = LOGIN_TEXT
	login_button.disabled = false
	register_button.disabled = false
	register_button.visible = true

	if create_account_button != null:
		create_account_button.disabled = not _is_register_form_valid()
	if back_to_login_button != null:
		back_to_login_button.disabled = false

	status_label.text = "Login or register to play."
	_show_login_form()
	_update_auth_status()
	_update_register_status()


func _update_auth_status() -> void:
	if _connect_cooldown_active:
		return

	var logged_in := Firebase.has_method("is_authenticated") and Firebase.is_authenticated()

	if logged_in:
		login_button.text = "Play"
		login_button.disabled = _auth_busy
		register_button.disabled = true
		var current_user := Firebase.get_current_user_data() if Firebase.has_method("get_current_user_data") else {}
		var username := str(current_user.get("username", current_user.get("displayName", ""))).strip_edges()
		if username == "":
			username = str(current_user.get("email", ""))
		if username != "":
			status_label.text = "Logged in as %s" % username
	else:
		login_button.text = LOGIN_TEXT
		login_button.disabled = _auth_busy or not _is_login_form_valid()
		register_button.disabled = _auth_busy
		if not _register_mode:
			register_button.visible = true
		if status_label.text == "":
			status_label.text = "Login or register to play."


func _update_register_status() -> void:
	if create_account_button == null or back_to_login_button == null:
		return

	if _connect_cooldown_active:
		create_account_button.disabled = true
		back_to_login_button.disabled = true
		return

	var logged_in := Firebase.has_method("is_authenticated") and Firebase.is_authenticated()
	create_account_button.disabled = logged_in or _auth_busy or not _is_register_form_valid()
	back_to_login_button.disabled = _auth_busy


func _get_email_text() -> String:
	return email_input.text.strip_edges().to_lower()


func _get_register_email_text() -> String:
	return register_email_input.text.strip_edges().to_lower()


func _get_register_username_text() -> String:
	return register_username_input.text.strip_edges()


func _is_login_form_valid() -> bool:
	return _get_email_text() != "" and password_input.text.length() >= MIN_PASSWORD_LENGTH


func _get_login_form_error() -> String:
	if _get_email_text() == "":
		return "Enter an email address."

	if password_input.text.length() < MIN_PASSWORD_LENGTH:
		return "Password must be at least %d characters." % MIN_PASSWORD_LENGTH

	return ""


func _is_register_form_valid() -> bool:
	return _get_register_form_error() == ""


func _get_register_form_error() -> String:
	if _get_register_username_text().length() < MIN_USERNAME_LENGTH:
		return "Username must be at least %d characters." % MIN_USERNAME_LENGTH

	if _get_register_email_text() == "":
		return "Enter an email address."

	if register_password_input.text.length() < MIN_PASSWORD_LENGTH:
		return "Password must be at least %d characters." % MIN_PASSWORD_LENGTH

	if register_confirm_password_input.text != register_password_input.text:
		return "Passwords do not match."

	return ""
