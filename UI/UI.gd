extends CanvasLayer

@onready var ui_frame: Control = $UIFrame
@onready var top_ui: Control = $UIFrame/TopUI
@onready var bottom_ui: Control = $UIFrame/BottomUI
@onready var modal: Control = $UIFrame/Modal

@onready var top_box: BoxContainer = $UIFrame/TopUI/MarginContainer/BoxContainer
@onready var cards_container: HBoxContainer = $UIFrame/TopUI/MarginContainer/BoxContainer/CardsContainer
@onready var enemy_card: PanelContainer = $UIFrame/TopUI/MarginContainer/BoxContainer/CardsContainer/EnemyCard
@onready var menu_buttons: HBoxContainer = $UIFrame/TopUI/MarginContainer/BoxContainer/MenuButtons

@onready var bottom_box: BoxContainer = $UIFrame/BottomUI/MarginContainer/BoxContainer

@onready var label_map: Label = $UIFrame/BottomUI/MarginContainer/BoxContainer/LabelMap
@onready var battle_buttons: HBoxContainer = $UIFrame/BottomUI/MarginContainer/BoxContainer/BattleButtons

const MAX_LANDSCAPE_ASPECT := 16.0 / 9.0

const MAP_LABEL_UPDATE_INTERVAL := 0.25
var _map_label_timer := 0.0
var _last_map_label_text := ""
var current_enemy_target: Node = null

func _ready() -> void:
	get_viewport().size_changed.connect(_on_resized)
	modal.visible = false

	if SceneManager.has_signal("map_status_changed"):
		SceneManager.map_status_changed.connect(_update_map_label)
	
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().size_changed.emit()

func _process(delta):
	_map_label_timer += delta
#
	if _map_label_timer >= MAP_LABEL_UPDATE_INTERVAL:
		_map_label_timer = 0.0
		_update_map_label()

func _on_resized() -> void:
	call_deferred("update_ui")

func is_mobile() -> bool:
	return OS.has_feature("android") or (
		OS.has_feature("ios") and not OS.has_feature("ipad")
	)

func update_ui():
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size := get_viewport().get_visible_rect().size
	var aspect := screen_size.x / screen_size.y

	var frame_pos := Vector2(safe_area.position / DisplayServer.screen_get_scale())
	var frame_size := Vector2(safe_area.size / DisplayServer.screen_get_scale())
	var portrait := screen_size.y > screen_size.x

	if portrait:
		top_box.vertical = true
		top_box.move_child(menu_buttons, 0)
		menu_buttons.alignment = BoxContainer.ALIGNMENT_BEGIN
		cards_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		
		bottom_box.vertical = true
		bottom_box.move_child(battle_buttons, 0)
		battle_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		label_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		top_box.vertical = false
		top_box.move_child(cards_container, 0)
		menu_buttons.alignment = BoxContainer.ALIGNMENT_END
		cards_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		
		bottom_box.vertical = false
		bottom_box.move_child(label_map, 0)
		battle_buttons.alignment = BoxContainer.ALIGNMENT_END
		label_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


	# Landscape wider than 16:9: keep UI inside 16:9 area
	if not is_mobile() and aspect > 16.0 / 9.0:
		var target_width := screen_size.y * (16.0 / 9.0)
		var bar_width := (screen_size.x - target_width) * 0.5

		frame_pos.x = bar_width
		frame_size.x = target_width

	ui_frame.position = frame_pos
	ui_frame.size = frame_size

	label_map.add_theme_constant_override(
		"outline_size",
		roundi(4)
	)
	label_map.add_theme_color_override("font_outline_color", Color.BLACK)

func _update_map_label() -> void:
	if label_map == null:
		return

	var map_name := SceneManager.current_map
	if map_name == "":
		map_name = "-"

	var text := "Map: %s | Instance: %d | Players: %d" % [
		map_name,
		SceneManager.current_instance,
		SceneManager.current_map_population
	]

	if text == _last_map_label_text:
		return

	_last_map_label_text = text
	label_map.text = text


func _on_server_lost() -> void:
	modal.force_close()


# ---------------------
# BUTTONS
# ---------------------

func _on_disconnect_pressed() -> void:
	ServerManager.handle_server_disconnect()

func _on_modal_pressed() -> void:
	modal.toggle()

func _on_close_button_pressed() -> void:
	modal.close()


func show_enemy_card(enemy: Node) -> void:
	current_enemy_target = enemy

	if enemy_card == null:
		return

	enemy_card.visible = true

	var display_name := str(enemy.get("enemy_name"))
	if display_name == "" or display_name == "<null>":
		display_name = enemy.name

	var hp_value := float(enemy.get("hp")) if enemy.get("hp") != null else 100.0
	var hp_max := float(enemy.get("max_hp")) if enemy.get("max_hp") != null else 100.0
	var mp_value := float(enemy.get("mp")) if enemy.get("mp") != null else 0.0
	var mp_max := float(enemy.get("max_mp")) if enemy.get("max_mp") != null else 0.0

	if enemy_card.has_method("set_card_data"):
		enemy_card.set_card_data(display_name, hp_value, hp_max, mp_value, mp_max)


func hide_enemy_card() -> void:
	current_enemy_target = null

	if enemy_card != null:
		enemy_card.visible = false
