extends Node2D

@onready var container: Node = self
@onready var ui: CanvasLayer = $UI
@onready var main_menu: CanvasLayer = $MainMenu

var _client_started := false

const MIN_SHORT_SIDE := 576


func _ready() -> void:
	apply_ui_scale()

	SceneManager.setup(container)

	ui.visible = false
	main_menu.visible = true

	if main_menu.has_signal("start_pressed") and not main_menu.start_pressed.is_connected(_on_main_menu_start_pressed):
		main_menu.start_pressed.connect(_on_main_menu_start_pressed)

	if not ServerManager.is_server:
		if not ServerManager.server_lost.is_connected(_on_server_lost):
			ServerManager.server_lost.connect(_on_server_lost)
		if not ServerManager.server_ready.is_connected(_on_server_ready):
			ServerManager.server_ready.connect(_on_server_ready)


func _process(_delta: float) -> void:
	if _is_window_too_small():
		if _client_started:
			_disconnect_to_main_menu()


func apply_ui_scale():
	var screen := DisplayServer.window_get_current_screen()
	var ui_scale := DisplayServer.screen_get_scale(screen)

	get_window().content_scale_factor = ui_scale


func _on_main_menu_start_pressed() -> void:
	start_client_from_menu()


func start_client_from_menu() -> void:
	if ServerManager.is_server or _client_started:
		return

	if _is_window_too_small():
		ui.visible = false
		main_menu.visible = true

		if main_menu.has_method("start_connect_cooldown"):
			main_menu.start_connect_cooldown(5)

		return

	_client_started = true
	ui.visible = false
	ServerManager.start_client(ServerManager.SERVER_IP)


func _on_server_ready() -> void:
	if _is_window_too_small():
		_disconnect_to_main_menu()
		return

	ui.visible = true

	await SceneManager.load_map()

	if _is_window_too_small():
		_disconnect_to_main_menu()
		return
	
	await get_tree().process_frame

	if _is_window_too_small():
		_disconnect_to_main_menu()
		return

	ServerManager.send_to_server({
		"type": "c_request_sync"
	})

func _on_server_lost() -> void:
	_client_started = false
	SceneManager.unload_map()
	SceneManager.unload_camera()

	ui.visible = false
	main_menu.visible = true

	if main_menu.has_method("start_connect_cooldown"):
		main_menu.start_connect_cooldown(5)


func _disconnect_to_main_menu() -> void:
	_client_started = false

	if ServerManager.has_method("handle_server_disconnect"):
		ServerManager.handle_server_disconnect()

	SceneManager.unload_map()
	SceneManager.unload_camera()

	ui.visible = false
	main_menu.visible = true


func _is_window_too_small() -> bool:
	var size := get_window().size
	return min(size.x, size.y) < MIN_SHORT_SIDE
