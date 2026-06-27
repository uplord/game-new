@tool
extends Button

@onready var button_icon: TextureRect = $Icon
@onready var button_icon_trim: TextureRect = $Trim
@onready var countdown_label: Label = get_node_or_null("CountdownLabel") as Label

@export var icon_image: Texture2D
@export var icon_trim: Texture2D
@export_range(0.0, 1.0) var icon_scale: float = 0.6

@export var border_color: Color = Color("#000000")
@export var bg_color: Color = Color("#222222")
@export var bg_color_hover: Color = Color("#222222")
@export var bg_color_pressed: Color = Color("#222222")
@export var bg_color_disabled: Color = Color("#aaaaaa")
@export var trim_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0) var disabled_icon_alpha: float = 0.45

@export_range(0.0, 1.0) var progress := 0.75:
	set(value):
		progress = clamp(value, 0.0, 1.0)
		queue_redraw()

@export var progress_padding := 1.0
@export var progress_thickness := 3.0
@export var progress_color := Color.RED

var _countdown_text := ""
var _last_disabled := false
var _show_disabled_visuals := false
var _progress_draw_color := Color.RED


func _ready() -> void:
	_progress_draw_color = progress_color
	_make_children_ignore_input()
	_apply_button_style()
	_setup_countdown_label()
	set_process(true)
	_refresh_disabled_visuals()


func _process(_delta: float) -> void:
	if _last_disabled != disabled:
		_refresh_disabled_visuals()


func set_countdown_text(value: String) -> void:
	_countdown_text = value
	_show_disabled_visuals = _countdown_text != ""

	if countdown_label != null:
		countdown_label.text = _countdown_text
		countdown_label.visible = _countdown_text != ""

	_refresh_disabled_visuals()


func set_progress(value: float) -> void:
	progress = value


func set_progress_color(color: Color) -> void:
	_progress_draw_color = color
	queue_redraw()


func _refresh_disabled_visuals() -> void:
	_last_disabled = disabled

	var icon_alpha := disabled_icon_alpha if _show_disabled_visuals else 1.0

	if button_icon != null:
		button_icon.modulate = Color(1.0, 1.0, 1.0, icon_alpha)

	if button_icon_trim != null:
		if disabled:
			button_icon_trim.modulate = Color(1.0, 1.0, 1.0, disabled_icon_alpha)
		else:
			button_icon_trim.modulate = _get_normal_trim_color()

	if countdown_label != null:
		countdown_label.visible = _countdown_text != ""


func _get_normal_trim_color() -> Color:
	if trim_color != Color.TRANSPARENT:
		return trim_color
	return progress_color


func _draw() -> void:
	var center := size * 0.5
	var border_radius: float = min(size.x, size.y) * 0.5
	var progress_radius: float = border_radius - progress_padding - progress_thickness * 0.5

	draw_arc(
		center,
		progress_radius,
		deg_to_rad(-90),
		deg_to_rad(-90 + 360.0),
		256,
		Color("ffffff40"),
		progress_thickness,
		true
	)

	draw_arc(
		center,
		progress_radius,
		deg_to_rad(-90),
		deg_to_rad(-90 + progress * 360.0),
		256,
		_progress_draw_color,
		progress_thickness,
		true
	)


func _apply_button_state_styles() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var stylebox := get_theme_stylebox(state)

		if not stylebox is StyleBoxFlat:
			continue

		var flat_stylebox := stylebox.duplicate() as StyleBoxFlat

		var border := 1
		var radius := 32

		flat_stylebox.corner_radius_top_left = radius
		flat_stylebox.corner_radius_top_right = radius
		flat_stylebox.corner_radius_bottom_left = radius
		flat_stylebox.corner_radius_bottom_right = radius

		flat_stylebox.border_width_left = border
		flat_stylebox.border_width_right = border
		flat_stylebox.border_width_top = border
		flat_stylebox.border_width_bottom = border

		flat_stylebox.border_color = border_color
		flat_stylebox.bg_color = _get_state_background_color(state)

		add_theme_stylebox_override(state, flat_stylebox)


func _apply_button_style() -> void:
	_apply_button_state_styles()
	_update_icon_size()


func _get_state_background_color(state: String) -> Color:
	match state:
		"hover":
			return bg_color_hover
		"pressed":
			return bg_color_pressed
		"disabled":
			return bg_color_disabled
		"focus":
			return bg_color
		_:
			return bg_color


func _update_icon_size() -> void:
	_update_texture_rect(button_icon, icon_image)

	if button_icon_trim and icon_trim:
		_update_texture_rect(button_icon_trim, icon_trim)
		button_icon_trim.modulate = _get_normal_trim_color()


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


func _setup_countdown_label() -> void:
	if countdown_label == null:
		return

	countdown_label.visible = false


func _make_children_ignore_input() -> void:
	for child in [button_icon, button_icon_trim, get_node_or_null("Panel")]:
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
