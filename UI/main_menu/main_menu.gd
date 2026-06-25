extends CanvasLayer

signal start_pressed

@onready var connect_button: Button = $ColorRect/CenterContainer/VBoxContainer/Button

const CONNECT_TEXT := "Connect"
const RECONNECT_TEXT := "Reconnect in %ds"

var _connect_cooldown_active := false
var _connect_cooldown_token := 0


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	_reset_connect_button()


func _on_connect_pressed() -> void:
	if _connect_cooldown_active or connect_button.disabled:
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
	connect_button.disabled = false
	connect_button.text = CONNECT_TEXT
