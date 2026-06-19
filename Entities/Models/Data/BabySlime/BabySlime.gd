extends Node2D

@onready var shadow: ColorRect = $Shadow
@onready var base: Sprite2D = $Body/Chest/Base

var body_type: String = "Green"

var parts := {
	"Chest": "chest",
}

var shadow_width := {
	"baby": 86.0,
	"adult": 166.0,
	"king": 260.0,
}

func _ready() -> void:
	load_body_textures()


func apply_model_data(data: ModelData) -> void:
	if not data is BabySlimeModelData:
		push_error("Slime received wrong model data")
		return

	var slime_data := data as BabySlimeModelData
	body_type = slime_data.body_type

	if is_inside_tree():
		load_body_textures()


func load_body_textures() -> void:
	for node_name in parts:
		var sprite: Sprite2D = get_node("Body/%s/Base" % node_name)

		var texture_path := (
			"res://Entities/Models/Data/BabySlime/Art/%s/%s/base.png"
			% [body_type, parts[node_name]]
		)

		var tex := load(texture_path)

		if tex:
			sprite.texture = tex

			if node_name == "Chest":
				update_shadow_size()
		else:
			push_warning("Texture not found: " + texture_path)


func update_shadow_size() -> void:
	var key := body_type.to_lower().strip_edges()

	var width: float = shadow_width.get(key, 141.0) + 64.0
	var height: float = width * 0.5

	shadow.offset_left = -width * 0.5
	shadow.offset_right = width * 0.5

	shadow.offset_top = 0
	shadow.offset_bottom = height * 0.5

	shadow.position.y = -height * 0.25
