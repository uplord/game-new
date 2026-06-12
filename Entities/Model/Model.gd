extends Node2D

var selected_model: Node
const Z_SORT_OFFSET := 540
var _last_z_index: int = -2147483648


func _ready() -> void:
	y_sort_enabled = false
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_apply_z_sort()


func _apply_z_sort() -> void:
	var new_z := int(global_position.y) + Z_SORT_OFFSET

	if _last_z_index == new_z:
		return

	_last_z_index = new_z
	z_index = new_z
