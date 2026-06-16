extends Control

@export var border_size: float = 1.0
@export var radius_size: float = 8.0

@onready var background: Panel = $Background

@onready var top_bar: Control = $MarginContainer/VBoxContainer/Top

var display_scale: float = DisplayServer.screen_get_scale()

func _ready() -> void:
	get_viewport().size_changed.connect(update_layout)
	update_layout()


func is_mobile() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"


func update_layout() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size := get_viewport().get_visible_rect().size

	var left_inset = safe_area.position.x
	var top_inset = safe_area.position.y
	var right_inset = screen_size.x - (safe_area.position.x + safe_area.size.x)
	var bottom_inset = screen_size.y - (safe_area.position.y + safe_area.size.y)

	background.offset_left = -left_inset
	background.offset_top = -top_inset
	background.offset_right = right_inset
	background.offset_bottom = bottom_inset

	top_bar.custom_minimum_size.y = (48.0 * display_scale) + 32.0

func toggle() -> void:
	visible = not visible

func close() -> void:
	visible = false


func _on_button_pressed() -> void:
	close()
