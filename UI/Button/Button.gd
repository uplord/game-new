extends Button

@onready var button_icon: TextureRect = $Icon
@onready var button_icon_trim: TextureRect = $Trim

@export var icon_image: Texture2D
@export var icon_trim: Texture2D
@export_range(0.0, 1.0) var icon_scale: float = 0.65

enum TextAlignment {
	LEFT,
	CENTER,
	RIGHT
}

@export var text_alignment: TextAlignment = TextAlignment.CENTER

@export var full_width: bool = false

@export var padding_x: float = 16.0
@export var padding_y: float = 8.0

@export var font_size: float = 16.0
@export var border_size: float = 1.0
@export var radius_size: float = 8.0

@export var border_color: Color = Color("#222222")
@export var bg_color: Color = Color("#222222")
@export var bg_color_hover: Color = Color("#222222")
@export var bg_color_pressed: Color = Color("#222222")
@export var font_color: Color = Color("#ffffff")

@export var offset_border_size: float = 0.0
@export var offset_border_color: Color = Color("#ffffff00")

@export var trim_color: Color = Color.TRANSPARENT

const BASE_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)

func _ready() -> void:
	_apply_button_style()


func _apply_button_style() -> void:
	if full_width:
		custom_minimum_size = Vector2(0, custom_minimum_size.y)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	add_theme_color_override("font_color", font_color)
	add_theme_font_size_override("font_size", int(font_size))

	_apply_text_alignment()

	_apply_button_state_styles()
	_apply_offset_panel_style()
	_update_icon_size()


func _apply_text_alignment() -> void:
	match text_alignment:
		TextAlignment.LEFT:
			alignment = HORIZONTAL_ALIGNMENT_LEFT
		TextAlignment.CENTER:
			alignment = HORIZONTAL_ALIGNMENT_CENTER
		TextAlignment.RIGHT:
			alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _apply_button_state_styles() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var stylebox := get_theme_stylebox(state)

		if not stylebox is StyleBoxFlat:
			continue

		var flat_stylebox := stylebox.duplicate() as StyleBoxFlat

		var radius := int(round(radius_size))
		var border := int(round(border_size))

		flat_stylebox.corner_radius_top_left = radius
		flat_stylebox.corner_radius_top_right = radius
		flat_stylebox.corner_radius_bottom_left = radius
		flat_stylebox.corner_radius_bottom_right = radius

		flat_stylebox.border_width_left = border
		flat_stylebox.border_width_right = border
		flat_stylebox.border_width_top = border
		flat_stylebox.border_width_bottom = border

		flat_stylebox.content_margin_left = padding_x
		flat_stylebox.content_margin_right = padding_x
		flat_stylebox.content_margin_top = padding_y
		flat_stylebox.content_margin_bottom = padding_y

		flat_stylebox.border_color = border_color
		flat_stylebox.bg_color = _get_state_background_color(state)

		add_theme_stylebox_override(state, flat_stylebox)


func _get_state_background_color(state: String) -> Color:
	match state:
		"hover":
			return bg_color_hover
		"pressed":
			return bg_color_pressed
		"disabled":
			return bg_color
		"focus":
			return bg_color
		_:
			return bg_color


func _apply_offset_panel_style(
) -> void:
	var panel := get_node_or_null("Panel") as Panel

	if not panel:
		return

	var stylebox := panel.get_theme_stylebox("panel")

	if not stylebox is StyleBoxFlat:
		return

	var inner_radius = max(0.0, radius_size - border_size)

	var border = border_size
	var radius = inner_radius

	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0

	panel.offset_left = border
	panel.offset_right = -border
	panel.offset_top = border
	panel.offset_bottom = -border

	var flat_stylebox := stylebox.duplicate() as StyleBoxFlat

	var offset_border := int(round(offset_border_size))
	flat_stylebox.border_width_left = offset_border
	flat_stylebox.border_width_right = offset_border
	flat_stylebox.border_width_top = offset_border
	flat_stylebox.border_width_bottom = offset_border

	flat_stylebox.border_color = offset_border_color

	flat_stylebox.corner_radius_top_left = radius
	flat_stylebox.corner_radius_top_right = radius
	flat_stylebox.corner_radius_bottom_left = radius
	flat_stylebox.corner_radius_bottom_right = radius

	panel.add_theme_stylebox_override("panel", flat_stylebox)


func _update_icon_size() -> void:
	_update_texture_rect(button_icon, icon_image)

	if button_icon_trim and icon_trim:
		_update_texture_rect(button_icon_trim, icon_trim)

		if trim_color != Color.TRANSPARENT:
			button_icon_trim.modulate = trim_color
		else:
			button_icon_trim.modulate = offset_border_color


func _update_texture_rect(texture_rect: TextureRect, texture: Texture2D) -> void:
	if not texture_rect or not texture:
		return

	var current_size := size

	if current_size == Vector2.ZERO:
		current_size = custom_minimum_size

	var icon_dimension = min(current_size.x, current_size.y) * icon_scale

	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	texture_rect.anchor_left = 0.5
	texture_rect.anchor_top = 0.5
	texture_rect.anchor_right = 0.5
	texture_rect.anchor_bottom = 0.5

	texture_rect.size = Vector2(icon_dimension, icon_dimension)
	texture_rect.position = (current_size - texture_rect.size) / 2.0
