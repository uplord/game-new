extends Node2D

@onready var container: Node = self
@onready var ui: CanvasLayer = $UI
@onready var main_menu: CanvasLayer = $MainMenu

var _client_started := false


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


func apply_ui_scale():
	var screen := DisplayServer.window_get_current_screen()
	var ui_scale := DisplayServer.screen_get_scale(screen)

	get_window().content_scale_factor = ui_scale


func _on_main_menu_start_pressed() -> void:
	start_client_from_menu()


func start_client_from_menu() -> void:
	if ServerManager.is_server or _client_started:
		return

	_client_started = true
	ui.visible = false
	ServerManager.start_client(ServerManager.SERVER_IP)


func _on_server_ready() -> void:
	ui.visible = true

	await SceneManager.load_map()
	
	await get_tree().process_frame
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
