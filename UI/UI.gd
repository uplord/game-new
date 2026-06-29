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
@onready var player_card: PanelContainer = $UIFrame/TopUI/MarginContainer/BoxContainer/CardsContainer/PlayerCard

@onready var player_effects_label: Label = player_card.get_node_or_null("MarginContainer/VBoxContainer/Effects")
@onready var enemy_effects_label: Label = enemy_card.get_node_or_null("MarginContainer/VBoxContainer/Effects")

var camera_manager: Node = null

const MAX_LANDSCAPE_ASPECT := 16.0 / 9.0

const MAP_LABEL_UPDATE_INTERVAL := 0.25
const AUTO_SKILL_PENDING_TIMEOUT := 1.0
const PLAYER_GLOBAL_SKILL_COOLDOWN := 1.0

var _map_label_timer := 0.0
var _last_map_label_text := ""
var current_enemy_target: Node = null
var battle_state: Dictionary = {}
var battle_state_received_at := 0.0
var effect_label_update_timer := 0.0
var skill_button_order := ["slash", "fire", "defend", "heal", "ultra_attack"]
var death_screen: Control = null
var death_screen_label: Label = null
var death_reset_button: Button = null
var was_dead := false
var auto_skill_1_timer := 0.0
var auto_skill_pending: Dictionary = {}
var support_skill_pose_preserve_until := 0.0
var original_skill_button_text: Dictionary = {}

var skill_info_panel: PanelContainer = null
var skill_info_title: Label = null
var skill_info_body: RichTextLabel = null
var selected_skill_info_id := ""

var battle_button_timer := 0.0
var queued_battle_skill_id := ""

func _ready() -> void:
	get_viewport().size_changed.connect(_on_resized)
	modal.visible = false

	if SceneManager.has_signal("map_status_changed"):
		SceneManager.map_status_changed.connect(_update_map_label)
	if Firebase.has_signal("character_update_success") and not Firebase.character_update_success.is_connected(_on_character_update_success):
		Firebase.character_update_success.connect(_on_character_update_success)
	if Firebase.has_signal("login_success") and not Firebase.login_success.is_connected(_on_firebase_login_success):
		Firebase.login_success.connect(_on_firebase_login_success)
	
	_setup_battle_buttons()
	_setup_death_screen()
	_hide_effect_labels()
	await get_tree().process_frame
	await get_tree().process_frame
	_hide_effect_labels()
	get_window().size_changed.emit()
	_refresh_player_card_from_firebase()
	_update_battle_buttons()


func _on_character_update_success(_data: Dictionary) -> void:
	_refresh_player_card_from_firebase()


func _on_firebase_login_success(_data: Dictionary) -> void:
	_refresh_player_card_from_firebase()


func _get_loaded_character_skills() -> Dictionary:
	if Firebase.has_method("get_character_skills"):
		return Firebase.get_character_skills()
	return Firebase.get_character_value("skills", {})


func _refresh_player_card_from_firebase() -> void:
	if player_card == null or not player_card.has_method("set_card_data"):
		return

	var player = battle_state.get("player", {}) if battle_state is Dictionary else {}
	player_card.set_card_data(
		Firebase.get_character_name(),
		float(player.get("hp", 100.0)),
		float(player.get("max_hp", 100.0)),
		float(player.get("mp", 100.0)),
		float(player.get("max_mp", 100.0)),
		_get_loaded_character_skills(),
		int(Firebase.get_character_value("gold", 0)),
		true,
	)


func _process(delta):
	auto_skill_1_timer += delta
	_map_label_timer += delta
#
	if _map_label_timer >= MAP_LABEL_UPDATE_INTERVAL:
		_map_label_timer = 0.0
		_update_map_label()

	effect_label_update_timer += delta
	if effect_label_update_timer >= 1.0:
		effect_label_update_timer = 0.0
		_update_effect_labels()

	battle_button_timer += delta

	if battle_button_timer >= 0.1:
		battle_button_timer = 0.0
		_update_battle_buttons()

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

	label_map.add_theme_constant_override("outline_size", roundi(4))
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
	_clear_user_for_logout()

	if Firebase.has_method("logout"):
		Firebase.logout()
	elif Firebase.has_method("sign_out"):
		Firebase.sign_out()
	elif Firebase.has_method("clear_user"):
		Firebase.clear_user()

	ServerManager.handle_server_disconnect()


func _clear_user_for_logout() -> void:
	queued_battle_skill_id = ""
	battle_state = {}
	battle_state_received_at = 0.0
	was_dead = false
	_clear_auto_skill_pending()
	hide_enemy_card(true)
	_hide_death_screen()
	_hide_effect_labels()
	_update_battle_buttons()

	if player_card != null and player_card.has_method("set_card_data"):
		player_card.set_card_data("Player", 100.0, 100.0, 100.0, 100.0, {}, 0)

	if label_map != null:
		_last_map_label_text = ""
		label_map.text = "Map: - | Instance: 0 | Players: 0"


func _on_modal_pressed() -> void:
	modal.toggle()

func _on_close_button_pressed() -> void:
	modal.close()


func show_enemy_card(enemy: Node) -> void:
	if current_enemy_target != null and is_instance_valid(current_enemy_target):
		if current_enemy_target.has_method("set_selected"):
			current_enemy_target.set_selected(false)

	current_enemy_target = enemy
	
	# Camera positioning for enemy targeting is handled by Player.gd.
	# Do not focus the camera here: this runs before the player has chosen the
	# final engagement side, so it can fight the approach camera lock.

	if current_enemy_target != null and current_enemy_target.has_method("set_selected"):
		current_enemy_target.set_selected(true)

	_select_enemy_on_server(enemy)
	show_enemy_card_local(enemy)


func _move_player_close_to_enemy(enemy: Node, force_reposition: bool = false) -> void:
	var player := SceneManager.player
	if player != null and is_instance_valid(player) and player.has_method("move_close_to_enemy"):
		player.move_close_to_enemy(enemy, force_reposition)


func _should_move_player_back_to_enemy(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if not enemy.visible:
		return false

	var player := SceneManager.player
	if player == null or not is_instance_valid(player):
		return false

	if player.has_method("is_close_to_enemy"):
		return not player.is_close_to_enemy(enemy)

	return false


func hide_enemy_card(force: bool = false) -> void:
	if not force and is_player_in_battle():
		return

	if current_enemy_target != null and is_instance_valid(current_enemy_target):
		if current_enemy_target.has_method("set_selected"):
			current_enemy_target.set_selected(false)

	current_enemy_target = null


	if enemy_card != null:
		enemy_card.visible = false

	_update_effect_labels()
	
	camera_manager = get_tree().root.get_node("Game/CameraManager")

	if camera_manager != null:
		camera_manager.clear_enemy_focus()


func is_player_in_battle() -> bool:
	var player = battle_state.get("player", {})
	return (bool(player.get("in_battle", false))) and float(player.get("hp", 100.0)) > 0.0

func on_enemy_visibility_changed(enemy: Node, enemy_visible: bool) -> void:
	if current_enemy_target == enemy and not enemy_visible:
		hide_enemy_card(true)
	elif current_enemy_target == enemy and enemy_visible:
		show_enemy_card_local(enemy)
	_update_battle_buttons()


# ---------------------
# BATTLE SYSTEM
# ---------------------
func _setup_death_screen() -> void:
	if death_screen != null:
		return

	death_screen = Control.new()
	death_screen.name = "DeathScreen"
	death_screen.visible = false
	death_screen.z_index = 4000
	death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_frame.add_child(death_screen)

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.72)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 180)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	death_screen_label = Label.new()
	death_screen_label.text = "You died"
	death_screen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_screen_label.add_theme_font_size_override("font_size", 32)
	box.add_child(death_screen_label)

	var info := Label.new()
	info.text = "You have run out of health."
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)

	death_reset_button = Button.new()
	death_reset_button.text = "Reset HP / MP"
	death_reset_button.custom_minimum_size = Vector2(180, 44)
	death_reset_button.pressed.connect(_on_death_reset_pressed)
	box.add_child(death_reset_button)


func _show_death_screen() -> void:
	# Clear the enemy target through hide_enemy_card() so the enemy shadow is
	# properly unselected before the target reference is removed.
	hide_enemy_card(true)

	if death_screen == null:
		_setup_death_screen()
	death_screen.visible = true
	death_screen.move_to_front()
	_update_battle_buttons()


func _hide_death_screen() -> void:
	if death_screen != null:
		death_screen.visible = false


func _on_death_reset_pressed() -> void:
	# Do not set current_enemy_target directly here. hide_enemy_card(true) calls
	# set_selected(false), which resets the enemy shadow when it is untargeted.
	hide_enemy_card(true)
	ServerManager.send_to_server({
		"type": "c_reset_player_battle",
	})


func _setup_battle_buttons() -> void:
	if battle_buttons == null:
		return

	for i in range(battle_buttons.get_child_count()):
		var button := battle_buttons.get_child(i) as Button
		if button == null:
			continue

		if i < skill_button_order.size():
			var skill_id := str(skill_button_order[i])
			original_skill_button_text[skill_id] = button.text
			button.tooltip_text = skill_id.replace("_", " ").capitalize()


func _select_enemy_on_server(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var packet := _make_enemy_battle_packet(enemy)
	packet["type"] = "c_select_enemy"
	ServerManager.send_to_server(packet)


func _get_skill_data(skill_id: String) -> Dictionary:
	var server_skills = battle_state.get("skills", {})
	if server_skills is Dictionary and server_skills.has(skill_id):
		return server_skills.get(skill_id, {})
	return {}


func _on_battle_skill_pressed(skill_id: String) -> void:
	if queued_battle_skill_id != "":
		return

	var skill: Dictionary = _get_skill_data(skill_id)
	var skill_type := str(skill.get("type", ""))
	var needs_enemy := skill_type == "melee" or skill_type == "magic" or skill_type == "debuff"

	if needs_enemy and (current_enemy_target == null or not is_instance_valid(current_enemy_target) or not current_enemy_target.visible):
		if bool(skill.get("target_closest_enemy", false)):
			var closest_enemy := _find_closest_visible_enemy()
			if closest_enemy != null:
				show_enemy_card(closest_enemy)
				_move_player_close_to_enemy(closest_enemy)
				# Auto-selecting a target from a battle button should move the player
				# into engagement range, but Player.gd keeps the camera from focusing.
			else:
				return
		else:
			return

	# If an attack requires an enemy, press first moves the player back to the
	# proper engagement side. The actual skill packet is delayed until Player.gd
	# reports that the approach movement has finished, so attacks do not fire
	# while the player is still running into position.
	if needs_enemy and current_enemy_target != null and is_instance_valid(current_enemy_target):
		_move_player_close_to_enemy(current_enemy_target, true)
		if _is_player_approaching_enemy(current_enemy_target):
			queued_battle_skill_id = skill_id
			_set_auto_skill_pending(skill_id)
			_update_battle_buttons()
			await _wait_for_player_enemy_approach(current_enemy_target)
			if queued_battle_skill_id != skill_id:
				return
			queued_battle_skill_id = ""
			if current_enemy_target == null or not is_instance_valid(current_enemy_target) or not current_enemy_target.visible:
				auto_skill_pending.erase(skill_id)
				_update_battle_buttons()
				return

	# Battle UI buttons can select/approach the target, but camera focus remains disabled.

	_send_battle_skill_packet(skill_id)


func _send_battle_skill_packet(skill_id: String) -> void:
	var packet := {
		"type": "c_use_skill",
		"skill_id": skill_id,
	}

	if current_enemy_target != null and is_instance_valid(current_enemy_target):
		packet.merge(_make_enemy_battle_packet(current_enemy_target), true)

	_set_auto_skill_pending(skill_id)
	_update_battle_buttons()
	ServerManager.send_to_server(packet)


func _is_player_approaching_enemy(enemy: Node) -> bool:
	var player := SceneManager.player
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_enemy_approach_in_progress"):
		return bool(player.call("is_enemy_approach_in_progress", enemy))
	return false


func _wait_for_player_enemy_approach(enemy: Node) -> void:
	while _is_player_approaching_enemy(enemy):
		await get_tree().physics_frame


func apply_battle_state(state: Dictionary) -> void:
	battle_state = state
	battle_state_received_at = Time.get_ticks_msec() / 1000.0
	_clear_auto_skill_pending()
	var player = state.get("player", {})
	var is_dead := float(player.get("hp", 100.0)) <= 0.0 or str(state.get("status", "active")) == "enemy_won"
	if is_dead and not was_dead:
		_show_death_screen()
	elif not is_dead and was_dead:
		_hide_death_screen()
	was_dead = is_dead

	if player_card != null and player_card.has_method("set_card_data"):
		player_card.set_card_data(
			Firebase.get_character_name(),
			float(player.get("hp", 100.0)),
			float(player.get("max_hp", 100.0)),
			float(player.get("mp", 100.0)),
			float(player.get("max_mp", 100.0)),
			_get_loaded_character_skills(),
			int(Firebase.get_character_value("gold", 0)),
			true
		)

	_update_effect_labels()
	call_deferred("_update_effect_labels")

	var enemy = state.get("enemy", {})
	if current_enemy_target != null and is_instance_valid(current_enemy_target):
		current_enemy_target.set("hp", float(enemy.get("hp", current_enemy_target.get("hp"))))
		current_enemy_target.set("max_hp", float(enemy.get("max_hp", current_enemy_target.get("max_hp"))))
		current_enemy_target.set("mp", float(enemy.get("mp", current_enemy_target.get("mp"))))
		current_enemy_target.set("max_mp", float(enemy.get("max_mp", current_enemy_target.get("max_mp"))))
		var defeated := bool(enemy.get("defeated", false))
		current_enemy_target.visible = not defeated
		if defeated:
			hide_enemy_card(true)
		else:
			show_enemy_card_local(current_enemy_target)

	_update_battle_buttons()


func show_enemy_card_local(enemy: Node) -> void:
	if enemy_card == null:
		return
	enemy_card.visible = true
	var display_name := _get_enemy_name(enemy)
	var hp_value := float(enemy.get("hp")) if enemy.get("hp") != null else 100.0
	var hp_max := float(enemy.get("max_hp")) if enemy.get("max_hp") != null else 100.0
	var mp_value := float(enemy.get("mp")) if enemy.get("mp") != null else 0.0
	var mp_max := float(enemy.get("max_mp")) if enemy.get("max_mp") != null else 0.0
	if enemy_card.has_method("set_card_data"):
		enemy_card.set_card_data(display_name, hp_value, hp_max, mp_value, mp_max)

	_update_effect_labels()
	call_deferred("_update_effect_labels")


func _update_battle_buttons() -> void:
	if battle_buttons == null:
		return

	for i in range(battle_buttons.get_child_count()):
		var button := battle_buttons.get_child(i) as Button
		if button == null or i >= skill_button_order.size():
			continue

		var skill_id = skill_button_order[i]
		var usable := _is_skill_usable(skill_id, false)
		var disabled_for_pending := _is_auto_skill_pending(str(skill_id)) or queued_battle_skill_id != ""
		button.disabled = not usable or disabled_for_pending

		var cooldown_status := _get_battle_button_cooldown_status(str(skill_id))
		var countdown_remaining := float(cooldown_status.get("remaining", 0.0))
		var cooldown_total := float(cooldown_status.get("total", 0.0))

		if button.has_method("set_countdown_text"):
			if countdown_remaining > 0.0:
				button.call("set_countdown_text", str(int(ceil(countdown_remaining))))
			else:
				button.call("set_countdown_text", "")

		if button.has_method("set_progress"):
			if countdown_remaining > 0.0 and cooldown_total > 0.0:
				button.call("set_progress", 1.0 - clamp(countdown_remaining / cooldown_total, 0.0, 1.0))
			else:
				button.call("set_progress", 1.0)

		button.tooltip_text = _build_skill_tooltip(skill_id)


func _setup_skill_info_panel() -> void:
	if skill_info_panel != null:
		skill_info_panel.visible = false


func _find_label_by_name(root: Node, label_name: String) -> Label:
	if root == null:
		return null

	if root.name == label_name and root is Label:
		return root as Label

	for child in root.get_children():
		var result := _find_label_by_name(child, label_name)
		if result != null:
			return result

	return null


func _hide_effect_labels() -> void:
	_set_effects_label(player_effects_label, [])
	_set_effects_label(enemy_effects_label, [])


func _update_effect_labels() -> void:
	var player = battle_state.get("player", {})
	var enemy = battle_state.get("enemy", {})

	# Re-resolve these each update. On some loads the @onready references
	# can be null/stale, which means player buffs such as Defend are applied
	# server-side but never written to the card label.

	_set_effects_label(player_effects_label, player.get("effects", []))

	var enemy_has_visible_card := enemy_card != null and enemy_card.visible
	var enemy_has_target = current_enemy_target != null and is_instance_valid(current_enemy_target) and current_enemy_target.visible
	var enemy_defeated := bool(enemy.get("defeated", false))

	if enemy_has_visible_card and enemy_has_target and not enemy_defeated:
		_set_effects_label(enemy_effects_label, enemy.get("effects", []))
	else:
		_set_effects_label(enemy_effects_label, [])


func _set_effects_label(label: Label, effects) -> void:
	if label == null:
		return

	var text := _format_active_effects(effects)
	label.text = text
	label.visible = text != ""


func _format_active_effects(effects) -> String:
	if not effects is Array or effects.is_empty():
		return ""

	var elapsed_since_state = max(0.0, (Time.get_ticks_msec() / 1000.0) - battle_state_received_at)
	var names := []
	for effect in effects:
		if not effect is Dictionary:
			continue

		if bool(effect.get("hide_effect", false)):
			continue

		var effect_name := str(effect.get("name", effect.get("id", "Effect")))
		if effect_name == "" or effect_name == "<null>":
			effect_name = "Effect"

		var stacks := int(effect.get("stacks", 1))
		var received_remaining := float(effect.get("remaining", 0.0))
		var remaining = max(0.0, received_remaining - elapsed_since_state) if received_remaining > 0.0 else 0.0

		# Timed effects may expire locally before the next server packet. Hide them
		# at zero, while permanent effects with no timer still stay visible.
		if received_remaining > 0.0 and remaining <= 0.0:
			continue

		var effect_text = effect_name
		if stacks > 1:
			effect_text += " x%d" % stacks
		if remaining > 0.0:
			effect_text += " %ds" % ceili(remaining)

		names.append(effect_text)

	if names.is_empty():
		return ""

	return ", ".join(names)


func _show_skill_info(skill_id: String) -> void:
	selected_skill_info_id = skill_id

	if skill_info_title == null or skill_info_body == null:
		return

	var skill := _get_skill_data(skill_id)
	if skill.is_empty():
		skill_info_title.text = skill_id.replace("_", " ").capitalize()
		skill_info_body.text = "No skill data received from server yet."
		return

	skill_info_title.text = str(skill.get("name", skill_id))
	skill_info_body.text = _build_skill_info_text(skill_id)


func _build_skill_tooltip(skill_id: String) -> String:
	var skill := _get_skill_data(skill_id)
	if skill.is_empty():
		return skill_id.replace("_", " ").capitalize()

	return _build_skill_info_text(skill_id)


func _build_skill_info_text(skill_id: String) -> String:
	var skill := _get_skill_data(skill_id)
	if skill.is_empty():
		return "No skill data."

	var lines := []
	var skill_type := str(skill.get("type", "melee"))
	var damage := float(skill.get("damage", 0.0))
	var mp_cost := float(skill.get("mp_cost", 0.0))
	var cooldown := float(skill.get("cooldown", 0.0))
	var remaining := _skill_cooldown_remaining(skill_id)
	var global_remaining := _global_skill_cooldown_remaining()

	lines.append("Type: %s" % skill_type.capitalize())

	if damage > 0.0:
		lines.append("Damage: %s" % _format_number(damage))

	lines.append("MP Cost: %s" % _format_number(mp_cost))
	lines.append("Cooldown: %.1fs" % cooldown)

	if remaining > 0.0:
		lines.append("Ready in: %.1fs" % remaining)
	elif global_remaining > 0.0:
		lines.append("Global cooldown: %.1fs" % global_remaining)

	if bool(skill.get("target_closest_enemy", false)):
		lines.append("Targeting: closest enemy")
	elif skill_type == "melee" or skill_type == "magic" or skill_type == "debuff":
		lines.append("Targeting: selected enemy")
	else:
		lines.append("Targeting: self")

	var effects_text := _format_skill_effects(skill.get("effects", []))
	if effects_text != "":
		lines.append("")
		lines.append(effects_text)

	return "\n".join(lines)


func _format_skill_effects(effects) -> String:
	if not effects is Array or effects.is_empty():
		return ""

	var lines := ["Effects:"]
	for effect in effects:
		if not effect is Dictionary:
			continue

		lines.append("- %s" % _format_skill_effect(effect))

	return "\n".join(lines)


func _format_skill_effect(effect: Dictionary) -> String:
	var effect_name := str(effect.get("name", effect.get("id", "Effect")))
	var effect_type := str(effect.get("type", ""))
	var flat := float(effect.get("flat_amount", 0.0))
	var percent := float(effect.get("percent_amount", 0.0))
	var duration := float(effect.get("duration", 0.0))
	var tick_rate := float(effect.get("tick_rate", 0.0))
	var max_stacks := int(effect.get("max_stacks", 1))

	var parts := [effect_name]

	if not is_equal_approx(percent, 0.0):
		parts.append("%+d%%" % roundi(percent * 100.0))

	if not is_equal_approx(flat, 0.0):
		parts.append("%+s HP" % _format_number(flat))

	if duration > 0.0:
		parts.append("for %.1fs" % duration)

	if tick_rate > 0.0 and (effect_type == "dot" or effect_type == "hot"):
		parts.append("every %.1fs" % tick_rate)

	if max_stacks > 1:
		parts.append("max %d stacks" % max_stacks)

	return " ".join(parts)


func _format_stat_name(stat: String) -> String:
	match stat:
		"damage":
			return "Damage"
		"defence":
			return "Defence"
		"haste":
			return "Haste"
		"hit_chance":
			return "Hit Chance"
		"dodge":
			return "Dodge"
		"crit_chance":
			return "Crit Chance"
		"crit_damage":
			return "Crit Damage"
		"hp_regen":
			return "HP Regen"
		"mp_regen":
			return "MP Regen"
		_:
			return stat.replace("_", " ").capitalize()


func _format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _battle_button_disabled_cooldown_remaining(skill_id: String) -> float:
	return max(_global_skill_cooldown_remaining(), _skill_cooldown_remaining(skill_id))


func _get_battle_button_cooldown_status(skill_id: String) -> Dictionary:
	var skill_remaining := _skill_cooldown_remaining(skill_id)
	var global_remaining := _global_skill_cooldown_remaining()

	if skill_remaining >= global_remaining and skill_remaining > 0.0:
		var skill := _get_skill_data(skill_id)
		return {
			"remaining": skill_remaining,
			"total": max(skill_remaining, float(skill.get("cooldown", 0.0))),
		}

	if global_remaining > 0.0:
		return {
			"remaining": global_remaining,
			"total": max(global_remaining, PLAYER_GLOBAL_SKILL_COOLDOWN),
		}

	return {
		"remaining": 0.0,
		"total": 0.0,
	}


func _global_skill_cooldown_remaining() -> float:
	var player = battle_state.get("player", {})
	var cooldowns = player.get("cooldowns", {})
	var received_remaining := float(cooldowns.get("_global_skill", 0.0))
	var elapsed_since_state = max(0.0, Time.get_ticks_msec() / 1000.0 - battle_state_received_at)
	return max(0.0, received_remaining - elapsed_since_state)

func _skill_cooldown_remaining(skill_id: String) -> float:
	var player = battle_state.get("player", {})
	var cooldowns = player.get("cooldowns", {})
	var received_remaining := float(cooldowns.get(skill_id, 0.0))
	var elapsed_since_state = max(0.0, Time.get_ticks_msec() / 1000.0 - battle_state_received_at)
	return max(0.0, received_remaining - elapsed_since_state)


func _can_skill_find_target(skill_id: String) -> bool:
	var skill: Dictionary = _get_skill_data(skill_id)
	return bool(skill.get("target_closest_enemy", false)) and _find_closest_visible_enemy() != null


func _is_skill_usable(skill_id: String, require_target_now: bool = true) -> bool:
	var player = battle_state.get("player", {})
	var skill: Dictionary = _get_skill_data(skill_id)
	if skill.is_empty():
		return false
	if str(battle_state.get("status", "active")) == "enemy_won":
		return false
	if float(player.get("hp", 100.0)) <= 0.0:
		return false
	if _global_skill_cooldown_remaining() > 0.0:
		return false
	if _skill_cooldown_remaining(skill_id) > 0.0:
		return false
	if float(player.get("mp", 0.0)) < float(skill.get("mp_cost", 0.0)):
		return false

	var needs_enemy := str(skill.get("type", "")) == "melee" or str(skill.get("type", "")) == "magic" or str(skill.get("type", "")) == "debuff"
	if needs_enemy:
		var has_target = current_enemy_target != null and is_instance_valid(current_enemy_target) and current_enemy_target.visible
		if not has_target and require_target_now:
			return _can_skill_find_target(skill_id)
		if not has_target and not require_target_now:
			return _can_skill_find_target(skill_id)
	return true


func _ensure_auto_skill_pending() -> void:
	if auto_skill_pending == null:
		auto_skill_pending = {}


func _set_auto_skill_pending(skill_id: String) -> void:
	_ensure_auto_skill_pending()
	auto_skill_pending[skill_id] = Time.get_ticks_msec() / 1000.0


func _clear_auto_skill_pending() -> void:
	_ensure_auto_skill_pending()
	auto_skill_pending.clear()


func _auto_skill_pending_elapsed(skill_id: String) -> float:
	_ensure_auto_skill_pending()

	if not auto_skill_pending.has(skill_id):
		return AUTO_SKILL_PENDING_TIMEOUT

	var sent_at := float(auto_skill_pending.get(skill_id, 0.0))
	return max(0.0, (Time.get_ticks_msec() / 1000.0) - sent_at)


func _is_auto_skill_pending(skill_id: String) -> bool:
	_ensure_auto_skill_pending()

	if not auto_skill_pending.has(skill_id):
		return false

	var sent_at := float(auto_skill_pending.get(skill_id, 0.0))
	var elapsed := (Time.get_ticks_msec() / 1000.0) - sent_at

	if elapsed > AUTO_SKILL_PENDING_TIMEOUT:
		auto_skill_pending.erase(skill_id)
		return false

	return true

func _find_closest_visible_enemy() -> Node:
	var player := SceneManager.player
	if player == null or not is_instance_valid(player):
		return null

	var best_enemy: Node = null
	var best_distance := INF
	for enemy in get_tree().get_nodes_in_group("targetable_enemies"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.visible:
			continue
		if enemy is Node2D:
			var distance := (enemy as Node2D).global_position.distance_squared_to(player.global_position)
			if distance < best_distance:
				best_distance = distance
				best_enemy = enemy
	return best_enemy


func _make_enemy_battle_packet(enemy: Node) -> Dictionary:
	var packet := {
		"enemy_id": _get_enemy_id(enemy),
		"enemy_name": _get_enemy_name(enemy),
		"enemy_hp": _get_enemy_hp(enemy),
		"enemy_max_hp": _get_enemy_max_hp(enemy),
		"enemy_mp": _get_enemy_mp(enemy),
		"enemy_max_mp": _get_enemy_max_mp(enemy),
	}

	if enemy != null and enemy.has_method("get_enemy_battle_data"):
		packet.merge(enemy.get_enemy_battle_data(), true)

	_apply_cached_enemy_definition_to_packet(enemy, packet)

	return packet


func _apply_cached_enemy_definition_to_packet(enemy: Node, packet: Dictionary) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not Firebase.has_method("get_enemy_definition"):
		return

	var definition_id := str(packet.get("enemy_definition_id", enemy.get("enemy_definition_id"))).strip_edges()
	if definition_id == "":
		return

	packet["enemy_definition_id"] = definition_id
	var definition = Firebase.get_enemy_definition(definition_id)
	if not (definition is Dictionary) or (definition as Dictionary).is_empty():
		return

	var definition_data := definition as Dictionary
	packet["enemy_name"] = str(definition_data.get("name", packet.get("enemy_name", "Enemy")))
	packet["enemy_max_hp"] = float(definition_data.get("max_hp", packet.get("enemy_max_hp", 100.0)))
	packet["enemy_max_mp"] = float(definition_data.get("max_mp", packet.get("enemy_max_mp", 100.0)))
	packet["enemy_respawn_seconds"] = float(definition_data.get("respawn_seconds", packet.get("enemy_respawn_seconds", 10.0)))

	var rewards = definition_data.get("rewards", {})
	if rewards is Dictionary:
		packet["enemy_reward_gold_min"] = int((rewards as Dictionary).get("gold_min", packet.get("enemy_reward_gold_min", 0)))
		packet["enemy_reward_gold_max"] = int((rewards as Dictionary).get("gold_max", packet.get("enemy_reward_gold_max", 0)))

	var current_xp = packet.get("enemy_reward_xp", {})
	if current_xp is Dictionary and not (current_xp as Dictionary).is_empty():
		return

	var xp = definition_data.get("xp", {})
	if xp is Dictionary:
		packet["enemy_reward_xp"] = (xp as Dictionary).duplicate(true)


func _get_enemy_id(enemy: Node) -> String:
	return str(enemy.get_path())


func _get_enemy_hp(enemy: Node) -> float:
	var value = enemy.get("hp")
	if value == null:
		return _get_enemy_max_hp(enemy)
	return float(value)


func _get_enemy_max_hp(enemy: Node) -> float:
	var value = enemy.get("max_hp")
	if value == null:
		return 100.0
	return max(1.0, float(value))


func _get_enemy_mp(enemy: Node) -> float:
	var value = enemy.get("mp")
	if value == null:
		return _get_enemy_max_mp(enemy)
	return float(value)


func _get_enemy_max_mp(enemy: Node) -> float:
	var value = enemy.get("max_mp")
	if value == null:
		return 100.0
	return max(0.0, float(value))


func _get_enemy_name(enemy: Node) -> String:
	var display_name := str(enemy.get("enemy_name"))
	if display_name == "" or display_name == "<null>":
		display_name = enemy.name
	return display_name


func _on_button_pressed() -> void:
	_on_battle_skill_pressed("slash")

func _on_button_2_pressed() -> void:
	_on_battle_skill_pressed("fire")

func _on_button_3_pressed() -> void:
	_on_battle_skill_pressed("defend")

func _on_button_4_pressed() -> void:
	_on_battle_skill_pressed("heal")

func _on_button_5_pressed() -> void:
	_on_battle_skill_pressed("ultra_attack")
