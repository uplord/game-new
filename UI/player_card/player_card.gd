extends PanelContainer

@onready var margin_container: MarginContainer = $MarginContainer
@onready var label_name: Label = $MarginContainer/VBoxContainer/LabelName
@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/HPBar
@onready var mp_bar: ProgressBar = $MarginContainer/VBoxContainer/MPBar

var hp_value_label: Label = null
var mp_value_label: Label = null
var skills_label: Label = null

func _ready() -> void:
	get_viewport().size_changed.connect(_on_resized)
	_setup_value_labels()
	_setup_skills_label()


func _on_resized() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var card_width = 200.0
	if screen_size.y > screen_size.x:
		card_width = min(card_width, (screen_size.x - 48) / 2)
	
	margin_container.custom_minimum_size.x = card_width


func _setup_value_labels() -> void:
	hp_value_label = _create_bar_value_label(hp_bar)
	mp_value_label = _create_bar_value_label(mp_bar)


func _setup_skills_label() -> void:
	if skills_label != null:
		return

	var vbox := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vbox == null:
		return

	skills_label = Label.new()
	skills_label.name = "SkillsLabel"
	skills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skills_label.add_theme_font_size_override("font_size", 11)
	skills_label.add_theme_color_override("font_color", Color.WHITE)
	skills_label.add_theme_constant_override("outline_size", 2)
	skills_label.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(skills_label)


func _format_skills(skills: Dictionary) -> String:
	if skills.is_empty():
		return ""

	return "Melee %d  |  Def %d  |  Magic %d  |  Heal %d" % [
		int(skills.get("melee", 0)),
		int(skills.get("defence", 0)),
		int(skills.get("magic", 0)),
		int(skills.get("healing", 0)),
	]


func _create_bar_value_label(bar: ProgressBar) -> Label:
	if bar == null:
		return null

	bar.show_percentage = false

	var label := Label.new()
	label.name = "ValueLabel"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	bar.add_child(label)
	return label


func _format_stat_value(value: float, max_value: float) -> String:
	return "%d / %d" % [roundi(value), roundi(max_value)]


func set_card_data(display_name: String, hp_value: float = 100.0, hp_max: float = 100.0, mp_value: float = 0.0, mp_max: float = 100.0, skills: Dictionary = {}) -> void:
	if label_name != null:
		label_name.text = display_name

	if hp_bar != null:
		hp_bar.show_percentage = false
		hp_bar.max_value = max(hp_max, 1.0)
		hp_bar.value = clamp(hp_value, 0.0, hp_bar.max_value)
		if hp_value_label != null:
			hp_value_label.text = _format_stat_value(hp_bar.value, hp_bar.max_value)

	if mp_bar != null:
		mp_bar.show_percentage = false
		mp_bar.max_value = max(mp_max, 1.0)
		mp_bar.value = clamp(mp_value, 0.0, mp_bar.max_value)
		mp_bar.visible = mp_max > 0.0
		if mp_value_label != null:
			mp_value_label.text = _format_stat_value(mp_bar.value, mp_bar.max_value)
			mp_value_label.visible = mp_bar.visible

	set_skills(skills)


func set_skills(skills: Dictionary) -> void:
	if skills_label == null:
		_setup_skills_label()
	if skills_label == null:
		return
	skills_label.text = _format_skills(skills)
	skills_label.visible = skills_label.text != ""
