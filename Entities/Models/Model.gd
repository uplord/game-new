@tool
extends Node2D

@export var model_data: ModelData

@export var animation_tree_enabled := false
@export var keep_animation_tree_for_player := false
@export var starting_pose: PlayerUtil.PlayerPose = PlayerUtil.PlayerPose.IDLE

@export_category("Targeting")

var selected_model: Node
const Z_SORT_OFFSET := 1000
var _last_z_index: int = -2147483648
var _last_global_position := Vector2.INF

func _ready() -> void:
	y_sort_enabled = false
	load_model()


func _process(_delta: float) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	if parent_node is Node2D:
		if _last_global_position != global_position:
			_last_global_position = global_position
			_apply_z_sort()


func load_model() -> void:
	for child in get_children():
		child.queue_free()

	if model_data == null:
		push_error("No model data assigned on: " + name)
		return

	var model_type := model_data.get_model_type()
	var model_path := "res://Entities/Models/Data/%s/%s.tscn" % [model_type, model_type]

	var packed_model: PackedScene = load(model_path)

	if packed_model == null:
		push_warning("Failed to load model: " + model_path)
		return

	selected_model = packed_model.instantiate()
	add_child(selected_model)

	if selected_model.has_method("apply_model_data"):
		selected_model.apply_model_data(model_data)

	_apply_facing_direction()
	
	_configure_animation_tree()
	_apply_starting_pose()
	_sync_target_area()
	_apply_z_sort()


func get_model_root() -> Node:
	return selected_model
	


func _apply_facing_direction() -> void:
	if selected_model == null or model_data == null:
		return

	var facing := 1
	if model_data.facing_direction == ModelData.FacingDirection.LEFT:
		facing = -1

	selected_model.scale.x = abs(selected_model.scale.x) * facing

func _configure_animation_tree() -> void:
	if selected_model == null:
		return

	var anim_tree: AnimationTree = selected_model.get_node_or_null("AnimationTree") as AnimationTree

	if anim_tree == null:
		return

	var needs_animation_tree: bool = animation_tree_enabled \
		or keep_animation_tree_for_player \
		or starting_pose != PlayerUtil.PlayerPose.IDLE

	anim_tree.active = needs_animation_tree
	anim_tree.process_mode = Node.PROCESS_MODE_INHERIT if needs_animation_tree else Node.PROCESS_MODE_DISABLED

func _apply_starting_pose() -> void:
	if selected_model == null:
		return

	var anim_tree: AnimationTree = selected_model.get_node_or_null("AnimationTree") as AnimationTree

	if anim_tree == null:
		return

	if not anim_tree.active:
		return

	var animation_state: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	if animation_state == null:
		return

	animation_state.start(PlayerUtil.to_anim_name(starting_pose))

	if not animation_tree_enabled and not keep_animation_tree_for_player:
		await get_tree().process_frame
		anim_tree.process_mode = Node.PROCESS_MODE_DISABLED

func _apply_z_sort() -> void:
	var new_z := int(global_position.y) + Z_SORT_OFFSET

	if _last_z_index == new_z:
		return

	_last_z_index = new_z
	z_index = new_z


func get_target_area() -> Area2D:
	if selected_model == null:
		return null

	return selected_model.get_node_or_null("TargetArea") as Area2D


func _sync_target_area() -> void:
	var area := get_target_area()
	if area == null:
		return

	area.input_pickable = true
	area.collision_layer = 1
	area.collision_mask = 0
