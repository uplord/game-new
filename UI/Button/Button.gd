extends Button

@onready var button_icon: TextureRect = $TextureRect

@export var icon_image: Texture2D
@export var icon_scale: float = 0.62

@export var button_width: float = 48.0
@export var button_height: float = 48.0

@export var font_size: float = 16.0
@export var border_size: float = 1.0
@export var radius_size: float = 8.0

@export var border_color: Color = Color("222222")
@export var bg_color: Color = Color("854a28ff")
@export var bg_color_hover: Color = Color("854a28ff")
@export var bg_color_pressed: Color = Color("854a28ff")
@export var font_color: Color = Color("ffffff")

@export var offset_border_size: float = 3.0
@export var offset_border_color: Color = Color("d09f54ff")

var button_scale = DisplayServer.screen_get_scale()

func _ready() -> void:
	set_buttons()
	_update_icon_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_icon_size()


func set_buttons() -> void:
	button_width *= button_scale
	button_height *= button_scale
	font_size *= button_scale
	border_size *= button_scale
	radius_size *= button_scale
	
	custom_minimum_size = Vector2(button_width, button_height)
	add_theme_font_size_override("font_size", int(font_size))
	add_theme_color_override("font_color", font_color)

	var states := ["normal", "hover", "pressed", "disabled"]
	for state in states:
		var sb = get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			sb = sb.duplicate()

			sb.border_width_left = border_size
			sb.border_width_right = border_size
			sb.border_width_top = border_size
			sb.border_width_bottom = border_size
			sb.border_color = border_color
			sb.corner_radius_top_left = radius_size
			sb.corner_radius_top_right = radius_size
			sb.corner_radius_bottom_left = radius_size
			sb.corner_radius_bottom_right = radius_size
			sb.bg_color = bg_color

			if state == "hover":
				sb.bg_color = bg_color_hover
			elif state == "pressed":
				sb.bg_color = bg_color_pressed

			add_theme_stylebox_override(state, sb)
	
	var panel := get_node_or_null("Panel") as Panel
	if panel:
		offset_border_size *= button_scale
		
		var sb = panel.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb = sb.duplicate()

			panel.offset_left = border_size
			panel.offset_right = -border_size
			panel.offset_top = border_size
			panel.offset_bottom = -border_size

			sb.border_width_left = offset_border_size
			sb.border_width_right = offset_border_size
			sb.border_width_top = offset_border_size
			sb.border_width_bottom = offset_border_size
			sb.border_color = offset_border_color

			radius_size = max(
				0,
				radius_size - border_size
			)

			sb.corner_radius_top_left = radius_size
			sb.corner_radius_top_right = radius_size
			sb.corner_radius_bottom_left = radius_size
			sb.corner_radius_bottom_right = radius_size

			panel.add_theme_stylebox_override("panel", sb)

func _update_icon_size() -> void:
	if not button_icon or not icon_image:
		return

	button_icon.texture = icon_image
	button_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	button_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var icon_dimension = min(size.x, size.y) * icon_scale
	button_icon.size = Vector2(icon_dimension, icon_dimension)

	button_icon.position = (size - button_icon.size) / 2
