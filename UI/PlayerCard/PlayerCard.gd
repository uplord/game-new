extends PanelContainer

@onready var margin_container: MarginContainer = $MarginContainer
@onready var label_name: Label = $MarginContainer/VBoxContainer/LabelName
@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/HPBar
@onready var mp_bar: ProgressBar = $MarginContainer/VBoxContainer/MPBar

var display_scale: float = DisplayServer.screen_get_scale()

func _ready() -> void:
	get_viewport().size_changed.connect(_on_resized)

	var margin_size := roundi(8.0 * display_scale)

	margin_container.add_theme_constant_override("margin_left", margin_size)
	margin_container.add_theme_constant_override("margin_top", margin_size)
	margin_container.add_theme_constant_override("margin_right", margin_size)
	margin_container.add_theme_constant_override("margin_bottom", margin_size)

	label_name.add_theme_font_size_override(
		"font_size",
		int(12 * DisplayServer.screen_get_scale())
	)

	hp_bar.custom_minimum_size.y = 16.0 * display_scale
	mp_bar.custom_minimum_size.y = 16.0 * display_scale

	_style_bar(hp_bar, Color(0.85, 0.05, 0.05), Color("ffffff1a"))
	_style_bar(mp_bar, Color(0.1, 0.35, 0.95), Color("ffffff1a"))

func _on_resized() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var card_width = 200.0 * display_scale
	if screen_size.y > screen_size.x:
		card_width = min(card_width, (screen_size.x - 48) / 2)
	
	margin_container.custom_minimum_size.x = card_width

func _style_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var radius := int(4.0 * display_scale)

	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.corner_radius_top_left = radius
	bg.corner_radius_top_right = radius
	bg.corner_radius_bottom_left = radius
	bg.corner_radius_bottom_right = radius

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color

	fill.corner_radius_top_left = radius
	fill.corner_radius_bottom_left = radius

	if is_equal_approx(bar.value, bar.max_value):
		fill.corner_radius_top_right = radius
		fill.corner_radius_bottom_right = radius
	else:
		fill.corner_radius_top_right = 0
		fill.corner_radius_bottom_right = 0

	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
