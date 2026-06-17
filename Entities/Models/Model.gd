extends Node2D

@export var model_data: ModelData

@export var animation_tree_enabled := false
@export var keep_animation_tree_for_player := false
@export var starting_pose: PlayerUtil.PlayerPose = PlayerUtil.PlayerPose.IDLE

var selected_model: Node
const Z_SORT_OFFSET := 1000
var _last_z_index: int = -2147483648

func _ready() -> void:
	y_sort_enabled = false
	load_model()
	apply_default_scale()

func _process(_delta: float) -> void:
	_apply_z_sort()

func load_model() -> void:
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
	
	_configure_animation_tree()
	_apply_starting_pose()
	_apply_z_sort()

func apply_default_scale() -> void:
	if model_data == null:
		return

	var x_scale := model_data.default_scale

	if model_data.facing_direction == ModelData.FacingDirection.LEFT:
		x_scale = -x_scale

	scale = Vector2(x_scale, model_data.default_scale)

func get_model_root() -> Node:
	return selected_model
	

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
