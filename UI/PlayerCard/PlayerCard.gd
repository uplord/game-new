extends PanelContainer

@onready var margin_container: MarginContainer = $MarginContainer
@onready var label_name: Label = $MarginContainer/VBoxContainer/LabelName
@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/HPBar
@onready var mp_bar: ProgressBar = $MarginContainer/VBoxContainer/MPBar

func _ready() -> void:
	get_viewport().size_changed.connect(_on_resized)
#
	_style_bar(hp_bar, Color(0.85, 0.05, 0.05), Color("ffffff1a"))
	_style_bar(mp_bar, Color(0.1, 0.35, 0.95), Color("ffffff1a"))
#
func _on_resized() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var card_width = 200.0
	if screen_size.y > screen_size.x:
		card_width = min(card_width, (screen_size.x - 48) / 2)
	
	margin_container.custom_minimum_size.x = card_width

func _style_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color

	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
