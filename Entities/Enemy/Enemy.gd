@tool
extends Node2D

signal targeted(enemy: Node)

# Expose the nested Model node's options on the Enemy itself so every Enemy
# instance placed in a map can be configured from the Inspector.
@export_category("Model")
@export var model_data: ModelData:
	set(value):
		model_data = value
		_sync_model_options()

@export var animation_tree_enabled := false:
	set(value):
		animation_tree_enabled = value
		_sync_model_options()

@export var keep_animation_tree_for_player := false:
	set(value):
		keep_animation_tree_for_player = value
		_sync_model_options()

@export var starting_pose: PlayerUtil.PlayerPose = PlayerUtil.PlayerPose.IDLE:
	set(value):
		starting_pose = value
		_sync_model_options()


@export_category("Targeting")
@export var enemy_name := "Enemy"
@export var max_hp := 100.0
@export var hp := 100.0
@export var max_mp := 100.0
@export var mp := 100.0

@onready var body: Node = $Base/Model

var is_selected := false


func _ready() -> void:
	_sync_model_options()

	if Engine.is_editor_hint():
		return

	add_to_group("targetable_enemies")

	_connect_target_area()


func set_selected(value: bool) -> void:
	is_selected = value

	var model_node := get_node_or_null("Base/Model")
	if model_node == null:
		return

	var shadow := model_node.find_child("Shadow", true, false)
	if shadow == null:
		return

	if shadow.material:
		shadow.material = shadow.material.duplicate()

	shadow.modulate = Color.WHITE

	if value:
		shadow.material.set_shader_parameter("selected", true)
	else:
		shadow.material.set_shader_parameter("selected", false)


func _sync_model_options() -> void:
	var model_node := get_node_or_null("Base/Model")
	if model_node == null:
		return

	model_node.set("model_data", model_data)
	model_node.set("animation_tree_enabled", animation_tree_enabled)
	model_node.set("keep_animation_tree_for_player", keep_animation_tree_for_player)
	model_node.set("starting_pose", starting_pose)


func _connect_target_area() -> void:
	var model_node := get_node_or_null("Base/Model")
	if model_node == null or not model_node.has_method("get_target_area"):
		return

	var target_area: Area2D = model_node.get_target_area()
	if target_area != null and not target_area.input_event.is_connected(_on_target_area_input_event):
		target_area.input_event.connect(_on_target_area_input_event)


func _on_target_area_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return

	if not event is InputEventMouseButton:
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	target()
	get_viewport().set_input_as_handled()

func target() -> void:
	if Engine.is_editor_hint():
		return

	targeted.emit(self)
	_cancel_player_mouse_movement()
	_show_enemy_card()
	_move_player_close_to_self()

func _move_player_close_to_self() -> void:
	var player := SceneManager.player
	if player != null and is_instance_valid(player) and player.has_method("move_close_to_enemy"):
		player.move_close_to_enemy(self)

func _show_enemy_card() -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game == null:
		return

	var ui := game.get_node_or_null("UI")
	if ui != null and ui.has_method("show_enemy_card"):
		ui.show_enemy_card(self)


func _cancel_player_mouse_movement() -> void:
	var player := SceneManager.player
	if player != null and is_instance_valid(player) and player.has_method("cancel_mouse_movement"):
		# Keep the current camera offset when targeting an enemy. The player should
		# move to engagement range, but the camera should not jump/focus on target.
		player.cancel_mouse_movement(false)
