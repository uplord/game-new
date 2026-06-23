extends Node2D

var selected_model: Node
const Z_SORT_OFFSET := 1000
var _last_z_index: int = -2147483648

func _ready() -> void:
	y_sort_enabled = false
	_apply_z_sort()


func _apply_z_sort() -> void:
	var new_z := int(global_position.y) + Z_SORT_OFFSET

	if _last_z_index == new_z:
		return

	_last_z_index = new_z
	z_index = new_z
