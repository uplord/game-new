extends Control

@export var fade_duration := 0.2

@onready var background: Panel = $Background

var _fade_tween: Tween


func _ready() -> void:
	get_viewport().size_changed.connect(update_layout)
	update_layout()
	modulate.a = 0.0
	visible = false


func is_mobile() -> bool:
	return OS.has_feature("android") or (
		OS.has_feature("ios") and not OS.has_feature("ipad")
	)


func update_layout() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size := get_viewport().get_visible_rect().size

	var left_inset = safe_area.position.x / DisplayServer.screen_get_scale()
	var top_inset = safe_area.position.y / DisplayServer.screen_get_scale()
	var right_inset = screen_size.x - ((safe_area.position.x + safe_area.size.x) / DisplayServer.screen_get_scale())
	var bottom_inset = screen_size.y - ((safe_area.position.y + safe_area.size.y) / DisplayServer.screen_get_scale())

	background.offset_left = -left_inset
	background.offset_top = -top_inset
	background.offset_right = right_inset
	background.offset_bottom = bottom_inset
	

func open() -> void:
	move_to_front()
	visible = true
	_fade_to(1.0)


func close() -> void:
	await _fade_to(0.0)
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func force_close() -> void:
	if _fade_tween:
		_fade_tween.kill()

	modulate.a = 0.0
	visible = false


func _fade_to(alpha: float) -> void:
	if _fade_tween:
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", alpha, fade_duration)
	await _fade_tween.finished


func _on_button_pressed() -> void:
	close()
