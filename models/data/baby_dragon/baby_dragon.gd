@tool
extends Node2D

@onready var shadow: ColorRect = $Shadow
@onready var base: Sprite2D = $Body/Chest/Base

var body_type: String = "fire_dragon"

var parts := {
	"Chest": "chest",
}

func _ready() -> void:
	load_body_textures()


func apply_model_data(data: ModelData) -> void:
	if not data is BabyDragonModelData:
		push_error("Dragon received wrong model data")
		return

	var dragon_data := data as BabyDragonModelData
	body_type = dragon_data.body_type

	if is_inside_tree():
		load_body_textures()

func load_body_textures() -> void:
	for node_name in parts:
		var sprite: Sprite2D = get_node("Body/%s/Base" % node_name)

		var texture_path := (
			"res://models/data/baby_dragon/art/%s/%s/base.png"
			% [body_type, parts[node_name]]
		)

		var tex = load(texture_path)

		if tex:
			sprite.texture = tex
		else:
			push_warning("Texture not found: " + texture_path)
